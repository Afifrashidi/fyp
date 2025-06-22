// lib/src/presentation/notifiers/image_notifier.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/canvas_operations_enums.dart';
import 'package:flutter_drawing_board/src/constants/interaction_enums.dart'; // Added this import
import 'package:vector_math/vector_math_64.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';
import 'package:flutter_drawing_board/src/domain/models/image_command.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';
import 'package:flutter_drawing_board/src/services/error_handling_service.dart';

// Unified ImageState class combining both versions
class ImageState {
  final Map<String, CanvasImage> images;
  final Set<String> selectedIds;
  final List<CanvasImage> clipboard;
  final List<ImageCommand> history;
  final int historyIndex;

  const ImageState({
    this.images = const {},
    this.selectedIds = const {},
    this.clipboard = const [],
    this.history = const [],
    this.historyIndex = -1,
  });

  factory ImageState.from(ImageState other) {
    return ImageState(
      images: Map<String, CanvasImage>.from(other.images),
      selectedIds: Set<String>.from(other.selectedIds),
      clipboard: List<CanvasImage>.from(other.clipboard),
    );
  }

  List<CanvasImage> get imageList => images.values.toList();

  List<CanvasImage> get selectedImages {
    return selectedIds
        .map((id) => images[id])
        .where((image) => image != null)
        .cast<CanvasImage>()
        .toList();
  }

  bool get hasSelection => selectedIds.isNotEmpty;
  bool get canUndo => historyIndex >= 0;
  bool get canRedo => historyIndex < history.length - 1;

  ImageState copyWith({
    Map<String, CanvasImage>? images,
    Set<String>? selectedIds,
    List<CanvasImage>? clipboard,
    List<ImageCommand>? history,
    int? historyIndex,
  }) {
    return ImageState(
      images: images ?? this.images,
      selectedIds: selectedIds ?? this.selectedIds,
      clipboard: clipboard ?? this.clipboard,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
    );
  }
}

/// Improved ImageNotifier with consistent command execution
class ImageNotifier extends ValueNotifier<ImageState> {
  final ErrorHandlingService _errorHandler = ErrorHandlingService();
  final Set<String> _removedImageIds = <String>{};

  ImageNotifier() : super(const ImageState());

  // Convenience getters
  List<CanvasImage> get imageList => value.imageList;
  Set<String> get selectedIds => value.selectedIds;
  bool get hasSelection => value.hasSelection;
  List<CanvasImage> get selectedImages => value.selectedImages;
  bool get canUndo => value.canUndo;
  bool get canRedo => value.canRedo;

  /// Execute a command and add to history
  void executeCommand(ImageCommand command) {
    try {
      // Execute the command
      command.execute(this);

      // Update history
      final newHistory = List<ImageCommand>.from(value.history);

      // Remove any commands after current index (for redo scenario)
      if (value.historyIndex >= 0) {
        newHistory.removeRange(value.historyIndex + 1, newHistory.length);
      }

      // Add new command
      newHistory.add(command);

      // Limit history size
      if (newHistory.length > AppConstants.maxUndoOperations) {
        newHistory.removeAt(0);
      }

      final newIndex = newHistory.length - 1;

      value = value.copyWith(
        history: newHistory,
        historyIndex: newIndex,
      );

    } catch (e, stackTrace) {
      _errorHandler.handleError(
        AppError.canvas(e, operation: 'executeCommand'),
        showToUser: true,
      );
      debugPrint('Error executing command: $e\n$stackTrace');
    }
  }

  /// Add a single image - now uses command pattern consistently
  void addImage(CanvasImage image) {
    executeCommand(AddImagesCommand([image]));
  }

  /// Add multiple images - called by commands, not user directly
  void addImages(List<CanvasImage> images) {
    if (images.isEmpty) return;

    try {
      final newImages = Map<String, CanvasImage>.from(value.images);

      for (final image in images) {
        newImages[image.id] = image;
      }

      value = value.copyWith(images: newImages);
      debugPrint('Added ${images.length} images');

    } catch (e, stackTrace) {
      _errorHandler.handleError(
        AppError.canvas(e, operation: 'addImages'),
        showToUser: true,
      );
      throw e; // Re-throw for command error handling
    }
  }

  /// Remove images by IDs - called by commands
  void removeImages(List<String> imageIds) {
    if (imageIds.isEmpty) return;

    try {
      final newImages = Map<String, CanvasImage>.from(value.images);
      final newSelection = Set<String>.from(value.selectedIds);

      for (final id in imageIds) {
        newImages.remove(id);
        newSelection.remove(id);
        _removedImageIds.add(id);
      }

      value = value.copyWith(
        images: newImages,
        selectedIds: newSelection,
      );

      _scheduleImageCleanup();
      debugPrint('Removed ${imageIds.length} images');

    } catch (e, stackTrace) {
      _errorHandler.handleError(
        AppError.canvas(e, operation: 'removeImages'),
        showToUser: true,
      );
      throw e;
    }
  }

  /// Apply transforms - called by commands
  void applyTransforms(Map<String, Matrix4> transforms) {
    if (transforms.isEmpty) return;

    try {
      final newImages = Map<String, CanvasImage>.from(value.images);

      transforms.forEach((id, newTransform) {
        final image = newImages[id];
        if (image != null) {
          newImages[id] = image.copyWith(transform: newTransform);
        }
      });

      value = value.copyWith(images: newImages);

    } catch (e, stackTrace) {
      _errorHandler.handleError(
        AppError.canvas(e, operation: 'applyTransforms'),
        showToUser: true,
      );
      throw e;
    }
  }

  /// Public methods that create and execute commands
  void removeSelectedImages() {
    if (hasSelection) {
      final imagesToRemove = selectedImages;
      executeCommand(RemoveImagesCommand(imagesToRemove));
    }
  }

  /// Remove all images from canvas
  void removeAllImages() {
    if (value.images.isNotEmpty) {
      final allImages = value.imageList;
      executeCommand(RemoveImagesCommand(allImages));
    }
  }

  void clearAll() {
    removeAllImages();
  }

  void transform({
    double? rotation,
    double? scale,
    Offset? translation,
    bool? flipHorizontal,
    bool? flipVertical,
    List<String>? imageIds,
  }) {
    final targetIds = imageIds ?? selectedIds.toList();
    if (targetIds.isEmpty) return;

    final oldTransforms = <String, Matrix4>{};
    final newTransforms = <String, Matrix4>{};

    for (final id in targetIds) {
      final image = value.images[id];
      if (image != null) {
        oldTransforms[id] = Matrix4.copy(image.transform);
        final newTransform = Matrix4.copy(image.transform);

        // Apply transformations
        if (rotation != null) {
          final center = image.center;
          newTransform.translate(center.dx, center.dy);
          newTransform.rotateZ(rotation);
          newTransform.translate(-center.dx, -center.dy);
        }

        if (scale != null) {
          final center = image.center;
          newTransform.translate(center.dx, center.dy);
          newTransform.scale(scale);
          newTransform.translate(-center.dx, -center.dy);
        }

        if (flipHorizontal == true) {
          final center = image.center;
          newTransform.translate(center.dx, center.dy);
          newTransform.scale(-1.0, 1.0);
          newTransform.translate(-center.dx, -center.dy);
        }

        if (flipVertical == true) {
          final center = image.center;
          newTransform.translate(center.dx, center.dy);
          newTransform.scale(1.0, -1.0);
          newTransform.translate(-center.dx, -center.dy);
        }

        if (translation != null) {
          newTransform.translate(translation.dx, translation.dy);
        }

        newTransforms[id] = newTransform;
      }
    }

    if (newTransforms.isNotEmpty) {
      executeCommand(TransformCommand(
        oldTransforms: oldTransforms,
        newTransforms: newTransforms,
      ));
    }
  }

  /// Bring images to front
  void bringToFront(List<String> imageIds) {
    final targetIds = imageIds.isEmpty ? selectedIds.toList() : imageIds;
    if (targetIds.isEmpty) return;

    try {
      final newImages = Map<String, CanvasImage>.from(value.images);
      final imagesToMove = <CanvasImage>[];

      // Collect images to move
      for (final id in targetIds) {
        final image = newImages[id];
        if (image != null) {
          imagesToMove.add(image);
          newImages.remove(id);
        }
      }

      // Add them back at the end (front)
      for (final image in imagesToMove) {
        newImages[image.id] = image;
      }

      value = value.copyWith(images: newImages);
      debugPrint('Brought ${imagesToMove.length} images to front');

    } catch (e, stackTrace) {
      _errorHandler.handleError(
        AppError.canvas(e, operation: 'bringToFront'),
        showToUser: true,
      );
    }
  }

  /// Send images to back
  void sendToBack(List<String> imageIds) {
    final targetIds = imageIds.isEmpty ? selectedIds.toList() : imageIds;
    if (targetIds.isEmpty) return;

    try {
      final currentImages = Map<String, CanvasImage>.from(value.images);
      final imagesToMove = <CanvasImage>[];
      final remainingImages = <String, CanvasImage>{};

      // Collect images to move and remaining images
      for (final entry in currentImages.entries) {
        if (targetIds.contains(entry.key)) {
          imagesToMove.add(entry.value);
        } else {
          remainingImages[entry.key] = entry.value;
        }
      }

      // Create new map with moved images first (back)
      final newImages = <String, CanvasImage>{};
      for (final image in imagesToMove) {
        newImages[image.id] = image;
      }
      newImages.addAll(remainingImages);

      value = value.copyWith(images: newImages);
      debugPrint('Sent ${imagesToMove.length} images to back');

    } catch (e, stackTrace) {
      _errorHandler.handleError(
        AppError.canvas(e, operation: 'sendToBack'),
        showToUser: true,
      );
    }
  }

  void transformImages(Map<String, Matrix4> oldTransforms, Map<String, Matrix4> newTransforms) {
    executeCommand(TransformCommand(
      oldTransforms: oldTransforms,
      newTransforms: newTransforms,
    ));
  }

  /// Undo last operation
  bool undo() {
    if (canUndo) {
      try {
        final command = value.history[value.historyIndex];
        command.undo(this);

        value = value.copyWith(historyIndex: value.historyIndex - 1);
        return true;

      } catch (e) {
        debugPrint('Error during undo: $e');
        return false;
      }
    }
    return false;
  }

  /// Redo last undone operation
  bool redo() {
    if (canRedo) {
      try {
        final newIndex = value.historyIndex + 1;
        final command = value.history[newIndex];
        command.execute(this);

        value = value.copyWith(historyIndex: newIndex);
        return true;

      } catch (e) {
        debugPrint('Error during redo: $e');
        return false;
      }
    }
    return false;
  }

  /// Selection operations (these don't need commands as they're not undoable)
  void selectImage(String id) {
    if (value.images.containsKey(id)) {
      value = value.copyWith(selectedIds: {id});
    }
  }

  void selectImages(List<String> ids) {
    final validIds = ids.where((id) => value.images.containsKey(id)).toSet();
    if (validIds.isNotEmpty) {
      value = value.copyWith(selectedIds: validIds);
    }
  }

  void resetSelectedImages() {
    final selectedIds = value.selectedIds.toList();
    if (selectedIds.isEmpty) return;

    try {
      final oldTransforms = <String, Matrix4>{};
      final newTransforms = <String, Matrix4>{};

      for (final id in selectedIds) {
        final image = value.images[id];
        if (image != null && image.isModified) {
          oldTransforms[id] = Matrix4.copy(image.transform);
          newTransforms[id] = Matrix4.identity(); // Reset to identity transform
        }
      }

      if (newTransforms.isNotEmpty) {
        executeCommand(TransformCommand(
          oldTransforms: oldTransforms,
          newTransforms: newTransforms,
        ));
      }

      debugPrint('Reset ${newTransforms.length} selected images');

    } catch (e, stackTrace) {
      _errorHandler.handleError(
        AppError.canvas(e, operation: 'resetSelectedImages'),
        showToUser: true,
      );
    }
  }

  void toggleSelection(String id) {
    if (value.images.containsKey(id)) {
      final newSelection = Set<String>.from(value.selectedIds);
      if (newSelection.contains(id)) {
        newSelection.remove(id);
      } else {
        newSelection.add(id);
      }
      value = value.copyWith(selectedIds: newSelection);
    }
  }

  void selectAll() {
    value = value.copyWith(selectedIds: value.images.keys.toSet());
  }

  void clearSelection() {
    if (value.selectedIds.isNotEmpty) {
      value = value.copyWith(selectedIds: const <String>{});
    }
  }

  /// Copy/Paste operations
  void copy() {
    final selectedImages = value.selectedImages;
    if (selectedImages.isNotEmpty) {
      // Create clipboard items with new IDs to avoid conflicts
      final clipboardImages = selectedImages.map((img) =>
          img.copyWith(id: '${DateTime.now().millisecondsSinceEpoch}_${img.id}')
      ).toList();

      value = value.copyWith(clipboard: clipboardImages);
      debugPrint('Copied ${selectedImages.length} image(s)');
    }
  }

  void paste({Offset? offset}) {
    if (value.clipboard.isNotEmpty) {
      final pasteOffset = offset ?? const Offset(20, 20);
      final pastedImages = <CanvasImage>[];

      for (final clipImage in value.clipboard) {
        final newId = '${DateTime.now().millisecondsSinceEpoch}_${clipImage.id}';
        final currentTranslation = clipImage.transform.getTranslation();
        final newTransform = Matrix4.copy(clipImage.transform);
        newTransform.setTranslation(
          Vector3(
            currentTranslation.x + pasteOffset.dx,
            currentTranslation.y + pasteOffset.dy,
            currentTranslation.z,
          ),
        );

        final pastedImage = clipImage.copyWith(
          id: newId,
          transform: newTransform,
        );
        pastedImages.add(pastedImage);
      }

      executeCommand(AddImagesCommand(pastedImages));
      selectImages(pastedImages.map((img) => img.id).toList());
    }
  }

  void duplicateSelected({Offset? offset}) {
    copy();
    paste(offset: offset);
  }

  /// Get command history for debugging
  List<String> get commandHistory {
    return value.history
        .take(value.historyIndex + 1)
        .map((cmd) => cmd.description)
        .toList();
  }

  /// Schedule cleanup of removed images
  void _scheduleImageCleanup() {
    Future.delayed(const Duration(seconds: 30), () {
      _cleanupRemovedImages();
    });
  }

  void _cleanupRemovedImages() {
    try {
      final imagesToDispose = <String>[];

      for (final id in _removedImageIds) {
        bool inUse = false;

        // Check current state
        if (value.images.containsKey(id)) inUse = true;

        // Check clipboard
        if (value.clipboard.any((img) => img.id == id)) inUse = true;

        // Check history
        for (final command in value.history) {
          if (command is AddImagesCommand &&
              command.images.any((img) => img.id == id)) {
            inUse = true;
            break;
          }
        }

        if (!inUse) {
          imagesToDispose.add(id);
        }
      }

      for (final id in imagesToDispose) {
        _removedImageIds.remove(id);
      }

      if (imagesToDispose.isNotEmpty) {
        debugPrint('Cleaned up ${imagesToDispose.length} unused image references');
      }
    } catch (e) {
      debugPrint('Error during image cleanup: $e');
    }
  }

  // Align selected images using the fixed AlignmentType from interaction_enums.dart
  void align(AlignmentType alignmentType) {
    final selectedImages = value.selectedImages;
    if (selectedImages.length < 2) return;

    try {
      final oldTransforms = <String, Matrix4>{};
      final newTransforms = <String, Matrix4>{};

      // Calculate alignment bounds
      double? alignmentValue;
      switch (alignmentType) {
        case AlignmentType.left:
          alignmentValue = selectedImages.map((img) => img.bounds.left).reduce(math.min);
          break;
        case AlignmentType.right:
          alignmentValue = selectedImages.map((img) => img.bounds.right).reduce(math.max);
          break;
        case AlignmentType.top:
          alignmentValue = selectedImages.map((img) => img.bounds.top).reduce(math.min);
          break;
        case AlignmentType.bottom:
          alignmentValue = selectedImages.map((img) => img.bounds.bottom).reduce(math.max);
          break;
        case AlignmentType.centerHorizontal:
          final minLeft = selectedImages.map((img) => img.bounds.left).reduce(math.min);
          final maxRight = selectedImages.map((img) => img.bounds.right).reduce(math.max);
          alignmentValue = (minLeft + maxRight) / 2;
          break;
        case AlignmentType.centerVertical:
          final minTop = selectedImages.map((img) => img.bounds.top).reduce(math.min);
          final maxBottom = selectedImages.map((img) => img.bounds.bottom).reduce(math.max);
          alignmentValue = (minTop + maxBottom) / 2;
          break;
      }

      // Apply alignment to each image
      for (final image in selectedImages) {
        oldTransforms[image.id] = Matrix4.copy(image.transform);
        final newTransform = Matrix4.copy(image.transform);
        final currentTranslation = newTransform.getTranslation();

        switch (alignmentType) {
          case AlignmentType.left:
            newTransform.setTranslation(Vector3(alignmentValue!, currentTranslation.y, currentTranslation.z));
            break;
          case AlignmentType.right:
            newTransform.setTranslation(Vector3(alignmentValue! - image.size.width, currentTranslation.y, currentTranslation.z));
            break;
          case AlignmentType.top:
            newTransform.setTranslation(Vector3(currentTranslation.x, alignmentValue!, currentTranslation.z));
            break;
          case AlignmentType.bottom:
            newTransform.setTranslation(Vector3(currentTranslation.x, alignmentValue! - image.size.height, currentTranslation.z));
            break;
          case AlignmentType.centerHorizontal:
            newTransform.setTranslation(Vector3(alignmentValue! - image.size.width / 2, currentTranslation.y, currentTranslation.z));
            break;
          case AlignmentType.centerVertical:
            newTransform.setTranslation(Vector3(currentTranslation.x, alignmentValue! - image.size.height / 2, currentTranslation.z));
            break;
        }

        newTransforms[image.id] = newTransform;
      }

      if (newTransforms.isNotEmpty) {
        executeCommand(TransformCommand(
          oldTransforms: oldTransforms,
          newTransforms: newTransforms,
        ));
      }

      debugPrint('Aligned ${selectedImages.length} images: $alignmentType');

    } catch (e, stackTrace) {
      _errorHandler.handleError(
        AppError.canvas(e, operation: 'align'),
        showToUser: true,
      );
    }
  }

  /// Distribute selected images using the fixed DistributeType from interaction_enums.dart
  void distribute(DistributeType distributeType) {
    final selectedImages = value.selectedImages;
    if (selectedImages.length < 3) return;

    try {
      final oldTransforms = <String, Matrix4>{};
      final newTransforms = <String, Matrix4>{};

      // Sort images by position
      late List<CanvasImage> sortedImages;
      switch (distributeType) {
        case DistributeType.horizontal:
          sortedImages = List.from(selectedImages)
            ..sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));
          break;
        case DistributeType.vertical:
          sortedImages = List.from(selectedImages)
            ..sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));
          break;
      }

      // Calculate distribution
      final first = sortedImages.first;
      final last = sortedImages.last;

      late double totalSpan;
      late double spacing;

      switch (distributeType) {
        case DistributeType.horizontal:
          totalSpan = last.bounds.center.dx - first.bounds.center.dx;
          spacing = totalSpan / (sortedImages.length - 1);
          break;
        case DistributeType.vertical:
          totalSpan = last.bounds.center.dy - first.bounds.center.dy;
          spacing = totalSpan / (sortedImages.length - 1);
          break;
      }

      // Apply distribution (skip first and last)
      for (int i = 1; i < sortedImages.length - 1; i++) {
        final image = sortedImages[i];
        oldTransforms[image.id] = Matrix4.copy(image.transform);
        final newTransform = Matrix4.copy(image.transform);
        final currentTranslation = newTransform.getTranslation();

        switch (distributeType) {
          case DistributeType.horizontal:
            final newX = first.bounds.center.dx + (spacing * i) - image.size.width / 2;
            newTransform.setTranslation(Vector3(newX, currentTranslation.y, currentTranslation.z));
            break;
          case DistributeType.vertical:
            final newY = first.bounds.center.dy + (spacing * i) - image.size.height / 2;
            newTransform.setTranslation(Vector3(currentTranslation.x, newY, currentTranslation.z));
            break;
        }

        newTransforms[image.id] = newTransform;
      }

      if (newTransforms.isNotEmpty) {
        executeCommand(TransformCommand(
          oldTransforms: oldTransforms,
          newTransforms: newTransforms,
        ));
      }

      debugPrint('Distributed ${selectedImages.length} images: $distributeType');

    } catch (e, stackTrace) {
      _errorHandler.handleError(
        AppError.canvas(e, operation: 'distribute'),
        showToUser: true,
      );
    }
  }

  @override
  void dispose() {
    _cleanupRemovedImages();
    _removedImageIds.clear();
    super.dispose();
  }
}