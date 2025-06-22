// lib/src/presentation/pages/liveblocks_collaborative_drawing_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/services/liveblocks_service.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/src.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color kCanvasColor = Color(0xFFF0F0F0);
const double kStandardCanvasWidth = 1920.0;
const double kStandardCanvasHeight = 1080.0;

class LiveblocksCollaborativeDrawingPage extends StatefulWidget {
  final String? roomId;
  final bool isHost;

  const LiveblocksCollaborativeDrawingPage({
    super.key,
    this.roomId,
    this.isHost = false,
  });

  @override
  State<LiveblocksCollaborativeDrawingPage> createState() =>
      _LiveblocksCollaborativeDrawingPageState();
}

class _LiveblocksCollaborativeDrawingPageState
    extends State<LiveblocksCollaborativeDrawingPage>
    with SingleTickerProviderStateMixin {
  // Services
  final _liveblocksService = LiveblocksService();
  final _authService = AuthService();
  final _supabase = Supabase.instance.client;

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
  final ValueNotifier<Map<String, LiveblocksPresence>> remoteCursors = ValueNotifier({});
  final ValueNotifier<LiveblocksConnectionState> connectionStatus =
  ValueNotifier(LiveblocksConnectionState.disconnected);

  String? _currentRoomId;
  String _roomTitle = 'Collaborative Drawing';
  late Color _userColor;
  String? _userId;
  String? _userName;

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  // Throttle cursor updates
  Timer? _cursorThrottle;
  Offset? _lastCursorPosition;

  // Track if we're updating from remote to avoid loops
  bool _isUpdatingFromRemote = false;

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
    _initializeRoom();
  }

  Color _generateUserColor() {
    final colors = [
      Colors.blue, Colors.red, Colors.green, Colors.purple,
      Colors.orange, Colors.teal, Colors.pink, Colors.indigo,
    ];
    return colors[math.Random().nextInt(colors.length)];
  }

  Future<void> _initializeRoom() async {
    // Generate or use provided room ID
    _currentRoomId = widget.roomId ?? 'drawing-${DateTime.now().millisecondsSinceEpoch}';
    _roomTitle = 'Room: ${_currentRoomId!.substring(0, math.min(8, _currentRoomId!.length))}';

    try {
      // Get user info
      final user = _authService.currentUser;
      _userId = user?.id ?? 'guest-${DateTime.now().millisecondsSinceEpoch}';
      _userName = user?.email?.split('@').first ?? 'Guest';

      // Enter Liveblocks room
      await _liveblocksService.enterRoom(
        _currentRoomId!,
        userName: _userName!,
        userColor: _userColor,
        userId: _userId,
      );

      // Set up listeners
      _setupLiveblocksListeners();

      // Listen to local drawing changes
      allStrokes.addListener(_onLocalStrokesChanged);
      currentStroke.addListener(_onCurrentStrokeChanged);
      showGrid.addListener(_onCanvasSettingsChanged);
      selectedColor.addListener(_updatePresence);
      strokeSize.addListener(_updatePresence);
      drawingTool.addListener(_updatePresence);
      imageNotifier.addListener(_onImagesChanged);

    } catch (e) {
      _showErrorSnackBar('Failed to join room: $e');
    }
  }

  void _setupLiveblocksListeners() {
    // Connection state
    _subscriptions.add(
      _liveblocksService.connectionStream.listen((status) {
        connectionStatus.value = status;

        switch (status) {
          case LiveblocksConnectionState.connecting:
            _showInfoSnackBar('Connecting to session...');
            break;
          case LiveblocksConnectionState.authenticated:
            _showSuccessSnackBar('Connected!');
            _sendInitialPresence();
            break;
          case LiveblocksConnectionState.error:
            _showErrorSnackBar('Connection error');
            break;
          case LiveblocksConnectionState.disconnected:
            break;
          case LiveblocksConnectionState.authenticating:
            break;
          case LiveblocksConnectionState.connected:
            // TODO: Handle this case.
            throw UnimplementedError();
        }
      }),
    );

    // Stroke events from Liveblocks
    _subscriptions.add(
      _liveblocksService.strokeStream.listen((strokeData) {
        _isUpdatingFromRemote = true;

        try {
          // Parse stroke data
          final stroke = Stroke.fromJson(strokeData.strokeData);

          // Add to strokes if it's not already there
          if (!allStrokes.value.any((s) => s == stroke)) {
            allStrokes.value = [...allStrokes.value, stroke];
          }
        } catch (e) {
          debugPrint('Error parsing stroke: $e');
        }

        _isUpdatingFromRemote = false;
      }),
    );

    // Image events
    _subscriptions.add(
      _liveblocksService.imageAddStream.listen((imageData) async {
        _isUpdatingFromRemote = true;
        await _loadAndAddImage(imageData);
        _isUpdatingFromRemote = false;
      }),
    );

    _subscriptions.add(
      _liveblocksService.imageUpdateStream.listen((imageData) {
        _isUpdatingFromRemote = true;
        _updateImageTransform(imageData);
        _isUpdatingFromRemote = false;
      }),
    );

    _subscriptions.add(
      _liveblocksService.imageRemoveStream.listen((imageId) {
        _isUpdatingFromRemote = true;
        imageNotifier.removeImages([imageId]);
        _isUpdatingFromRemote = false;
      }),
    );

    // Clear canvas events
    _subscriptions.add(
      _liveblocksService.clearCanvasStream.listen((userId) {
        _isUpdatingFromRemote = true;
        setState(() {
          allStrokes.value = [];
          imageNotifier.removeAllImages();
        });
        _isUpdatingFromRemote = false;
      }),
    );

    // Presence updates
    _subscriptions.add(
      _liveblocksService.presenceStream.listen((presence) {
        remoteCursors.value = Map.from(presence);
      }),
    );

    // Errors
    _subscriptions.add(
      _liveblocksService.errorStream.listen((error) {
        _showErrorSnackBar(error);
      }),
    );
  }

  void _sendInitialPresence() {
    _updatePresence();
  }

  void _updatePresence() {
    _liveblocksService.updatePresence({
      'cursor': _lastCursorPosition != null ? {
        'x': _lastCursorPosition!.dx,
        'y': _lastCursorPosition!.dy,
      } : null,
      'userName': _userName!,
      'userColor': '#${_userColor.value.toRadixString(16).substring(2)}',
      'isDrawing': currentStroke.hasStroke,
      'selectedTool': drawingTool.value.toString().split('.').last,
      'strokeSize': strokeSize.value,
      'strokeColor': '#${selectedColor.value.value.toRadixString(16).substring(2)}',
    });
  }

  void _onCurrentStrokeChanged() {
    _updatePresence();
  }

  void _onLocalStrokesChanged() {
    if (_isUpdatingFromRemote) return;

    // Get the latest stroke if any was added
    if (allStrokes.value.isNotEmpty) {
      final latestStroke = allStrokes.value.last;

      // Send to Liveblocks
      _liveblocksService.broadcastStroke(latestStroke);
    }
  }

  void _onCanvasSettingsChanged() {
    if (_isUpdatingFromRemote) return;

    _liveblocksService.broadcastCanvasSettings({
      'showGrid': showGrid.value,
      'backgroundColor': '#${kCanvasColor.value.toRadixString(16).substring(2)}',
      'lastModified': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _onImagesChanged() async {
    if (_isUpdatingFromRemote) return;

    // Handle image additions/updates
    final currentImages = imageNotifier.value.imageList;

    for (final image in currentImages) {
      // Check if this is a new image
      final needsSync = true; // Implement proper check

      if (needsSync) {
        // First upload image to Supabase
        final imageUrl = await _uploadImageToSupabase(image);

        if (imageUrl != null) {
          // Then sync with Liveblocks
          final imageData = LiveblocksImage(
            id: image.id,
            url: imageUrl,
            userId: _userId!,
            userName: _userName!,
            transform: image.transform.storage,
            width: image.image.width.toDouble(),
            height: image.image.height.toDouble(),
            timestamp: DateTime.now().millisecondsSinceEpoch,
            addedBy: _userId!,
          );

          _liveblocksService.broadcastImageAdd(imageData);
        }
      }
    }
  }

  Future<String?> _uploadImageToSupabase(CanvasImage image) async {
    try {
      // Convert ui.Image to bytes
      final byteData = await image.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final bytes = byteData.buffer.asUint8List();
      final fileName = 'collab_${_currentRoomId}_${image.id}.png';
      final path = 'collaborative/$_currentRoomId/$fileName';

      // Upload to Supabase storage
      await _supabase.storage
          .from('images')
          .uploadBinary(path, bytes);

      // Get public URL
      return _supabase.storage
          .from('images')
          .getPublicUrl(path);
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _loadAndAddImage(LiveblocksImage imageData) async {
    try {
      // Download image from URL
      final response = await _supabase.storage
          .from('images')
          .download(imageData.url);

      // Convert to ui.Image
      final codec = await ui.instantiateImageCodec(response);
      final frame = await codec.getNextFrame();

      // Create CanvasImage with transform
      final transform = Matrix4.fromList(imageData.transform);
      final canvasImage = CanvasImage(
        id: imageData.id,
        image: frame.image,
        transform: transform,
      );

      // Add to canvas
      imageNotifier.addImage(canvasImage);
    } catch (e) {
      print('Error loading image: $e');
    }
  }

  void _updateImageTransform(LiveblocksImage imageData) {
    // Update image transform
    final transform = Matrix4.fromList(imageData.transform);
    imageNotifier.transform(
      imageIds: [imageData.id],
      transform: transform,
    );
  }

  void _handlePointerMove(Offset position) {
    _lastCursorPosition = position;

    // Throttle cursor updates
    _cursorThrottle?.cancel();
    _cursorThrottle = Timer(const Duration(milliseconds: 50), () {
      if (_lastCursorPosition != null) {
        _updatePresence();
      }
    });
  }

  void _handlePointerExit() {
    _lastCursorPosition = null;
    _updatePresence();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvasColor,
      body: HotkeyListener(
        onRedo: undoRedoStack.redo,
        onUndo: () {
          undoRedoStack.undo();
          // TODO: Implement undo broadcast
        },
        child: MouseRegion(
          onHover: (event) => _handlePointerMove(event.localPosition),
          onExit: (_) => _handlePointerExit(),
          child: Stack(
            children: [
              // Main drawing canvas
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
                  remoteCursors,
                ]),
                builder: (context, _) {
                  return Stack(
                    children: [
                      // Drawing canvas
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

                      // Remote cursors
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

              // App bar
              _LiveblocksAppBar(
                animationController: animationController,
                title: _roomTitle,
                roomId: _currentRoomId,
                connectionStatus: connectionStatus,
                participants: remoteCursors,
                onShare: _shareRoom,
                onLeave: () => Navigator.pop(context),
                onClear: _clearCanvas,
              ),

              // Image toolbar
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
                      onTransform: (imageId, transform) {
                        // Update transform in Liveblocks
                        _liveblocksService.broadcastImageUpdate(imageId, transform);
                      },
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
    return remoteCursors.value.entries
        .where((entry) => entry.key != _userId) // Don't show own cursor
        .map((entry) {
      final presence = entry.value;
      if (presence.cursor == null) return const SizedBox.shrink();

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
                child: Text(
                  presence.userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
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
    return Color(int.parse(colorString.replaceFirst('#', '0xFF')));
  }

  void _shareRoom() {
    if (_currentRoomId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this room ID with others:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _currentRoomId!,
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
        content: const Text('This will clear the canvas for all participants.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _liveblocksService.broadcastClearCanvas();
              imageNotifier.removeAllImages();
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _cursorThrottle?.cancel();
    allStrokes.removeListener(_onLocalStrokesChanged);
    currentStroke.removeListener(_onCurrentStrokeChanged);
    showGrid.removeListener(_onCanvasSettingsChanged);
    selectedColor.removeListener(_updatePresence);
    strokeSize.removeListener(_updatePresence);
    drawingTool.removeListener(_updatePresence);
    imageNotifier.removeListener(_onImagesChanged);

    for (final sub in _subscriptions) {
      sub.cancel();
    }

    _liveblocksService.leaveRoom();

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
    remoteCursors.dispose();
    connectionStatus.dispose();

    super.dispose();
  }
}

// App bar widget
class _LiveblocksAppBar extends StatelessWidget {
  final AnimationController animationController;
  final String title;
  final String? roomId;
  final ValueNotifier<LiveblocksConnectionState> connectionStatus;
  final ValueNotifier<Map<String, LiveblocksPresence>> participants;
  final VoidCallback onShare;
  final VoidCallback onLeave;
  final VoidCallback onClear;

  const _LiveblocksAppBar({
    Key? key,
    required this.animationController,
    required this.title,
    required this.roomId,
    required this.connectionStatus,
    required this.participants,
    required this.onShare,
    required this.onLeave,
    required this.onClear,
  }) : super(key: key);

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
                  // Connection status
                  ValueListenableBuilder<LiveblocksConnectionState>(
                    valueListenable: connectionStatus,
                    builder: (context, state, _) {
                      String label = '';
                      Color color = Colors.grey;

                      switch (state) {
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
                          // TODO: Handle this case.
                          throw UnimplementedError();
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
            // Participant count
            if (roomId != null)
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
            const SizedBox(width: 8),
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear Canvas',
            ),
            IconButton(
              onPressed: onShare,
              icon: const Icon(Icons.share),
              tooltip: 'Share Session',
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
  final void Function(String imageId, Matrix4 transform) onTransform;

  const _QuickImageToolbar({
    Key? key,
    required this.imageNotifier,
    required this.onTransform,
  }) : super(key: key);

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
                    final selectedIds = imageNotifier.value.selectedIds;
                    for (final id in selectedIds) {
                      final image = imageNotifier.value.images[id];
                      if (image != null) {
                        final newTransform = image.transform.clone()
                          ..rotateZ(-math.pi / 2);
                        imageNotifier.transform(
                          imageIds: [id],
                          transform: newTransform,
                        );
                        onTransform(id, newTransform);
                      }
                    }
                  },
                  tooltip: 'Rotate Left',
                ),
                IconButton(
                  icon: const Icon(Icons.rotate_right),
                  iconSize: 20,
                  onPressed: () {
                    final selectedIds = imageNotifier.value.selectedIds;
                    for (final id in selectedIds) {
                      final image = imageNotifier.value.images[id];
                      if (image != null) {
                        final newTransform = image.transform.clone()
                          ..rotateZ(math.pi / 2);
                        imageNotifier.transform(
                          imageIds: [id],
                          transform: newTransform,
                        );
                        onTransform(id, newTransform);
                      }
                    }
                  },
                  tooltip: 'Rotate Right',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  iconSize: 20,
                  onPressed: () {
                    final selectedIds = imageNotifier.value.selectedIds;
                    imageNotifier.removeImages(selectedIds.toList());
                    // Also remove from Liveblocks
                    for (final id in selectedIds) {
                      LiveblocksService().broadcastImageRemove(id);
                    }
                  },
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
      // Show different cursor when drawing
      canvas.drawCircle(
        const Offset(10, 10),
        5,
        paint..style = PaintingStyle.stroke..strokeWidth = 2,
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

      // White outline
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