// lib/src/domain/models/image_command.dart
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';

// Base command interface
abstract class ImageCommand {
  String get description;
  void execute(ImageNotifier notifier);
  void undo(ImageNotifier notifier);
}

// Add images command
class AddImagesCommand implements ImageCommand {
  final List<CanvasImage> images;

  AddImagesCommand(this.images);

  @override
  String get description => 'Add ${images.length} image${images.length == 1 ? '' : 's'}';

  @override
  void execute(ImageNotifier notifier) {
    notifier.addImages(images);
  }

  @override
  void undo(ImageNotifier notifier) {
    notifier.removeImages(images.map((img) => img.id).toList());
  }
}

// Remove images command
class RemoveImagesCommand implements ImageCommand {
  final List<CanvasImage> images;

  RemoveImagesCommand(this.images);

  @override
  String get description => 'Remove ${images.length} image${images.length == 1 ? '' : 's'}';

  @override
  void execute(ImageNotifier notifier) {
    notifier.removeImages(images.map((img) => img.id).toList());
  }

  @override
  void undo(ImageNotifier notifier) {
    notifier.addImages(images);
  }
}

// Transform command
class TransformCommand implements ImageCommand {
  final Map<String, Matrix4> oldTransforms;
  final Map<String, Matrix4> newTransforms;

  TransformCommand({
    required this.oldTransforms,
    required this.newTransforms,
  });

  @override
  String get description => 'Transform ${newTransforms.length} image${newTransforms.length == 1 ? '' : 's'}';

  @override
  void execute(ImageNotifier notifier) {
    notifier.applyTransforms(newTransforms);
  }

  @override
  void undo(ImageNotifier notifier) {
    notifier.applyTransforms(oldTransforms);
  }
}