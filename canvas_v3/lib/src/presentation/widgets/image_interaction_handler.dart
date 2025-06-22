// lib/src/presentation/handlers/image_interaction_handler.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/extensions/extensions.dart';

enum InteractionState {
  idle,
  dragging,
  resizing,
  rotating,
  selecting,
}

class InteractionContext {
  final Offset startPosition;
  final CanvasImage? targetImage;
  final List<CanvasImage>? selectedImages;
  final HandleType? handle;
  final Map<String, Matrix4>? initialTransforms;
  final Rect? selectionRect;

  InteractionContext({
    required this.startPosition,
    this.targetImage,
    this.selectedImages,
    this.handle,
    this.initialTransforms,
    this.selectionRect,
  });

  InteractionContext copyWith({
    Offset? startPosition,
    CanvasImage? targetImage,
    List<CanvasImage>? selectedImages,
    HandleType? handle,
    Map<String, Matrix4>? initialTransforms,
    Rect? selectionRect,
  }) {
    return InteractionContext(
      startPosition: startPosition ?? this.startPosition,
      targetImage: targetImage ?? this.targetImage,
      selectedImages: selectedImages ?? this.selectedImages,
      handle: handle ?? this.handle,
      initialTransforms: initialTransforms ?? this.initialTransforms,
      selectionRect: selectionRect ?? this.selectionRect,
    );
  }
}

class ImageInteractionHandler {
  final ImageNotifier imageNotifier;
  final ValueNotifier<InteractionContext?> contextNotifier = ValueNotifier(null);

  InteractionState _state = InteractionState.idle;
  InteractionContext? _context;

  // Keyboard state
  bool _isShiftPressed = false;
  bool _isCtrlPressed = false;
  bool _isAltPressed = false;

  static const double handleSize = 16.0;
  static const double rotationHandleDistance = 30.0;

  ImageInteractionHandler({required this.imageNotifier}) {
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    contextNotifier.dispose();
  }

  InteractionState get state => _state;
  InteractionContext? get context => _context;

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyUpEvent) {
      _isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      _isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      _isAltPressed = HardwareKeyboard.instance.isAltPressed;
    }

    if (event is KeyDownEvent) {
      // Handle keyboard shortcuts
      if (_isCtrlPressed) {
        switch (event.logicalKey) {
          case LogicalKeyboardKey.keyA:
            imageNotifier.selectAll();
            return true;
          case LogicalKeyboardKey.keyC:
            imageNotifier.copy();
            return true;
          case LogicalKeyboardKey.keyX:
            imageNotifier.cut();
            return true;
          case LogicalKeyboardKey.keyV:
            imageNotifier.paste(const Offset(400, 300)); // Center of standard canvas
            return true;
          case LogicalKeyboardKey.keyD:
            imageNotifier.deselectAll();
            return true;
          case LogicalKeyboardKey.keyZ:
            if (_isShiftPressed) {
              imageNotifier.redo();
            } else {
              imageNotifier.undo();
            }
            return true;
          case LogicalKeyboardKey.keyY:
            imageNotifier.redo();
            return true;
        }
      }

      // Delete selected images
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        imageNotifier.removeSelectedImages();
        return true;
      }

      // Arrow keys for nudging
      if (imageNotifier.value.hasSelection) {
        Offset? nudge;
        final nudgeAmount = _isShiftPressed ? 10.0 : 1.0;

        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            nudge = Offset(-nudgeAmount, 0);
            break;
          case LogicalKeyboardKey.arrowRight:
            nudge = Offset(nudgeAmount, 0);
            break;
          case LogicalKeyboardKey.arrowUp:
            nudge = Offset(0, -nudgeAmount);
            break;
          case LogicalKeyboardKey.arrowDown:
            nudge = Offset(0, nudgeAmount);
            break;
        }

        if (nudge != null) {
          imageNotifier.transform(delta: nudge);
          return true;
        }
      }
    }

    return false;
  }

  void handlePointerDown(Offset position, Size canvasSize) {
    final standardPosition = position.scaleToStandard(canvasSize);
    final hitResult = _hitTest(standardPosition);

    if (hitResult.image != null) {
      if (hitResult.handle != null) {
        // Start resizing or rotating
        _startHandleInteraction(hitResult.image!, hitResult.handle!, standardPosition);
      } else {
        // Start dragging
        _startDragging(hitResult.image!, standardPosition);
      }
    } else {
      // Start selection rectangle
      _startSelection(standardPosition);
    }

    contextNotifier.value = _context;
  }

  void handlePointerMove(Offset position, Size canvasSize) {
    if (_state == InteractionState.idle) return;

    final standardPosition = position.scaleToStandard(canvasSize);

    switch (_state) {
      case InteractionState.dragging:
        _updateDragging(standardPosition);
        break;
      case InteractionState.resizing:
        _updateResizing(standardPosition);
        break;
      case InteractionState.rotating:
        _updateRotating(standardPosition);
        break;
      case InteractionState.selecting:
        _updateSelection(standardPosition);
        break;
      case InteractionState.idle:
        break;
    }

    contextNotifier.value = _context;
  }

  void handlePointerUp() {
    _state = InteractionState.idle;
    _context = null;
    _lastDragPosition = null; // Reset last drag position
    contextNotifier.value = null;
  }


  MouseCursor getCursor(Offset position, Size canvasSize) {
    final standardPosition = position.scaleToStandard(canvasSize);
    final hitResult = _hitTest(standardPosition);

    if (hitResult.handle != null) {
      switch (hitResult.handle!) {
        case HandleType.topLeft:
        case HandleType.bottomRight:
          return SystemMouseCursors.resizeUpLeftDownRight;
        case HandleType.topRight:
        case HandleType.bottomLeft:
          return SystemMouseCursors.resizeUpRightDownLeft;
        case HandleType.topMiddle:
        case HandleType.bottomMiddle:
          return SystemMouseCursors.resizeUpDown;
        case HandleType.leftMiddle:
        case HandleType.rightMiddle:
          return SystemMouseCursors.resizeLeftRight;
        case HandleType.rotation:
          return SystemMouseCursors.click;
      }
    } else if (hitResult.image != null) {
      return SystemMouseCursors.move;
    }

    return SystemMouseCursors.basic;
  }

  // Hit testing
  HitTestResult _hitTest(Offset position) {
    // Check handles first (only for single selection)
    if (imageNotifier.value.selectedIds.length == 1) {
      final selectedId = imageNotifier.value.selectedIds.first;
      final selectedImage = imageNotifier.value.images[selectedId];

      if (selectedImage != null) {
        final handles = selectedImage.getHandles();

        for (final entry in handles.entries) {
          final handleRect = Rect.fromCenter(
            center: entry.value,
            width: handleSize,
            height: handleSize,
          );

          if (handleRect.contains(position)) {
            return HitTestResult(image: selectedImage, handle: entry.key);
          }
        }
      }
    }

    // Check images from top to bottom
    final image = imageNotifier.getImageAt(position);
    return HitTestResult(image: image);
  }

  // Interaction starters
  void _startHandleInteraction(CanvasImage image, HandleType handle, Offset position) {
    if (handle == HandleType.rotation) {
      _state = InteractionState.rotating;
    } else {
      _state = InteractionState.resizing;
    }

    _context = InteractionContext(
      startPosition: position,
      targetImage: image,
      handle: handle,
      initialTransforms: {
        image.id: image.transform.clone(),
      },
    );
  }

  Offset? _lastDragPosition;


  void _startDragging(CanvasImage image, Offset position) {
    // Select if not already selected
    if (!imageNotifier.value.selectedIds.contains(image.id)) {
      imageNotifier.select([image.id], toggle: _isCtrlPressed, clear: !_isCtrlPressed);
    }

    // Store initial transforms for all selected images
    final initialTransforms = <String, Matrix4>{};
    for (final id in imageNotifier.value.selectedIds) {
      final img = imageNotifier.value.images[id];
      if (img != null) {
        initialTransforms[id] = img.transform.clone();
      }
    }

    _lastDragPosition = position;

    _state = InteractionState.dragging;
    _context = InteractionContext(
      startPosition: position,
      targetImage: image,
      selectedImages: imageNotifier.value.selectedImages,
      initialTransforms: initialTransforms,
    );
  }


  void _startSelection(Offset position) {
    if (!_isCtrlPressed) {
      imageNotifier.deselectAll();
    }

    _state = InteractionState.selecting;
    _context = InteractionContext(
      startPosition: position,
      selectionRect: Rect.fromPoints(position, position),
    );
  }

  // Update methods
  void _updateDragging(Offset position) {
    if (_context == null || _lastDragPosition == null) return;

    // Calculate delta from last position, not from start
    final delta = position - _lastDragPosition!;

    // Update last position
    _lastDragPosition = position;

    imageNotifier.transform(delta: delta);
  }

  void _updateResizing(Offset position) {
    if (_context == null || _context!.targetImage == null || _context!.handle == null) return;

    final image = _context!.targetImage!;
    final handle = _context!.handle!;
    final initialTransform = _context!.initialTransforms![image.id]!;

    // Calculate new transform based on handle
    final newTransform = _calculateResizeTransform(
      image: image,
      handle: handle,
      currentPosition: position,
      initialTransform: initialTransform,
      maintainAspectRatio: _isShiftPressed,
    );

    imageNotifier.transform(
      imageIds: [image.id],
      transform: newTransform,
    );
  }

  void _updateRotating(Offset position) {
    if (_context == null || _context!.targetImage == null) return;

    final image = _context!.targetImage!;

    // Get the image bounds in world space
    final bounds = image.bounds;
    final center = bounds.center;

    // Store initial angle on first rotation
    if (!_context!.initialTransforms!.containsKey('_rotation_start_angle')) {
      final startAngle = math.atan2(
        _context!.startPosition.dy - center.dy,
        _context!.startPosition.dx - center.dx,
      );
      // Store as a pseudo entry
      _rotationStartAngle = startAngle;
      _initialRotation = image.rotation;
    }

    final currentAngle = math.atan2(
      position.dy - center.dy,
      position.dx - center.dx,
    );

    var rotationDelta = currentAngle - _rotationStartAngle!;

    // Snap to 45 degree increments if Alt is pressed
    if (_isAltPressed) {
      const snapAngle = math.pi / 4; // 45 degrees
      rotationDelta = (rotationDelta / snapAngle).round() * snapAngle;
    }

    // Apply rotation as absolute value, not delta
    final newRotation = _initialRotation! + rotationDelta;

    imageNotifier.transform(
      imageIds: [image.id],
      rotation: rotationDelta, // Pass delta, not absolute
      scaleOrigin: center,
    );
  }

// Add these fields to ImageInteractionHandler:
  double? _rotationStartAngle;
  double? _initialRotation;

  void _updateSelection(Offset position) {
    if (_context == null) return;

    final rect = Rect.fromPoints(_context!.startPosition, position);
    _context = _context!.copyWith(selectionRect: rect);

    imageNotifier.selectInRect(rect);
  }

  // Helper method to calculate resize transform
  Matrix4 _calculateResizeTransform({
    required CanvasImage image,
    required HandleType handle,
    required Offset currentPosition,
    required Matrix4 initialTransform,
    required bool maintainAspectRatio,
  }) {
    // This is a simplified version - you would implement full resize logic here
    final bounds = image.bounds;
    final delta = currentPosition - _context!.startPosition;

    double scaleX = 1.0;
    double scaleY = 1.0;
    Offset translation = Offset.zero;

    switch (handle) {
      case HandleType.bottomRight:
        scaleX = 1 + (delta.dx / bounds.width);
        scaleY = 1 + (delta.dy / bounds.height);
        break;
      case HandleType.topLeft:
        scaleX = 1 - (delta.dx / bounds.width);
        scaleY = 1 - (delta.dy / bounds.height);
        translation = delta;
        break;
    // Add other handle cases...
      default:
        break;
    }

    if (maintainAspectRatio) {
      final scale = (scaleX + scaleY) / 2;
      scaleX = scale;
      scaleY = scale;
    }

    final transform = Matrix4.identity()
      ..translate(translation.dx, translation.dy)
      ..scale(scaleX, scaleY);

    return initialTransform.clone()..multiply(transform);
  }
}

class HitTestResult {
  final CanvasImage? image;
  final HandleType? handle;

  HitTestResult({this.image, this.handle});
}