// lib/src/presentation/widgets/image_interaction_handler.dart

import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/interaction_enums.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';

class ImageInteractionHandler {
  final ImageNotifier imageNotifier;
  final VoidCallback? onImageStateChanged;
  final ValueNotifier<InteractionContext?> contextNotifier = ValueNotifier(null);

  InteractionState _state = InteractionState.idle;
  String? _activeImageId;
  Offset? _lastPanPoint;
  double _initialScale = 1.0;
  double _initialRotation = 0.0;
  Matrix4? _initialTransform;

  // Double-tap detection
  DateTime? _lastTapTime;
  String? _lastTappedImageId;

  ImageInteractionHandler(
      this.imageNotifier, {
        this.onImageStateChanged,
      });

  InteractionState get state => _state;

  void handlePointerDown(Offset offset, Size canvasSize) {
    final now = DateTime.now();
    final images = imageNotifier.value.imageList;
    String? tappedImageId;

    // Find which image was tapped (check in reverse order for top-most)
    for (final image in images.reversed) {
      if (_isPointInImage(offset, image, canvasSize)) {
        tappedImageId = image.id;
        break;
      }
    }

    // Check for double-tap
    if (tappedImageId != null &&
        _lastTappedImageId == tappedImageId &&
        _lastTapTime != null &&
        now.difference(_lastTapTime!) < AppConstants.doubleTapTimeout) {

      // Double-tap detected - reset image
      _handleDoubleClick(tappedImageId);

      // Clear tap tracking
      _lastTapTime = null;
      _lastTappedImageId = null;

      return;
    }

    // Update tap tracking
    _lastTapTime = now;
    _lastTappedImageId = tappedImageId;

    // Continue with normal interaction
    if (tappedImageId != null) {
      _startDrag(tappedImageId, offset, canvasSize);
    } else {
      // Clear selection if clicking on empty space
      imageNotifier.clearSelection();
      _setState(InteractionState.idle);
    }
  }

  void handlePointerMove(Offset offset, Size canvasSize) {
    if (_state == InteractionState.idle || _activeImageId == null) return;

    switch (_state) {
      case InteractionState.dragging:
        _handleDrag(offset, canvasSize);
        break;
      case InteractionState.scaling:
        _handleScale(offset, canvasSize);
        break;
      case InteractionState.rotating:
        _handleRotation(offset, canvasSize);
        break;
      case InteractionState.idle:
        break;
    }
  }

  void handlePointerUp() {
    if (_state != InteractionState.idle) {
      _finalizeTransform();
      _setState(InteractionState.idle);
    }

    _activeImageId = null;
    _lastPanPoint = null;
    _initialTransform = null;
  }

  void _handleDoubleClick(String imageId) {
    final currentState = imageNotifier.value;
    final image = currentState.images[imageId];

    if (image != null && image.isModified) {
      // Store old transform for undo
      final oldTransform = Matrix4.copy(image.transform);

      // Reset image to original transform
      final resetImage = image.resetTransform();

      // Update image in the notifier
      final newImages = Map<String, CanvasImage>.from(currentState.images);
      newImages[imageId] = resetImage;

      imageNotifier.value = currentState.copyWith(images: newImages);
      onImageStateChanged?.call();

      // Show feedback to user
      debugPrint('Image ${image.id} reset to original transform');
    }
  }

  void _startDrag(String imageId, Offset offset, Size canvasSize) {
    _activeImageId = imageId;
    _lastPanPoint = offset;

    // Select the image
    imageNotifier.selectImage(imageId);

    final image = imageNotifier.value.images[imageId];
    if (image != null) {
      _initialTransform = Matrix4.copy(image.transform);
      _initialScale = image.scale;
      _initialRotation = image.rotation;
    }

    _setState(InteractionState.dragging);
  }

  void _handleDrag(Offset offset, Size canvasSize) {
    if (_lastPanPoint == null || _activeImageId == null) return;

    final delta = offset - _lastPanPoint!;
    _lastPanPoint = offset;

    // Apply translation
    final transform = Matrix4.identity()..translate(delta.dx, delta.dy);

    imageNotifier.applyTransforms({
      _activeImageId!: transform,
    });

    onImageStateChanged?.call();
  }

  void _handleScale(Offset offset, Size canvasSize) {
    // TODO: Implement pinch-to-scale functionality
    // This would require multi-touch support
  }

  void _handleRotation(Offset offset, Size canvasSize) {
    // TODO: Implement rotation gesture
    // This would require detecting rotation gestures
  }

  void _finalizeTransform() {
    if (_activeImageId == null || _initialTransform == null) return;

    final currentImage = imageNotifier.value.images[_activeImageId!];
    if (currentImage != null) {
      // The transform has already been applied through applyTransforms
      // This is where we could add the operation to undo/redo stack
      onImageStateChanged?.call();
    }
  }

  bool _isPointInImage(Offset point, CanvasImage image, Size canvasSize) {
    try {
      // Convert point to image space
      final inverse = Matrix4.inverted(image.transform);
      final imagePoint = MatrixUtils.transformPoint(inverse, point);

      // Check if point is within image bounds
      return imagePoint.dx >= 0 &&
          imagePoint.dx <= image.image.width &&
          imagePoint.dy >= 0 &&
          imagePoint.dy <= image.image.height;
    } catch (e) {
      // If matrix inversion fails, fall back to bounds check
      return image.bounds.contains(point);
    }
  }

  void _setState(InteractionState newState) {
    if (_state != newState) {
      _state = newState;

      // Update context for UI feedback
      contextNotifier.value = _state != InteractionState.idle
          ? InteractionContext(
        state: _state,
        activeImageId: _activeImageId,
        lastPointerPosition: _lastPanPoint,
      )
          : null;
    }
  }

  /// Reset image to original transform programmatically
  void resetImage(String imageId) {
    _handleDoubleClick(imageId);
  }

  /// Reset all selected images
  void resetSelectedImages() {
    final selectedIds = imageNotifier.value.selectedIds;
    for (final id in selectedIds) {
      resetImage(id);
    }
  }

  /// Check if image can be reset (has been modified)
  bool canResetImage(String imageId) {
    final image = imageNotifier.value.images[imageId];
    return image?.isModified ?? false;
  }

  void dispose() {
    contextNotifier.dispose();
  }
}

/// Context information for current interaction
class InteractionContext {
  final InteractionState state;
  final String? activeImageId;
  final Offset? lastPointerPosition;

  const InteractionContext({
    required this.state,
    this.activeImageId,
    this.lastPointerPosition,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is InteractionContext &&
        other.state == state &&
        other.activeImageId == activeImageId &&
        other.lastPointerPosition == lastPointerPosition;
  }

  @override
  int get hashCode {
    return Object.hash(state, activeImageId, lastPointerPosition);
  }

  @override
  String toString() {
    return 'InteractionContext('
        'state: $state, '
        'activeImageId: $activeImageId, '
        'lastPointerPosition: $lastPointerPosition'
        ')';
  }
}