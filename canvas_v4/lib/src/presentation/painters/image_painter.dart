// lib/src/presentation/painters/image_painter.dart
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // Add this import for Colors
import 'package:flutter_drawing_board/src/domain/domain.dart';

class ImagePainter extends CustomPainter {
  final List<CanvasImage> images;
  final Set<String> selectedIds;
  final Map<String, ui.Picture> _pictureCache = {};

  ImagePainter({
    required this.images,
    required this.selectedIds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final image in images) {
      _drawImage(canvas, size, image);
    }
  }

  void _drawImage(Canvas canvas, Size canvasSize, CanvasImage image) {
    canvas.save();

    // Apply transform
    canvas.transform(image.transform.storage);

    // Draw from cache if available
    final cacheKey = '${image.id}_${image.transform.hashCode}';
    final cachedPicture = _pictureCache[cacheKey];

    if (cachedPicture != null) {
      canvas.drawPicture(cachedPicture);
    } else {
      // Create and cache the picture
      final recorder = ui.PictureRecorder();
      final pictureCanvas = Canvas(recorder);

      // Draw image
      pictureCanvas.drawImageRect(
        image.image,
        Rect.fromLTWH(0, 0, image.image.width.toDouble(), image.image.height.toDouble()),
        Rect.fromLTWH(0, 0, image.image.width.toDouble(), image.image.height.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );

      // Draw selection if needed
      if (selectedIds.contains(image.id)) {
        _drawSelection(pictureCanvas, image);
      }

      _pictureCache[cacheKey] = recorder.endRecording();
      canvas.drawPicture(_pictureCache[cacheKey]!);
    }

    canvas.restore();
  }

  void _drawSelection(Canvas canvas, CanvasImage image) {
    final imageWidth = image.image.width.toDouble();
    final imageHeight = image.image.height.toDouble();

    // Draw selection outline
    final selectionPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final selectionRect = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    canvas.drawRect(selectionRect, selectionPaint);

    // Draw selection handles (corners and sides)
    final handlePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    final handleBorderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const handleSize = 8.0;

    // Corner and side handles
    final handles = [
      Offset(0, 0), // Top-left
      Offset(imageWidth, 0), // Top-right
      Offset(0, imageHeight), // Bottom-left
      Offset(imageWidth, imageHeight), // Bottom-right
      Offset(imageWidth / 2, 0), // Top-middle
      Offset(imageWidth, imageHeight / 2), // Right-middle
      Offset(imageWidth / 2, imageHeight), // Bottom-middle
      Offset(0, imageHeight / 2), // Left-middle
    ];

    for (final handleCenter in handles) {
      final handleRect = Rect.fromCenter(
        center: handleCenter,
        width: handleSize,
        height: handleSize,
      );

      // Draw handle background
      canvas.drawRect(handleRect, handlePaint);
      // Draw handle border
      canvas.drawRect(handleRect, handleBorderPaint);
    }
  }

  @override
  bool shouldRepaint(ImagePainter oldDelegate) {
    return images != oldDelegate.images ||
        selectedIds != oldDelegate.selectedIds;
  }
}