// lib/src/services/liveblocks_service.dart
// CRITICAL FIXES for collaborative room connection issues

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/network_enums.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_drawing_board/src/constants/app_constants.dart';
import 'package:flutter_drawing_board/src/domain/models/stroke.dart';
import 'package:flutter_drawing_board/src/services/error_handling_service.dart';

/// Enhanced Liveblocks service with proper error handling and rate limiting
class LiveblocksService {
  static final LiveblocksService _instance = LiveblocksService._internal();
  factory LiveblocksService() => _instance;
  LiveblocksService._internal();

  // Connection state
  LiveblocksConnectionState _connectionState = LiveblocksConnectionState.disconnected;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // Room and user info
  String? _roomId;
  String? _userId;
  String? _userName;
  String? _userRole;

  // Rate limiting timers
  Timer? _strokeThrottle;
  Timer? _presenceThrottle;
  Timer? _cursorThrottle;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  // Event streams
  final StreamController<LiveblocksConnectionState> _connectionController =
  StreamController<LiveblocksConnectionState>.broadcast();
  final StreamController<String> _errorController =
  StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
  StreamController<Map<String, dynamic>>.broadcast();

  // Specific event streams for collaborative drawing
  final StreamController<Map<String, dynamic>> _strokeController =
  StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _clearCanvasController =
  StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _presenceController =
  StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _imageController =
  StreamController<Map<String, dynamic>>.broadcast();

  // Error handling
  final ErrorHandlingService _errorHandler = ErrorHandlingService();
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectBaseDelay = Duration(seconds: 2);

  // Message queue for offline mode
  final List<Map<String, dynamic>> _messageQueue = [];
  static const int maxQueueSize = 100;

  // Store current presence data
  final Map<String, dynamic> _currentPresence = {};

  // Getters
  String? get roomId => _roomId;
  String? get userId => _userId;
  String? get userName => _userName;
  String? get userRole => _userRole;
  bool get isConnected => _connectionState == LiveblocksConnectionState.connected;
  LiveblocksConnectionState get connectionState => _connectionState;
  String? get sessionId => _roomId;

  // Streams
  Stream<LiveblocksConnectionState> get connectionStream => _connectionController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get strokeStream => _strokeController.stream;
  Stream<Map<String, dynamic>> get clearStream => _clearCanvasController.stream;
  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;
  Stream<Map<String, dynamic>> get imageStream => _imageController.stream;

  /// Join a collaborative session - updated method name for consistency
  Future<void> joinSession(String sessionId) async {
    try {
      _updateConnectionState(LiveblocksConnectionState.connecting);

      // Store session info
      _roomId = sessionId;
      _userId = _userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
      _userName = _userName ?? 'Anonymous';
      _userRole = _userRole ?? 'editor';

      // Get authentication token from backend
      final authToken = await _getAuthToken(
        roomId: sessionId,
        userId: _userId!,
        userName: _userName!,
        userColor: Colors.blue, // Default color
        userRole: _userRole!,
      );

      if (authToken == null) {
        throw Exception('Failed to get authentication token');
      }

      // Connect to Liveblocks WebSocket
      await _connectWebSocket(authToken);

      // Start ping timer to keep connection alive
      _startPingTimer();

      // Reset reconnection state on successful connection
      _resetReconnectionState();

      debugPrint('Successfully joined session: $sessionId as $_userName');
    } catch (e, stackTrace) {
      await _errorHandler.handleError(
        AppError.collaborative(e, sessionId: sessionId),
        showToUser: true,
      );
      _updateConnectionState(LiveblocksConnectionState.error);
      _scheduleReconnect();
      rethrow;
    }
  }

  /// Enter a collaborative room with enhanced error handling
  Future<void> enterRoom(
      String roomId, {
        required String userName,
        required Color userColor,
        String? userId,
        String? userRole,
      }) async {
    try {
      _updateConnectionState(LiveblocksConnectionState.connecting);

      // Store room info
      _roomId = roomId;
      _userId = userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
      _userName = userName;
      _userRole = userRole ?? 'editor';

      // Get authentication token from backend
      final authToken = await _getAuthToken(
        roomId: roomId,
        userId: _userId!,
        userName: userName,
        userColor: userColor,
        userRole: _userRole!,
      );

      if (authToken == null) {
        throw Exception('Failed to get authentication token');
      }

      // Connect to Liveblocks WebSocket
      await _connectWebSocket(authToken);

      // Start ping timer to keep connection alive
      _startPingTimer();

      // Reset reconnection state on successful connection
      _resetReconnectionState();

      debugPrint('Successfully entered room: $roomId as $userName');
    } catch (e, stackTrace) {
      await _errorHandler.handleError(
        AppError.collaborative(e, sessionId: roomId),
        showToUser: true,
      );
      _updateConnectionState(LiveblocksConnectionState.error);
      _scheduleReconnect();
      rethrow;
    }
  }

  /// Leave room method
  Future<void> leaveRoom() async {
    await disconnect();
  }

  /// Leave session method for consistency
  Future<void> leaveSession() async {
    await disconnect();
  }

  /// CRITICAL FIX: Get authentication token from backend with enhanced error handling
  Future<String?> _getAuthToken({
    required String roomId,
    required String userId,
    required String userName,
    required Color userColor,
    required String userRole,
  }) async {
    const maxAttempts = 3;
    int attempts = 0;

    while (attempts < maxAttempts) {
      try {
        attempts++;
        debugPrint('Attempting to get auth token (attempt $attempts/$maxAttempts)');

        // Get user token from Supabase if authenticated
        String? userToken;
        try {
          final session = Supabase.instance.client.auth.currentSession;
          userToken = session?.accessToken;
        } catch (e) {
          debugPrint('No Supabase session available: $e');
          // Continue without user token for guest users
        }

        // CRITICAL FIX: Use correct backend URL and add timeout
        const backendUrl = String.fromEnvironment('BACKEND_URL',
            defaultValue: 'http://localhost:3001');
        final uri = Uri.parse('$backendUrl/api/liveblocks-auth');

        debugPrint('Requesting auth token from: $uri');

        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'room': roomId,
            'userId': userId,
            'userName': userName,
            'userColor': userColor.value.toRadixString(16),
            'userRole': userRole,
            'userToken': userToken,
          }),
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('Auth request timeout', const Duration(seconds: 10)),
        );

        debugPrint('Auth response status: ${response.statusCode}');
        debugPrint('Auth response body: ${response.body}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final token = data['token'] as String?;

          if (token != null && token.isNotEmpty) {
            debugPrint('Successfully obtained auth token');
            return token;
          } else {
            throw Exception('Invalid token received from server');
          }
        } else {
          final errorData = jsonDecode(response.body);
          throw Exception('Auth failed: ${errorData['error'] ?? 'Unknown error'} (${response.statusCode})');
        }

      } on TimeoutException catch (e) {
        debugPrint('Auth request timeout (attempt $attempts): $e');
        if (attempts == maxAttempts) {
          throw Exception('Backend server not responding. Please check if the server is running.');
        }
      } on SocketException catch (e) {
        debugPrint('Network error (attempt $attempts): $e');
        if (attempts == maxAttempts) {
          throw Exception('Cannot connect to backend server. Please check your network connection.');
        }
      } catch (e) {
        debugPrint('Auth error (attempt $attempts): $e');
        if (attempts == maxAttempts) rethrow;
      }

      // Wait before retry
      if (attempts < maxAttempts) {
        await Future.delayed(Duration(seconds: attempts));
      }
    }

    throw Exception('Failed to get authentication token after $maxAttempts attempts');
  }

  /// CRITICAL FIX: Connect to Liveblocks WebSocket with enhanced error handling
  Future<void> _connectWebSocket(String token) async {
    try {
      // CRITICAL FIX: Use correct Liveblocks WebSocket URL
      const liveblocksUrl = String.fromEnvironment('LIVEBLOCKS_WS_URL',
          defaultValue: 'wss://liveblocks.net/v1/websocket');

      final uri = Uri.parse('$liveblocksUrl?token=$token');
      debugPrint('Connecting to Liveblocks WebSocket: $uri');

      // Close existing connection if any
      await _subscription?.cancel();
      await _channel?.sink.close();

      // Create new WebSocket connection with timeout
      _channel = WebSocketChannel.connect(uri);

      // Wait for connection with timeout
      await _channel!.ready.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('WebSocket connection timeout'),
      );

      debugPrint('WebSocket connected successfully');

      // Set up message listener
      _subscription = _channel!.stream.timeout(
        const Duration(seconds: 30),
        onTimeout: (sink) => sink.close(),
      ).listen(
        _handleWebSocketMessage,
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _updateConnectionState(LiveblocksConnectionState.error);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          if (_connectionState != LiveblocksConnectionState.disconnected) {
            _updateConnectionState(LiveblocksConnectionState.disconnected);
            _scheduleReconnect();
          }
        },
      );

      // Send initial presence
      await Future.delayed(const Duration(milliseconds: 500));
      await _sendInitialPresence();

      _updateConnectionState(LiveblocksConnectionState.connected);
      debugPrint('Successfully connected to Liveblocks');

    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _updateConnectionState(LiveblocksConnectionState.error);

      // Provide specific error messages
      if (e is TimeoutException) {
        throw Exception('Connection timeout. Please check your internet connection.');
      } else if (e is WebSocketException) {
        throw Exception('WebSocket connection failed. Please try again.');
      } else {
        throw Exception('Failed to connect to Liveblocks: $e');
      }
    }
  }

  /// Send initial presence to establish user in room
  Future<void> _sendInitialPresence() async {
    try {
      final presenceData = {
        'type': 'presence',
        'data': {
          'userId': _userId,
          'userName': _userName,
          'userRole': _userRole,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'isConnected': true,
        },
      };

      await _sendMessage(presenceData);
      debugPrint('Initial presence sent');
    } catch (e) {
      debugPrint('Failed to send initial presence: $e');
    }
  }

  /// Enhanced error messages for better debugging
  String _getDetailedErrorMessage(dynamic error) {
    if (error is TimeoutException) {
      return 'Connection timeout - please check your internet connection';
    } else if (error is SocketException) {
      return 'Network error - cannot reach the server';
    } else if (error.toString().contains('401') || error.toString().contains('Unauthorized')) {
      return 'Authentication failed - please try signing in again';
    } else if (error.toString().contains('404')) {
      return 'Room not found - please check the room ID';
    } else if (error.toString().contains('403') || error.toString().contains('Forbidden')) {
      return 'Access denied - you may not have permission to join this room';
    } else if (error.toString().contains('Backend server not responding')) {
      return 'Server is temporarily unavailable - please try again later';
    } else {
      return 'Connection failed: ${error.toString()}';
    }
  }

  /// Create room with better error handling
  Future<Map<String, dynamic>?> createRoom(String roomName, String userId) async {
    try {
      debugPrint('Creating room: $roomName for user: $userId');

      const backendUrl = String.fromEnvironment('BACKEND_URL',
          defaultValue: 'http://localhost:3001');
      final uri = Uri.parse('$backendUrl/api/rooms/create');

      // Get user token
      String? userToken;
      try {
        final session = Supabase.instance.client.auth.currentSession;
        userToken = session?.accessToken;
      } catch (e) {
        debugPrint('No Supabase session: $e');
      }

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'roomName': roomName,
          'userId': userId,
          'userToken': userToken,
        }),
      ).timeout(const Duration(seconds: 10));

      debugPrint('Create room response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Room created successfully: ${data['roomId']}');
        return data;
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to create room');
      }

    } catch (e) {
      debugPrint('Room creation error: $e');
      final detailedError = _getDetailedErrorMessage(e);
      throw Exception(detailedError);
    }
  }

  /// Validate room ID format
  bool isValidRoomId(String roomId) {
    // Room IDs should match the format: room_timestamp_randomstring
    final pattern = RegExp(r'^room_\d+_[a-zA-Z0-9]{9}$');
    return pattern.hasMatch(roomId) && roomId.length >= 15;
  }

  /// Enhanced room joining with validation
  Future<void> joinRoom(String roomId, {
    required String userName,
    required Color userColor,
    String? userId,
    String? userRole,
  }) async {
    try {
      // Validate room ID format
      if (!isValidRoomId(roomId)) {
        throw Exception('Invalid room ID format. Please check the room ID and try again.');
      }

      debugPrint('Attempting to join room: $roomId');

      await enterRoom(
        roomId,
        userName: userName,
        userColor: userColor,
        userId: userId,
        userRole: userRole,
      );

    } catch (e) {
      debugPrint('Failed to join room $roomId: $e');
      final detailedError = _getDetailedErrorMessage(e);
      throw Exception('Cannot join room: $detailedError');
    }
  }

  /// Handle incoming WebSocket messages - renamed to avoid conflicts
  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      switch (data['type']) {
        case 'room-state':
          _handleRoomState(data);
          break;
        case 'user-joined':
          _handleUserJoined(data);
          break;
        case 'user-left':
          _handleUserLeft(data);
          break;
        case 'presence-update':
          _handlePresenceUpdate(data);
          break;
        case 'broadcast':
          _handleBroadcast(data);
          break;
        case 'error':
          _handleServerError(data);
          break;
        default:
          debugPrint('Unknown message type: ${data['type']}');
      }

      // Emit message to listeners
      _messageController.add(data);
    } catch (e) {
      debugPrint('Error handling message: $e');
    }
  }

  void _handleRoomState(Map<String, dynamic> data) {
    debugPrint('Room state updated: ${data.keys}');

    // Handle presence data from room state
    if (data['presence'] != null) {
      _presenceController.add(data['presence']);
    }
  }

  void _handleUserJoined(Map<String, dynamic> data) {
    final userName = data['user']?['name'] ?? 'Unknown';
    debugPrint('User joined: $userName');
  }

  void _handleUserLeft(Map<String, dynamic> data) {
    final userName = data['user']?['name'] ?? 'Unknown';
    debugPrint('User left: $userName');
  }

  void _handlePresenceUpdate(Map<String, dynamic> data) {
    // Handle presence updates from other users
    if (kDebugMode && DebugConfig.logVerbose) {
      debugPrint('Presence update: ${data['userId']}');
    }

    // Forward presence updates to stream
    _presenceController.add(data);
  }

  void _handleBroadcast(Map<String, dynamic> data) {
    // Handle broadcast messages
    final eventData = data['event'];
    if (eventData != null) {
      final eventType = eventData['type'];
      debugPrint('Broadcast received: $eventType');

      // Handle different broadcast types
      switch (eventType) {
        case 'stroke-add':
          _strokeController.add(eventData);
          break;
        case 'canvas-clear':
          _clearCanvasController.add(eventData);
          break;
        case 'image-add':
        case 'image-update':
        case 'image-delete':
          _imageController.add(eventData);
          break;
        default:
          debugPrint('Unknown broadcast type: $eventType');
      }
    }
  }

  void _handleServerError(Map<String, dynamic> data) {
    final errorMessage = data['message'] ?? 'Unknown server error';
    debugPrint('Server error: $errorMessage');
    _errorController.add(errorMessage);
  }

  /// Send message with rate limiting and queuing
  Future<void> _sendMessage(Map<String, dynamic> message) async {
    try {
      if (_channel?.sink != null && isConnected) {
        final jsonMessage = jsonEncode(message);
        _channel!.sink.add(jsonMessage);

        if (kDebugMode && DebugConfig.logVerbose) {
          debugPrint('Sent message: ${message['type']}');
        }
      } else {
        // Queue message for when connection is restored
        _queueMessage(message);
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      _queueMessage(message);
    }
  }

  /// Queue message for offline mode
  void _queueMessage(Map<String, dynamic> message) {
    if (_messageQueue.length >= maxQueueSize) {
      _messageQueue.removeAt(0); // Remove oldest
    }
    _messageQueue.add(message);
  }

  /// Process queued messages after reconnection
  void _processMessageQueue() {
    if (_messageQueue.isNotEmpty && isConnected) {
      final messages = List<Map<String, dynamic>>.from(_messageQueue);
      _messageQueue.clear();

      for (final message in messages) {
        _sendMessage(message);
      }

      debugPrint('Processed ${messages.length} queued messages');
    }
  }

  /// Broadcast stroke method - accepts Map<String, dynamic>
  void broadcastStroke(Map<String, dynamic> strokeData) {
    _strokeThrottle?.cancel();
    _strokeThrottle = Timer(AppConstants.strokeBroadcastDebounce, () {
      _sendMessage({
        'type': 'broadcast',
        'event': {
          'type': 'stroke-add',
          'stroke': strokeData,
          'userId': strokeData['userId'] ?? _userId,
          'timestamp': strokeData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        },
      });
    });
  }

  /// Broadcast stroke object - accepts Stroke object
  void broadcastStrokeObject(Stroke stroke) {
    _strokeThrottle?.cancel();
    _strokeThrottle = Timer(AppConstants.strokeBroadcastDebounce, () {
      _sendMessage({
        'type': 'broadcast',
        'event': {
          'type': 'stroke-add',
          'stroke': stroke.toJson(),
          'userId': _userId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      });
    });
  }

  /// Broadcast clear canvas
  void broadcastClearCanvas() {
    _sendMessage({
      'type': 'broadcast',
      'event': {
        'type': 'canvas-clear',
        'userId': _userId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }

  /// Broadcast message - generic method
  Future<void> broadcastMessage(Map<String, dynamic> message) async {
    await _sendMessage({
      'type': 'broadcast',
      'event': message,
    });
  }

  Future<void> broadcastImageUpdate(String imageId, Matrix4 transform) async {
    await _sendMessage({
      'type': 'broadcast',
      'event': {
        'type': 'image-update',
        'imageId': imageId,
        'transform': transform.storage,
        'userId': _userId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }

  /// Broadcast image deletion
  Future<void> broadcastImageDelete(String imageId) async {
    await _sendMessage({
      'type': 'broadcast',
      'event': {
        'type': 'image-delete',
        'imageId': imageId,
        'userId': _userId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }

  /// Broadcast image transform (alias for broadcastImageUpdate)
  Future<void> broadcastImageTransform(String imageId, Matrix4 transform) async {
    await broadcastImageUpdate(imageId, transform);
  }

  /// Broadcast image addition
  Future<void> broadcastImageAdd(LiveblocksImage imageData) async {
    await _sendMessage({
      'type': 'broadcast',
      'event': {
        'type': 'image-add',
        'image': imageData.toJson(),
        'userId': _userId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }

  /// Broadcast canvas settings
  void broadcastCanvasSettings(Map<String, dynamic> settings) {
    _sendMessage({
      'type': 'broadcast',
      'event': {
        'type': 'canvas-settings',
        'settings': settings,
        'userId': _userId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }

  /// Update presence with throttling
  Future<void> updatePresence(Map<String, dynamic> presence) async {
    _currentPresence.addAll(presence);

    _presenceThrottle?.cancel();
    _presenceThrottle = Timer(AppConstants.presenceUpdateInterval, () {
      _sendMessage({
        'type': 'update-presence',
        'presence': _currentPresence,
      });
    });
  }

  /// Upload image to Supabase with error handling
  Future<String> uploadImageToSupabase(ui.Image image, String roomId) async {
    try {
      // Validate inputs
      if (roomId.isEmpty) {
        throw Exception('Room ID cannot be empty');
      }

      // Convert ui.Image to bytes
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Failed to convert image to bytes');
      }

      final bytes = byteData.buffer.asUint8List();
      final fileName = 'collab_${roomId}_${DateTime.now().millisecondsSinceEpoch}.png';
      final path = 'collaborative/$roomId/$fileName';

      // Upload with timeout and retry
      const maxAttempts = 3;
      int attempts = 0;

      while (attempts < maxAttempts) {
        try {
          attempts++;

          await Supabase.instance.client.storage
              .from('images')
              .uploadBinary(path, bytes)
              .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
              'Image upload timeout',
              const Duration(seconds: 30),
            ),
          );

          // Get public URL
          final url = Supabase.instance.client.storage
              .from('images')
              .getPublicUrl(path);

          debugPrint('Image uploaded successfully: $path');
          return url;
        } catch (e) {
          if (attempts >= maxAttempts) {
            throw Exception('Failed to upload image after $maxAttempts attempts: $e');
          }

          // Exponential backoff
          await Future.delayed(Duration(seconds: attempts * 2));
        }
      }

      throw Exception('Upload failed after maximum attempts');
    } catch (e) {
      await _errorHandler.handleError(
        AppError.network(e),
        showToUser: true,
      );
      rethrow;
    }
  }

  /// Start ping timer to keep connection alive
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (isConnected) {
        _sendMessage({'type': 'ping'});
      } else {
        timer.cancel();
      }
    });
  }

  /// Stop ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      _updateConnectionState(LiveblocksConnectionState.error);
      _errorController.add('Max reconnection attempts reached');
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(
      seconds: reconnectBaseDelay.inSeconds * (1 << (_reconnectAttempts - 1)),
    );

    debugPrint('Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');

    _updateConnectionState(LiveblocksConnectionState.reconnecting);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_roomId != null && _userName != null) {
        try {
          await enterRoom(
            _roomId!,
            userName: _userName!,
            userColor: Colors.blue, // Default color for reconnection
            userId: _userId,
            userRole: _userRole,
          );
        } catch (e) {
          debugPrint('Reconnection attempt $_reconnectAttempts failed: $e');
          _scheduleReconnect();
        }
      }
    });
  }

  /// Reset reconnection state after successful connection
  void _resetReconnectionState() {
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Update connection state and notify listeners
  void _updateConnectionState(LiveblocksConnectionState state) {
    if (_connectionState != state) {
      _connectionState = state;
      _connectionController.add(state);

      // Process queued messages after successful connection
      if (state == LiveblocksConnectionState.connected) {
        _processMessageQueue();
      }
    }
  }

  /// Disconnect from the collaborative session
  Future<void> disconnect() async {
    try {
      _updateConnectionState(LiveblocksConnectionState.disconnected);

      // Cancel all timers
      _strokeThrottle?.cancel();
      _presenceThrottle?.cancel();
      _cursorThrottle?.cancel();
      _reconnectTimer?.cancel();
      _stopPingTimer();

      // Close WebSocket connection
      await _subscription?.cancel();
      await _channel?.sink.close();

      _subscription = null;
      _channel = null;

      // Clear room info
      _roomId = null;
      _userId = null;
      _userName = null;
      _userRole = null;

      // Clear message queue
      _messageQueue.clear();
      _currentPresence.clear();

      // Reset reconnection state
      _resetReconnectionState();

      debugPrint('Disconnected from collaborative session');
    } catch (e) {
      debugPrint('Error during disconnect: $e');
    }
  }

  /// Get connection statistics for debugging
  Map<String, dynamic> getConnectionStats() {
    return {
      'connectionState': _connectionState.name,
      'roomId': _roomId,
      'userId': _userId,
      'userName': _userName,
      'reconnectAttempts': _reconnectAttempts,
      'queuedMessages': _messageQueue.length,
      'isConnected': isConnected,
    };
  }

  /// Set user info (useful when reconnecting or initializing)
  void setUserInfo({
    String? userId,
    String? userName,
    String? userRole,
  }) {
    _userId = userId ?? _userId;
    _userName = userName ?? _userName;
    _userRole = userRole ?? _userRole;
  }

  /// Dispose the service
  void dispose() {
    disconnect();
    _connectionController.close();
    _errorController.close();
    _messageController.close();
    _strokeController.close();
    _clearCanvasController.close();
    _presenceController.close();
    _imageController.close();
  }
}

/// Data model for Liveblocks image
class LiveblocksImage {
  final String id;
  final String url;
  final String userId;
  final String userName;
  final List<double> transform;
  final double width;
  final double height;
  final int timestamp;
  final String addedBy;

  LiveblocksImage({
    required this.id,
    required this.url,
    required this.userId,
    required this.userName,
    required this.transform,
    required this.width,
    required this.height,
    required this.timestamp,
    required this.addedBy,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'userId': userId,
      'userName': userName,
      'transform': transform,
      'width': width,
      'height': height,
      'timestamp': timestamp,
      'addedBy': addedBy,
    };
  }

  factory LiveblocksImage.fromJson(Map<String, dynamic> json) {
    return LiveblocksImage(
      id: json['id'] as String,
      url: json['url'] as String,
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      transform: List<double>.from(json['transform']),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      timestamp: json['timestamp'] as int,
      addedBy: json['addedBy'] as String,
    );
  }
}