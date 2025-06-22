// lib/src/domain/models/unified_undo_redo_stack.dart

import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/domain/models/stroke.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';

/// Unified undo/redo system that handles both strokes and images
class UnifiedUndoRedoStack {
  final ValueNotifier<List<Stroke>> strokesNotifier;
  final ImageNotifier imageNotifier;
  final ValueNotifier<Stroke?> currentStrokeNotifier;

  final List<CanvasOperation> _undoStack = [];
  final List<CanvasOperation> _redoStack = [];
  final ValueNotifier<bool> _canUndo = ValueNotifier(false);
  final ValueNotifier<bool> _canRedo = ValueNotifier(false);

  UnifiedUndoRedoStack({
    required this.strokesNotifier,
    required this.imageNotifier,
    required this.currentStrokeNotifier,
  }) {
    // Listen for stroke changes
    strokesNotifier.addListener(_onStrokesChanged);

    // Listen for image changes
    imageNotifier.addListener(_onImagesChanged);
  }

  ValueNotifier<bool> get canUndo => _canUndo;
  ValueNotifier<bool> get canRedo => _canRedo;

  int _lastStrokeCount = 0;
  ImageState? _lastImageState;
  bool _isPerformingOperation = false;

  void _onStrokesChanged() {
    if (_isPerformingOperation) return;

    final currentCount = strokesNotifier.value.length;

    // Check if a stroke was added
    if (currentCount > _lastStrokeCount) {
      final newStroke = strokesNotifier.value.last;
      _addOperation(StrokeAddOperation(stroke: newStroke));
    }

    _lastStrokeCount = currentCount;
  }

  void _onImagesChanged() {
    if (_isPerformingOperation) return;

    final currentState = imageNotifier.value;

    if (_lastImageState != null) {
      // Determine what changed
      final operation = _detectImageOperation(_lastImageState!, currentState);
      if (operation != null) {
        _addOperation(operation);
      }
    }

    _lastImageState = ImageState.from(currentState);
  }

  CanvasOperation? _detectImageOperation(ImageState oldState, ImageState newState) {
    // Check for added images
    for (final entry in newState.images.entries) {
      if (!oldState.images.containsKey(entry.key)) {
        return ImageAddOperation(image: entry.value);
      }
    }

    // Check for removed images
    for (final entry in oldState.images.entries) {
      if (!newState.images.containsKey(entry.key)) {
        return ImageRemoveOperation(
          image: entry.value,
          index: oldState.imageList.indexOf(entry.value),
        );
      }
    }

    // Check for transformed images
    for (final entry in newState.images.entries) {
      final oldImage = oldState.images[entry.key];
      if (oldImage != null && !_matricesEqual(oldImage.transform, entry.value.transform)) {
        return ImageTransformOperation(
          imageId: entry.key,
          oldTransform: oldImage.transform,
          newTransform: entry.value.transform,
        );
      }
    }

    return null;
  }

  void _addOperation(CanvasOperation operation) {
    // Clear redo stack when new operation is added
    _redoStack.clear();

    // Add to undo stack
    _undoStack.add(operation);

    // Limit stack size
    if (_undoStack.length > AppConstants.maxUndoOperations) {
      _undoStack.removeAt(0);
    }

    _updateCanFlags();
  }

  /// Manually add an operation (for programmatic changes)
  void addOperation(CanvasOperation operation) {
    _addOperation(operation);
  }

  void undo() {
    if (_undoStack.isEmpty) return;

    _isPerformingOperation = true;

    try {
      final operation = _undoStack.removeLast();
      operation.undo(strokesNotifier, imageNotifier);
      _redoStack.add(operation);

      // Update tracking state
      _lastStrokeCount = strokesNotifier.value.length;
      _lastImageState = ImageState.from(imageNotifier.value);

      _updateCanFlags();
    } finally {
      _isPerformingOperation = false;
    }
  }

  void redo() {
    if (_redoStack.isEmpty) return;

    _isPerformingOperation = true;

    try {
      final operation = _redoStack.removeLast();
      operation.redo(strokesNotifier, imageNotifier);
      _undoStack.add(operation);

      // Update tracking state
      _lastStrokeCount = strokesNotifier.value.length;
      _lastImageState = ImageState.from(imageNotifier.value);

      _updateCanFlags();
    } finally {
      _isPerformingOperation = false;
    }
  }

  void clear() {
    _isPerformingOperation = true;

    try {
      _undoStack.clear();
      _redoStack.clear();
      strokesNotifier.value = [];
      imageNotifier.clearAll();
      currentStrokeNotifier.value = null;

      _lastStrokeCount = 0;
      _lastImageState = ImageState.from(imageNotifier.value);

      _updateCanFlags();
    } finally {
      _isPerformingOperation = false;
    }
  }

  void _updateCanFlags() {
    _canUndo.value = _undoStack.isNotEmpty;
    _canRedo.value = _redoStack.isNotEmpty;
  }

  bool _matricesEqual(Matrix4 a, Matrix4 b) {
    const tolerance = 0.001;
    for (int i = 0; i < 16; i++) {
      if ((a.storage[i] - b.storage[i]).abs() > tolerance) {
        return false;
      }
    }
    return true;
  }

  /// Get operation history for debugging
  List<String> get operationHistory {
    return _undoStack.map((op) => op.description).toList();
  }

  void dispose() {
    strokesNotifier.removeListener(_onStrokesChanged);
    imageNotifier.removeListener(_onImagesChanged);
    _canUndo.dispose();
    _canRedo.dispose();
  }
}

/// Base class for canvas operations
abstract class CanvasOperation {
  void undo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier);
  void redo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier);
  String get description;
  DateTime get timestamp => DateTime.now();
}

/// Operation for adding a stroke
class StrokeAddOperation extends CanvasOperation {
  final Stroke stroke;
  final DateTime _timestamp;

  StrokeAddOperation({required this.stroke}) : _timestamp = DateTime.now();

  @override
  void undo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    final strokes = List<Stroke>.from(strokesNotifier.value);
    if (strokes.isNotEmpty && strokes.last.toString() == stroke.toString()) {
      strokes.removeLast();
      strokesNotifier.value = strokes;
    }
  }

  @override
  void redo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    strokesNotifier.value = List<Stroke>.from(strokesNotifier.value)..add(stroke);
  }

  @override
  String get description => 'Add ${stroke.strokeType.name} stroke';

  @override
  DateTime get timestamp => _timestamp;
}

/// Operation for adding an image
class ImageAddOperation extends CanvasOperation {
  final CanvasImage image;
  final DateTime _timestamp;

  ImageAddOperation({required this.image}) : _timestamp = DateTime.now();

  @override
  void undo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    imageNotifier.removeImages([image.id]);
  }

  @override
  void redo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    imageNotifier.addImage(image);
  }

  @override
  String get description => 'Add image';

  @override
  DateTime get timestamp => _timestamp;
}

/// Operation for removing an image
class ImageRemoveOperation extends CanvasOperation {
  final CanvasImage image;
  final int index;
  final DateTime _timestamp;

  ImageRemoveOperation({required this.image, required this.index}) : _timestamp = DateTime.now();

  @override
  void undo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    imageNotifier.addImage(image);
  }

  @override
  void redo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    imageNotifier.removeImages([image.id]);
  }

  @override
  String get description => 'Remove image';

  @override
  DateTime get timestamp => _timestamp;
}

/// Operation for transforming an image
class ImageTransformOperation extends CanvasOperation {
  final String imageId;
  final Matrix4 oldTransform;
  final Matrix4 newTransform;
  final DateTime _timestamp;

  ImageTransformOperation({
    required this.imageId,
    required this.oldTransform,
    required this.newTransform,
  }) : _timestamp = DateTime.now();

  @override
  void undo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    imageNotifier.applyTransforms({imageId: oldTransform});
  }

  @override
  void redo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    imageNotifier.applyTransforms({imageId: newTransform});
  }

  @override
  String get description => 'Transform image';

  @override
  DateTime get timestamp => _timestamp;
}

/// Operation for resetting image transform
class ImageResetOperation extends CanvasOperation {
  final String imageId;
  final Matrix4 oldTransform;
  final Matrix4 originalTransform;
  final DateTime _timestamp;

  ImageResetOperation({
    required this.imageId,
    required this.oldTransform,
    required this.originalTransform,
  }) : _timestamp = DateTime.now();

  @override
  void undo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    imageNotifier.applyTransforms({imageId: oldTransform});
  }

  @override
  void redo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    imageNotifier.applyTransforms({imageId: originalTransform});
  }

  @override
  String get description => 'Reset image transform';

  @override
  DateTime get timestamp => _timestamp;
}

/// Compound operation for multiple changes
class CompoundOperation extends CanvasOperation {
  final List<CanvasOperation> operations;
  final String _description;
  final DateTime _timestamp;

  CompoundOperation({
    required this.operations,
    required String description,
  }) : _description = description,
        _timestamp = DateTime.now();

  @override
  void undo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    // Undo in reverse order
    for (final operation in operations.reversed) {
      operation.undo(strokesNotifier, imageNotifier);
    }
  }

  @override
  void redo(ValueNotifier<List<Stroke>> strokesNotifier, ImageNotifier imageNotifier) {
    // Redo in original order
    for (final operation in operations) {
      operation.redo(strokesNotifier, imageNotifier);
    }
  }

  @override
  String get description => _description;

  @override
  DateTime get timestamp => _timestamp;
}

/// Extension for ImageState to create copies
extension ImageStateExtensions on ImageState {
  static ImageState from(ImageState other) {
    return ImageState(
      images: Map<String, CanvasImage>.from(other.images),
      selectedIds: Set<String>.from(other.selectedIds),
      clipboard: List<CanvasImage>.from(other.clipboard),
    );
  }
}