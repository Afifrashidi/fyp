// lib/src/presentation/widgets/drawing_canvas.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';
import 'package:flutter_drawing_board/src/presentation/widgets/image_interaction_handler.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/src.dart';

// Improved cache entry with access tracking
class _CacheEntry {
  final ui.Picture picture;
  DateTime lastAccessed;

  _CacheEntry(this.picture) : lastAccessed = DateTime.now();

  void updateAccess() {
    lastAccessed = DateTime.now();
  }
}

// Improved Picture Cache Manager
class _PictureCache {
  final Map<String, _CacheEntry> _cache = {};
  static const int maxCacheSize = 30;
  static const Duration cacheExpiration = Duration(minutes: 5);

  // Get picture from cache
  ui.Picture? get(String key) {
    final entry = _cache[key];
    if (entry != null) {
      entry.updateAccess();
      return entry.picture;
    }
    return null;
  }

  // Add picture to cache
  void put(String key, ui.Picture picture) {
    // Remove if already exists to dispose old picture
    remove(key);

    // Check cache size before adding
    if (_cache.length >= maxCacheSize) {
      _evictLeastRecentlyUsed();
    }

    _cache[key] = _CacheEntry(picture);
  }

  // Remove specific entry
  void remove(String key) {
    final entry = _cache.remove(key);
    entry?.picture.dispose();
  }

  // Remove entries for a specific image
  void removeImage(String imageId) {
    final keysToRemove = _cache.keys
        .where((key) => key.startsWith('${imageId}_'))
        .toList();

    for (final key in keysToRemove) {
      remove(key);
    }
  }

  // Evict least recently used entries
  void _evictLeastRecentlyUsed() {
    if (_cache.isEmpty) return;

    // Sort entries by last access time
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed));

    // Remove oldest 25% of cache
    final toRemove = math.max(1, _cache.length ~/ 4);
    for (int i = 0; i < toRemove && i < entries.length; i++) {
      remove(entries[i].key);
    }
  }

  // Clean expired entries
  void cleanExpired() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    _cache.forEach((key, entry) {
      if (now.difference(entry.lastAccessed) > cacheExpiration) {
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      remove(key);
    }
  }

  // Clear entire cache
  void clear() {
    _cache.forEach((_, entry) => entry.picture.dispose());
    _cache.clear();
  }

  // Get cache info for debugging
  int get size => _cache.length;

  // Check if cache contains key
  bool contains(String key) => _cache.containsKey(key);
}

class DrawingCanvas extends StatefulWidget {
  final ValueNotifier<List<Stroke>> strokesListenable;
  final CurrentStrokeValueNotifier currentStrokeListenable;
  final DrawingCanvasOptions options;
  final Function(Stroke?)? onDrawingStrokeChanged;
  final GlobalKey canvasKey;
  final ValueNotifier<ui.Image?>? backgroundImageListenable;
  final ImageNotifier imageNotifier;

  const DrawingCanvas({
    super.key,
    required this.strokesListenable,
    required this.currentStrokeListenable,
    required this.options,
    this.onDrawingStrokeChanged,
    required this.canvasKey,
    this.backgroundImageListenable,
    required this.imageNotifier,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  late final ImageInteractionHandler _imageHandler;
  bool _isDrawing = false;

  // Instance-based picture cache
  late final _PictureCache _pictureCache;
  Timer? _cacheCleanupTimer;

  DrawingTool get currentTool => widget.options.currentTool;

  @override
  void initState() {
    super.initState();
    _imageHandler = ImageInteractionHandler(imageNotifier: widget.imageNotifier);
    _pictureCache = _PictureCache();

    // Set up periodic cache cleanup
    _cacheCleanupTimer = Timer.periodic(
      const Duration(minutes: 2),
          (_) => _pictureCache.cleanExpired(),
    );

    // Listen to image changes to clean up removed images
    widget.imageNotifier.addListener(_onImagesChanged);
  }

  void _onImagesChanged() {
    // Get current image IDs
    final currentImageIds = widget.imageNotifier.value.images.keys.toSet();

    // Find and remove cache entries for deleted images
    final cacheKeys = <String>[];
    for (final key in _pictureCache._cache.keys) {
      final imageId = key.split('_').first;
      if (!currentImageIds.contains(imageId)) {
        cacheKeys.add(key);
      }
    }

    for (final key in cacheKeys) {
      _pictureCache.remove(key);
    }
  }

  @override
  void dispose() {
    // Clean up timer
    _cacheCleanupTimer?.cancel();

    // Remove listener
    widget.imageNotifier.removeListener(_onImagesChanged);

    // Dispose picture cache
    _pictureCache.clear();

    // Dispose handler
    _imageHandler.dispose();

    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final offset = box.globalToLocal(event.position);

    if (currentTool == DrawingTool.pointer) {
      // Handle image interaction
      _imageHandler.handlePointerDown(offset, box.size);
    } else {
      // Handle drawing
      _isDrawing = true;
      final standardOffset = offset.scaleToStandard(box.size);

      widget.currentStrokeListenable.startStroke(
        standardOffset,
        color: widget.options.strokeColor,
        size: widget.options.size,
        opacity: widget.options.opacity,
        type: currentTool.strokeType,
        sides: widget.options.polygonSides,
        filled: widget.options.fillShape,
      );

      widget.onDrawingStrokeChanged?.call(widget.currentStrokeListenable.value);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final offset = box.globalToLocal(event.position);

    if (currentTool == DrawingTool.pointer && _imageHandler.state != InteractionState.idle) {
      _imageHandler.handlePointerMove(offset, box.size);
    } else if (_isDrawing) {
      final standardOffset = offset.scaleToStandard(box.size);
      widget.currentStrokeListenable.addPoint(standardOffset);
      widget.onDrawingStrokeChanged?.call(widget.currentStrokeListenable.value);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (currentTool == DrawingTool.pointer) {
      _imageHandler.handlePointerUp();
    } else if (_isDrawing && widget.currentStrokeListenable.hasStroke) {
      widget.strokesListenable.value = List<Stroke>.from(widget.strokesListenable.value)
        ..add(widget.currentStrokeListenable.value!);
      widget.currentStrokeListenable.clear();
      widget.onDrawingStrokeChanged?.call(null);
      _isDrawing = false;
    }
  }

  MouseCursor _getCursor() {
    if (currentTool == DrawingTool.pointer) {
      return SystemMouseCursors.basic;
    }
    return currentTool.cursor;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _getCursor(),
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        child: RepaintBoundary(
          key: widget.canvasKey,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              widget.strokesListenable,
              widget.currentStrokeListenable,
              widget.backgroundImageListenable ?? ValueNotifier(null),
              widget.imageNotifier,
              _imageHandler.contextNotifier,
            ]),
            builder: (context, _) {
              return CustomPaint(
                size: Size.infinite,
                painter: DrawingCanvasPainter(
                  strokes: widget.strokesListenable.value,
                  currentStroke: widget.currentStrokeListenable.value,
                  backgroundColor: widget.options.backgroundColor,
                  showGrid: widget.options.showGrid,
                  backgroundImage: widget.backgroundImageListenable?.value,
                  imageState: widget.imageNotifier.value,
                  interactionContext: _imageHandler.contextNotifier.value,
                  pictureCache: _pictureCache,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class DrawingCanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? currentStroke;
  final Color backgroundColor;
  final bool showGrid;
  final ui.Image? backgroundImage;
  final ImageState imageState;
  final InteractionContext? interactionContext;
  final _PictureCache pictureCache;

  DrawingCanvasPainter({
    required this.strokes,
    this.currentStroke,
    required this.backgroundColor,
    required this.showGrid,
    this.backgroundImage,
    required this.imageState,
    this.interactionContext,
    required this.pictureCache,
  });

  // Update drawing_canvas.dart paint method
  @override
  void paint(Canvas canvas, Size size) {
    try {
      // Validate canvas size
      if (size.width <= 0 || size.height <= 0) return;

      // 1. Draw background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..color = backgroundColor,
      );

      // 2. Draw background image if exists
      if (backgroundImage != null) {
        try {
          canvas.drawImageRect(
            backgroundImage!,
            Rect.fromLTWH(0, 0, backgroundImage!.width.toDouble(),
                backgroundImage!.height.toDouble()),
            Rect.fromLTWH(0, 0, size.width, size.height),
            Paint()
              ..filterQuality = FilterQuality.high,
          );
        } catch (e, stackTrace) {
          debugPrint('Error in paint: $e\n$stackTrace');
          // Draw error state
          final errorPaint = Paint()
            ..color = Colors.red.withOpacity(0.3)
            ..style = PaintingStyle.fill;
          canvas.drawRect(
              Rect.fromLTWH(0, 0, size.width, size.height), errorPaint);
        }
      }

      // 3. Draw grid if enabled
      if (showGrid) {
        _drawGrid(canvas, size);
      }

      // 4. Draw completed strokes
      for (final stroke in strokes) {
        _drawStroke(canvas, size, stroke);
      }

      // 5. Draw current stroke
      if (currentStroke != null) {
        _drawStroke(canvas, size, currentStroke!);
      }

      // 6. Draw images
      _drawImages(canvas, size);

      // 7. Draw interaction feedback
      _drawInteractionFeedback(canvas, size);
    }
  }

  void _drawImages(Canvas canvas, Size canvasSize) {
    for (final image in imageState.imageList) {
      _drawImage(canvas, canvasSize, image);
    }
  }

  void _drawImage(Canvas canvas, Size canvasSize, CanvasImage image) {
    final isSelected = imageState.selectedIds.contains(image.id);

    // Create cache key
    final cacheKey = '${image.id}_${image.transform.hashCode}_$isSelected';

    // Check cache
    final cachedPicture = pictureCache.get(cacheKey);
    if (cachedPicture != null) {
      try {
        canvas.drawPicture(cachedPicture);
        return;
      } catch (e) {
        // Remove invalid cached picture
        pictureCache.remove(cacheKey);
      }
    }

    // Record new picture
    final recorder = ui.PictureRecorder();
    final pictureCanvas = Canvas(recorder);

    try {
      // Save canvas state
      pictureCanvas.save();

      // Apply scaling for canvas size
      final scaleX = canvasSize.width / OffsetExtensions.standardWidth;
      final scaleY = canvasSize.height / OffsetExtensions.standardHeight;

      // Validate scale values
      if (scaleX <= 0 || scaleY <= 0) {
        pictureCanvas.restore();
        return;
      }

      pictureCanvas.scale(scaleX, scaleY);

      // Apply image transform
      pictureCanvas.transform(image.transform.storage);

      // Draw shadow for selected images
      if (isSelected) {
        final shadowPaint = Paint()
          ..color = Colors.black.withOpacity(0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

        pictureCanvas.drawRect(
          Rect.fromLTWH(2, 2, image.image.width.toDouble() - 4, image.image.height.toDouble() - 4),
          shadowPaint,
        );
      }

      // Draw the image
      pictureCanvas.drawImageRect(
        image.image,
        Rect.fromLTWH(0, 0, image.image.width.toDouble(), image.image.height.toDouble()),
        Rect.fromLTWH(0, 0, image.image.width.toDouble(), image.image.height.toDouble()),
        Paint()
          ..filterQuality = FilterQuality.high
          ..isAntiAlias = true,
      );

      // Draw selection outline
      if (isSelected) {
        final outlinePaint = Paint()
          ..color = Colors.blue
          ..strokeWidth = 2.0 / math.min(scaleX, scaleY) // Adjust for scale
          ..style = PaintingStyle.stroke;

        pictureCanvas.drawRect(
          Rect.fromLTWH(0, 0, image.image.width.toDouble(), image.image.height.toDouble()),
          outlinePaint,
        );

        // Draw handles for single selection
        if (imageState.selectedIds.length == 1) {
          _drawHandles(pictureCanvas, image, 1 / math.min(scaleX, scaleY));
        }
      }

      // Restore canvas state
      pictureCanvas.restore();

      // Cache the picture
      final picture = recorder.endRecording();
      pictureCache.put(cacheKey, picture);

      // Draw the cached picture
      canvas.drawPicture(picture);
    } catch (e) {
      debugPrint('Error drawing image: $e');
      pictureCanvas.restore();
      // Don't cache failed pictures
      recorder.endRecording().dispose();
    }
  }

  void _drawHandles(Canvas canvas, CanvasImage image, double scale) {
    const handleRadius = 4.0;
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final handleBorderPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = math.max(2.0 * scale, 1.0)
      ..style = PaintingStyle.stroke;

    // Get the actual image dimensions
    final imageWidth = image.image.width.toDouble();
    final imageHeight = image.image.height.toDouble();

    // Corner and side handles in local image space
    final corners = [
      Offset(0, 0), // Top-left
      Offset(imageWidth, 0), // Top-right
      Offset(0, imageHeight), // Bottom-left
      Offset(imageWidth, imageHeight), // Bottom-right
      Offset(imageWidth / 2, 0), // Top-middle
      Offset(imageWidth, imageHeight / 2), // Right-middle
      Offset(imageWidth / 2, imageHeight), // Bottom-middle
      Offset(0, imageHeight / 2), // Left-middle
    ];

    // Draw resize handles
    for (final corner in corners) {
      final adjustedRadius = math.max(handleRadius * scale, 2.0);
      canvas.drawCircle(corner, adjustedRadius, handlePaint);
      canvas.drawCircle(corner, adjustedRadius, handleBorderPaint);
    }

    // Draw rotation handle above the image
    final rotationHandleDistance = 30 * scale;
    final rotationHandlePos = Offset(imageWidth / 2, -rotationHandleDistance);

    // Draw line to rotation handle
    canvas.drawLine(
      Offset(imageWidth / 2, 0),
      rotationHandlePos,
      Paint()
        ..color = Colors.blue
        ..strokeWidth = math.max(1.0 * scale, 0.5),
    );

    // Draw rotation handle circle
    final rotationRadius = math.max(8 * scale, 4.0);
    canvas.drawCircle(rotationHandlePos, rotationRadius, handlePaint);
    canvas.drawCircle(rotationHandlePos, rotationRadius, handleBorderPaint);

    // Draw rotation icon
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.rotate_right.codePoint),
        style: TextStyle(
          fontSize: math.max(12 * scale, 8.0),
          fontFamily: Icons.rotate_right.fontFamily,
          package: Icons.rotate_right.fontPackage,
          color: Colors.blue,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(
      canvas,
      rotationHandlePos - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );
  }

  void _drawInteractionFeedback(Canvas canvas, Size canvasSize) {
    if (interactionContext?.selectionRect != null) {
      _drawSelectionRect(canvas, canvasSize, interactionContext!.selectionRect!);
    }
  }

  void _drawSelectionRect(Canvas canvas, Size canvasSize, Rect standardRect) {
    final topLeft = standardRect.topLeft.scaleFromStandard(canvasSize);
    final bottomRight = standardRect.bottomRight.scaleFromStandard(canvasSize);

    final rect = Rect.fromPoints(topLeft, bottomRight);

    // Fill
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.blue.withOpacity(0.1)
        ..style = PaintingStyle.fill,
    );

    // Border with dash pattern
    final borderPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawRect(rect, borderPaint);
  }

  void _drawStroke(Canvas canvas, Size size, Stroke stroke) {
    final points = stroke.points;
    if (points.isEmpty) return;

    final strokeSize = math.max(stroke.size, 0.1); // Ensure minimum stroke size
    final paint = Paint()
      ..color = stroke.color.withOpacity(math.max(stroke.opacity, 0.1))
      ..strokeWidth = strokeSize
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    try {
      if (stroke is NormalStroke) {
        if (points.length == 1) {
          final center = points.first.scaleFromStandard(size);
          canvas.drawCircle(center, strokeSize / 2, paint..style = PaintingStyle.fill);
        } else {
          final path = _getStrokePath(stroke, size);
          canvas.drawPath(path, paint);
        }
      } else if (stroke is EraserStroke) {
        paint
          ..color = backgroundColor
          ..blendMode = BlendMode.src;
        final path = _getStrokePath(stroke, size);
        canvas.drawPath(path, paint);
      } else if (stroke is LineStroke && points.length >= 2) {
        final firstPoint = points.first.scaleFromStandard(size);
        final lastPoint = points.last.scaleFromStandard(size);
        canvas.drawLine(firstPoint, lastPoint, paint);
      } else if (stroke is CircleStroke && points.length >= 2) {
        final firstPoint = points.first.scaleFromStandard(size);
        final lastPoint = points.last.scaleFromStandard(size);
        final rect = Rect.fromPoints(firstPoint, lastPoint);
        if ((stroke as CircleStroke).filled) paint.style = PaintingStyle.fill;
        canvas.drawOval(rect, paint);
      } else if (stroke is SquareStroke && points.length >= 2) {
        final firstPoint = points.first.scaleFromStandard(size);
        final lastPoint = points.last.scaleFromStandard(size);
        final rect = Rect.fromPoints(firstPoint, lastPoint);
        if ((stroke as SquareStroke).filled) paint.style = PaintingStyle.fill;
        canvas.drawRect(rect, paint);
      } else if (stroke is PolygonStroke && points.length >= 2) {
        _drawPolygon(canvas, size, stroke as PolygonStroke, paint);
      }
    } catch (e) {
      debugPrint('Error drawing stroke: $e');
    }
  }

  Path _getStrokePath(Stroke stroke, Size size) {
    final path = Path();
    final points = stroke.points;

    if (points.isNotEmpty) {
      final firstPoint = points.first.scaleFromStandard(size);
      path.moveTo(firstPoint.dx, firstPoint.dy);

      if (points.length == 2) {
        final lastPoint = points.last.scaleFromStandard(size);
        path.lineTo(lastPoint.dx, lastPoint.dy);
      } else if (points.length > 2) {
        for (int i = 1; i < points.length - 1; i++) {
          final p0 = points[i].scaleFromStandard(size);
          final p1 = points[i + 1].scaleFromStandard(size);
          path.quadraticBezierTo(
            p0.dx,
            p0.dy,
            (p0.dx + p1.dx) / 2,
            (p0.dy + p1.dy) / 2,
          );
        }

        final lastPoint = points.last.scaleFromStandard(size);
        path.lineTo(lastPoint.dx, lastPoint.dy);
      }
    }

    return path;
  }

  void _drawPolygon(Canvas canvas, Size size, PolygonStroke stroke, Paint paint) {
    final points = stroke.points;
    if (points.length < 2) return;

    final firstPoint = points.first.scaleFromStandard(size);
    final lastPoint = points.last.scaleFromStandard(size);
    final center = Offset(
      (firstPoint.dx + lastPoint.dx) / 2,
      (firstPoint.dy + lastPoint.dy) / 2,
    );
    final radius = math.max((firstPoint - lastPoint).distance / 2, 1.0);

    final path = Path();
    const startAngle = -math.pi / 2;
    final angleStep = (2 * math.pi) / math.max(stroke.sides, 3); // Ensure minimum 3 sides

    for (int i = 0; i < stroke.sides; i++) {
      final angle = startAngle + (angleStep * i);
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    if (stroke.filled) paint.style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    const gridSpacing = 50.0;
    const subGridSpacing = 10.0;

    final gridPaint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..strokeWidth = 1.0;

    final subGridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.05)
      ..strokeWidth = 0.5;

    // Draw sub-grid
    for (double y = 0; y <= size.height; y += subGridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), subGridPaint);
    }
    for (double x = 0; x <= size.width; x += subGridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), subGridPaint);
    }

    // Draw main grid
    for (double y = 0; y <= size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (double x = 0; x <= size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) {
    return strokes != oldDelegate.strokes ||
        currentStroke != oldDelegate.currentStroke ||
        backgroundColor != oldDelegate.backgroundColor ||
        showGrid != oldDelegate.showGrid ||
        backgroundImage != oldDelegate.backgroundImage ||
        imageState != oldDelegate.imageState ||
        interactionContext != oldDelegate.interactionContext;
  }
}