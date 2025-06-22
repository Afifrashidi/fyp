// lib/src/domain/models/image_command.dart
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';

// Base command interface
abstract class ImageCommand {
  void execute(ImageNotifier notifier);
  void undo(ImageNotifier notifier);
}

// Add images command
class AddImagesCommand implements ImageCommand {
  final List<CanvasImage> images;

  AddImagesCommand(this.images);

  @override
  void execute(ImageNotifier notifier) {
    notifier.addImagesDirectly(images);
  }

  @override
  void undo(ImageNotifier notifier) {
    notifier.removeImagesDirectly(images.map((img) => img.id).toList());
  }
}

// Remove images command
class RemoveImagesCommand implements ImageCommand {
  final List<CanvasImage> images;

  RemoveImagesCommand(this.images);

  @override
  void execute(ImageNotifier notifier) {
    notifier.removeImagesDirectly(images.map((img) => img.id).toList());
  }

  @override
  void undo(ImageNotifier notifier) {
    notifier.addImagesDirectly(images);
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
  void execute(ImageNotifier notifier) {
    notifier.applyTransforms(newTransforms);
  }

  @override
  void undo(ImageNotifier notifier) {
    notifier.applyTransforms(oldTransforms);
  }
}