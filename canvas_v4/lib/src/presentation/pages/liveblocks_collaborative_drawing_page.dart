// lib/src/presentation/pages/liveblocks_collaborative_drawing_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';
import 'package:flutter_drawing_board/src/constants/canvas_operations_enums.dart';
import 'package:flutter_drawing_board/src/constants/network_enums.dart';
import 'package:flutter_drawing_board/src/domain/domain.dart';
import 'package:flutter_drawing_board/src/domain/models/unified_undo_redo_stack.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/current_stroke_value_notifier.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/presentation/widgets/drawing_canvas.dart';
import 'package:flutter_drawing_board/src/presentation/widgets/canvas_side_bar.dart';
import 'package:flutter_drawing_board/src/presentation/widgets/hot_key_listener.dart';
import 'package:flutter_drawing_board/src/services/liveblocks_service.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';
import 'package:flutter_drawing_board/src/services/error_handling_service.dart';
import 'package:flutter_drawing_board/src/presentation/widgets/image_interaction_handler.dart';

class LiveblocksCollaborativeDrawingPage extends StatefulWidget {
  final String roomId;
  final String userName;
  final Color userColor;
  final bool isHost;

  LiveblocksCollaborativeDrawingPage({
    super.key,
    String? roomId,
    String? userName,
    Color? userColor,
    this.isHost = false,
  }) : roomId = roomId ?? _generateDefaultRoomId(),
        userName = userName ?? 'Guest User',
        userColor = userColor ?? Colors.blue;

  static String _generateDefaultRoomId() => 'room_${DateTime.now().millisecondsSinceEpoch}';

  @override
  State<LiveblocksCollaborativeDrawingPage> createState() => _LiveblocksCollaborativeDrawingPageState();
}

class _LiveblocksCollaborativeDrawingPageState extends State<LiveblocksCollaborativeDrawingPage>
    with TickerProviderStateMixin {

  // Core drawing state
  late CurrentStrokeValueNotifier currentStroke;
  late ValueNotifier<List<Stroke>> allStrokes;
  late ValueNotifier<ui.Image?> backgroundImage;
  late ImageNotifier imageNotifier;
  late UnifiedUndoRedoStack unifiedUndoRedoStack;

  // Drawing options
  final ValueNotifier<DrawingTool> drawingTool = ValueNotifier(DrawingTool.pencil);
  final ValueNotifier<Color> selectedColor = ValueNotifier(Colors.black);
  final ValueNotifier<double> strokeSize = ValueNotifier(AppConstants.defaultStrokeSize);
  final ValueNotifier<double> eraserSize = ValueNotifier(AppConstants.defaultEraserSize);
  final ValueNotifier<double> opacity = ValueNotifier(AppConstants.defaultOpacity);
  final ValueNotifier<bool> filled = ValueNotifier(false);
  final ValueNotifier<int> polygonSides = ValueNotifier(AppConstants.defaultPolygonSides);
  final ValueNotifier<bool> showGrid = ValueNotifier(false);
  final ValueNotifier<bool> snapToGrid = ValueNotifier(false);

  // Canvas and animation
  final GlobalKey canvasGlobalKey = GlobalKey();
  late AnimationController _sidebarAnimationController;
  late AnimationController _presenceAnimationController;
  bool _isSidebarVisible = true;

  // Collaborative features
  late LiveblocksService _liveblocksService;
  final AuthService _authService = AuthService();
  final ErrorHandlingService _errorHandlingService = ErrorHandlingService();

  // Connection state
  final ValueNotifier<LiveblocksConnectionState> connectionStatus =
  ValueNotifier(LiveblocksConnectionState.disconnected);

  // User presence
  final ValueNotifier<Map<String, LiveblocksPresence>> remoteUsers = ValueNotifier({});
  String? _currentUserId;
  LiveblocksPresence? _currentUserPresence;

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  // Interaction handling
  late ImageInteractionHandler _imageInteractionHandler;

  // Cursor tracking
  Timer? _cursorBroadcastTimer;
  Offset? _lastCursorPosition;
  bool _isCurrentlyDrawing = false;

  // Stroke tracking
  final Set<String> _processedStrokes = {};
  Timer? _strokeBroadcastTimer;

  @override
  void initState() {
    super.initState();

    _initializeNotifiers();
    _initializeAnimations();
    _initializeUndoRedoSystem();
    _initializeCollaborativeServices();
    _setupListeners();
    _initializeSession();
  }

  void _initializeNotifiers() {
    currentStroke = CurrentStrokeValueNotifier();
    allStrokes = ValueNotifier<List<Stroke>>([]);
    backgroundImage = ValueNotifier<ui.Image?>(null);
    imageNotifier = ImageNotifier();

    _imageInteractionHandler = ImageInteractionHandler(
      imageNotifier,
      onImageStateChanged: _onImageStateChanged,
    );
  }

  void _initializeAnimations() {
    _sidebarAnimationController = AnimationController(
      vsync: this,
      duration: AppConstants.sideBarAnimationDuration,
    );

    _presenceAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _sidebarAnimationController.forward(); // Start with sidebar visible
    _presenceAnimationController.repeat(reverse: true);
  }

  void _initializeUndoRedoSystem() {
    unifiedUndoRedoStack = UnifiedUndoRedoStack(
      currentStrokeNotifier: currentStroke,
      strokesNotifier: allStrokes,
      imageNotifier: imageNotifier,
    );
  }

  void _initializeCollaborativeServices() {
    _liveblocksService = LiveblocksService();
    _currentUserId = _authService.getUserId();

    // Create current user presence
    _currentUserPresence = LiveblocksPresence(
      userId: _currentUserId!,
      userName: widget.userName,
      userColor: '#${widget.userColor.value.toRadixString(16).padLeft(8, '0').substring(2)}',
      color: widget.userColor.value,
      isDrawing: false,
      cursor: null,
    );
  }

  void _setupListeners() {
    // Connection status listener
    _subscriptions.add(
      _liveblocksService.connectionStream.listen((connectionState) {
        if (mounted) {
          setState(() {
            connectionStatus.value = connectionState;
          });
        }
      }),
    );

    // Stroke stream listener
    _subscriptions.add(
      _liveblocksService.strokeStream.listen(_onRemoteStrokeReceived),
    );

    // Canvas clear listener
    _subscriptions.add(
      _liveblocksService.clearStream.listen(_onRemoteCanvasClear),
    );

    // Presence stream listener
    _subscriptions.add(
      _liveblocksService.presenceStream.listen(_onPresenceUpdate),
    );

    // Handle user join/leave through presence updates
    // (No separate userJoinStream/userLeaveStream needed)

    // Image stream listener
    _subscriptions.add(
      _liveblocksService.imageStream.listen(_onRemoteImageReceived),
    );

    // Local state listeners
    allStrokes.addListener(_onLocalStrokeAdded);
    imageNotifier.addListener(_onLocalImageChanged);
    drawingTool.addListener(_onDrawingToolChanged);
    selectedColor.addListener(_onColorChanged);
    strokeSize.addListener(_onStrokeSizeChanged);
  }

  Future<void> _initializeSession() async {
    try {
      setState(() {
        connectionStatus.value = LiveblocksConnectionState.connecting;
      });

      // Join the Liveblocks room
      await _liveblocksService.enterRoom(
        widget.roomId,
        userName: widget.userName,
        userColor: widget.userColor,
        userId: _currentUserId!,
        userRole: widget.isHost ? 'owner' : 'editor',
      );

      // Update presence
      await _updatePresence();

      if (mounted) {
        setState(() {
          connectionStatus.value = LiveblocksConnectionState.connected;
        });
      }

      _showSnackBar('Connected to room: ${widget.roomId}', AppColors.success);

    } catch (e) {
      debugPrint('Failed to initialize session: $e');
      if (mounted) {
        setState(() {
          connectionStatus.value = LiveblocksConnectionState.error;
        });
      }
      _showSnackBar('Failed to connect to room', AppColors.error);
      await _errorHandlingService.handleCollaborativeError(e, sessionId: widget.roomId);
    }
  }

  Future<void> _updatePresence({
    Offset? cursor,
    bool? isDrawing,
  }) async {
    if (_currentUserPresence == null) return;

    final updatedPresence = LiveblocksPresence(
      userId: _currentUserPresence!.userId,
      userName: _currentUserPresence!.userName,
      userColor: _currentUserPresence!.userColor,
      color: _currentUserPresence!.color,
      cursor: cursor,
      isDrawing: isDrawing ?? _isCurrentlyDrawing,
    );

    _currentUserPresence = updatedPresence;

    try {
      await _liveblocksService.updatePresence({
        'userId': updatedPresence.userId,
        'userName': updatedPresence.userName,
        'userColor': updatedPresence.userColor,
        'color': updatedPresence.color,
        'cursor': cursor != null ? {'x': cursor.dx, 'y': cursor.dy} : null,
        'isDrawing': updatedPresence.isDrawing,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('Failed to update presence: $e');
    }
  }

  // Event handlers
  void _onImageStateChanged() {
    _broadcastImageState();
  }

  void _onDrawingToolChanged() {
    // Update presence when tool changes
    _updatePresence();
  }

  void _onColorChanged() {
    // Update presence when color changes
    _updatePresence();
  }

  void _onStrokeSizeChanged() {
    // Update presence when stroke size changes
    _updatePresence();
  }

  void _onLocalStrokeAdded() {
    final strokes = allStrokes.value;
    if (strokes.isEmpty) return;

    final latestStroke = strokes.last;
    final strokeId = 'stroke_${DateTime.now().millisecondsSinceEpoch}_${latestStroke.hashCode}';

    // Avoid duplicate broadcasts
    if (_processedStrokes.contains(strokeId)) return;
    _processedStrokes.add(strokeId);

    // Debounce stroke broadcasting
    _strokeBroadcastTimer?.cancel();
    _strokeBroadcastTimer = Timer(AppConstants.strokeBroadcastDebounce, () {
      _broadcastStroke(latestStroke, strokeId);
    });
  }

  void _broadcastStroke(Stroke stroke, String strokeId) {
    final strokeData = {
      'id': strokeId,
      'userId': _currentUserId,
      'userName': widget.userName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'stroke': stroke.toJson(),
    };

    _liveblocksService.broadcastStroke(strokeData);
  }

  void _onLocalImageChanged() {
    _broadcastImageState();
  }

  void _broadcastImageState() {
    final imageData = imageNotifier.value.imageList.map((image) => {
      'id': image.id,
      'position': [image.position.dx, image.position.dy],
      'size': [image.size.width, image.size.height],
      'rotation': image.rotation,
      'transform': image.transform.storage,
    }).toList();

    _liveblocksService.broadcastMessage({
      'type': 'image_state',
      'images': imageData,
      'userId': _currentUserId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _onRemoteStrokeReceived(Map<String, dynamic> strokeData) {
    // Don't process strokes from current user
    if (strokeData['userId'] == _currentUserId) return;

    try {
      final strokeInfo = strokeData['stroke'] as Map<String, dynamic>;
      final strokeId = strokeData['id'] as String;

      // Avoid duplicate processing
      if (_processedStrokes.contains(strokeId)) return;
      _processedStrokes.add(strokeId);

      // Create stroke from JSON data
      final stroke = Stroke.fromJson(strokeInfo);

      if (stroke != null) {
        // Add to canvas without triggering local broadcast
        final currentStrokes = List<Stroke>.from(allStrokes.value);
        currentStrokes.add(stroke);
        allStrokes.value = currentStrokes;
      }

    } catch (e) {
      debugPrint('Error processing remote stroke: $e');
      _errorHandlingService.handleCanvasError(e, operation: 'receive_remote_stroke');
    }
  }

  void _onRemoteCanvasClear(Map<String, dynamic> clearData) {
    if (clearData['userId'] == _currentUserId) return;

    setState(() {
      allStrokes.value = [];
      currentStroke.clear();
      imageNotifier.clearAll();
    });

    _showSnackBar('Canvas cleared by ${clearData['userName'] ?? 'someone'}', AppColors.warning);
  }

  void _onPresenceUpdate(Map<String, dynamic> presenceData) {
    try {
      final newUsers = <String, LiveblocksPresence>{};
      final previousUsers = Map<String, LiveblocksPresence>.from(remoteUsers.value);

      presenceData.forEach((userId, data) {
        if (data is Map<String, dynamic> && userId != _currentUserId) {
          final presence = LiveblocksPresence.fromJson(data);
          newUsers[userId] = presence;

          // Check if this is a new user (user joined)
          if (!previousUsers.containsKey(userId)) {
            _onUserJoined({'userId': userId, 'userName': presence.userName});
          }
        }
      });

      // Check for users who left
      for (final userId in previousUsers.keys) {
        if (!newUsers.containsKey(userId)) {
          _onUserLeft(userId);
        }
      }

      if (mounted) {
        setState(() {
          remoteUsers.value = newUsers;
        });
      }
    } catch (e) {
      debugPrint('Error updating presence: $e');
    }
  }

  void _onUserJoined(Map<String, dynamic> userData) {
    final userName = userData['userName'] ?? 'Unknown User';
    _showSnackBar('$userName joined the room', AppColors.info);
  }

  void _onUserLeft(String userId) {
    final presence = remoteUsers.value[userId];
    if (presence != null) {
      _showSnackBar('${presence.userName} left the room', AppColors.info);
    }
  }

  void _onRemoteImageReceived(Map<String, dynamic> imageData) {
    if (imageData['userId'] == _currentUserId) return;

    try {
      // Handle remote image updates
      final images = imageData['images'] as List? ?? [];
      // Process image data based on your image model structure
    } catch (e) {
      debugPrint('Error processing remote image: $e');
    }
  }

  // Drawing event handlers
  void _onDrawingStrokeChanged(Stroke? stroke) {
    if (stroke != null) {
      // Stroke started or updated
      _isCurrentlyDrawing = true;
      _updatePresence(isDrawing: true);
    } else {
      // Stroke ended
      _isCurrentlyDrawing = false;
      _updatePresence(isDrawing: false);
    }
  }

  void _handleCursorMove(Offset position) {
    _lastCursorPosition = position;

    // Debounce cursor updates
    _cursorBroadcastTimer?.cancel();
    _cursorBroadcastTimer = Timer(AppConstants.presenceUpdateInterval, () {
      if (_lastCursorPosition != null && mounted) {
        _updatePresence(cursor: _lastCursorPosition);
      }
    });
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarVisible = !_isSidebarVisible;
    });

    if (_isSidebarVisible) {
      _sidebarAnimationController.forward();
    } else {
      _sidebarAnimationController.reverse();
    }
  }

  void _clearCanvas() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Clear Canvas'),
          ],
        ),
        content: const Text(
          'This will clear the canvas for everyone in the room. '
              'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performCanvasClear();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear Canvas', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _performCanvasClear() {
    // Clear locally
    setState(() {
      allStrokes.value = [];
      currentStroke.clear();
      imageNotifier.clearAll();
      unifiedUndoRedoStack.clear();
    });

    // Broadcast clear to other users
    _liveblocksService.broadcastClearCanvas();
    _showSnackBar('Canvas cleared for all participants', AppColors.success);
  }

  Future<void> _leaveRoom() async {
    try {
      await _liveblocksService.leaveRoom();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error leaving room: $e');
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  void _shareRoom() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.share, color: Colors.blue),
            SizedBox(width: 8),
            Text('Share Room'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share this room ID with others:'),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: SelectableText(
                widget.roomId,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<Map<String, LiveblocksPresence>>(
              valueListenable: remoteUsers,
              builder: (context, users, _) {
                final activeUsers = users.values.where((u) => u.isActive).length;
                return Text(
                  'Active participants: ${activeUsers + 1}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.roomId));
              Navigator.pop(context);
              _showSnackBar('Room ID copied to clipboard', AppColors.success);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy ID'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // Enhanced app bar
          _CollaborativeAppBar(
            roomId: widget.roomId,
            userName: widget.userName,
            userColor: widget.userColor,
            connectionStatus: connectionStatus,
            remoteUsers: remoteUsers,
            onToggleSidebar: _toggleSidebar,
            onLeaveRoom: _leaveRoom,
            onShareRoom: _shareRoom,
            onClearCanvas: _clearCanvas,
          ),

          // Main content
          Expanded(
            child: HotkeyListener(
              onUndo: unifiedUndoRedoStack.undo,
              onRedo: unifiedUndoRedoStack.redo,
              child: MouseRegion(
                onHover: (event) => _handleCursorMove(event.localPosition),
                child: Row(
                  children: [
                    // Animated sidebar
                    AnimatedContainer(
                      duration: AppConstants.sideBarAnimationDuration,
                      width: _isSidebarVisible ? 280 : 0,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(-1, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: _sidebarAnimationController,
                          curve: Curves.easeInOut,
                        )),
                        child: _isSidebarVisible
                            ? CanvasSideBar(
                          drawingTool: drawingTool,
                          selectedColor: selectedColor,
                          strokeSize: strokeSize,
                          currentSketch: currentStroke,
                          allSketches: allStrokes,
                          canvasGlobalKey: canvasGlobalKey,
                          filled: filled,
                          polygonSides: polygonSides,
                          backgroundImage: backgroundImage,
                          undoRedoStack: unifiedUndoRedoStack,
                          showGrid: showGrid,
                          snapToGrid: snapToGrid,
                          imageNotifier: imageNotifier,
                        )
                            : const SizedBox.shrink(),
                      ),
                    ),

                    // Main canvas area
                    Expanded(
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: const BoxDecoration(
                          color: Colors.grey,
                        ),
                        child: Stack(
                          children: [
                            // Drawing canvas
                            DrawingCanvas(
                              options: DrawingCanvasOptions(
                                currentTool: drawingTool.value,
                                size: strokeSize.value,
                                strokeColor: selectedColor.value,
                                backgroundColor: AppColors.canvasBackground,
                                opacity: opacity.value,
                                polygonSides: polygonSides.value,
                                showGrid: showGrid.value,
                                snapToGrid: snapToGrid.value,
                                fillShape: filled.value,
                              ),
                              canvasKey: canvasGlobalKey,
                              currentStrokeListenable: currentStroke,
                              strokesListenable: allStrokes,
                              backgroundImageListenable: backgroundImage,
                              imageNotifier: imageNotifier,
                              onDrawingStrokeChanged: _onDrawingStrokeChanged,
                            ),

                            // Remote user cursors
                            ...remoteUsers.value.entries
                                .where((entry) => entry.value.cursor != null)
                                .map((entry) => _buildUserCursor(entry.key, entry.value)),

                            // Connection status overlay
                            _buildConnectionStatusOverlay(),

                            // Sidebar toggle button (when hidden)
                            if (!_isSidebarVisible)
                              Positioned(
                                top: 16,
                                left: 16,
                                child: _buildSidebarToggleButton(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCursor(String userId, LiveblocksPresence presence) {
    return Positioned(
      left: presence.cursor!.dx - 10,
      top: presence.cursor!.dy - 10,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Color(presence.color ?? Colors.blue.value).withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    presence.userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (presence.isDrawing) ...[
                    const SizedBox(width: 4),
                    AnimatedBuilder(
                      animation: _presenceAnimationController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: 0.5 + (_presenceAnimationController.value * 0.5),
                          child: const Icon(
                            Icons.edit,
                            size: 10,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 2),
            // Enhanced cursor
            CustomPaint(
              size: const Size(20, 20),
              painter: _CollaborativeCursorPainter(
                color: Color(presence.color ?? Colors.blue.value),
                isDrawing: presence.isDrawing,
                animationValue: _presenceAnimationController.value,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatusOverlay() {
    return ValueListenableBuilder<LiveblocksConnectionState>(
      valueListenable: connectionStatus,
      builder: (context, status, _) {
        if (status == LiveblocksConnectionState.connected) {
          return const SizedBox.shrink();
        }

        String message;
        Color backgroundColor;
        IconData icon;

        switch (status) {
          case LiveblocksConnectionState.connecting:
            message = 'Connecting to room...';
            backgroundColor = AppColors.warning;
            icon = Icons.wifi_protected_setup;
            break;
          case LiveblocksConnectionState.reconnecting:
            message = 'Reconnecting...';
            backgroundColor = AppColors.warning;
            icon = Icons.refresh;
            break;
          case LiveblocksConnectionState.disconnected:
            message = 'Disconnected from room';
            backgroundColor = AppColors.error;
            icon = Icons.wifi_off;
            break;
          case LiveblocksConnectionState.error:
            message = 'Connection error';
            backgroundColor = AppColors.error;
            icon = Icons.error;
            break;
          default:
            return const SizedBox.shrink();
        }

        return Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebarToggleButton() {
    return FloatingActionButton.small(
      onPressed: _toggleSidebar,
      backgroundColor: Colors.white,
      child: const Icon(Icons.menu, color: Colors.black),
    );
  }

  @override
  void dispose() {
    // Cancel timers
    _cursorBroadcastTimer?.cancel();
    _strokeBroadcastTimer?.cancel();

    // Cancel subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // Dispose controllers and notifiers
    _sidebarAnimationController.dispose();
    _presenceAnimationController.dispose();
    currentStroke.dispose();
    allStrokes.dispose();
    backgroundImage.dispose();
    imageNotifier.dispose();
    unifiedUndoRedoStack.dispose();

    drawingTool.dispose();
    selectedColor.dispose();
    strokeSize.dispose();
    eraserSize.dispose();
    opacity.dispose();
    filled.dispose();
    polygonSides.dispose();
    showGrid.dispose();
    snapToGrid.dispose();
    connectionStatus.dispose();
    remoteUsers.dispose();

    // Dispose interaction handler
    _imageInteractionHandler.dispose();

    // Leave collaborative session
    _liveblocksService.leaveRoom();

    super.dispose();
  }
}

// Enhanced collaborative app bar
class _CollaborativeAppBar extends StatelessWidget {
  final String roomId;
  final String userName;
  final Color userColor;
  final ValueNotifier<LiveblocksConnectionState> connectionStatus;
  final ValueNotifier<Map<String, LiveblocksPresence>> remoteUsers;
  final VoidCallback onToggleSidebar;
  final VoidCallback onLeaveRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onClearCanvas;

  const _CollaborativeAppBar({
    required this.roomId,
    required this.userName,
    required this.userColor,
    required this.connectionStatus,
    required this.remoteUsers,
    required this.onToggleSidebar,
    required this.onLeaveRoom,
    required this.onShareRoom,
    required this.onClearCanvas,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Sidebar toggle
            IconButton(
              onPressed: onToggleSidebar,
              icon: const Icon(Icons.menu),
              tooltip: 'Toggle Sidebar',
            ),

            // Back button
            IconButton(
              onPressed: onLeaveRoom,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Leave Room',
            ),

            const SizedBox(width: 16),

            // Room info
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Collaborative Drawing',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Room: ${roomId.length > 12 ? '${roomId.substring(0, 12)}...' : roomId}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            // Connection status
            ValueListenableBuilder<LiveblocksConnectionState>(
              valueListenable: connectionStatus,
              builder: (context, status, _) {
                String label;
                Color color;
                IconData icon;

                switch (status) {
                  case LiveblocksConnectionState.connected:
                    label = 'LIVE';
                    color = AppColors.success;
                    icon = Icons.circle;
                    break;
                  case LiveblocksConnectionState.connecting:
                    label = 'CONNECTING';
                    color = AppColors.warning;
                    icon = Icons.sync;
                    break;
                  case LiveblocksConnectionState.reconnecting:
                    label = 'RECONNECTING';
                    color = AppColors.warning;
                    icon = Icons.refresh;
                    break;
                  case LiveblocksConnectionState.error:
                    label = 'ERROR';
                    color = AppColors.error;
                    icon = Icons.error;
                    break;
                  case LiveblocksConnectionState.disconnected:
                    label = 'OFFLINE';
                    color = Colors.grey;
                    icon = Icons.circle_outlined;
                    break;
                  default:
                    label = 'UNKNOWN';
                    color = Colors.grey;
                    icon = Icons.help;
                }

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: Colors.white, size: 12),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(width: 16),

            // Participants indicator
            ValueListenableBuilder<Map<String, LiveblocksPresence>>(
              valueListenable: remoteUsers,
              builder: (context, users, _) {
                final activeUsers = users.values.where((u) => u.isActive).toList();

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Current user avatar
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: userColor,
                        child: Text(
                          userName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      // Other user avatars (max 3)
                      ...activeUsers.take(3).map((user) => Container(
                        margin: const EdgeInsets.only(left: 4),
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: Color(user.color ?? Colors.blue.value),
                          child: Text(
                            user.userName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )),

                      if (activeUsers.length > 3) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+${activeUsers.length - 3}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(width: 8),
                      Text(
                        '${activeUsers.length + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(width: 8),

            // Action menu
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'share':
                    onShareRoom();
                    break;
                  case 'clear':
                    onClearCanvas();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share, size: 16),
                      SizedBox(width: 8),
                      Text('Share Room'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.clear_all, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Clear Canvas', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.more_vert, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Enhanced collaborative cursor painter
class _CollaborativeCursorPainter extends CustomPainter {
  final Color color;
  final bool isDrawing;
  final double animationValue;

  _CollaborativeCursorPainter({
    required this.color,
    this.isDrawing = false,
    this.animationValue = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    if (isDrawing) {
      // Drawing indicator - animated pulsing circle
      final center = Offset(size.width / 2, size.height / 2);
      final radius = 4 + (animationValue * 4);

      // Outer glow
      paint
        ..color = color.withOpacity(0.3 + (animationValue * 0.4))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius + 2, paint);

      // Inner circle
      paint
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, paint);

      // White border
      paint
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, paint);
    } else {
      // Normal cursor arrow
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(0, 16)
        ..lineTo(5, 12)
        ..lineTo(8, 19)
        ..lineTo(11, 17)
        ..lineTo(8, 10)
        ..lineTo(14, 10)
        ..close();

      // Drop shadow
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.save();
      canvas.translate(1, 1);
      canvas.drawPath(path, shadowPaint);
      canvas.restore();

      // Main cursor
      paint
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, paint);

      // White border
      paint
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>
      oldDelegate is _CollaborativeCursorPainter &&
          (oldDelegate.color != color ||
              oldDelegate.isDrawing != isDrawing ||
              oldDelegate.animationValue != animationValue);
}