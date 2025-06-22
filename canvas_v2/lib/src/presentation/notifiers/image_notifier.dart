// lib/src/presentation/notifiers/image_notifier.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';

class ImageNotifier extends ValueNotifier<List<CanvasImage>> {
  final Set<String> selectedImageIds = {};
  List<CanvasImage> copiedImages = [];

  ImageNotifier() : super([]);

  // Basic operations
  void addImage(CanvasImage image) {
    value = List<CanvasImage>.from(value)..add(image);
  }

  void addImages(List<CanvasImage> images) {
    value = List<CanvasImage>.from(value)..addAll(images);
  }

  void removeImage(CanvasImage image) {
    selectedImageIds.remove(image.id);
    value = List<CanvasImage>.from(value)..removeWhere((img) => img.id == image.id);
  }

  void removeSelectedImages() {
    value = List<CanvasImage>.from(value)
      ..removeWhere((img) => selectedImageIds.contains(img.id));
    selectedImageIds.clear();
    notifyListeners();
  }

  void removeAllImages() {
    selectedImageIds.clear();
    value = [];
  }

  // Update operations
  void updateImage(CanvasImage oldImage, CanvasImage newImage) {
    final index = value.indexWhere((img) => img.id == oldImage.id);
    if (index != -1) {
      final newList = List<CanvasImage>.from(value);
      newList[index] = newImage;
      value = newList;
    }
  }

  void updateImagePosition(CanvasImage image, Offset newPosition) {
    updateImage(image, image.copyWith(position: newPosition));
  }

  void updateImageSize(CanvasImage image, Size newSize) {
    updateImage(image, image.copyWith(size: newSize));
  }

  void updateImageRotation(CanvasImage image, double newRotation) {
    updateImage(image, image.copyWith(rotation: newRotation));
  }

  // Multiple selection methods
  void selectImage(String imageId) {
    selectedImageIds.add(imageId);
    notifyListeners();
  }

  void deselectImage(String imageId) {
    selectedImageIds.remove(imageId);
    notifyListeners();
  }

  void toggleImageSelection(String imageId) {
    if (selectedImageIds.contains(imageId)) {
      selectedImageIds.remove(imageId);
    } else {
      selectedImageIds.add(imageId);
    }
    notifyListeners();
  }

  void selectAll() {
    selectedImageIds.clear();
    selectedImageIds.addAll(value.map((img) => img.id));
    notifyListeners();
  }

  void deselectAll() {
    selectedImageIds.clear();
    notifyListeners();
  }

  void selectImagesInRect(Rect selectionRect) {
    selectedImageIds.clear();
    for (final image in value) {
      if (selectionRect.overlaps(image.bounds)) {
        selectedImageIds.add(image.id);
      }
    }
    notifyListeners();
  }

  // Move selected images
  void moveSelectedImages(Offset delta) {
    final newList = List<CanvasImage>.from(value);
    for (int i = 0; i < newList.length; i++) {
      if (selectedImageIds.contains(newList[i].id)) {
        newList[i] = newList[i].copyWith(
          position: newList[i].position + delta,
        );
      }
    }
    value = newList;
  }

  // Z-order management
  void bringToFront(CanvasImage image) {
    final index = value.indexWhere((img) => img.id == image.id);
    if (index != -1 && index < value.length - 1) {
      final newList = List<CanvasImage>.from(value);
      newList.removeAt(index);
      newList.add(image);
      value = newList;
    }
  }

  void sendToBack(CanvasImage image) {
    final index = value.indexWhere((img) => img.id == image.id);
    if (index != -1 && index > 0) {
      final newList = List<CanvasImage>.from(value);
      newList.removeAt(index);
      newList.insert(0, image);
      value = newList;
    }
  }

  void bringSelectedToFront() {
    final selected = value.where((img) => selectedImageIds.contains(img.id)).toList();
    final unselected = value.where((img) => !selectedImageIds.contains(img.id)).toList();
    value = [...unselected, ...selected];
  }

  void sendSelectedToBack() {
    final selected = value.where((img) => selectedImageIds.contains(img.id)).toList();
    final unselected = value.where((img) => !selectedImageIds.contains(img.id)).toList();
    value = [...selected, ...unselected];
  }

  void bringForward(CanvasImage image) {
    final index = value.indexWhere((img) => img.id == image.id);
    if (index != -1 && index < value.length - 1) {
      final newList = List<CanvasImage>.from(value);
      final temp = newList[index];
      newList[index] = newList[index + 1];
      newList[index + 1] = temp;
      value = newList;
    }
  }

  void sendBackward(CanvasImage image) {
    final index = value.indexWhere((img) => img.id == image.id);
    if (index != -1 && index > 0) {
      final newList = List<CanvasImage>.from(value);
      final temp = newList[index];
      newList[index] = newList[index - 1];
      newList[index - 1] = temp;
      value = newList;
    }
  }

  // Copy/paste functionality
  void copySelectedImages() {
    copiedImages = value
        .where((img) => selectedImageIds.contains(img.id))
        .map((img) => img.copyWith(
      id: null, // Will generate new ID
      position: img.position,
    ))
        .toList();
  }

  void pasteImages(Offset pastePosition) {
    if (copiedImages.isEmpty) return;

    // Calculate center of copied images
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final img in copiedImages) {
      minX = math.min(minX, img.bounds.left);
      minY = math.min(minY, img.bounds.top);
      maxX = math.max(maxX, img.bounds.right);
      maxY = math.max(maxY, img.bounds.bottom);
    }

    final groupCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final offset = pastePosition - groupCenter;

    final pastedImages = copiedImages.map((img) => CanvasImage(
      image: img.image,
      position: img.position + offset,
      size: img.size,
      rotation: img.rotation,
    )).toList();

    addImages(pastedImages);

    // Select the pasted images
    deselectAll();
    for (final img in pastedImages) {
      selectImage(img.id);
    }
  }

  void cutSelectedImages() {
    copySelectedImages();
    removeSelectedImages();
  }

  // Rotate selected images
  void rotateSelectedImages(double angleRadians) {
    final newList = List<CanvasImage>.from(value);

    // Find center of all selected images for group rotation
    if (selectedImageIds.length > 1) {
      double minX = double.infinity, minY = double.infinity;
      double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

      for (final image in newList) {
        if (selectedImageIds.contains(image.id)) {
          final bounds = image.bounds;
          minX = math.min(minX, bounds.left);
          minY = math.min(minY, bounds.top);
          maxX = math.max(maxX, bounds.right);
          maxY = math.max(maxY, bounds.bottom);
        }
      }

      final groupCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);

      // Rotate each image around group center
      for (int i = 0; i < newList.length; i++) {
        if (selectedImageIds.contains(newList[i].id)) {
          final image = newList[i];
          final imageCenter = image.center;

          // Rotate position around group center
          final dx = imageCenter.dx - groupCenter.dx;
          final dy = imageCenter.dy - groupCenter.dy;
          final cos = math.cos(angleRadians);
          final sin = math.sin(angleRadians);
          final newCenter = Offset(
            dx * cos - dy * sin + groupCenter.dx,
            dx * sin + dy * cos + groupCenter.dy,
          );

          newList[i] = image.copyWith(
            position: newCenter - Offset(image.size.width / 2, image.size.height / 2),
            rotation: image.rotation + angleRadians,
          );
        }
      }
    } else {
      // Single image rotation
      for (int i = 0; i < newList.length; i++) {
        if (selectedImageIds.contains(newList[i].id)) {
          newList[i] = newList[i].copyWith(
            rotation: newList[i].rotation + angleRadians,
          );
        }
      }
    }

    value = newList;
  }

  // Flip selected images
  void flipSelectedHorizontally() {
    final newList = List<CanvasImage>.from(value);
    for (int i = 0; i < newList.length; i++) {
      if (selectedImageIds.contains(newList[i].id)) {
        // For flip, we add π to rotation if vertical flip count is odd
        // This is a simplified approach - full flip would require transformation matrix
        newList[i] = newList[i].copyWith(
          rotation: newList[i].rotation + math.pi,
        );
      }
    }
    value = newList;
  }

  // Align selected images
  void alignSelectedImages(String alignment) {
    if (selectedImageIds.length < 2) return;

    final selectedImages = value.where((img) => selectedImageIds.contains(img.id)).toList();
    final newList = List<CanvasImage>.from(value);

    switch (alignment) {
      case 'left':
        final leftMost = selectedImages.map((img) => img.bounds.left).reduce(math.min);
        for (int i = 0; i < newList.length; i++) {
          if (selectedImageIds.contains(newList[i].id)) {
            final img = newList[i];
            newList[i] = img.copyWith(
              position: Offset(leftMost, img.position.dy),
            );
          }
        }
        break;
      case 'right':
        final rightMost = selectedImages.map((img) => img.bounds.right).reduce(math.max);
        for (int i = 0; i < newList.length; i++) {
          if (selectedImageIds.contains(newList[i].id)) {
            final img = newList[i];
            newList[i] = img.copyWith(
              position: Offset(rightMost - img.size.width, img.position.dy),
            );
          }
        }
        break;
      case 'top':
        final topMost = selectedImages.map((img) => img.bounds.top).reduce(math.min);
        for (int i = 0; i < newList.length; i++) {
          if (selectedImageIds.contains(newList[i].id)) {
            final img = newList[i];
            newList[i] = img.copyWith(
              position: Offset(img.position.dx, topMost),
            );
          }
        }
        break;
      case 'bottom':
        final bottomMost = selectedImages.map((img) => img.bounds.bottom).reduce(math.max);
        for (int i = 0; i < newList.length; i++) {
          if (selectedImageIds.contains(newList[i].id)) {
            final img = newList[i];
            newList[i] = img.copyWith(
              position: Offset(img.position.dx, bottomMost - img.size.height),
            );
          }
        }
        break;
      case 'center-h':
        final centerX = selectedImages.map((img) => img.center.dx).reduce((a, b) => a + b) / selectedImages.length;
        for (int i = 0; i < newList.length; i++) {
          if (selectedImageIds.contains(newList[i].id)) {
            final img = newList[i];
            newList[i] = img.copyWith(
              position: Offset(centerX - img.size.width / 2, img.position.dy),
            );
          }
        }
        break;
      case 'center-v':
        final centerY = selectedImages.map((img) => img.center.dy).reduce((a, b) => a + b) / selectedImages.length;
        for (int i = 0; i < newList.length; i++) {
          if (selectedImageIds.contains(newList[i].id)) {
            final img = newList[i];
            newList[i] = img.copyWith(
              position: Offset(img.position.dx, centerY - img.size.height / 2),
            );
          }
        }
        break;
    }

    value = newList;
  }

  // Get selected images
  List<CanvasImage> get selectedImages {
    return value.where((img) => selectedImageIds.contains(img.id)).toList();
  }

  // Check if any images are selected
  bool get hasSelection => selectedImageIds.isNotEmpty;
}