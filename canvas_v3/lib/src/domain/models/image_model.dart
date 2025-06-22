// lib/src/domain/models/image_model.dart
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

class CanvasImage {
  final String id;
  final ui.Image image;
  final Matrix4 transform;
  final DateTime createdAt;

  // Cache computed properties
  Offset? _cachedPosition;
  Size? _cachedSize;
  double? _cachedRotation;
  Rect? _cachedBounds;

  CanvasImage({
    String? id,
    required this.image,
    Matrix4? transform,
    DateTime? createdAt,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        transform = transform ?? Matrix4.identity(),
        createdAt = createdAt ?? DateTime.now();

  // Factory constructor for initial positioning
  factory CanvasImage.withPosition({
    required ui.Image image,
    required Offset position,
    Size? size,
  }) {
    final transform = Matrix4.identity()
      ..translate(position.dx, position.dy);

    if (size != null) {
      final scaleX = size.width / image.width;
      final scaleY = size.height / image.height;
      transform.scale(scaleX, scaleY);
    }

    return CanvasImage(image: image, transform: transform);
  }

  // Computed properties with caching
  Offset get position {
    if (_cachedPosition == null) {
      final translation = transform.getTranslation();
      _cachedPosition = Offset(translation.x, translation.y);
    }
    return _cachedPosition!;
  }

  double get rotation {
    if (_cachedRotation == null) {
      // Extract rotation more accurately considering scale
      final scaleX = math.sqrt(transform[0] * transform[0] + transform[1] * transform[1]);
      if (scaleX != 0) {
        _cachedRotation = math.atan2(transform[1] / scaleX, transform[0] / scaleX);
      } else {
        _cachedRotation = 0.0;
      }
    }
    return _cachedRotation!;
  }

  Size get size {
    if (_cachedSize == null) {
      // Get scale from transform
      final scaleX = math.sqrt(transform[0] * transform[0] + transform[1] * transform[1]);
      final scaleY = math.sqrt(transform[4] * transform[4] + transform[5] * transform[5]);
      _cachedSize = Size(image.width * scaleX, image.height * scaleY);
    }
    return _cachedSize!;
  }

  Size get originalSize => Size(image.width.toDouble(), image.height.toDouble());

  Rect get bounds {
    if (_cachedBounds == null) {
      _cachedBounds = position & size;
    }
    return _cachedBounds!;
  }

  Offset get center => position + Offset(size.width / 2, size.height / 2);

  // Clear cache when transform changes
  void _clearCache() {
    _cachedPosition = null;
    _cachedSize = null;
    _cachedRotation = null;
    _cachedBounds = null;
  }

  bool containsPoint(Offset point) {
    // Transform point to local space
    final inverse = Matrix4.tryInvert(transform.clone());
    if (inverse == null) return false;

    final vector = Vector3(point.dx, point.dy, 0);
    inverse.transform3(vector);

    return Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble())
        .contains(Offset(vector.x, vector.y));
  }

  CanvasImage copyWith({
    String? id,
    ui.Image? image,
    Matrix4? transform,
    DateTime? createdAt,
  }) {
    return CanvasImage(
      id: id ?? this.id,
      image: image ?? this.image,
      transform: transform ?? this.transform.clone(),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Get resize handles in world coordinates
  Map<HandleType, Offset> getHandles() {
    final corners = [
      Offset(0, 0), // top-left
      Offset(image.width.toDouble(), 0), // top-right
      Offset(0, image.height.toDouble()), // bottom-left
      Offset(image.width.toDouble(), image.height.toDouble()), // bottom-right
      Offset(image.width / 2, 0), // top-middle
      Offset(image.width.toDouble(), image.height / 2), // right-middle
      Offset(image.width / 2, image.height.toDouble()), // bottom-middle
      Offset(0, image.height / 2), // left-middle
    ];

    final handles = <HandleType, Offset>{};
    final handleTypes = [
      HandleType.topLeft,
      HandleType.topRight,
      HandleType.bottomLeft,
      HandleType.bottomRight,
      HandleType.topMiddle,
      HandleType.rightMiddle,
      HandleType.bottomMiddle,
      HandleType.leftMiddle,
    ];

    for (int i = 0; i < corners.length; i++) {
      final vector = Vector3(corners[i].dx, corners[i].dy, 0);
      transform.transform3(vector);
      handles[handleTypes[i]] = Offset(vector.x, vector.y);
    }

    // Add rotation handle above top-middle
    final topMiddle = handles[HandleType.topMiddle]!;
    final rotVector = Vector3(image.width / 2, -30, 0);
    transform.transform3(rotVector);
    handles[HandleType.rotation] = Offset(rotVector.x, rotVector.y);

    return handles;
  }

  // Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transform': transform.storage.toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // Deserialize from JSON
  static CanvasImage fromJson(Map<String, dynamic> json, ui.Image image) {
    final transformData = (json['transform'] as List).cast<double>();
    return CanvasImage(
      id: json['id'],
      image: image,
      transform: Matrix4.fromList(transformData),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

// Handle types for resize/rotate operations
enum HandleType {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  topMiddle,
  rightMiddle,
  bottomMiddle,
  leftMiddle,
  rotation,
}

// Batch operations
enum BatchOperationType {
  align,
  distribute,
  arrange,
}

enum ArrangementType {
  grid,
  circle,
  spiral,
}

class ImageBatchOperation {
  final BatchOperationType type;
  final List<String>? imageIds;
  final AlignmentType? alignment;
  final DistributeType? distributeType;
  final ArrangementType? arrangement;
  final Axis? axis;

  ImageBatchOperation({
    required this.type,
    this.imageIds,
    this.alignment,
    this.distributeType,
    this.arrangement,
    this.axis,
  });
}

// Note: AlignmentType and DistributeType are defined in ImageNotifier