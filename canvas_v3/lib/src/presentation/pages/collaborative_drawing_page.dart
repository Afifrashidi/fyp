// lib/src/presentation/pages/collaborative_drawing_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/services/collaborative_drawing_service.dart';
import 'package:flutter_drawing_board/src/services/liveblocks_service.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/src.dart';
import 'package:http/http.dart' as http;

const Color kCanvasColor = Color(0xFFF0F0F0);
const double kStandardCanvasWidth = 1920.0;
const double kStandardCanvasHeight = 1080.0;

class CollaborativeDrawingPage extends StatefulWidget {
  final String? sessionId;
  final bool isHost;

  const CollaborativeDrawingPage({
    super.key,
    this.sessionId,
    this.isHost = false,
  });

  @override
  State<CollaborativeDrawingPage> createState() =>
      _CollaborativeDrawingPageState();
}

class _CollaborativeDrawingPageState extends State<CollaborativeDrawingPage>
    with SingleTickerProviderStateMixin {
  // Services
  final _liveblocksService = LiveblocksService();
  final _authService = AuthService();

  // Animation controller for sidebar
  late final AnimationController animationController;

  // Drawing state
  final ValueNotifier<Color> selectedColor = ValueNotifier(Colors.black);
  final ValueNotifier<double> strokeSize = ValueNotifier(10.0);
  final ValueNotifier<DrawingTool> drawingTool = ValueNotifier(DrawingTool.pencil);
  final GlobalKey canvasGlobalKey = GlobalKey();
  final ValueNotifier<bool> filled = ValueNotifier(false);
  final ValueNotifier<int> polygonSides = ValueNotifier(3);
  final ValueNotifier<ui.Image?> backgroundImage = ValueNotifier(null);
  final CurrentStrokeValueNotifier currentStroke = CurrentStrokeValueNotifier();
  final ValueNotifier<List<Stroke>> allStrokes = ValueNotifier([]);
  late final UndoRedoStack undoRedoStack;
  final ValueNotifier<bool> showGrid = ValueNotifier(false);
  final ImageNotifier imageNotifier = ImageNotifier();

  // Collaborative state
  final ValueNotifier<Map<String, LiveblocksPresence>> participants = ValueNotifier({});
  final ValueNotifier<LiveblocksConnectionState> connectionStatus =
  ValueNotifier(LiveblocksConnectionState.disconnected);
  String? _currentSessionId;
  String _sessionTitle = 'Collaborative Drawing';
  late Color _userColor;

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
      duration: const Duration(milliseconds: 300),
    );

    undoRedoStack = UndoRedoStack(
      currentStrokeNotifier: currentStroke,
      strokesNotifier: allStrokes,
    );

    _userColor = _generateUserColor();
    _currentSessionId = widget.sessionId ?? 'session-${DateTime.now().millisecondsSinceEpoch}';
    _initializeSession();

    // Listen to local strokes
    allStrokes.addListener(_onLocalStrokeAdded);
  }

  Color _generateUserColor() {
    final colors = [
      Colors.blue, Colors.red, Colors.green, Colors.purple,
      Colors.orange, Colors.teal, Colors.pink, Colors.indigo,
    ];
    return colors[math.Random().nextInt(colors.length)];
  }

  Future<void> _initializeSession() async {
    try {
      // Get user info
      final currentUser = _authService.currentUser;
      final userName = currentUser?.email?.split('@')[0] ?? 'Guest User';
      final userId = currentUser?.id ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';

      // Determine role
      final userRole = widget.isHost ? 'owner' : 'editor';

      // Connect to Liveblocks
      await _liveblocksService.enterRoom(
        _currentSessionId!,
        userName: userName,
        userColor: _userColor,
        userId: userId,
        userRole: userRole,
      );

      // Set up listeners for real-time updates
      _setupLiveblocksListeners();

    } catch (e) {
      debugPrint('Failed to initialize session: $e');
      _showErrorSnackBar('Failed to connect to session');
    }
  }

  void _setupLiveblocksListeners() {
    // Listen for strokes from other users
    _subscriptions.add(
      _liveblocksService.strokeStream.listen((strokeData) {
        try {
          // Extract the stroke data properly
          final stroke = Stroke.fromJson(strokeData['stroke'] as Map<String, dynamic>);

          // Add to canvas if it's not from the current user
          if (strokeData['userId'] != _authService.currentUser?.id) {
            setState(() {
              allStrokes.value = [...allStrokes.value, stroke];
            });
          }
        } catch (e) {
          debugPrint('Error parsing stroke: $e');
        }
      }),
    );

    // Listen for canvas clear events
    _subscriptions.add(
      _liveblocksService.clearCanvasStream.listen((_) {
        setState(() {
          allStrokes.value = [];
          imageNotifier.removeAllImages();
        });
      }),
    );

    // Listen for connection status
    _subscriptions.add(
      _liveblocksService.connectionStream.listen((isConnected) {
        setState(() {
          connectionStatus.value = isConnected
              ? LiveblocksConnectionState.connected
              : LiveblocksConnectionState.disconnected;
        });
      }),
    );

    // Listen for presence updates
    _subscriptions.add(
      _liveblocksService.presenceStream.listen((presenceData) {
        // Parse presence data and update participants
        if (presenceData is Map<String, dynamic>) {
          final newParticipants = <String, LiveblocksPresence>{};

          presenceData.forEach((userId, data) {
            if (data is Map<String, dynamic>) {
              newParticipants[userId] = LiveblocksPresence(
                userId: userId,
                userName: data['userName'] ?? 'Unknown',
                userColor: data['userColor'] ?? '#000000',
                cursor: data['cursor'] != null
                    ? Offset((data['cursor']['x'] as num).toDouble(),
                    (data['cursor']['y'] as num).toDouble())
                    : null,
                isDrawing: data['isDrawing'] ?? false,
                selectedTool: data['selectedTool'] ?? 'pencil',
                strokeSize: (data['strokeSize'] as num?)?.toDouble() ?? 10.0,
                strokeColor: data['strokeColor'] ?? '#000000',
              );
            }
          });

          participants.value = newParticipants;
        }
      }),
    );
  }

  void _onLocalStrokeAdded() {
    final currentStrokes = allStrokes.value;
    if (currentStrokes.isEmpty) return;

    // Get the last stroke
    final lastStroke = currentStrokes.last;

    // Generate a unique ID for this stroke
    final strokeId = '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000)}';

    // Check if we've already broadcast this stroke
    if (!_localStrokeIds.contains(strokeId)) {
      _localStrokeIds.add(strokeId);

      // Create stroke data for broadcasting
      final strokeData = {
        'userId': _authService.currentUser?.id ?? 'guest',
        'userName': _authService.currentUser?.email?.split('@')[0] ?? 'Guest',
        'stroke': lastStroke.toJson(),
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Broadcast the stroke
      _liveblocksService.broadcastStroke(strokeData);
    }
  }

  void _handleMouseMove(Offset position) {
    _lastCursorPosition = position;
    _cursorBroadcastTimer?.cancel();
    _cursorBroadcastTimer = Timer(const Duration(milliseconds: 50), () {
      if (_lastCursorPosition != null && mounted) {
        // Update presence through Liveblocks
        // This would be handled by the Liveblocks service
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvasColor,
      body: HotkeyListener(
        onRedo: undoRedoStack.redo,
        onUndo: () {
          undoRedoStack.undo();
        },
        child: MouseRegion(
          onHover: (event) => _handleMouseMove(event.localPosition),
          child: Stack(
            children: [
              // Main drawing canvas with cursors
              AnimatedBuilder(
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
                  imageNotifier,
                  participants,
                ]),
                builder: (context, _) {
                  return Stack(
                    children: [
                      DrawingCanvas(
                        options: DrawingCanvasOptions(
                          currentTool: drawingTool.value,
                          size: strokeSize.value,
                          strokeColor: selectedColor.value,
                          backgroundColor: kCanvasColor,
                          polygonSides: polygonSides.value,
                          showGrid: showGrid.value,
                          fillShape: filled.value,
                        ),
                        canvasKey: canvasGlobalKey,
                        currentStrokeListenable: currentStroke,
                        strokesListenable: allStrokes,
                        backgroundImageListenable: backgroundImage,
                        imageNotifier: imageNotifier,
                      ),
                      ..._buildRemoteCursors(),
                    ],
                  );
                },
              ),

              // Sidebar
              Positioned(
                top: kToolbarHeight + 10,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(-1, 0),
                    end: Offset.zero,
                  ).animate(animationController),
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
                    imageNotifier: imageNotifier,
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
                onLeave: () => Navigator.pop(context),
                onClearCanvas: _clearCanvas,
              ),

              // Quick access toolbar
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
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRemoteCursors() {
    return participants.value.entries
        .where((entry) => entry.value.cursor != null && entry.key != _authService.currentUser?.id)
        .map((entry) {
      final presence = entry.value;
      return Positioned(
        left: presence.cursor!.dx - 10,
        top: presence.cursor!.dy - 10,
        child: IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _parseColor(presence.userColor).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      presence.userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (presence.isDrawing) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 12, color: Colors.white),
                    ],
                  ],
                ),
              ),
              CustomPaint(
                size: const Size(20, 20),
                painter: _CursorPainter(
                  color: _parseColor(presence.userColor),
                  isDrawing: presence.isDrawing,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Color _parseColor(String colorString) {
    final hex = colorString.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  void _shareSession() {
    if (_currentSessionId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this code with others:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _currentSessionId!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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

  void _clearCanvas() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Canvas?'),
        content: const Text('This will clear the canvas for everyone. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Clear locally
              setState(() {
                allStrokes.value = [];
                imageNotifier.removeAllImages();
              });
              // Broadcast clear
              _liveblocksService.broadcastClearCanvas();
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
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

    // Clean up controllers
    animationController.dispose();
    selectedColor.dispose();
    strokeSize.dispose();
    drawingTool.dispose();
    currentStroke.dispose();
    allStrokes.dispose();
    undoRedoStack.dispose();
    filled.dispose();
    polygonSides.dispose();
    backgroundImage.dispose();
    showGrid.dispose();
    imageNotifier.dispose();
    connectionStatus.dispose();
    participants.dispose();

    super.dispose();
  }
}

// LiveblocksPresence model
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
}

// App bar widget
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
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                if (animationController.value == 0) {
                  animationController.forward();
                } else {
                  animationController.reverse();
                }
              },
              icon: const Icon(Icons.menu),
            ),
            IconButton(
              onPressed: onLeave,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Connection indicator
                  ValueListenableBuilder<LiveblocksConnectionState>(
                    valueListenable: connectionStatus,
                    builder: (context, status, _) {
                      String label;
                      Color color;

                      switch (status) {
                        case LiveblocksConnectionState.authenticated:
                          label = 'LIVE';
                          color = Colors.green;
                          break;
                        case LiveblocksConnectionState.connecting:
                        case LiveblocksConnectionState.authenticating:
                          label = 'CONNECTING';
                          color = Colors.orange;
                          break;
                        case LiveblocksConnectionState.error:
                          label = 'ERROR';
                          color = Colors.red;
                          break;
                        case LiveblocksConnectionState.disconnected:
                          label = 'OFFLINE';
                          color = Colors.grey;
                          break;
                        case LiveblocksConnectionState.connected:
                          label = 'CONNECTED';
                          color = Colors.blue;
                          break;
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Actions
            IconButton(
              onPressed: onClearCanvas,
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear Canvas',
            ),
            IconButton(
              onPressed: onShare,
              icon: const Icon(Icons.share),
              tooltip: 'Share Session',
            ),
            // Participant count
            ValueListenableBuilder<Map<String, LiveblocksPresence>>(
              valueListenable: participants,
              builder: (context, users, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        '${users.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Quick image toolbar
class _QuickImageToolbar extends StatelessWidget {
  final ImageNotifier imageNotifier;

  const _QuickImageToolbar({
    required this.imageNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<ImageState>(
              valueListenable: imageNotifier,
              builder: (context, state, _) {
                final selectedCount = state.selectedIds.length;
                return Text(
                  '$selectedCount selected',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.rotate_left),
                  iconSize: 20,
                  onPressed: () {
                    imageNotifier.transform(rotation: -math.pi / 2);
                  },
                  tooltip: 'Rotate Left',
                ),
                IconButton(
                  icon: const Icon(Icons.rotate_right),
                  iconSize: 20,
                  onPressed: () {
                    imageNotifier.transform(rotation: math.pi / 2);
                  },
                  tooltip: 'Rotate Right',
                ),
                IconButton(
                  icon: const Icon(Icons.flip_to_front),
                  iconSize: 20,
                  onPressed: () => imageNotifier.bringToFront([]),
                  tooltip: 'Bring to Front',
                ),
                IconButton(
                  icon: const Icon(Icons.flip_to_back),
                  iconSize: 20,
                  onPressed: () => imageNotifier.sendToBack([]),
                  tooltip: 'Send to Back',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  iconSize: 20,
                  onPressed: () => imageNotifier.removeSelectedImages(),
                  tooltip: 'Delete',
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Cursor painter
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
      // Show pencil icon when drawing
      canvas.drawCircle(
        const Offset(10, 10),
        8,
        paint..style = PaintingStyle.stroke..strokeWidth = 2,
      );
      canvas.drawCircle(
        const Offset(10, 10),
        3,
        paint..style = PaintingStyle.fill,
      );
    } else {
      // Normal cursor
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(0, 15)
        ..lineTo(4, 12)
        ..lineTo(7, 18)
        ..lineTo(10, 16)
        ..lineTo(7, 10)
        ..lineTo(12, 10)
        ..close();

      canvas.drawPath(path, paint);

      paint
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}