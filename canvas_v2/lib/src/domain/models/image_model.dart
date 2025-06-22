// lib/src/domain/models/image_model.dart
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

class CanvasImage {
  final String id;
  final ui.Image image;
  final Offset position; // In standard coordinates (800x600)
  final Size size; // In standard coordinates
  final double rotation; // In radians
  final DateTime createdAt;

  // Original image dimensions for quality preservation
  final Size originalSize;

  static const Offset defaultPosition = Offset(100, 100);
  static const double defaultRotation = 0.0;

  CanvasImage({
    String? id,
    required this.image,
    Offset? position,
    Size? size,
    this.rotation = defaultRotation,
    DateTime? createdAt,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        originalSize = Size(image.width.toDouble(), image.height.toDouble()),
        position = position ?? defaultPosition,
        size = size ?? _calculateInitialSize(image),
        createdAt = createdAt ?? DateTime.now();

  static Size _calculateInitialSize(ui.Image image) {
    // Calculate initial size preserving aspect ratio
    const maxInitialSize = 300.0; // In standard coordinates
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    final aspectRatio = imageWidth / imageHeight;

    if (imageWidth > imageHeight) {
      final width = math.min(imageWidth, maxInitialSize);
      return Size(width, width / aspectRatio);
    } else {
      final height = math.min(imageHeight, maxInitialSize);
      return Size(height * aspectRatio, height);
    }
  }

  CanvasImage copyWith({
    String? id,
    ui.Image? image,
    Offset? position,
    Size? size,
    double? rotation,
    DateTime? createdAt,
  }) {
    return CanvasImage(
      id: id ?? this.id,
      image: image ?? this.image,
      position: position ?? this.position,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Get bounds in standard coordinates
  Rect get bounds => Rect.fromLTWH(
    position.dx,
    position.dy,
    size.width,
    size.height,
  );

  // Get center point
  Offset get center => position + Offset(size.width / 2, size.height / 2);

  // Check if a point (in standard coordinates) is inside this image considering rotation
  bool containsPoint(Offset point) {
    if (rotation == 0) {
      return bounds.contains(point);
    }

    // Rotate point back to check
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final cos = math.cos(-rotation);
    final sin = math.sin(-rotation);
    final rotatedX = dx * cos - dy * sin + center.dx;
    final rotatedY = dx * sin + dy * cos + center.dy;

    return bounds.contains(Offset(rotatedX, rotatedY));
  }

  // Get resize handle positions (in standard coordinates)
  Map<String, Offset> getResizeHandles() {
    final rect = bounds;
    final handles = {
      'tl': rect.topLeft,
      'tr': rect.topRight,
      'bl': rect.bottomLeft,
      'br': rect.bottomRight,
      'tm': Offset(rect.center.dx, rect.top),
      'bm': Offset(rect.center.dx, rect.bottom),
      'ml': Offset(rect.left, rect.center.dy),
      'mr': Offset(rect.right, rect.center.dy),
    };

    // Apply rotation to handles
    if (rotation != 0) {
      final rotatedHandles = <String, Offset>{};

      handles.forEach((key, handle) {
        final dx = handle.dx - center.dx;
        final dy = handle.dy - center.dy;
        final cos = math.cos(rotation);
        final sin = math.sin(rotation);
        rotatedHandles[key] = Offset(
          dx * cos - dy * sin + center.dx,
          dx * sin + dy * cos + center.dy,
        );
      });

      return rotatedHandles;
    }

    return handles;
  }

  // Get rotation handle position
  Offset getRotationHandle() {
    final topCenter = Offset(center.dx, bounds.top);
    if (rotation != 0) {
      final dx = topCenter.dx - center.dx;
      final dy = topCenter.dy - center.dy;
      final cos = math.cos(rotation);
      final sin = math.sin(rotation);
      return Offset(
        dx * cos - dy * sin + center.dx,
        dx * sin + dy * cos + center.dy - 30, // 30 pixels above in standard coords
      );
    }
    return topCenter + Offset(0, -30);
  }

  // Convert to JSON for saving/loading
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'position': [position.dx, position.dy],
      'size': [size.width, size.height],
      'rotation': rotation,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}