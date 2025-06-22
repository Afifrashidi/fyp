// lib/src/domain/models/image_model.dart

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';


/// Represents an image on the canvas with transform and metadata
class CanvasImage {
  final String id;
  final ui.Image image;
  final Matrix4 transform;
  final Matrix4 originalTransform;
  final DateTime createdAt;
  final DateTime lastModified;

  CanvasImage({
    required this.id,
    required this.image,
    Matrix4? transform,
    Matrix4? originalTransform,
    DateTime? createdAt,
    DateTime? lastModified,
  }) : transform = transform ?? Matrix4.identity(),
        originalTransform = originalTransform ?? (transform ?? Matrix4.identity()),
        createdAt = createdAt ?? DateTime.now(),
        lastModified = lastModified ?? DateTime.now();

  /// Named constructor for positioned images
  CanvasImage.withPosition({
    required this.image,
    required Offset position,
    double scale = 1.0,
    double rotation = 0.0,
    String? id,
    DateTime? createdAt,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        transform = Matrix4.identity()
          ..translate(position.dx, position.dy)
          ..scale(scale)
          ..rotateZ(rotation),
        originalTransform = Matrix4.identity()
          ..translate(position.dx, position.dy)
          ..scale(scale)
          ..rotateZ(rotation),
        createdAt = createdAt ?? DateTime.now(),
        lastModified = DateTime.now();


  /// Create a copy with updated properties
  CanvasImage copyWith({
    String? id,
    ui.Image? image,
    Matrix4? transform,
    Matrix4? originalTransform,
    DateTime? createdAt,
    DateTime? lastModified,
  }) {
    return CanvasImage(
      id: id ?? this.id,
      image: image ?? this.image,
      transform: transform ?? Matrix4.copy(this.transform),
      originalTransform: originalTransform ?? Matrix4.copy(this.originalTransform),
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? DateTime.now(),
    );
  }

  /// Check if image has been modified from original
  bool get isModified {
    return !_matricesEqual(transform, originalTransform);
  }

  /// Reset to original transform
  CanvasImage resetTransform() {
    return copyWith(
      transform: Matrix4.copy(originalTransform),
      lastModified: DateTime.now(),
    );
  }

  /// Get center point of the image
  Offset get center {
    final translation = transform.getTranslation();
    return Offset(
      translation.x + (image.width / 2),
      translation.y + (image.height / 2),
    );
  }

  /// Get bounding rectangle in canvas coordinates
  Rect get bounds {
    final translation = transform.getTranslation();
    final scale = transform.getMaxScaleOnAxis();

    return Rect.fromLTWH(
      translation.x,
      translation.y,
      image.width.toDouble() * scale,
      image.height.toDouble() * scale,
    );
  }

  /// Get original bounds (without transform)
  Rect get originalBounds {
    final translation = originalTransform.getTranslation();
    return Rect.fromLTWH(
      translation.x,
      translation.y,
      image.width.toDouble(),
      image.height.toDouble(),
    );
  }

  /// Get transform scale factor
  double get scale => transform.getMaxScaleOnAxis();

  /// Get transform translation
  Vector3 get translation => transform.getTranslation();

  /// Get position of the image from transform
  Offset get position {
    final translation = transform.getTranslation();
    return Offset(translation.x, translation.y);
  }

  /// Get size of the image (considering scale)
  Size get size {
    final scale = transform.getMaxScaleOnAxis();
    return Size(
      image.width.toDouble() * scale,
      image.height.toDouble() * scale,
    );
  }
  /// Check if point is inside this image
  bool containsPoint(Offset point) {
    try {
      final inverse = Matrix4.inverted(transform);
      final localPoint = MatrixUtils.transformPoint(inverse, point);

      return localPoint.dx >= 0 &&
          localPoint.dx <= image.width &&
          localPoint.dy >= 0 &&
          localPoint.dy <= image.height;
    } catch (e) {
      // If matrix is not invertible, assume point is not inside
      return false;
    }
  }

  /// Get original size of the image (without any scaling)
  Size get originalSize {
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  /// Get rotation angle in radians
  double get rotation {
    // Extract rotation from transform matrix
    final rotationMatrix = Matrix4.copy(transform);
    rotationMatrix.setTranslation(Vector3.zero());

    // Get the rotation around Z axis
    final m11 = rotationMatrix.entry(0, 0);
    final m12 = rotationMatrix.entry(0, 1);
    return math.atan2(m12, m11);
  }
  /// Compare matrices with tolerance for floating point errors
  bool _matricesEqual(Matrix4 a, Matrix4 b) {
    const tolerance = 0.001;
    for (int i = 0; i < 16; i++) {
      if ((a.storage[i] - b.storage[i]).abs() > tolerance) {
        return false;
      }
    }
    return true;
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transform': transform.storage,
      'originalTransform': originalTransform.storage,
      'createdAt': createdAt.toIso8601String(),
      'lastModified': lastModified.toIso8601String(),
      'width': image.width,
      'height': image.height,
    };
  }

  /// Create from JSON (note: ui.Image must be loaded separately)
  static CanvasImage fromJson(Map<String, dynamic> json, ui.Image image) {
    return CanvasImage(
      id: json['id'] as String,
      image: image,
      transform: Matrix4.fromList(List<double>.from(json['transform'])),
      originalTransform: Matrix4.fromList(List<double>.from(json['originalTransform'])),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastModified: DateTime.parse(json['lastModified'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CanvasImage &&
        other.id == id &&
        other.image == image &&
        _matricesEqual(other.transform, transform) &&
        _matricesEqual(other.originalTransform, originalTransform);
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      image.hashCode,
      transform.hashCode,
      originalTransform.hashCode,
    );
  }

  @override
  String toString() {
    return 'CanvasImage('
        'id: $id, '
        'bounds: $bounds, '
        'isModified: $isModified, '
        'scale: ${scale.toStringAsFixed(2)}, '
        'rotation: ${(rotation * 180 / 3.14159).toStringAsFixed(1)}°'
        ')';
  }
}
