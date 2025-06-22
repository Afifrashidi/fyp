// lib/src/presentation/pages/collaborative_drawing_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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

class CollaborativeDrawingPage extends StatefulWidget {
  final String? sessionId;
  final bool isHost;

  const CollaborativeDrawingPage({
    super.key,
    this.sessionId,
    this.isHost = false,
  });

  @override
  State<CollaborativeDrawingPage> createState() => _CollaborativeDrawingPageState();
}

class _CollaborativeDrawingPageState extends State<CollaborativeDrawingPage>
    with TickerProviderStateMixin {
  // Services
  final _liveblocksService = LiveblocksService();
  final _authService = AuthService();
  final _errorHandlingService = ErrorHandlingService();

  // Animation controller for sidebar
  late final AnimationController animationController;

  // Drawing state
  final ValueNotifier<Color> selectedColor = ValueNotifier(Colors.black);
  final ValueNotifier<double> strokeSize = ValueNotifier(10.0);
  final ValueNotifier<double> opacity = ValueNotifier(1.0);
  final ValueNotifier<DrawingTool> drawingTool = ValueNotifier(DrawingTool.pencil);
  final GlobalKey canvasGlobalKey = GlobalKey();
  final ValueNotifier<bool> filled = ValueNotifier(false);
  final ValueNotifier<int> polygonSides = ValueNotifier(3);
  final ValueNotifier<ui.Image?> backgroundImage = ValueNotifier(null);
  final CurrentStrokeValueNotifier currentStroke = CurrentStrokeValueNotifier();
  final ValueNotifier<List<Stroke>> allStrokes = ValueNotifier([]);
  late final UnifiedUndoRedoStack undoRedoStack;
  final ValueNotifier<bool> showGrid = ValueNotifier(false);
  final ValueNotifier<bool> snapToGrid = ValueNotifier(false);
  final ImageNotifier imageNotifier = ImageNotifier();

  // Collaborative state
  final ValueNotifier<Map<String, LiveblocksPresence>> participants = ValueNotifier({});
  final ValueNotifier<LiveblocksConnectionState> connectionStatus =
  ValueNotifier(LiveblocksConnectionState.disconnected);
  String? _currentSessionId;
  String _sessionTitle = 'Collaborative Drawing';
  late Color _userColor;
  String? _currentUserId;

  // Track local strokes to avoid duplicates
  final Set<String> _localStrokeIds = {};

  // Mouse position tracking for cursor sharing
  Timer? _cursorBroadcastTimer;
  Offset? _lastCursorPosition;

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();

    animationController = AnimationController(
      vsync: this,
      duration: AppConstants.sideBarAnimationDuration,
    );

    undoRedoStack = UnifiedUndoRedoStack(
      currentStrokeNotifier: currentStroke,
      strokesNotifier: allStrokes,
      imageNotifier: imageNotifier,
    );

    _userColor = _generateUserColor();
    _currentSessionId = widget.sessionId ?? 'session-${DateTime.now().millisecondsSinceEpoch}';
    _initializeSession();

    // Listen to local strokes for broadcasting
    allStrokes.addListener(_onLocalStrokeAdded);
  }

  Color _generateUserColor() {
    final colors = [
      Colors.blue, Colors.red, Colors.green, Colors.purple,
      Colors.orange, Colors.teal, Colors.pink, Colors.indigo,
      Colors.amber, Colors.cyan, Colors.lime, Colors.deepOrange,
    ];
    return colors[math.Random().nextInt(colors.length)];
  }

  Future<void> _initializeSession() async {
    try {
      // Get user info
      final currentUser = _authService.currentUser;
      final userName = currentUser?.email?.split('@')[0] ?? 'Guest User';
      _currentUserId = currentUser?.id ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';

      // Determine role
      final userRole = widget.isHost ? 'owner' : 'editor';

      // Connect to Liveblocks
      await _liveblocksService.enterRoom(
        _currentSessionId!,
        userName: userName,
        userColor: _userColor,
        userId: _currentUserId!,
        userRole: userRole,
      );

      // Set up listeners for real-time updates
      _setupLiveblocksListeners();

      setState(() {
        connectionStatus.value = LiveblocksConnectionState.connected;
      });

    } catch (e) {
      debugPrint('Failed to initialize session: $e');
      _showErrorSnackBar('Failed to connect to session');
      setState(() {
        connectionStatus.value = LiveblocksConnectionState.error;
      });
    }
  }

  void _setupLiveblocksListeners() {
    // Listen for connection status changes
    _subscriptions.add(
      _liveblocksService.connectionStream.listen((connectionState) {
        setState(() {
          connectionStatus.value = connectionState;
        });
      }),
    );

    // Listen for strokes from other users
    _subscriptions.add(
      _liveblocksService.strokeStream.listen((strokeData) {
        _onRemoteStrokeReceived(strokeData);
      }),
    );

    // Listen for canvas clear events
    _subscriptions.add(
      _liveblocksService.clearStream.listen((_) {
        _onRemoteCanvasCleared();
      }),
    );

    // Listen for presence updates
    _subscriptions.add(
      _liveblocksService.presenceStream.listen((presenceData) {
        _onPresenceUpdated(presenceData);
      }),
    );

    // REMOVED: userJoinStream and userLeaveStream listeners
    // User join/leave events are now handled through presence updates
  }

  void _onRemoteStrokeReceived(Map<String, dynamic> strokeData) {
    try {
      // Don't process strokes from current user
      if (strokeData['userId'] == _currentUserId) return;

      // Extract stroke data
      final strokeInfo = strokeData['stroke'] as Map<String, dynamic>;
      final tool = _parseDrawingTool(strokeInfo['tool'] ?? 'pencil');
      final points = (strokeInfo['points'] as List? ?? [])
          .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList();
      final color = Color(strokeInfo['color'] ?? Colors.black.value);
      final size = (strokeInfo['size'] ?? 5.0).toDouble();
      final opacity = (strokeInfo['opacity'] ?? 1.0).toDouble();
      final filled = strokeInfo['filled'] ?? false;

      // Create the appropriate stroke type
      final Stroke stroke;
      switch (tool) {
        case DrawingTool.pencil:
          stroke = NormalStroke(
            points: points,
            color: color,
            size: size,
            opacity: opacity,
          );
          break;
        case DrawingTool.eraser:
          stroke = EraserStroke(
            points: points,
            color: color,
            size: size,
            opacity: opacity,
          );
          break;
        case DrawingTool.line:
          stroke = LineStroke(
            points: points,
            color: color,
            size: size,
            opacity: opacity,
          );
          break;
        case DrawingTool.rectangle:
          stroke = RectangleStroke(
            points: points,
            color: color,
            size: size,
            opacity: opacity,
            filled: filled,
          );
          break;
        case DrawingTool.square:
          stroke = SquareStroke(
            points: points,
            color: color,
            size: size,
            opacity: opacity,
            filled: filled,
          );
          break;
        case DrawingTool.circle:
          stroke = CircleStroke(
            points: points,
            color: color,
            size: size,
            opacity: opacity,
            filled: filled,
          );
          break;
        case DrawingTool.polygon:
          stroke = PolygonStroke(
            points: points,
            sides: strokeInfo['sides'] ?? 3,
            color: color,
            size: size,
            opacity: opacity,
            filled: filled,
          );
          break;
        case DrawingTool.text:
          stroke = TextStroke(
            points: points,
            text: strokeInfo['text'] ?? '',
            fontSize: strokeInfo['fontSize']?.toDouble() ?? 16.0,
            fontFamily: strokeInfo['fontFamily'],
            color: color,
            size: size,
            opacity: opacity,
          );
          break;
        default:
          stroke = NormalStroke(
            points: points,
            color: color,
            size: size,
            opacity: opacity,
          );
      }

      // Add stroke to canvas
      setState(() {
        final currentStrokes = List<Stroke>.from(allStrokes.value);
        currentStrokes.add(stroke);
        allStrokes.value = currentStrokes;
      });

    } catch (e) {
      _errorHandlingService.handleCanvasError(e, operation: 'receive_remote_stroke');
    }
  }

  DrawingTool _parseDrawingTool(String toolString) {
    switch (toolString.toLowerCase()) {
      case 'pencil': return DrawingTool.pencil;
      case 'eraser': return DrawingTool.eraser;
      case 'line': return DrawingTool.line;
      case 'rectangle': return DrawingTool.rectangle;
      case 'square': return DrawingTool.square;
      case 'circle': return DrawingTool.circle;
      case 'polygon': return DrawingTool.polygon;
      case 'text': return DrawingTool.text;
      default: return DrawingTool.pencil;
    }
  }

  void _onRemoteCanvasCleared() {
    setState(() {
      allStrokes.value = [];
      imageNotifier.removeAllImages();
    });
  }

  void _onPresenceUpdated(Map<String, dynamic> presenceData) {
    try {
      final newParticipants = <String, LiveblocksPresence>{};
      final previousParticipants = Map<String, LiveblocksPresence>.from(participants.value);

      presenceData.forEach((userId, data) {
        if (data is Map<String, dynamic> && userId != _currentUserId) {
          final presence = LiveblocksPresence.fromJson(data);
          newParticipants[userId] = presence;

          // Check if this is a new user (user joined)
          if (!previousParticipants.containsKey(userId)) {
            _onUserJoined({'userId': userId, 'userName': presence.displayName});
          }
        }
      });

      // Check for users who left (were in previous but not in new)
      for (final userId in previousParticipants.keys) {
        if (!newParticipants.containsKey(userId)) {
          _onUserLeft(userId);
        }
      }

      setState(() {
        participants.value = newParticipants;
      });
    } catch (e) {
      debugPrint('Error updating presence: $e');
    }
  }

  void _onUserJoined(Map<String, dynamic> userData) {
    final userName = userData['userName'] ?? 'Unknown User';
    _showInfoSnackBar('$userName joined the session');
  }

  void _onUserLeft(String userId) {
    final presence = participants.value[userId];
    if (presence != null) {
      _showInfoSnackBar('${presence.displayName} left the session');
    }
    // Note: participants.value is already updated in _onPresenceUpdated
  }

  void _onLocalStrokeAdded() {
    final currentStrokes = allStrokes.value;
    if (currentStrokes.isEmpty) return;

    // Get the last stroke
    final lastStroke = currentStrokes.last;

    // Generate a unique ID for this stroke
    final strokeId = '${DateTime.now().millisecondsSinceEpoch}_${lastStroke.hashCode}';

    // Check if we've already broadcast this stroke
    if (!_localStrokeIds.contains(strokeId)) {
      _localStrokeIds.add(strokeId);

      // Create stroke data for broadcasting
      final strokeData = {
        'userId': _currentUserId,
        'userName': _authService.currentUser?.email?.split('@')[0] ?? 'Guest',
        'stroke': lastStroke.toJson(),
        'timestamp': DateTime.now().toIso8601String(),
        'strokeId': strokeId,
      };

      // Broadcast the stroke
      _liveblocksService.broadcastStroke(strokeData);
    }
  }

  void _handleMouseMove(Offset position) {
    _lastCursorPosition = position;
    _cursorBroadcastTimer?.cancel();
    _cursorBroadcastTimer = Timer(AppConstants.strokeBroadcastDebounce, () {
      if (_lastCursorPosition != null && mounted) {
        _updatePresence(cursor: _lastCursorPosition);
      }
    });
  }

  void _updatePresence({
    Offset? cursor,
    bool? isDrawing,
    String? selectedTool,
    double? strokeSize,
    String? strokeColor,
  }) {
    final presenceData = {
      'userId': _currentUserId,
      'userName': _authService.currentUser?.email?.split('@')[0] ?? 'Guest',
      'userColor': '#${_userColor.value.toRadixString(16).substring(2)}',
      'cursor': cursor != null ? {'x': cursor.dx, 'y': cursor.dy} : null,
      'isDrawing': isDrawing ?? currentStroke.value != null,
      'selectedTool': selectedTool ?? drawingTool.value.toString().split('.').last,
      'strokeSize': strokeSize ?? this.strokeSize.value,
      'strokeColor': strokeColor ?? '#${selectedColor.value.value.toRadixString(16).substring(2)}',
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
    };

    _liveblocksService.updatePresence(presenceData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvasBackground,
      body: HotkeyListener(
        onRedo: undoRedoStack.redo,
        onUndo: undoRedoStack.undo,
        child: MouseRegion(
          onHover: (event) => _handleMouseMove(event.localPosition),
          child: Stack(
            children: [
              // Main drawing canvas
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    currentStroke,
                    allStrokes,
                    selectedColor,
                    strokeSize,
                    drawingTool,
                    filled,
                    polygonSides,
                    backgroundImage,
                    showGrid,
                    snapToGrid,
                    opacity,
                    imageNotifier,
                  ]),
                  builder: (context, _) {
                    return Stack(
                      children: [
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
                          onDrawingStrokeChanged: (stroke) {
                            if (stroke != null) {
                              // Stroke started or updated
                              _updatePresence(isDrawing: true);
                            } else {
                              // Stroke ended
                              _updatePresence(isDrawing: false);
                            }
                          },
                        ),
                        // Remote user cursors overlay
                        ..._buildRemoteCursors(),
                      ],
                    );
                  },
                ),
              ),

              // Animated sidebar
              Positioned(
                top: kToolbarHeight + 10,
                left: 0,
                child: AnimatedContainer(
                  duration: AppConstants.sideBarAnimationDuration,
                  width: animationController.value == 1.0 ? 280 : 0,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(-1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animationController,
                      curve: Curves.easeInOut,
                    )),
                    child: CanvasSideBar(
                      drawingTool: drawingTool,
                      selectedColor: selectedColor,
                      strokeSize: strokeSize,
                      currentSketch: currentStroke,
                      allSketches: allStrokes,
                      canvasGlobalKey: canvasGlobalKey,
                      filled: filled,
                      polygonSides: polygonSides,
                      backgroundImage: backgroundImage,
                      undoRedoStack: undoRedoStack,
                      showGrid: showGrid,
                      snapToGrid: snapToGrid,
                      imageNotifier: imageNotifier,
                    ),
                  ),
                ),
              ),

              // Enhanced app bar
              _CollaborativeAppBar(
                animationController: animationController,
                title: _sessionTitle,
                sessionId: _currentSessionId,
                participants: participants,
                connectionStatus: connectionStatus,
                onShare: _shareSession,
                onLeave: () => _leaveSession(),
                onClearCanvas: _clearCanvas,
              ),

              // Quick access toolbar for selected images
              ValueListenableBuilder<ImageState>(
                valueListenable: imageNotifier,
                builder: (context, imageState, _) {
                  if (imageState.selectedIds.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Positioned(
                    top: kToolbarHeight + 10,
                    right: 10,
                    child: _QuickImageToolbar(
                      imageNotifier: imageNotifier,
                    ),
                  );
                },
              ),

              // Connection status overlay
              _buildConnectionStatusOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRemoteCursors() {
    return participants.value.entries
        .where((entry) =>
    entry.value.cursor != null &&
        entry.key != _currentUserId &&
        entry.value.isActive)
        .map((entry) {
      final presence = entry.value;
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
                  color: presence.getEffectiveColor().withOpacity(0.9),
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
                      presence.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (presence.isDrawing) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.edit,
                        size: 10,
                        color: Colors.white,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 2),
              // Cursor pointer
              CustomPaint(
                size: const Size(20, 20),
                painter: _CursorPainter(
                  color: presence.getEffectiveColor(),
                  isDrawing: presence.isDrawing,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
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
            message = 'Connecting to session...';
            backgroundColor = AppColors.warning;
            icon = Icons.wifi_protected_setup;
            break;
          case LiveblocksConnectionState.reconnecting:
            message = 'Reconnecting...';
            backgroundColor = AppColors.warning;
            icon = Icons.refresh;
            break;
          case LiveblocksConnectionState.disconnected:
            message = 'Disconnected from session';
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
          top: kToolbarHeight + 10,
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

  void _shareSession() {
    if (_currentSessionId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.share, color: Colors.blue),
            SizedBox(width: 8),
            Text('Share Session'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share this session code with others:'),
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
                _currentSessionId!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Participants: ${participants.value.length + 1}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
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
              // Copy to clipboard functionality would go here
              Navigator.pop(context);
              _showInfoSnackBar('Session code copied to clipboard');
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Code'),
          ),
        ],
      ),
    );
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
          'This will clear the canvas for everyone in the session. '
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
              // Clear locally
              setState(() {
                allStrokes.value = [];
                imageNotifier.removeAllImages();
                undoRedoStack.clear();
              });
              // Broadcast clear
              _liveblocksService.broadcastClearCanvas();
              _showInfoSnackBar('Canvas cleared for all participants');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear Canvas', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveSession() async {
    try {
      // Leave the Liveblocks room
      await _liveblocksService.leaveRoom();

      // Navigate back
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error leaving session: $e');
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showInfoSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: AppColors.info,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _cursorBroadcastTimer?.cancel();
    allStrokes.removeListener(_onLocalStrokeAdded);

    // Cancel subscriptions
    for (final sub in _subscriptions) {
      sub.cancel();
    }

    // Leave room
    _liveblocksService.leaveRoom();

    // Clean up controllers and notifiers
    animationController.dispose();
    selectedColor.dispose();
    strokeSize.dispose();
    opacity.dispose();
    drawingTool.dispose();
    currentStroke.dispose();
    allStrokes.dispose();
    undoRedoStack.dispose();
    filled.dispose();
    polygonSides.dispose();
    backgroundImage.dispose();
    showGrid.dispose();
    snapToGrid.dispose();
    imageNotifier.dispose();
    connectionStatus.dispose();
    participants.dispose();

    super.dispose();
  }
}

// Enhanced collaborative app bar
class _CollaborativeAppBar extends StatelessWidget {
  final AnimationController animationController;
  final String title;
  final String? sessionId;
  final ValueNotifier<LiveblocksConnectionState> connectionStatus;
  final ValueNotifier<Map<String, LiveblocksPresence>> participants;
  final VoidCallback onShare;
  final VoidCallback onLeave;
  final VoidCallback onClearCanvas;

  const _CollaborativeAppBar({
    required this.animationController,
    required this.title,
    required this.sessionId,
    required this.connectionStatus,
    required this.participants,
    required this.onShare,
    required this.onLeave,
    required this.onClearCanvas,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kToolbarHeight,
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
            // Menu button
            IconButton(
              onPressed: () {
                if (animationController.value == 0) {
                  animationController.forward();
                } else {
                  animationController.reverse();
                }
              },
              icon: AnimatedIcon(
                icon: AnimatedIcons.menu_close,
                progress: animationController,
              ),
              tooltip: 'Toggle Sidebar',
            ),

            // Back button
            IconButton(
              onPressed: onLeave,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Leave Session',
            ),

            const SizedBox(width: 16),

            // Title and connection status
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sessionId != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${sessionId!.substring(0, 8)}...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Connection indicator
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

            // Participant count with avatars
            ValueListenableBuilder<Map<String, LiveblocksPresence>>(
              valueListenable: participants,
              builder: (context, users, _) {
                final activeUsers = users.values.where((u) => u.isActive).toList();

                return GestureDetector(
                  onTap: () => _showParticipantsList(context, activeUsers),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // User avatars
                        ...activeUsers.take(3).map((user) => Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: user.getEffectiveColor(),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              user.displayName[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        )),

                        // Count
                        const Icon(Icons.people, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${activeUsers.length + 1}', // +1 for current user
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(width: 8),

            // Action buttons
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'share':
                    onShare();
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
                      Text('Share Session'),
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

  void _showParticipantsList(BuildContext context, List<LiveblocksPresence> participants) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session Participants'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Current user
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: const Text('You'),
              subtitle: const Text('Session host'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'ONLINE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Other participants
            ...participants.map((participant) => ListTile(
              leading: CircleAvatar(
                backgroundColor: participant.getEffectiveColor(),
                child: Text(
                  participant.displayName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(participant.displayName),
              subtitle: Text(participant.isDrawing ? 'Drawing...' : 'Viewing'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: participant.isActive ? Colors.green : Colors.grey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  participant.isActive ? 'ONLINE' : 'AWAY',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// Quick image toolbar for selected images
class _QuickImageToolbar extends StatelessWidget {
  final ImageNotifier imageNotifier;

  const _QuickImageToolbar({
    required this.imageNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<ImageState>(
              valueListenable: imageNotifier,
              builder: (context, state, _) {
                final selectedCount = state.selectedIds.length;
                return Text(
                  '$selectedCount image${selectedCount != 1 ? 's' : ''} selected',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              children: [
                _ToolbarButton(
                  icon: Icons.rotate_left,
                  tooltip: 'Rotate Left',
                  onPressed: () {
                    imageNotifier.transform(rotation: -math.pi / 2);
                  },
                ),
                _ToolbarButton(
                  icon: Icons.rotate_right,
                  tooltip: 'Rotate Right',
                  onPressed: () {
                    imageNotifier.transform(rotation: math.pi / 2);
                  },
                ),
                _ToolbarButton(
                  icon: Icons.flip_to_front,
                  tooltip: 'Bring to Front',
                  onPressed: () => imageNotifier.bringToFront([]),
                ),
                _ToolbarButton(
                  icon: Icons.flip_to_back,
                  tooltip: 'Send to Back',
                  onPressed: () => imageNotifier.sendToBack([]),
                ),
                _ToolbarButton(
                  icon: Icons.delete,
                  tooltip: 'Delete',
                  color: Colors.red,
                  onPressed: () => imageNotifier.removeSelectedImages(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 18,
            color: color ?? Colors.grey[700],
          ),
        ),
      ),
    );
  }
}

// Enhanced cursor painter
class _CursorPainter extends CustomPainter {
  final Color color;
  final bool isDrawing;

  _CursorPainter({required this.color, this.isDrawing = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    if (isDrawing) {
      // Drawing indicator - pulsing circle
      final center = Offset(size.width / 2, size.height / 2);

      // Outer glow
      paint
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 8, paint);

      // Inner circle
      paint
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 4, paint);

      // White border
      paint
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, 4, paint);
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
        ..strokeWidth = 1;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>
      oldDelegate is _CursorPainter &&
          (oldDelegate.color != color || oldDelegate.isDrawing != isDrawing);
}