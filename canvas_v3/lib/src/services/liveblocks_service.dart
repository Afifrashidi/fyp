// lib/src/services/liveblocks_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_drawing_board/src/config/liveblocks_config.dart';
import 'package:flutter_drawing_board/src/domain/models/stroke.dart';

// Define the missing LiveblocksPresence class
class LiveblocksPresence {
  final String userId;
  final String userName;
  final String userColor;
  final Offset? cursor;
  final bool isDrawing;
  final String selectedTool;
  final double strokeSize;
  final String strokeColor;

  LiveblocksPresence({
    required this.userId,
    required this.userName,
    required this.userColor,
    this.cursor,
    this.isDrawing = false,
    this.selectedTool = 'pencil',
    this.strokeSize = 10.0,
    this.strokeColor = '#000000',
  });

  factory LiveblocksPresence.fromJson(Map<String, dynamic> json) {
    return LiveblocksPresence(
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? 'Unknown',
      userColor: json['userColor'] ?? '#000000',
      cursor: json['cursor'] != null
          ? Offset((json['cursor']['x'] as num).toDouble(),
          (json['cursor']['y'] as num).toDouble())
          : null,
      isDrawing: json['isDrawing'] ?? false,
      selectedTool: json['selectedTool'] ?? 'pencil',
      strokeSize: (json['strokeSize'] as num?)?.toDouble() ?? 10.0,
      strokeColor: json['strokeColor'] ?? '#000000',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'userColor': userColor,
      'cursor': cursor != null ? {'x': cursor!.dx, 'y': cursor!.dy} : null,
      'isDrawing': isDrawing,
      'selectedTool': selectedTool,
      'strokeSize': strokeSize,
      'strokeColor': strokeColor,
    };
  }
}

// Define the missing StrokeData class
class StrokeData {
  final Map<String, dynamic> strokeData;
  final String userId;
  final String userName;

  StrokeData({
    required this.strokeData,
    required this.userId,
    required this.userName,
  });
}

// Define the missing LiveblocksImage class
class LiveblocksImage {
  final String id;
  final String url;
  final String userId;
  final String userName;
  final List<double> transform;
  final double width;
  final double height;
  final int timestamp;
  final String? addedBy;

  LiveblocksImage({
    required this.id,
    required this.url,
    required this.userId,
    required this.userName,
    required this.transform,
    required this.width,
    required this.height,
    required this.timestamp,
    this.addedBy,
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
      id: json['id'],
      url: json['url'],
      userId: json['userId'],
      userName: json['userName'],
      transform: List<double>.from(json['transform']),
      width: json['width'].toDouble(),
      height: json['height'].toDouble(),
      timestamp: json['timestamp'],
      addedBy: json['addedBy'],
    );
  }
}

class LiveblocksService {
  static final LiveblocksService _instance = LiveblocksService._internal();
  factory LiveblocksService() => _instance;
  LiveblocksService._internal();

  // Connection properties
  WebSocketChannel? _channel;
  String? _authToken;
  String? _roomId;
  String? _userId;
  String? _userName;
  String? _userRole;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  // Connection state
  LiveblocksConnectionState _connectionState = LiveblocksConnectionState.disconnected;
  bool get isConnected => _connectionState == LiveblocksConnectionState.authenticated;

  // Stream controllers with error handling
  final _connectionController = StreamController<LiveblocksConnectionState>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _strokeController = StreamController<StrokeData>.broadcast();
  final _clearCanvasController = StreamController<String>.broadcast();
  final _presenceController = StreamController<Map<String, LiveblocksPresence>>.broadcast();
  final _imageAddController = StreamController<LiveblocksImage>.broadcast();
  final _imageUpdateController = StreamController<LiveblocksImage>.broadcast();
  final _imageRemoveController = StreamController<String>.broadcast();
  final _canvasSettingsController = StreamController<Map<String, dynamic>>.broadcast();

  // Presence tracking
  final Map<String, LiveblocksPresence> _presenceMap = {};

  // Streams
  Stream<LiveblocksConnectionState> get connectionStream => _connectionController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<StrokeData> get strokeStream => _strokeController.stream;
  Stream<String> get clearCanvasStream => _clearCanvasController.stream;
  Stream<Map<String, LiveblocksPresence>> get presenceStream => _presenceController.stream;
  Stream<LiveblocksImage> get imageAddStream => _imageAddController.stream;
  Stream<LiveblocksImage> get imageUpdateStream => _imageUpdateController.stream;
  Stream<String> get imageRemoveStream => _imageRemoveController.stream;
  Stream<Map<String, dynamic>> get canvasSettingsStream => _canvasSettingsController.stream;

  // Getters
  String? get roomId => _roomId;
  String? get userId => _userId;
  String? get userName => _userName;
  bool get canClearCanvas => _userRole == 'owner' || _userRole == 'editor';

  /// Connect to a Liveblocks room with error handling
  Future<void> enterRoom(
      String roomId, {
        required String userName,
        required Color userColor,
        String? userId,
        String userRole = 'editor',
      }) async {
    try {
      _roomId = roomId;
      _userId = userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
      _userName = userName;
      _userRole = userRole;

      _updateConnectionState(LiveblocksConnectionState.connecting);

      // Step 1: Authenticate with your backend
      debugPrint('Authenticating with backend...');
      final authResponse = await http.post(
        Uri.parse(LiveblocksConfig.authEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'roomId': roomId,
          'userId': _userId,
          'userName': userName,
          'userRole': userRole,
        }),
      ).timeout(const Duration(seconds: 10));

      if (authResponse.statusCode != 200) {
        throw Exception('Authentication failed: ${authResponse.body}');
      }

      final authData = jsonDecode(authResponse.body);
      _authToken = authData['token'];

      debugPrint('Authentication successful, connecting to WebSocket...');
      _updateConnectionState(LiveblocksConnectionState.authenticating);

      // Step 2: Connect to Liveblocks WebSocket
      final wsUri = Uri.parse(
          '${LiveblocksConfig.wsUrl}/room/$roomId/socket?access_token=$_authToken');

      _channel = WebSocketChannel.connect(wsUri);

      // Listen to WebSocket messages
      _channel!.stream.listen(
        _handleWebSocketMessage,
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _handleError('Connection error: $error');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WebSocket closed');
          _handleDisconnect();
          _scheduleReconnect();
        },
      );

      // Mark as connected
      _updateConnectionState(LiveblocksConnectionState.authenticated);

      // Send initial presence
      updatePresence({
        'userId': _userId!,
        'userName': _userName!,
        'userColor': '#${userColor.value.toRadixString(16).substring(2)}',
        'cursor': null,
        'isDrawing': false,
        'selectedTool': 'pencil',
        'strokeSize': 10.0,
        'strokeColor': '#000000',
      });

      // Start ping timer to keep connection alive
      _startPingTimer();

    } catch (e) {
      debugPrint('Failed to enter room: $e');
      _handleError('Failed to connect: $e');
      _scheduleReconnect();
      rethrow;
    }
  }

  /// Handle incoming WebSocket messages with proper error handling
  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      debugPrint('Received: ${data['type']}');

      switch (data['type']) {
        case 'stroke':
          _handleStrokeMessage(data['data']);
          break;
        case 'clear_canvas':
          _handleClearCanvasMessage(data['data']);
          break;
        case 'presence_update':
          _handlePresenceUpdate(data['data']);
          break;
        case 'image_add':
          _handleImageAdd(data['data']);
          break;
        case 'image_update':
          _handleImageUpdate(data['data']);
          break;
        case 'image_remove':
          _handleImageRemove(data['data']);
          break;
        case 'canvas_settings':
          _handleCanvasSettings(data['data']);
          break;
        case 'pong':
        // Keep alive response
          break;
        default:
          debugPrint('Unknown message type: ${data['type']}');
      }
    } catch (e) {
      debugPrint('Error handling message: $e');
      _handleError('Failed to process message: $e');
    }
  }

  void _handleStrokeMessage(Map<String, dynamic> data) {
    try {
      _strokeController.add(StrokeData(
        strokeData: data['stroke'],
        userId: data['userId'],
        userName: data['userName'],
      ));
    } catch (e) {
      debugPrint('Error handling stroke: $e');
    }
  }

  void _handleClearCanvasMessage(Map<String, dynamic> data) {
    _clearCanvasController.add(data['userId']);
  }

  void _handlePresenceUpdate(Map<String, dynamic> data) {
    try {
      final userId = data['userId'] as String;

      if (data['left'] == true) {
        _presenceMap.remove(userId);
      } else {
        _presenceMap[userId] = LiveblocksPresence.fromJson(data);
      }

      _presenceController.add(Map.from(_presenceMap));
    } catch (e) {
      debugPrint('Error handling presence: $e');
    }
  }

  void _handleImageAdd(Map<String, dynamic> data) {
    try {
      _imageAddController.add(LiveblocksImage.fromJson(data));
    } catch (e) {
      debugPrint('Error handling image add: $e');
    }
  }

  void _handleImageUpdate(Map<String, dynamic> data) {
    try {
      _imageUpdateController.add(LiveblocksImage.fromJson(data));
    } catch (e) {
      debugPrint('Error handling image update: $e');
    }
  }

  void _handleImageRemove(Map<String, dynamic> data) {
    _imageRemoveController.add(data['imageId']);
  }

  void _handleCanvasSettings(Map<String, dynamic> data) {
    _canvasSettingsController.add(data);
  }

  /// Broadcast methods with error handling
  void broadcastStroke(Stroke stroke) {
    if (!isConnected || _channel == null) return;

    try {
      final message = jsonEncode({
        'type': 'stroke',
        'data': {
          'userId': _userId,
          'userName': _userName,
          'stroke': stroke.toJson(),
          'timestamp': DateTime.now().toIso8601String(),
        },
      });

      _channel!.sink.add(message);
    } catch (e) {
      debugPrint('Error broadcasting stroke: $e');
      _handleError('Failed to send stroke: $e');
    }
  }

  void broadcastClearCanvas() {
    if (!isConnected || _channel == null || !canClearCanvas) return;

    try {
      final message = jsonEncode({
        'type': 'clear_canvas',
        'data': {
          'userId': _userId,
          'userName': _userName,
          'timestamp': DateTime.now().toIso8601String(),
        },
      });

      _channel!.sink.add(message);
    } catch (e) {
      debugPrint('Error broadcasting clear canvas: $e');
      _handleError('Failed to clear canvas: $e');
    }
  }

  void broadcastImageAdd(LiveblocksImage image) {
    if (!isConnected || _channel == null) return;

    try {
      final message = jsonEncode({
        'type': 'image_add',
        'data': image.toJson(),
      });

      _channel!.sink.add(message);
    } catch (e) {
      debugPrint('Error broadcasting image add: $e');
      _handleError('Failed to add image: $e');
    }
  }

  void broadcastImageUpdate(String imageId, Matrix4 transform) {
    if (!isConnected || _channel == null) return;

    try {
      final message = jsonEncode({
        'type': 'image_update',
        'data': {
          'id': imageId,
          'transform': transform.storage,
          'userId': _userId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      });

      _channel!.sink.add(message);
    } catch (e) {
      debugPrint('Error broadcasting image update: $e');
      _handleError('Failed to update image: $e');
    }
  }

  void broadcastImageRemove(String imageId) {
    if (!isConnected || _channel == null) return;

    try {
      final message = jsonEncode({
        'type': 'image_remove',
        'data': {
          'imageId': imageId,
          'userId': _userId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      });

      _channel!.sink.add(message);
    } catch (e) {
      debugPrint('Error broadcasting image remove: $e');
      _handleError('Failed to remove image: $e');
    }
  }

  void broadcastCanvasSettings(Map<String, dynamic> settings) {
    if (!isConnected || _channel == null) return;

    try {
      final message = jsonEncode({
        'type': 'canvas_settings',
        'data': {
          ...settings,
          'userId': _userId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      });

      _channel!.sink.add(message);
    } catch (e) {
      debugPrint('Error broadcasting canvas settings: $e');
      _handleError('Failed to update settings: $e');
    }
  }

  void updatePresence(Map<String, dynamic> presence) {
    if (!isConnected || _channel == null) return;

    try {
      final message = jsonEncode({
        'type': 'presence_update',
        'data': presence,
      });

      _channel!.sink.add(message);
    } catch (e) {
      debugPrint('Error updating presence: $e');
    }
  }

  /// Broadcast generic message
  void broadcast(String eventType, Map<String, dynamic> data) {
    if (!isConnected || _channel == null) return;

    try {
      final message = jsonEncode({
        'type': eventType,
        'data': {
          ...data,
          'userId': _userId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      });

      _channel!.sink.add(message);
    } catch (e) {
      debugPrint('Error broadcasting $eventType: $e');
      _handleError('Failed to broadcast: $e');
    }
  }

  /// Upload image to Supabase with error handling
  Future<String> uploadImageToSupabase(ui.Image image, String roomId) async {
    try {
      // Convert ui.Image to bytes
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to convert image');

      final bytes = byteData.buffer.asUint8List();
      final fileName = 'collab_${roomId}_${DateTime.now().millisecondsSinceEpoch}.png';
      final path = 'collaborative/$roomId/$fileName';

      // Upload to Supabase storage
      await Supabase.instance.client.storage
          .from('images')
          .uploadBinary(path, bytes);

      // Get public URL
      return Supabase.instance.client.storage
          .from('images')
          .getPublicUrl(path);
    } catch (e) {
      debugPrint('Error uploading image: $e');
      throw Exception('Failed to upload image: $e');
    }
  }

  /// Connection management methods
  void _updateConnectionState(LiveblocksConnectionState state) {
    _connectionState = state;
    _connectionController.add(state);
  }

  void _handleError(String error) {
    _errorController.add(error);
    if (_connectionState != LiveblocksConnectionState.disconnected) {
      _updateConnectionState(LiveblocksConnectionState.error);
    }
  }

  void _handleDisconnect() {
    _updateConnectionState(LiveblocksConnectionState.disconnected);
    _stopPingTimer();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      if (_roomId != null && _userName != null) {
        try {
          await enterRoom(
            _roomId!,
            userName: _userName!,
            userColor: Colors.blue,
            userId: _userId,
            userRole: _userRole ?? 'editor',
          );
        } catch (e) {
          debugPrint('Reconnection failed: $e');
          _scheduleReconnect();
        }
      }
    });
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isConnected && _channel != null) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
        } catch (e) {
          debugPrint('Ping failed: $e');
        }
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
  }

  /// Leave room
  void leaveRoom() {
    _reconnectTimer?.cancel();
    _stopPingTimer();

    if (_channel != null) {
      try {
        // Send leave message
        updatePresence({
          'userId': _userId,
          'left': true,
        });

        _channel!.sink.close();
      } catch (e) {
        debugPrint('Error closing channel: $e');
      }
      _channel = null;
    }

    _presenceMap.clear();
    _updateConnectionState(LiveblocksConnectionState.disconnected);
    _roomId = null;
    _authToken = null;
  }

  void dispose() {
    leaveRoom();
    _connectionController.close();
    _errorController.close();
    _strokeController.close();
    _clearCanvasController.close();
    _presenceController.close();
    _imageAddController.close();
    _imageUpdateController.close();
    _imageRemoveController.close();
    _canvasSettingsController.close();
  }
}