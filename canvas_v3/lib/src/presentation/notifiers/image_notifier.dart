// lib/src/presentation/notifiers/image_notifier.dart
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';
import 'package:flutter_drawing_board/src/extensions/extensions.dart';
import 'package:flutter_drawing_board/src/domain/models/image_command.dart';

// Immutable state class
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

  List<CanvasImage> get imageList => images.values.toList();
  List<CanvasImage> get selectedImages =>
      selectedIds.map((id) => images[id]).whereType<CanvasImage>().toList();
  bool get hasSelection => selectedIds.isNotEmpty;
  bool get canUndo => historyIndex >= 0;
  bool get canRedo => historyIndex < history.length - 1;
}

class ImageNotifier extends ValueNotifier<ImageState> {
  ImageNotifier() : super(const ImageState());

  static const int maxHistorySize = 50;

  // Track images for disposal
  final Map<String, ui.Image> _imageReferences = {};
  final Set<String> _removedImageIds = {};

  // Direct manipulation methods (for commands)
  void addImagesDirectly(List<CanvasImage> images) {
    final newImages = Map<String, CanvasImage>.from(value.images);
    for (final image in images) {
      newImages[image.id] = image;
      // Track image reference
      _imageReferences[image.id] = image.image;
    }
    value = value.copyWith(images: newImages);
  }

  void removeImagesDirectly(List<String> imageIds) {
    final newImages = Map<String, CanvasImage>.from(value.images);
    final newSelection = Set<String>.from(value.selectedIds);

    for (final id in imageIds) {
      newImages.remove(id);
      newSelection.remove(id);
      // Mark for disposal (don't dispose immediately as it might be in undo history)
      _removedImageIds.add(id);
    }

    value = value.copyWith(
      images: newImages,
      selectedIds: newSelection,
    );

    // Schedule cleanup of removed images
    _scheduleImageCleanup();
  }

  // Schedule cleanup of removed images after a delay
  void _scheduleImageCleanup() {
    // Delay disposal to allow for undo operations
    Future.delayed(const Duration(seconds: 30), () {
      _cleanupRemovedImages();
    });
  }

  // Clean up images that are no longer referenced
  void _cleanupRemovedImages() {
    final imagesToDispose = <String>[];

    for (final id in _removedImageIds) {
      // Check if image is still in use
      bool inUse = false;

      // Check if in current state
      if (value.images.containsKey(id)) {
        inUse = true;
      }

      // Check if in clipboard
      if (value.clipboard.any((img) => img.id == id)) {
        inUse = true;
      }

      // Check if in history
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

    // Dispose unused images
    for (final id in imagesToDispose) {
      final image = _imageReferences.remove(id);
      // Note: ui.Image doesn't have a dispose method in Flutter
      // The garbage collector will handle it when no longer referenced
      _removedImageIds.remove(id);
    }
  }

  void applyTransforms(Map<String, Matrix4> transforms) {
    final newImages = Map<String, CanvasImage>.from(value.images);

    transforms.forEach((id, transform) {
      final image = newImages[id];
      if (image != null) {
        newImages[id] = image.copyWith(transform: transform);
      }
    });

    value = value.copyWith(images: newImages);
  }

  // Command execution
  void _executeCommand(ImageCommand command) {
    // Remove any commands after current index
    final newHistory = value.historyIndex >= 0
        ? value.history.sublist(0, value.historyIndex + 1)
        : <ImageCommand>[];

    // Add new command
    newHistory.add(command);

    // Limit history size and clean up old commands
    if (newHistory.length > maxHistorySize) {
      final removedCommand = newHistory.removeAt(0);
      // Clean up images from removed command
      if (removedCommand is AddImagesCommand) {
        for (final img in removedCommand.images) {
          _removedImageIds.add(img.id);
        }
        _scheduleImageCleanup();
      }
    }

    // Execute command
    command.execute(this);

    // Update history
    value = value.copyWith(
      history: newHistory,
      historyIndex: newHistory.length - 1,
    );
  }

  // Public API
  void addImages(List<CanvasImage> images) {
    _executeCommand(AddImagesCommand(images));
  }

  void addImage(CanvasImage image) {
    addImages([image]);
  }

  void removeImages(List<String> imageIds) {
    final imagesToRemove = imageIds
        .map((id) => value.images[id])
        .whereType<CanvasImage>()
        .toList();

    if (imagesToRemove.isNotEmpty) {
      _executeCommand(RemoveImagesCommand(imagesToRemove));
    }
  }

  void removeSelectedImages() {
    removeImages(value.selectedIds.toList());
  }

  void removeAllImages() {
    removeImages(value.images.keys.toList());
  }

  // Transform operations
  void transform({
    List<String>? imageIds,
    Matrix4? transform,
    Offset? delta,
    double? rotation,
    double? scale,
    Offset? scaleOrigin,
    bool? flipHorizontal,
    bool? flipVertical,
  }) {
    final ids = imageIds ?? value.selectedIds.toList();
    if (ids.isEmpty) return;

    final oldTransforms = <String, Matrix4>{};
    final newTransforms = <String, Matrix4>{};

    for (final id in ids) {
      final image = value.images[id];
      if (image == null) continue;

      oldTransforms[id] = image.transform.clone();

      Matrix4 newTransform;
      if (transform != null) {
        newTransform = transform.clone();
      } else {
        newTransform = image.transform.clone();

        if (delta != null) {
          newTransform.translate(delta.dx, delta.dy);
        }

        if (rotation != null || scale != null || flipHorizontal == true || flipVertical == true) {
          // Get the current bounds for proper pivot calculation
          final bounds = image.bounds;
          final pivot = scaleOrigin ?? bounds.center;

          // Create a transform that rotates around the pivot
          final pivotTransform = Matrix4.identity()
            ..translate(pivot.dx, pivot.dy);

          if (rotation != null) {
            pivotTransform.rotateZ(rotation);
          }

          if (scale != null) {
            pivotTransform.scale(scale, scale);
          }

          if (flipHorizontal == true) {
            pivotTransform.scale(-1, 1);
          }

          if (flipVertical == true) {
            pivotTransform.scale(1, -1);
          }

          pivotTransform.translate(-pivot.dx, -pivot.dy);

          // Apply the pivot transform to the existing transform
          newTransform = newTransform * pivotTransform;
        }
      }

      newTransforms[id] = newTransform;
    }

    if (newTransforms.isNotEmpty) {
      _executeCommand(TransformCommand(
        oldTransforms: oldTransforms,
        newTransforms: newTransforms,
      ));
    }
  }

  // Selection operations
  void select(List<String> ids, {bool toggle = false, bool clear = true}) {
    Set<String> newSelection;

    if (toggle) {
      newSelection = Set<String>.from(value.selectedIds);
      for (final id in ids) {
        if (newSelection.contains(id)) {
          newSelection.remove(id);
        } else {
          newSelection.add(id);
        }
      }
    } else if (clear) {
      newSelection = ids.toSet();
    } else {
      newSelection = {...value.selectedIds, ...ids};
    }

    value = value.copyWith(selectedIds: newSelection);
  }

  void selectAll() {
    select(value.images.keys.toList());
  }

  void deselectAll() {
    select([]);
  }

  void selectInRect(Rect rect) {
    final selected = <String>[];

    for (final entry in value.images.entries) {
      if (rect.overlaps(entry.value.bounds)) {
        selected.add(entry.key);
      }
    }

    select(selected);
  }

  // Copy/Paste operations
  void copy() {
    final selectedImages = value.selectedImages;
    if (selectedImages.isNotEmpty) {
      // Clean up old clipboard images
      for (final img in value.clipboard) {
        _removedImageIds.add(img.id);
      }

      // Create new clipboard items
      value = value.copyWith(
        clipboard: selectedImages.map((img) => img.copyWith(id: DateTime.now().millisecondsSinceEpoch.toString())).toList(),
      );

      _scheduleImageCleanup();
    }
  }

  void cut() {
    copy();
    removeSelectedImages();
  }

  void paste(Offset position) {
    if (value.clipboard.isEmpty) return;

    // Calculate center of clipboard content
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final img in value.clipboard) {
      final bounds = img.bounds;
      minX = math.min(minX, bounds.left);
      minY = math.min(minY, bounds.top);
      maxX = math.max(maxX, bounds.right);
      maxY = math.max(maxY, bounds.bottom);
    }

    final clipboardCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final offset = position - clipboardCenter;

    // Create new images with offset
    final newImages = value.clipboard.map((img) {
      final newTransform = img.transform.clone()
        ..translate(offset.dx, offset.dy);
      return CanvasImage(
        image: img.image,
        transform: newTransform,
      );
    }).toList();

    addImages(newImages);

    // Select pasted images
    select(newImages.map((img) => img.id).toList());
  }

  // Z-order operations
  void bringToFront(List<String> imageIds) {
    final ids = imageIds.isEmpty ? value.selectedIds.toList() : imageIds;
    if (ids.isEmpty) return;

    final newImages = Map<String, CanvasImage>.from(value.images);

    // Remove selected images
    final selected = <CanvasImage>[];
    for (final id in ids) {
      final image = newImages.remove(id);
      if (image != null) selected.add(image);
    }

    // Add them back at the end
    for (final image in selected) {
      newImages[image.id] = image;
    }

    value = value.copyWith(images: newImages);
  }

  void sendToBack(List<String> imageIds) {
    final ids = imageIds.isEmpty ? value.selectedIds.toList() : imageIds;
    if (ids.isEmpty) return;

    final selected = <CanvasImage>[];
    final remaining = <CanvasImage>[];

    for (final entry in value.images.entries) {
      if (ids.contains(entry.key)) {
        selected.add(entry.value);
      } else {
        remaining.add(entry.value);
      }
    }

    final newImages = <String, CanvasImage>{};
    for (final image in selected) {
      newImages[image.id] = image;
    }
    for (final image in remaining) {
      newImages[image.id] = image;
    }

    value = value.copyWith(images: newImages);
  }

  // Alignment operations
  void align(AlignmentType alignment, {List<String>? imageIds}) {
    final ids = imageIds ?? value.selectedIds.toList();
    if (ids.length < 2) return;

    final images = ids.map((id) => value.images[id]).whereType<CanvasImage>().toList();
    if (images.isEmpty) return;

    final oldTransforms = <String, Matrix4>{};
    final newTransforms = <String, Matrix4>{};

    // Calculate alignment position
    double alignPosition = 0;
    switch (alignment) {
      case AlignmentType.left:
        alignPosition = images.map((img) => img.bounds.left).reduce(math.min);
        for (final img in images) {
          oldTransforms[img.id] = img.transform.clone();
          final delta = alignPosition - img.bounds.left;
          newTransforms[img.id] = img.transform.clone()..translate(delta, 0);
        }
        break;

      case AlignmentType.right:
        alignPosition = images.map((img) => img.bounds.right).reduce(math.max);
        for (final img in images) {
          oldTransforms[img.id] = img.transform.clone();
          final delta = alignPosition - img.bounds.right;
          newTransforms[img.id] = img.transform.clone()..translate(delta, 0);
        }
        break;

      case AlignmentType.top:
        alignPosition = images.map((img) => img.bounds.top).reduce(math.min);
        for (final img in images) {
          oldTransforms[img.id] = img.transform.clone();
          final delta = alignPosition - img.bounds.top;
          newTransforms[img.id] = img.transform.clone()..translate(0, delta);
        }
        break;

      case AlignmentType.bottom:
        alignPosition = images.map((img) => img.bounds.bottom).reduce(math.max);
        for (final img in images) {
          oldTransforms[img.id] = img.transform.clone();
          final delta = alignPosition - img.bounds.bottom;
          newTransforms[img.id] = img.transform.clone()..translate(0, delta);
        }
        break;

      case AlignmentType.centerHorizontal:
        final centerX = images.map((img) => img.center.dx).reduce((a, b) => a + b) / images.length;
        for (final img in images) {
          oldTransforms[img.id] = img.transform.clone();
          final delta = centerX - img.center.dx;
          newTransforms[img.id] = img.transform.clone()..translate(delta, 0);
        }
        break;

      case AlignmentType.centerVertical:
        final centerY = images.map((img) => img.center.dy).reduce((a, b) => a + b) / images.length;
        for (final img in images) {
          oldTransforms[img.id] = img.transform.clone();
          final delta = centerY - img.center.dy;
          newTransforms[img.id] = img.transform.clone()..translate(0, delta);
        }
        break;
    }

    if (newTransforms.isNotEmpty) {
      _executeCommand(TransformCommand(
        oldTransforms: oldTransforms,
        newTransforms: newTransforms,
      ));
    }
  }

  // Distribute operations
  void distribute(DistributeType type, {List<String>? imageIds}) {
    final ids = imageIds ?? value.selectedIds.toList();
    if (ids.length < 3) return;

    final images = ids.map((id) => value.images[id]).whereType<CanvasImage>().toList();
    if (images.length < 3) return;

    final oldTransforms = <String, Matrix4>{};
    final newTransforms = <String, Matrix4>{};

    if (type == DistributeType.horizontal) {
      // Sort by x position
      images.sort((a, b) => a.center.dx.compareTo(b.center.dx));

      final leftMost = images.first.center.dx;
      final rightMost = images.last.center.dx;
      final spacing = (rightMost - leftMost) / (images.length - 1);

      for (int i = 0; i < images.length; i++) {
        final img = images[i];
        oldTransforms[img.id] = img.transform.clone();

        final targetX = leftMost + (spacing * i);
        final deltaX = targetX - img.center.dx;

        newTransforms[img.id] = img.transform.clone()..translate(deltaX, 0);
      }
    } else {
      // Sort by y position
      images.sort((a, b) => a.center.dy.compareTo(b.center.dy));

      final topMost = images.first.center.dy;
      final bottomMost = images.last.center.dy;
      final spacing = (bottomMost - topMost) / (images.length - 1);

      for (int i = 0; i < images.length; i++) {
        final img = images[i];
        oldTransforms[img.id] = img.transform.clone();

        final targetY = topMost + (spacing * i);
        final deltaY = targetY - img.center.dy;

        newTransforms[img.id] = img.transform.clone()..translate(0, deltaY);
      }
    }

    if (newTransforms.isNotEmpty) {
      _executeCommand(TransformCommand(
        oldTransforms: oldTransforms,
        newTransforms: newTransforms,
      ));
    }
  }

  // Undo/Redo
  void undo() {
    if (!value.canUndo) return;

    final command = value.history[value.historyIndex];
    command.undo(this);

    value = value.copyWith(historyIndex: value.historyIndex - 1);
  }

  void redo() {
    if (!value.canRedo) return;

    final command = value.history[value.historyIndex + 1];
    command.execute(this);

    value = value.copyWith(historyIndex: value.historyIndex + 1);
  }

  // Utility methods
  CanvasImage? getImage(String id) => value.images[id];

  CanvasImage? getImageAt(Offset point) {
    // Check from top to bottom (reverse order)
    final images = value.imageList.reversed;

    for (final image in images) {
      if (image.containsPoint(point)) {
        return image;
      }
    }

    return null;
  }

  void clearHistory() {
    // Clean up images from history before clearing
    for (final command in value.history) {
      if (command is AddImagesCommand) {
        for (final img in command.images) {
          _removedImageIds.add(img.id);
        }
      }
    }

    value = value.copyWith(history: [], historyIndex: -1);
    _scheduleImageCleanup();
  }

  @override
  void dispose() {
    // Clean up all image references
    _imageReferences.clear();
    _removedImageIds.clear();

    // Clear history
    clearHistory();

    super.dispose();
  }
}

enum AlignmentType {
  left,
  right,
  top,
  bottom,
  centerHorizontal,
  centerVertical
}

enum DistributeType {
  horizontal,
  vertical
}