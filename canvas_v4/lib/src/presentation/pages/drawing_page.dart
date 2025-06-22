// lib/src/presentation/pages/drawing_page.dart
// UPDATED: Add guest mode warning to save functionality

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';
import 'package:flutter_drawing_board/src/constants/canvas_operations_enums.dart';
import 'package:flutter_drawing_board/src/domain/domain.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/current_stroke_value_notifier.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/presentation/widgets/drawing_canvas.dart';
import 'package:flutter_drawing_board/src/presentation/widgets/canvas_side_bar.dart';
import 'package:flutter_drawing_board/src/presentation/widgets/hot_key_listener.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';
import 'package:flutter_drawing_board/src/services/drawing_persistence_service.dart';
import 'package:flutter_drawing_board/src/services/error_handling_service.dart';
import 'package:flutter_drawing_board/src/src.dart';
import 'package:flutter_drawing_board/src/domain/models/drawing_data.dart';

class DrawingPage extends StatefulWidget {
  final String? drawingId;
  final String? initialTitle;

  const DrawingPage({
    Key? key,
    this.drawingId,
    this.initialTitle,
  }) : super(key: key);

  @override
  State<DrawingPage> createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage>
    with TickerProviderStateMixin {

  // Core drawing state
  final ValueNotifier<Color> selectedColor = ValueNotifier(Colors.black);
  final ValueNotifier<double> strokeSize = ValueNotifier(AppConstants.defaultStrokeSize);
  final ValueNotifier<double> eraserSize = ValueNotifier(AppConstants.defaultEraserSize);
  final ValueNotifier<double> opacity = ValueNotifier(AppConstants.defaultOpacity);
  final ValueNotifier<DrawingTool> drawingTool = ValueNotifier(DrawingTool.pencil);
  final ValueNotifier<int> polygonSides = ValueNotifier(AppConstants.defaultPolygonSides);
  final ValueNotifier<bool> filled = ValueNotifier(false);

  // Canvas state
  final ValueNotifier<bool> showGrid = ValueNotifier(false);
  final ValueNotifier<bool> snapToGrid = ValueNotifier(false);
  final GlobalKey canvasGlobalKey = GlobalKey();

  // Drawing data
  late final CurrentStrokeValueNotifier currentStroke;
  late final ValueNotifier<List<Stroke>> allStrokes;
  late final ValueNotifier<ui.Image?> backgroundImage;
  late final ImageNotifier imageNotifier;

  // Unified undo/redo system
  late final UnifiedUndoRedoStack unifiedUndoRedoStack;

  // UI state
  late final AnimationController animationController;
  bool _hasUnsavedChanges = false;
  DateTime? _lastSaveTime;
  String _drawingTitle = 'Untitled Drawing';

  // Services
  final AuthService _authService = AuthService();
  final DrawingPersistenceService _persistenceService = DrawingPersistenceService();
  final ErrorHandlingService _errorHandlingService = ErrorHandlingService();

  @override
  void initState() {
    super.initState();

    _initializeNotifiers();
    _initializeAnimation();
    _initializeUndoRedoSystem();
    _setupListeners();
    _loadDrawing();
  }

  void _initializeNotifiers() {
    currentStroke = CurrentStrokeValueNotifier();
    allStrokes = ValueNotifier<List<Stroke>>([]);
    backgroundImage = ValueNotifier<ui.Image?>(null);
    imageNotifier = ImageNotifier();

    _drawingTitle = widget.initialTitle ?? 'Untitled Drawing';
  }

  void _initializeAnimation() {
    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    animationController.forward();
  }

  void _initializeUndoRedoSystem() {
    unifiedUndoRedoStack = UnifiedUndoRedoStack(
      strokesNotifier: allStrokes,
      imageNotifier: imageNotifier,
      currentStrokeNotifier: currentStroke,
    );
  }

  void _setupListeners() {
    // Listen for changes to mark as unsaved
    allStrokes.addListener(_markAsUnsaved);
    imageNotifier.addListener(_markAsUnsaved);
    currentStroke.addListener(_markAsUnsaved);

    // Listen for keyboard shortcuts
    RawKeyboard.instance.addListener(_handleKeyEvent);
  }

  void _markAsUnsaved() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      final isCtrlPressed = event.isControlPressed;
      final key = event.logicalKey;

      if (isCtrlPressed) {
        switch (key) {
          case LogicalKeyboardKey.keyZ:
            if (event.isShiftPressed) {
              unifiedUndoRedoStack.redo();
            } else {
              unifiedUndoRedoStack.undo();
            }
            break;
          case LogicalKeyboardKey.keyY:
            unifiedUndoRedoStack.redo();
            break;
          case LogicalKeyboardKey.keyS:
            _saveDrawing();
            break;
          case LogicalKeyboardKey.keyN:
            _newDrawing();
            break;
          case LogicalKeyboardKey.keyO:
            _openDrawing();
            break;
          case LogicalKeyboardKey.keyR:
            _resetSelectedImages();
            break;
        }
      } else {
        // Tool shortcuts
        switch (key) {
          case LogicalKeyboardKey.keyP:
            drawingTool.value = DrawingTool.pencil;
            break;
          case LogicalKeyboardKey.keyL:
            drawingTool.value = DrawingTool.line;
            break;
          case LogicalKeyboardKey.keyR:
            drawingTool.value = DrawingTool.rectangle;
            break;
          case LogicalKeyboardKey.keyS:
            drawingTool.value = DrawingTool.square;
            break;
          case LogicalKeyboardKey.keyC:
            drawingTool.value = DrawingTool.circle;
            break;
          case LogicalKeyboardKey.keyT:
            drawingTool.value = DrawingTool.text;
            break;
          case LogicalKeyboardKey.keyE:
            drawingTool.value = DrawingTool.eraser;
            break;
          case LogicalKeyboardKey.keyV:
            drawingTool.value = DrawingTool.imageManipulator; // ✅ Updated
            break;
          case LogicalKeyboardKey.keyM:
            drawingTool.value = DrawingTool.imageManipulator; // ✅ Updated
            break;
          case LogicalKeyboardKey.keyG:
            if (event.isShiftPressed) {
              snapToGrid.value = !snapToGrid.value;
            } else {
              showGrid.value = !showGrid.value;
            }
            break;
          case LogicalKeyboardKey.escape:
          // Cancel current operation
            currentStroke.clear();
            imageNotifier.clearSelection();
            break;
        }
      }
    }
  }

  Future<void> _loadDrawing() async {
    if (widget.drawingId != null) {
      try {
        final drawingData = await _persistenceService.loadDrawing(widget.drawingId!);
        if (drawingData != null) {
          setState(() {
            _drawingTitle = drawingData.title;
            allStrokes.value = drawingData.strokes;
            // Note: Images are not loaded from persistence in this implementation
            _hasUnsavedChanges = false;
          });
        }
      } catch (e) {
        await _errorHandlingService.handleError(
          AppError.file(e, filePath: widget.drawingId),
          showToUser: true,
        );
      }
    }
  }

  // UPDATED: Add guest mode warning to save functionality
  Future<void> _saveDrawing() async {
    try {
      // Check if user is authenticated first
      if (!_authService.isAuthenticated) {
        _showGuestSaveWarning();
        return;
      }

      // Proceed with normal save for authenticated users
      final drawingData = DrawingData(
        title: _drawingTitle,
        strokes: allStrokes.value,
        images: imageNotifier.value.imageList,
        options: _getCurrentOptions(),
      );

      if (widget.drawingId != null) {
        await _persistenceService.saveDrawing(widget.drawingId!, drawingData);
      } else {
        // Create new drawing for authenticated user
        final userId = _authService.currentUser?.id;
        if (userId != null) {
          final drawingId = await _persistenceService.createNewDrawing(
            title: _drawingTitle,
            userId: userId,
          );
          await _persistenceService.saveDrawing(drawingId, drawingData);
        }
      }

      setState(() {
        _hasUnsavedChanges = false;
        _lastSaveTime = DateTime.now();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(SuccessMessages.drawingSaved),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      await _errorHandlingService.handleError(
        AppError.file(e, filePath: _drawingTitle),
        showToUser: true,
      );
    }
  }

  // NEW: Show guest mode save warning
  void _showGuestSaveWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Sign In Required'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To save your drawing permanently, you need to sign in.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('In guest mode:'),
            SizedBox(height: 8),
            Text('• Drawings are saved locally only'),
            Text('• Work may be lost when app is closed'),
            Text('• Cannot sync across devices'),
            Text('• Limited to 10 local drawings'),
            SizedBox(height: 12),
            Text('Sign in to save unlimited drawings to the cloud!'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue as Guest'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToSignIn();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: const Text('Sign In', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // NEW: Navigate to sign in page
  void _navigateToSignIn() {
    Navigator.pushNamed(context, '/login');
  }

  DrawingCanvasOptions _getCurrentOptions() {
    return DrawingCanvasOptions(
      currentTool: drawingTool.value,
      size: strokeSize.value,
      strokeColor: selectedColor.value,
      backgroundColor: AppColors.canvasBackground,
      opacity: opacity.value,
      polygonSides: polygonSides.value,
      showGrid: showGrid.value,
      snapToGrid: snapToGrid.value,
      fillShape: filled.value,
    );
  }

  void _newDrawing() {
    if (_hasUnsavedChanges) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved Changes'),
          content: const Text('You have unsaved changes. Do you want to save before creating a new drawing?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _createNewDrawing();
              },
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _saveDrawing();
                _createNewDrawing();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } else {
      _createNewDrawing();
    }
  }

  void _createNewDrawing() {
    setState(() {
      _drawingTitle = 'Untitled Drawing';
      allStrokes.value = [];
      imageNotifier.clearAll();
      currentStroke.clear();
      unifiedUndoRedoStack.clear();
      _hasUnsavedChanges = false;
      _lastSaveTime = null;
    });
  }

  void _openDrawing() {
    // Navigate to home page to select a drawing
    Navigator.pop(context);
  }

  void _resetSelectedImages() {
    final selectedImages = imageNotifier.value.selectedImages;
    if (selectedImages.isNotEmpty) {
      imageNotifier.resetSelectedImages();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(SuccessMessages.imageReset),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvoked: (bool didPop) async {
        if (!didPop && _hasUnsavedChanges) {
          final shouldPop = await _showExitDialog();
          if (shouldPop == true && context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.canvasBackground,
        body: HotkeyListener(
          onRedo: unifiedUndoRedoStack.redo,
          onUndo: unifiedUndoRedoStack.undo,
          child: Stack(
            children: [
              // Canvas
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
                  snapToGrid,
                  imageNotifier,
                ]),
                builder: (context, _) {
                  return DrawingCanvas(
                    options: _getCurrentOptions(),
                    canvasKey: canvasGlobalKey,
                    currentStrokeListenable: currentStroke,
                    strokesListenable: allStrokes,
                    backgroundImageListenable: backgroundImage,
                    imageNotifier: imageNotifier,
                  );
                },
              ),

              // Side panel
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
                    undoRedoStack: unifiedUndoRedoStack,
                    showGrid: showGrid,
                    snapToGrid: snapToGrid,
                    imageNotifier: imageNotifier,
                  ),
                ),
              ),

              // Top app bar
              _CustomAppBar(
                animationController: animationController,
                title: _drawingTitle,
                hasUnsavedChanges: _hasUnsavedChanges,
                isAuthenticated: _authService.isAuthenticated,
                lastSaveTime: _lastSaveTime,
                onSave: _saveDrawing,
                onTitleChanged: (newTitle) {
                  setState(() {
                    _drawingTitle = newTitle;
                    _hasUnsavedChanges = true;
                  });
                },
                onNew: _newDrawing,
                onOpen: _openDrawing,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showExitDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. Do you want to save before leaving?'),
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
              if (context.mounted) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Clean up listeners
    RawKeyboard.instance.removeListener(_handleKeyEvent);
    allStrokes.removeListener(_markAsUnsaved);
    imageNotifier.removeListener(_markAsUnsaved);
    currentStroke.removeListener(_markAsUnsaved);

    // Dispose notifiers
    selectedColor.dispose();
    strokeSize.dispose();
    eraserSize.dispose();
    opacity.dispose();
    drawingTool.dispose();
    polygonSides.dispose();
    filled.dispose();
    showGrid.dispose();
    snapToGrid.dispose();
    currentStroke.dispose();
    allStrokes.dispose();
    backgroundImage.dispose();
    imageNotifier.dispose();

    // Dispose undo/redo system
    unifiedUndoRedoStack.dispose();

    // Dispose animation
    animationController.dispose();

    super.dispose();
  }
}

/// Custom app bar with drawing-specific functionality
class _CustomAppBar extends StatelessWidget {
  final AnimationController animationController;
  final String title;
  final bool hasUnsavedChanges;
  final bool isAuthenticated;
  final DateTime? lastSaveTime;
  final VoidCallback onSave;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onNew;
  final VoidCallback onOpen;

  const _CustomAppBar({
    required this.animationController,
    required this.title,
    required this.hasUnsavedChanges,
    required this.isAuthenticated,
    this.lastSaveTime,
    required this.onSave,
    required this.onTitleChanged,
    required this.onNew,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kToolbarHeight,
      color: Colors.white,
      child: Row(
        children: [
          // Menu button
          IconButton(
            onPressed: () {
              if (animationController.isCompleted) {
                animationController.reverse();
              } else {
                animationController.forward();
              }
            },
            icon: AnimatedBuilder(
              animation: animationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: animationController.value * 0.5,
                  child: const Icon(Icons.menu),
                );
              },
            ),
          ),

          // Title with edit capability
          Expanded(
            child: GestureDetector(
              onTap: () => _editTitle(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasUnsavedChanges)
                      const Icon(
                        Icons.circle,
                        size: 8,
                        color: Colors.orange,
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Action buttons
          if (lastSaveTime != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Saved ${_formatTime(lastSaveTime!)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                ),
              ),
            ),

          IconButton(
            onPressed: onNew,
            icon: const Icon(Icons.add),
            tooltip: 'New Drawing (${AppShortcuts.newDrawing})',
          ),

          // UPDATED: Only show Open button for authenticated users
          if (isAuthenticated)
            IconButton(
              onPressed: onOpen,
              icon: const Icon(Icons.folder_open),
              tooltip: 'Open Drawing (${AppShortcuts.open})',
            ),

          IconButton(
            onPressed: onSave,
            icon: Icon(
              Icons.save,
              color: hasUnsavedChanges ? Colors.orange : null,
            ),
            tooltip: isAuthenticated
                ? 'Save Drawing (${AppShortcuts.save})'
                : 'Save (Sign in required)',
          ),

          // User status
          if (isAuthenticated)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.cloud_done,
                color: Colors.green,
                size: 20,
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.cloud_off,
                color: Colors.orange,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  void _editTitle(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: title);
        return AlertDialog(
          title: const Text('Rename Drawing'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Drawing Name',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                onTitleChanged(value.trim());
              }
              Navigator.pop(context);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newTitle = controller.text.trim();
                if (newTitle.isNotEmpty) {
                  onTitleChanged(newTitle);
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}