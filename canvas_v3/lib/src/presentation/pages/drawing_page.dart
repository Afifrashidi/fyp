// lib/src/presentation/pages/drawing_page.dart
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/presentation/pages/auth/login_page.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';
import 'package:flutter_drawing_board/src/services/drawing_persistence_service.dart';
import 'package:flutter_drawing_board/src/src.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DrawingPage extends StatefulWidget {
  final String? drawingId;
  final bool isNewDrawing; // Add this to explicitly indicate new drawing

  const DrawingPage({
    super.key,
    this.drawingId,
    this.isNewDrawing = false, // Default to false
  });

  @override
  State<DrawingPage> createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController animationController;
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

  // Persistence
  final DrawingPersistenceService _persistenceService = DrawingPersistenceService();
  final AuthService _authService = AuthService();

  String? _currentDrawingId;
  String _drawingTitle = 'Untitled';
  bool _hasUnsavedChanges = false;
  Timer? _autoSaveTimer;
  bool _isLoading = true;
  DateTime? _lastSaveTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    undoRedoStack = UndoRedoStack(
      currentStrokeNotifier: currentStroke,
      strokesNotifier: allStrokes,
    );

    // Initialize drawing
    _initializeDrawing();

    // Setup auto-save for authenticated users
    if (_authService.isAuthenticated) {
      _startAutoSave();
    }

    // Listen for changes
    _setupChangeListeners();
  }

  void _setupChangeListeners() {
    // Mark as changed when drawing changes
    allStrokes.addListener(_markAsChanged);
    imageNotifier.addListener(_markAsChanged);
    selectedColor.addListener(_markAsChanged);
    strokeSize.addListener(_markAsChanged);
    filled.addListener(_markAsChanged);
    polygonSides.addListener(_markAsChanged);
    showGrid.addListener(_markAsChanged);
    drawingTool.addListener(_markAsChanged);
    backgroundImage.addListener(_markAsChanged);
  }

  void _markAsChanged() {
    if (!_hasUnsavedChanges && !_isLoading) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  // Update in DrawingPage's _initializeDrawing method
  Future<void> _initializeDrawing() async {
    setState(() => _isLoading = true);

    try {
      // If a specific drawing ID is provided, load it
      if (widget.drawingId != null) {
        await _loadDrawing(widget.drawingId!);
        // Update the last opened timestamp after loading
        await _updateLastOpenedTimestamp(widget.drawingId!);
      }
      // If explicitly creating a new drawing, create it
      else if (widget.isNewDrawing && _authService.isAuthenticated) {
        await _createNewDrawing();
      }
      // For authenticated users without specific intent, load last drawing
      else if (_authService.isAuthenticated && !widget.isNewDrawing) {
        final lastDrawingId = await _persistenceService.getLastOpenedDrawingId();
        if (lastDrawingId != null) {
          await _loadDrawing(lastDrawingId);
          // Update the last opened timestamp after loading
          await _updateLastOpenedTimestamp(lastDrawingId);
        } else {
          // No last drawing, create a new one
          await _createNewDrawing();
        }
      }
      // For guests or when no drawing ID is provided, start fresh
    } catch (e) {
      print('Error initializing drawing: $e');
      // If loading fails, start fresh
      if (_authService.isAuthenticated) {
        await _createNewDrawing();
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateLastOpenedTimestamp(String drawingId) async {
    if (!_authService.isAuthenticated) return;

    try {
      await Supabase.instance.client.from('drawings').update({
        'last_opened_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', drawingId);

      print('Updated last_opened_at timestamp for drawing: $drawingId');
    } catch (e) {
      print('Error updating last_opened_at: $e');
    }
  }


  Future<void> _createNewDrawing() async {
    if (!_authService.isAuthenticated) return;

    try {
      _currentDrawingId = await _persistenceService.createNewDrawing(
        title: 'Untitled Drawing',
        userId: _authService.currentUser!.id,
      );

      setState(() {
        _drawingTitle = 'Untitled Drawing';
        _hasUnsavedChanges = false;
      });
    } catch (e) {
      print('Error creating new drawing: $e');
    }
  }

  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_hasUnsavedChanges && _currentDrawingId != null) {
        _saveDrawing(showNotification: false);
      }
    });
  }

  Future<void> _loadDrawing(String drawingId) async {
    try {
      final drawingData = await _persistenceService.loadDrawingState(drawingId);
      if (drawingData != null && mounted) {
        setState(() {
          _currentDrawingId = drawingData.id;
          _drawingTitle = drawingData.title;
          allStrokes.value = drawingData.strokes;

          // Load images - clear existing and add new ones
          imageNotifier.removeAllImages();
          if (drawingData.images.isNotEmpty) {
            imageNotifier.addImages(drawingData.images);
          }

          // Apply options
          selectedColor.value = drawingData.options.strokeColor;
          strokeSize.value = drawingData.options.size;
          showGrid.value = drawingData.options.showGrid;
          filled.value = drawingData.options.fillShape;
          polygonSides.value = drawingData.options.polygonSides;
          drawingTool.value = drawingData.options.currentTool;
          backgroundImage.value = drawingData.backgroundImage;

          _lastSaveTime = drawingData.lastSaved;
          _hasUnsavedChanges = false;
        });
      }
    } catch (e) {
      print('Error loading drawing: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load drawing: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveDrawing({bool showNotification = true}) async {
    if (!_authService.isAuthenticated) {
      _showLoginPrompt();
      return;
    }

    if (_currentDrawingId == null) {
      await _createNewDrawing();
      if (_currentDrawingId == null) return;
    }

    setState(() => _isLoading = true);

    try {
      // Update both timestamps when saving
      final now = DateTime.now().toUtc().toIso8601String();

      // First update the drawing metadata
      await Supabase.instance.client.from('drawings').update({
        'title': _drawingTitle,
        'updated_at': now,
        'last_opened_at': now, // Update this too when saving
      }).eq('id', _currentDrawingId!);

      // Then save the drawing state
      final savedId = await _persistenceService.saveDrawingState(
        drawingId: _currentDrawingId,
        title: _drawingTitle,
        strokes: allStrokes.value,
        images: imageNotifier.value.imageList,
        options: DrawingCanvasOptions(
          currentTool: drawingTool.value,
          size: strokeSize.value,
          strokeColor: selectedColor.value,
          backgroundColor: kCanvasColor,
          polygonSides: polygonSides.value,
          showGrid: showGrid.value,
          fillShape: filled.value,
        ),
        backgroundImage: backgroundImage.value,
      );

      setState(() {
        _currentDrawingId = savedId;
        _hasUnsavedChanges = false;
        _lastSaveTime = DateTime.now();
      });

      if (showNotification && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Drawing saved'),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: 'View All',
              onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
            ),
          ),
        );
      }
    } catch (e) {
      print('Error saving drawing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showLoginPrompt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign in to Save'),
        content: const Text(
          'You need to sign in to save your drawings. '
              'Would you like to sign in now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Save when app goes to background
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_hasUnsavedChanges && _authService.isAuthenticated) {
        _saveDrawing(showNotification: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && widget.drawingId == null && !widget.isNewDrawing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Loading drawing...'),
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (_hasUnsavedChanges && _authService.isAuthenticated) {
          final shouldLeave = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Unsaved Changes'),
              content: const Text(
                'You have unsaved changes. '
                    'Do you want to save before leaving?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Discard'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _saveDrawing();
                    if (mounted) Navigator.pop(context, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          return shouldLeave ?? false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: kCanvasColor,
        body: HotkeyListener(
          onRedo: undoRedoStack.redo,
          onUndo: undoRedoStack.undo,
          child: Stack(
            children: [
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
                ]),
                builder: (context, _) {
                  return DrawingCanvas(
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
                  );
                },
              ),
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
              _CustomAppBar(
                animationController: animationController,
                title: _drawingTitle,
                hasUnsavedChanges: _hasUnsavedChanges,
                isAuthenticated: _authService.isAuthenticated,
                lastSaveTime: _lastSaveTime,
                onSave: () => _saveDrawing(),
                onTitleEdit: () => _showTitleEditDialog(),
                onNewDrawing: _handleNewDrawing,
                onHome: () => Navigator.pushReplacementNamed(context, '/home'),
              ),
              // Quick access toolbar for image operations
              if (imageNotifier.value.hasSelection)
                Positioned(
                  top: kToolbarHeight + 10,
                  right: 10,
                  child: _QuickImageToolbar(
                    imageNotifier: imageNotifier,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTitleEditDialog() {
    final controller = TextEditingController(text: _drawingTitle);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Title'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Drawing Title',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _drawingTitle = controller.text.trim().isEmpty
                    ? 'Untitled'
                    : controller.text.trim();
                _hasUnsavedChanges = true;
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNewDrawing() async {
    if (_hasUnsavedChanges) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Create New Drawing?'),
          content: const Text(
            'You have unsaved changes. '
                'Do you want to save before creating a new drawing?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _saveDrawing(showNotification: false);
                if (mounted) Navigator.pop(context, true);
              },
              child: const Text('Save First'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    // Clear everything
    setState(() {
      allStrokes.value = [];
      imageNotifier.removeAllImages();
      backgroundImage.value = null;
      selectedColor.value = Colors.black;
      strokeSize.value = 10.0;
      showGrid.value = false;
      filled.value = false;
      polygonSides.value = 3;
      drawingTool.value = DrawingTool.pencil;
      _drawingTitle = 'Untitled Drawing';
      _hasUnsavedChanges = false;
      _lastSaveTime = null;
    });

    if (_authService.isAuthenticated) {
      await _createNewDrawing();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();

    // Save before disposing if authenticated
    if (_hasUnsavedChanges && _authService.isAuthenticated && _currentDrawingId != null) {
      _saveDrawing(showNotification: false);
    }

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
    super.dispose();
  }
}

// Rest of the custom widgets remain the same...
class _CustomAppBar extends StatelessWidget {
  final AnimationController animationController;
  final String title;
  final bool hasUnsavedChanges;
  final bool isAuthenticated;
  final DateTime? lastSaveTime;
  final VoidCallback onSave;
  final VoidCallback onTitleEdit;
  final VoidCallback onNewDrawing;
  final VoidCallback onHome;

  const _CustomAppBar({
    Key? key,
    required this.animationController,
    required this.title,
    required this.hasUnsavedChanges,
    required this.isAuthenticated,
    this.lastSaveTime,
    required this.onSave,
    required this.onTitleEdit,
    required this.onNewDrawing,
    required this.onHome,
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
              onPressed: onHome,
              icon: const Icon(Icons.home),
              tooltip: 'Home',
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GestureDetector(
                onTap: onTitleEdit,
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
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 16, color: Colors.grey),
                    if (hasUnsavedChanges) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Save status
            if (isAuthenticated && lastSaveTime != null) ...[
              Text(
                _getLastSaveText(),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (isAuthenticated) ...[
              IconButton(
                onPressed: onNewDrawing,
                icon: const Icon(Icons.add),
                tooltip: 'New Drawing',
              ),
              IconButton(
                onPressed: hasUnsavedChanges ? onSave : null,
                icon: const Icon(Icons.save),
                tooltip: 'Save',
              ),
              PopupMenuButton(
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'save_as',
                    child: ListTile(
                      leading: Icon(Icons.save_as),
                      title: Text('Save As...'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: ListTile(
                      leading: Icon(Icons.copy),
                      title: Text('Duplicate'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                      leading: Icon(Icons.share),
                      title: Text('Share'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'export',
                    child: ListTile(
                      leading: Icon(Icons.download),
                      title: Text('Export'),
                    ),
                  ),
                ],
                onSelected: (value) {
                  // Handle menu actions
                },
              ),
            ] else ...[
              TextButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                },
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Sign In to Save'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getLastSaveText() {
    if (lastSaveTime == null) return '';

    final now = DateTime.now();
    final diff = now.difference(lastSaveTime!);

    if (diff.inSeconds < 60) {
      return 'Saved just now';
    } else if (diff.inMinutes < 60) {
      return 'Saved ${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return 'Saved ${diff.inHours}h ago';
    } else {
      return 'Saved ${diff.inDays}d ago';
    }
  }
}

class _QuickImageToolbar extends StatelessWidget {
  final ImageNotifier imageNotifier;

  const _QuickImageToolbar({
    Key? key,
    required this.imageNotifier,
  }) : super(key: key);

  // Add this method here too
  Offset? _calculateSelectionCenter() {
    final selectedImages = imageNotifier.value.selectedImages;
    if (selectedImages.isEmpty) return null;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final img in selectedImages) {
      final bounds = img.bounds;
      minX = math.min(minX, bounds.left);
      minY = math.min(minY, bounds.top);
      maxX = math.max(maxX, bounds.right);
      maxY = math.max(maxY, bounds.bottom);
    }

    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ImageState>(
      valueListenable: imageNotifier,
      builder: (context, state, _) {
        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${state.selectedIds.length} selected',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Rotate Left (-90 degrees)
                    IconButton(
                      icon: const Icon(Icons.rotate_left),
                      iconSize: 20,
                      onPressed: () => imageNotifier.transform(
                        rotation: -math.pi / 2,
                        scaleOrigin: _calculateSelectionCenter(),
                      ),
                      tooltip: 'Rotate Left',
                    ),

                    // Rotate Right (+90 degrees)
                    IconButton(
                      icon: const Icon(Icons.rotate_right),
                      iconSize: 20,
                      onPressed: () => imageNotifier.transform(
                        rotation: math.pi / 2,
                        scaleOrigin: _calculateSelectionCenter(),
                      ),
                      tooltip: 'Rotate Right',
                    ),
                    IconButton(
                      icon: const Icon(Icons.flip_to_front),
                      iconSize: 20,
                      onPressed: () => imageNotifier.bringToFront(
                        state.selectedIds.toList(),
                      ),
                      tooltip: 'Bring to Front',
                    ),
                    IconButton(
                      icon: const Icon(Icons.flip_to_back),
                      iconSize: 20,
                      onPressed: () => imageNotifier.sendToBack(
                        state.selectedIds.toList(),
                      ),
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
      },
    );
  }
}