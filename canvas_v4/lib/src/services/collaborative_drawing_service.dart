// lib/src/services/enhanced_collaborative_drawing_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/network_enums.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_drawing_board/src/domain/domain.dart';

class CollaborativeDrawingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Realtime channels
  RealtimeChannel? _drawingChannel;
  RealtimeChannel? _presenceChannel;

  // Stream controllers
  final _strokesController = StreamController<CollaborativeStroke>.broadcast();
  final _participantsController = StreamController<List<Participant>>.broadcast();
  final _cursorPositionsController = StreamController<Map<String, CursorPosition>>.broadcast();
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _sessionEventsController = StreamController<SessionEvent>.broadcast();

  // Current session state
  String? _currentSessionId;
  String? _currentUserId;
  String? _currentUserName;
  Color? _currentUserColor;
  Map<String, Participant> _participants = {};
  Map<String, CursorPosition> _cursorPositions = {};
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;

  // Stroke batching for performance
  final List<Stroke> _pendingStrokes = [];
  Timer? _strokeBatchTimer;
  static const Duration _batchInterval = Duration(milliseconds: 100);

  // Rate limiting
  final Map<String, List<DateTime>> _userActionHistory = {};
  static const int _maxActionsPerSecond = 50;

  // Reconnection logic
  Timer? _reconnectionTimer;
  int _reconnectionAttempts = 0;
  static const int _maxReconnectionAttempts = 5;
  static const Duration _baseReconnectionDelay = Duration(seconds: 2);

  // Session activity tracking
  DateTime? _lastActivity;
  Timer? _activityTimer;

  // Streams
  Stream<CollaborativeStroke> get strokeStream => _strokesController.stream;
  Stream<List<Participant>> get participantsStream => _participantsController.stream;
  Stream<Map<String, CursorPosition>> get cursorPositionsStream => _cursorPositionsController.stream;
  Stream<ConnectionStatus> get connectionStatusStream => _connectionStatusController.stream;
  Stream<SessionEvent> get sessionEventsStream => _sessionEventsController.stream;

  // Connection status getter
  ConnectionStatus get connectionStatus => _connectionStatus;
  bool get isConnected => _connectionStatus == ConnectionStatus.connected;

  /// Create a new collaborative session with persistent storage
  Future<String> createSession({
    required String hostUserId,
    required String title,
    String? password,
    int? maxParticipants,
    Map<String, dynamic>? canvasSettings,
  }) async {
    try {
      final response = await _supabase.from('collaborative_sessions').insert({
        'host_user_id': hostUserId,
        'title': title,
        'password': password,
        'max_participants': maxParticipants ?? 10,
        'canvas_settings': canvasSettings != null ? jsonEncode(canvasSettings) : null,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'last_activity_at': DateTime.now().toIso8601String(),
      }).select().single();

      final sessionId = response['id'] as String;
      _sessionEventsController.add(SessionEvent.sessionCreated(sessionId, title));
      return sessionId;
    } catch (e) {
      _sessionEventsController.add(SessionEvent.error('Failed to create session: $e'));
      rethrow;
    }
  }

  /// Join a collaborative session with full state restoration
  Future<void> joinSession({
    required String sessionId,
    required String userId,
    required String userName,
    Color? userColor,
    String? password,
  }) async {
    try {
      _updateConnectionStatus(ConnectionStatus.connecting);

      // Validate session exists and check password
      await _validateAndJoinSession(sessionId, password);

      _currentSessionId = sessionId;
      _currentUserId = userId;
      _currentUserName = userName;
      _currentUserColor = userColor ?? _generateUserColor();

      // Set up realtime channels
      await _setupRealtimeChannels();

      // Load existing strokes from database
      await _loadSessionHistory();

      // Track presence
      await _trackUserPresence();

      _updateConnectionStatus(ConnectionStatus.connected);
      _resetReconnectionState();

      _sessionEventsController.add(SessionEvent.joinedSession(sessionId, userName));
      _updateSessionActivity();

    } catch (e) {
      _updateConnectionStatus(ConnectionStatus.error);
      _sessionEventsController.add(SessionEvent.error('Failed to join session: $e'));
      rethrow;
    }
  }

  /// Validate session and check constraints
  Future<void> _validateAndJoinSession(String sessionId, String? password) async {
    final session = await _supabase
        .from('collaborative_sessions')
        .select('*')
        .eq('id', sessionId)
        .eq('is_active', true)
        .single();

    // Check password
    if (session['password'] != null && session['password'] != password) {
      throw Exception('Invalid session password');
    }

    // Check participant limit (this is approximate due to realtime nature)
    final recentParticipants = await _supabase
        .from('session_participants')
        .select('user_id')
        .eq('session_id', sessionId)
        .gte('last_seen_at', DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String())
        .count();

    if (recentParticipants.count >= (session['max_participants'] as int)) {
      throw Exception('Session is full');
    }
  }

  /// Set up realtime channels with enhanced error handling
  Future<void> _setupRealtimeChannels() async {
    // Drawing channel for strokes and actions
    _drawingChannel = _supabase.channel('drawing:$_currentSessionId')
      ..onBroadcast(event: 'stroke_batch', callback: _handleStrokeBatchEvent)
      ..onBroadcast(event: 'stroke', callback: _handleStrokeEvent)
      ..onBroadcast(event: 'cursor', callback: _handleCursorEvent)
      ..onBroadcast(event: 'clear', callback: _handleClearEvent)
      ..onBroadcast(event: 'undo', callback: _handleUndoEvent)
      ..onBroadcast(event: 'session_action', callback: _handleSessionActionEvent);

    // Presence channel for participants
    _presenceChannel = _supabase.channel('presence:$_currentSessionId')
      ..onPresenceSync(_handlePresenceSync)
      ..onPresenceJoin(_handlePresenceJoin)
      ..onPresenceLeave(_handlePresenceLeave);

    // Subscribe with retry logic
    await _subscribeWithRetry(_drawingChannel!);
    await _subscribeWithRetry(_presenceChannel!);
  }

  /// Subscribe to channel with retry mechanism
  Future<void> _subscribeWithRetry(RealtimeChannel channel) async {
    int attempts = 0;
    while (attempts < 3) {
      try {
        final status = await channel.subscribe();
        if (status == RealtimeSubscribeStatus.subscribed) {
          return;
        }
        attempts++;
        if (attempts < 3) {
          await Future.delayed(Duration(seconds: attempts));
        }
      } catch (e) {
        attempts++;
        if (attempts >= 3) rethrow;
        await Future.delayed(Duration(seconds: attempts));
      }
    }
    throw Exception('Failed to subscribe to channel after 3 attempts');
  }

  /// Load existing strokes from database for session history
  Future<void> _loadSessionHistory() async {
    try {
      final strokesData = await _supabase
          .from('session_strokes')
          .select('*')
          .eq('session_id', _currentSessionId!)
          .order('created_at', ascending: true);

      final strokes = <CollaborativeStroke>[];

      for (final data in strokesData) {
        try {
          final strokeJson = jsonDecode(data['stroke_data']) as Map<String, dynamic>;
          final stroke = Stroke.fromJson(strokeJson);

          strokes.add(CollaborativeStroke(
            stroke: stroke,
            userId: data['user_id'],
            userName: data['user_name'] ?? 'Unknown',
            userColor: Color(data['user_color'] ?? Colors.grey.value),
            timestamp: DateTime.parse(data['created_at']),
          ));
        } catch (e) {
          // Skip corrupted stroke data
          debugPrint('Skipped corrupted stroke: $e');
        }
      }

      // Emit all historical strokes
      for (final stroke in strokes) {
        _strokesController.add(stroke);
      }

      _sessionEventsController.add(SessionEvent.historyLoaded(strokes.length));

    } catch (e) {
      _sessionEventsController.add(SessionEvent.error('Failed to load session history: $e'));
    }
  }

  /// Track user presence with metadata
  Future<void> _trackUserPresence() async {
    await _presenceChannel!.track({
      'user_id': _currentUserId!,
      'user_name': _currentUserName!,
      'color': _currentUserColor!.value,
      'joined_at': DateTime.now().toIso8601String(),
      'version': '1.0', // For future compatibility
    });

    // Update participant record in database
    await _supabase.from('session_participants').upsert({
      'session_id': _currentSessionId!,
      'user_id': _currentUserId!,
      'user_name': _currentUserName!,
      'user_color': _currentUserColor!.value,
      'joined_at': DateTime.now().toIso8601String(),
      'last_seen_at': DateTime.now().toIso8601String(),
    });
  }

  /// Broadcast stroke with batching for performance
  Future<void> broadcastStroke(Stroke stroke) async {
    if (!_canPerformAction()) return;

    // Add to pending batch
    _pendingStrokes.add(stroke);

    // Save to database immediately for persistence
    await _saveStrokeToDatabase(stroke);

    // Start batch timer if not already running
    if (_strokeBatchTimer == null || !_strokeBatchTimer!.isActive) {
      _strokeBatchTimer = Timer(_batchInterval, _flushStrokeBatch);
    }

    _updateSessionActivity();
  }

  /// Flush pending strokes as a batch
  Future<void> _flushStrokeBatch() async {
    if (_pendingStrokes.isEmpty || _drawingChannel == null) return;

    try {
      final strokesJson = _pendingStrokes.map((s) => s.toJson()).toList();

      await _drawingChannel!.sendBroadcastMessage(
        event: 'stroke_batch',
        payload: {
          'user_id': _currentUserId!,
          'user_name': _currentUserName!,
          'user_color': _currentUserColor!.value,
          'strokes': strokesJson,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _pendingStrokes.clear();
    } catch (e) {
      _handleConnectionError(e);
    }
  }

  /// Save stroke to database for persistence
  Future<void> _saveStrokeToDatabase(Stroke stroke) async {
    try {
      await _supabase.from('session_strokes').insert({
        'session_id': _currentSessionId!,
        'user_id': _currentUserId!,
        'user_name': _currentUserName!,
        'user_color': _currentUserColor!.value,
        'stroke_data': jsonEncode(stroke.toJson()),
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Non-critical error, strokes still work via realtime
      debugPrint('Failed to save stroke to database: $e');
    }
  }

  /// Broadcast cursor position with throttling
  Future<void> broadcastCursorPosition(Offset position) async {
    if (!_canPerformAction()) return;

    try {
      await _drawingChannel!.sendBroadcastMessage(
        event: 'cursor',
        payload: {
          'user_id': _currentUserId!,
          'user_name': _currentUserName!,
          'user_color': _currentUserColor!.value,
          'x': position.dx,
          'y': position.dy,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      _handleConnectionError(e);
    }
  }

  /// Broadcast clear canvas action
  Future<void> broadcastClear() async {
    if (!_canPerformAction()) return;

    try {
      // Clear strokes from database
      await _supabase
          .from('session_strokes')
          .delete()
          .eq('session_id', _currentSessionId!);

      await _drawingChannel!.sendBroadcastMessage(
        event: 'clear',
        payload: {
          'user_id': _currentUserId!,
          'user_name': _currentUserName!,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _updateSessionActivity();
    } catch (e) {
      _handleConnectionError(e);
    }
  }

  /// Broadcast undo action
  Future<void> broadcastUndo() async {
    if (!_canPerformAction()) return;

    try {
      // Remove last stroke from database
      final lastStroke = await _supabase
          .from('session_strokes')
          .select('id')
          .eq('session_id', _currentSessionId!)
          .eq('user_id', _currentUserId!)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (lastStroke != null) {
        await _supabase
            .from('session_strokes')
            .delete()
            .eq('id', lastStroke['id']);
      }

      await _drawingChannel!.sendBroadcastMessage(
        event: 'undo',
        payload: {
          'user_id': _currentUserId!,
          'user_name': _currentUserName!,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _updateSessionActivity();
    } catch (e) {
      _handleConnectionError(e);
    }
  }

  /// Handle incoming stroke batch for better performance
  void _handleStrokeBatchEvent(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String;
    if (userId == _currentUserId) return;

    final strokesJson = payload['strokes'] as List;
    final userName = payload['user_name'] as String? ?? 'Unknown';
    final userColor = Color(payload['user_color'] as int? ?? Colors.grey.value);

    for (final strokeJson in strokesJson) {
      try {
        final stroke = Stroke.fromJson(strokeJson as Map<String, dynamic>);
        _strokesController.add(CollaborativeStroke(
          stroke: stroke,
          userId: userId,
          userName: userName,
          userColor: userColor,
          timestamp: DateTime.parse(payload['timestamp']),
        ));
      } catch (e) {
        debugPrint('Failed to parse stroke: $e');
      }
    }
  }

  /// Handle incoming individual stroke (fallback)
  void _handleStrokeEvent(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String;
    if (userId == _currentUserId) return;

    try {
      final strokeJson = payload['stroke'] as Map<String, dynamic>;
      final stroke = Stroke.fromJson(strokeJson);

      _strokesController.add(CollaborativeStroke(
        stroke: stroke,
        userId: userId,
        userName: payload['user_name'] as String? ?? 'Unknown',
        userColor: Color(payload['user_color'] as int? ?? Colors.grey.value),
        timestamp: DateTime.parse(payload['timestamp']),
      ));
    } catch (e) {
      debugPrint('Failed to handle stroke event: $e');
    }
  }

  /// Handle cursor movement with position validation
  void _handleCursorEvent(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String;
    if (userId == _currentUserId) return;

    try {
      final x = (payload['x'] as num).toDouble();
      final y = (payload['y'] as num).toDouble();

      // Basic position validation
      if (x.isFinite && y.isFinite && x >= 0 && y >= 0) {
        _cursorPositions[userId] = CursorPosition(
          userId: userId,
          position: Offset(x, y),
          userName: payload['user_name'] as String? ?? 'Unknown',
          color: Color(payload['user_color'] as int? ?? Colors.grey.value),
          timestamp: DateTime.parse(payload['timestamp']),
        );

        _cursorPositionsController.add(Map.from(_cursorPositions));
      }
    } catch (e) {
      debugPrint('Failed to handle cursor event: $e');
    }
  }

  /// Handle clear event
  void _handleClearEvent(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String;
    if (userId == _currentUserId) return;

    _strokesController.add(CollaborativeStroke.clear(
      userId: userId,
      userName: payload['user_name'] as String? ?? 'Unknown',
      timestamp: DateTime.parse(payload['timestamp']),
    ));
  }

  /// Handle undo event
  void _handleUndoEvent(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String;
    if (userId == _currentUserId) return;

    _strokesController.add(CollaborativeStroke.undo(
      userId: userId,
      userName: payload['user_name'] as String? ?? 'Unknown',
      timestamp: DateTime.parse(payload['timestamp']),
    ));
  }

  /// Handle session-level actions (future extensibility)
  void _handleSessionActionEvent(Map<String, dynamic> payload) {
    final action = payload['action'] as String;
    final userId = payload['user_id'] as String;
    final userName = payload['user_name'] as String? ?? 'Unknown';

    switch (action) {
      case 'session_locked':
        _sessionEventsController.add(SessionEvent.sessionLocked(userName));
        break;
      case 'user_kicked':
        if (payload['target_user_id'] == _currentUserId) {
          _sessionEventsController.add(SessionEvent.userKicked());
          leaveSession();
        }
        break;
    // Add more session actions as needed
    }
  }

  /// Enhanced presence handling
  void _handlePresenceSync(dynamic payload) {
    _participants.clear();
    _extractParticipantsFromPayload(payload);
    _participantsController.add(_participants.values.toList());
  }

  void _handlePresenceJoin(dynamic payload) {
    _extractParticipantsFromPayload(payload, isJoin: true);
    _participantsController.add(_participants.values.toList());
  }

  void _handlePresenceLeave(dynamic payload) {
    _extractParticipantsFromPayload(payload, isLeave: true);
    _participantsController.add(_participants.values.toList());
    _cursorPositionsController.add(Map.from(_cursorPositions));
  }

  /// Extract participants from presence payload
  void _extractParticipantsFromPayload(dynamic payload, {bool isJoin = false, bool isLeave = false}) {
    List<dynamic>? presenceList;

    if (payload is Map) {
      if (isJoin && payload['newPresences'] != null) {
        presenceList = payload['newPresences'] as List;
      } else if (isLeave && payload['leftPresences'] != null) {
        presenceList = payload['leftPresences'] as List;
        // Remove participants who left
        for (final presenceState in presenceList) {
          if (presenceState is Map && presenceState['presences'] is List) {
            final presences = presenceState['presences'] as List;
            for (final presence in presences) {
              if (presence is Map<String, dynamic>) {
                final userId = presence['user_id'] as String?;
                if (userId != null) {
                  _participants.remove(userId);
                  _cursorPositions.remove(userId);
                }
              }
            }
          }
        }
        return;
      } else if (payload['currentPresences'] != null) {
        presenceList = payload['currentPresences'] as List;
      }
    } else if (payload is List) {
      presenceList = payload;
    }

    if (presenceList != null) {
      for (final presenceState in presenceList) {
        if (presenceState is Map && presenceState['presences'] is List) {
          final presences = presenceState['presences'] as List;
          for (final presence in presences) {
            if (presence is Map<String, dynamic>) {
              final userId = presence['user_id'] as String?;
              if (userId != null) {
                _participants[userId] = Participant(
                  userId: userId,
                  name: presence['user_name'] as String? ?? 'Unknown',
                  color: presence['color'] as int? ?? Colors.grey.value,
                  joinedAt: DateTime.tryParse(presence['joined_at'] as String? ?? '') ?? DateTime.now(),
                );
              }
            }
          }
        }
      }
    }
  }

  /// Rate limiting check
  bool _canPerformAction() {
    if (_currentUserId == null) return false;

    final now = DateTime.now();
    final userActions = _userActionHistory.putIfAbsent(_currentUserId!, () => []);

    // Remove actions older than 1 second
    userActions.removeWhere((time) => now.difference(time).inSeconds >= 1);

    if (userActions.length >= _maxActionsPerSecond) {
      return false;
    }

    userActions.add(now);
    return true;
  }

  /// Handle connection errors with auto-reconnection
  void _handleConnectionError(dynamic error) {
    debugPrint('Connection error: $error');
    _updateConnectionStatus(ConnectionStatus.error);

    if (_reconnectionAttempts < _maxReconnectionAttempts) {
      _scheduleReconnection();
    } else {
      _sessionEventsController.add(SessionEvent.connectionFailed());
    }
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnection() {
    final delay = Duration(
      seconds: _baseReconnectionDelay.inSeconds * math.pow(2, _reconnectionAttempts).toInt(),
    );

    _reconnectionTimer?.cancel();
    _reconnectionTimer = Timer(delay, () async {
      try {
        _reconnectionAttempts++;
        _updateConnectionStatus(ConnectionStatus.reconnecting);

        if (_currentSessionId != null) {
          await _setupRealtimeChannels();
          await _trackUserPresence();
          _updateConnectionStatus(ConnectionStatus.connected);
          _resetReconnectionState();
          _sessionEventsController.add(SessionEvent.reconnected());
        }
      } catch (e) {
        _handleConnectionError(e);
      }
    });
  }

  /// Reset reconnection state
  void _resetReconnectionState() {
    _reconnectionAttempts = 0;
    _reconnectionTimer?.cancel();
  }

  /// Update connection status
  void _updateConnectionStatus(ConnectionStatus status) {
    if (_connectionStatus != status) {
      _connectionStatus = status;
      _connectionStatusController.add(status);
    }
  }

  /// Update session activity timestamp
  void _updateSessionActivity() {
    _lastActivity = DateTime.now();

    // Update database activity timestamp periodically
    _activityTimer?.cancel();
    _activityTimer = Timer(const Duration(minutes: 1), () async {
      if (_currentSessionId != null) {
        try {
          await _supabase
              .from('collaborative_sessions')
              .update({'last_activity_at': DateTime.now().toIso8601String()})
              .eq('id', _currentSessionId!);
        } catch (e) {
          debugPrint('Failed to update session activity: $e');
        }
      }
    });
  }

  /// Generate random user color
  Color _generateUserColor() {
    final colors = [
      Colors.blue, Colors.red, Colors.green, Colors.purple,
      Colors.orange, Colors.teal, Colors.pink, Colors.indigo,
      Colors.amber, Colors.cyan, Colors.lime, Colors.deepOrange,
    ];
    return colors[math.Random().nextInt(colors.length)];
  }

  /// Get active sessions with participant counts
  Future<List<CollaborativeSession>> getActiveSessions({int limit = 20}) async {
    try {
      final response = await _supabase
          .from('collaborative_sessions')
          .select('''
            *,
            users!host_user_id(username, display_name)
          ''')
          .eq('is_active', true)
          .order('last_activity_at', ascending: false)
          .limit(limit);

      final sessions = <CollaborativeSession>[];

      for (final data in response) {
        // Get approximate participant count
        final participantCount = await _getActiveParticipantCount(data['id']);

        sessions.add(CollaborativeSession.fromJson({
          ...data,
          'participant_count': participantCount,
        }));
      }

      return sessions;
    } catch (e) {
      _sessionEventsController.add(SessionEvent.error('Failed to load sessions: $e'));
      return [];
    }
  }

  /// Get active participant count for a session
  Future<int> _getActiveParticipantCount(String sessionId) async {
    try {
      final count = await _supabase
          .from('session_participants')
          .select('user_id')
          .eq('session_id', sessionId)
          .gte('last_seen_at', DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String())
          .count();

      return count.count;
    } catch (e) {
      return 0;
    }
  }

  /// Leave session and cleanup
  Future<void> leaveSession() async {
    try {
      // Flush any pending strokes
      _strokeBatchTimer?.cancel();
      if (_pendingStrokes.isNotEmpty) {
        await _flushStrokeBatch();
      }

      // Untrack presence
      if (_presenceChannel != null) {
        await _presenceChannel!.untrack();
        await _supabase.removeChannel(_presenceChannel!);
      }

      // Close drawing channel
      if (_drawingChannel != null) {
        await _supabase.removeChannel(_drawingChannel!);
      }

      // Update last seen timestamp
      if (_currentSessionId != null && _currentUserId != null) {
        await _supabase
            .from('session_participants')
            .update({'last_seen_at': DateTime.now().toIso8601String()})
            .eq('session_id', _currentSessionId!)
            .eq('user_id', _currentUserId!);
      }

      _sessionEventsController.add(SessionEvent.leftSession());

    } catch (e) {
      debugPrint('Error leaving session: $e');
    } finally {
      // Clean up state
      _cleanup();
    }
  }

  Future<void> joinExistingSession({required String sessionId}) async {
    try {
      // Validate that the session exists and is active
      final session = await Supabase.instance.client
          .from('collaborative_sessions')
          .select()
          .eq('id', sessionId)
          .eq('is_active', true)
          .single();

      if (session == null) {
        throw Exception('Session not found or inactive');
      }

      // Add the current user as a participant
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      await Supabase.instance.client
          .from('session_participants')
          .insert({
        'session_id': sessionId,
        'user_id': currentUser.id,
        'joined_at': DateTime.now().toIso8601String(),
      });

      print('Successfully joined session: $sessionId');
    } catch (e) {
      print('Error joining session: $e');
      rethrow;
    }
  }

  /// Clean up all state and timers
  void _cleanup() {
    _participants.clear();
    _cursorPositions.clear();
    _pendingStrokes.clear();
    _userActionHistory.clear();

    _currentSessionId = null;
    _currentUserId = null;
    _currentUserName = null;
    _currentUserColor = null;

    _strokeBatchTimer?.cancel();
    _reconnectionTimer?.cancel();
    _activityTimer?.cancel();

    _resetReconnectionState();
    _updateConnectionStatus(ConnectionStatus.disconnected);
  }

  /// Dispose all resources
  void dispose() {
    _cleanup();
    _strokesController.close();
    _participantsController.close();
    _cursorPositionsController.close();
    _connectionStatusController.close();
    _sessionEventsController.close();
  }
}

// Enhanced data classes
class CollaborativeStroke {
  final Stroke? stroke;
  final String userId;
  final String userName;
  final Color userColor;
  final bool isClear;
  final bool isUndo;
  final DateTime timestamp;

  CollaborativeStroke({
    required this.stroke,
    required this.userId,
    required this.userName,
    required this.userColor,
    DateTime? timestamp,
    this.isClear = false,
    this.isUndo = false,
  }) : timestamp = timestamp ?? DateTime.now();

  CollaborativeStroke.clear({
    required this.userId,
    required this.userName,
    DateTime? timestamp,
  }) : stroke = null,
        userColor = Colors.transparent,
        isClear = true,
        isUndo = false,
        timestamp = timestamp ?? DateTime.now();

  CollaborativeStroke.undo({
    required this.userId,
    required this.userName,
    DateTime? timestamp,
  }) : stroke = null,
        userColor = Colors.transparent,
        isClear = false,
        isUndo = true,
        timestamp = timestamp ?? DateTime.now();
}

class Participant {
  final String userId;
  final String name;
  final int color;
  final DateTime joinedAt;
  final bool isHost;

  Participant({
    required this.userId,
    required this.name,
    required this.color,
    required this.joinedAt,
    this.isHost = false,
  });
}

class CursorPosition {
  final String userId;
  final Offset position;
  final String userName;
  final Color color;
  final DateTime timestamp;

  CursorPosition({
    required this.userId,
    required this.position,
    required this.userName,
    required this.color,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class CollaborativeSession {
  final String id;
  final String hostUserId;
  final String hostName;
  final String title;
  final bool requiresPassword;
  final int maxParticipants;
  final int currentParticipants;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final Map<String, dynamic>? canvasSettings;

  CollaborativeSession({
    required this.id,
    required this.hostUserId,
    required this.hostName,
    required this.title,
    required this.requiresPassword,
    required this.maxParticipants,
    required this.currentParticipants,
    required this.createdAt,
    required this.lastActivityAt,
    this.canvasSettings,
  });

  factory CollaborativeSession.fromJson(Map<String, dynamic> json) {
    final userData = json['users'] as Map<String, dynamic>?;

    return CollaborativeSession(
      id: json['id'],
      hostUserId: json['host_user_id'],
      hostName: userData?['display_name'] ?? userData?['username'] ?? 'Unknown',
      title: json['title'],
      requiresPassword: json['password'] != null,
      maxParticipants: json['max_participants'],
      currentParticipants: json['participant_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      lastActivityAt: DateTime.parse(json['last_activity_at'] ?? json['created_at']),
      canvasSettings: json['canvas_settings'] != null
          ? jsonDecode(json['canvas_settings']) as Map<String, dynamic>
          : null,
    );
  }
}

// Session events for UI feedback
class SessionEvent {
  final SessionEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  SessionEvent._({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();

  factory SessionEvent.sessionCreated(String sessionId, String title) =>
      SessionEvent._(
        type: SessionEventType.sessionCreated,
        message: 'Session "$title" created',
        data: {'session_id': sessionId, 'title': title},
      );

  factory SessionEvent.joinedSession(String sessionId, String userName) =>
      SessionEvent._(
        type: SessionEventType.joinedSession,
        message: '$userName joined the session',
        data: {'session_id': sessionId, 'user_name': userName},
      );

  factory SessionEvent.leftSession() =>
      SessionEvent._(
        type: SessionEventType.leftSession,
        message: 'Left the session',
      );

  factory SessionEvent.historyLoaded(int strokeCount) =>
      SessionEvent._(
        type: SessionEventType.historyLoaded,
        message: 'Loaded $strokeCount strokes from history',
        data: {'stroke_count': strokeCount},
      );

  factory SessionEvent.reconnected() =>
      SessionEvent._(
        type: SessionEventType.reconnected,
        message: 'Reconnected to session',
      );

  factory SessionEvent.connectionFailed() =>
      SessionEvent._(
        type: SessionEventType.connectionFailed,
        message: 'Failed to connect to session',
      );

  factory SessionEvent.sessionLocked(String byUserName) =>
      SessionEvent._(
        type: SessionEventType.sessionLocked,
        message: 'Session locked by $byUserName',
        data: {'by_user': byUserName},
      );

  factory SessionEvent.userKicked() =>
      SessionEvent._(
        type: SessionEventType.userKicked,
        message: 'You have been removed from the session',
      );

  factory SessionEvent.error(String error) =>
      SessionEvent._(
        type: SessionEventType.error,
        message: error,
      );
}

enum SessionEventType {
  sessionCreated,
  joinedSession,
  leftSession,
  historyLoaded,
  reconnected,
  connectionFailed,
  sessionLocked,
  userKicked,
  error,
}