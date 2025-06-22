// lib/src/presentation/widgets/drawing_canvas.dart

import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_drawing_board/src/constants/canvas_operations_enums.dart';
import 'package:flutter_drawing_board/src/constants/interaction_enums.dart';
import 'package:flutter_drawing_board/src/domain/domain.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';
import 'package:flutter_drawing_board/src/extensions/extensions.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/current_stroke_value_notifier.dart';
import 'package:flutter_drawing_board/src/presentation/widgets/image_interaction_handler.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/presentation/widgets/text_input_dialog.dart';
import 'package:flutter_drawing_board/src/services/memory_safe_picture_cache.dart';
import 'package:flutter_drawing_board/src/extensions/grid_snap_extensions.dart';
import 'package:flutter_drawing_board/src/src.dart';
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';

class DrawingCanvas extends StatefulWidget {
  final DrawingCanvasOptions options;
  final GlobalKey canvasKey;
  final CurrentStrokeValueNotifier currentStrokeListenable;
  final ValueNotifier<List<Stroke>> strokesListenable;
  final ValueNotifier<ui.Image?>? backgroundImageListenable;
  final ImageNotifier imageNotifier;
  final Function(Stroke?)? onDrawingStrokeChanged;

  const DrawingCanvas({
    Key? key,
    required this.options,
    required this.canvasKey,
    required this.currentStrokeListenable,
    required this.strokesListenable,
    this.backgroundImageListenable,
    required this.imageNotifier,
    this.onDrawingStrokeChanged,
  }) : super(key: key);

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas>
    with PictureCacheLifecycle {
  bool _isDrawing = false;
  late ImageInteractionHandler _imageHandler;
  bool _isTextMode = false;
  String? _selectedImageId;

  @override
  void initState() {
    super.initState();
    _imageHandler = ImageInteractionHandler(
      widget.imageNotifier,
      onImageStateChanged: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _imageHandler.dispose();
    super.dispose();
  }

  DrawingTool get currentTool => widget.options.currentTool;

  // UPDATED: Replace pointer and selector handling with unified imageManipulator
  void _onPointerDown(PointerDownEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    var offset = box.globalToLocal(event.position);

    // Apply grid snapping if enabled
    if (widget.options.snapToGrid) {
      offset = offset.snapToGrid(
        snapEnabled: true,
        gridSpacing: AppConstants.gridSpacing,
        tolerance: AppConstants.gridSnapTolerance,
      );
    }

    switch (currentTool) {
      case DrawingTool.imageManipulator:
      // UPDATED: Handle unified image manipulation (select + move + transform)
        _handleImageManipulation(offset, box.size);
        break;

      case DrawingTool.text:
        _handleTextTool(offset);
        break;

      default:
        _handleDrawingStart(offset, box.size);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    var offset = box.globalToLocal(event.position);

    // Apply grid snapping if enabled and currently drawing
    if (_isDrawing && widget.options.snapToGrid && !_isTextMode) {
      offset = offset.snapToGrid(
        snapEnabled: true,
        gridSpacing: AppConstants.gridSpacing,
        tolerance: AppConstants.gridSnapTolerance,
      );
    }

    if (currentTool == DrawingTool.imageManipulator &&
        _imageHandler.state != InteractionState.idle) {
      _imageHandler.handlePointerMove(offset, box.size);
    } else if (_isDrawing && !_isTextMode) {
      final standardOffset = offset.scaleToStandard(box.size);
      widget.currentStrokeListenable.addPoint(standardOffset);
      widget.onDrawingStrokeChanged?.call(widget.currentStrokeListenable.value);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (currentTool == DrawingTool.imageManipulator) {
      _imageHandler.handlePointerUp();
    } else if (_isDrawing && widget.currentStrokeListenable.hasStroke && !_isTextMode) {
      widget.strokesListenable.value =
      List<Stroke>.from(widget.strokesListenable.value)
        ..add(widget.currentStrokeListenable.value!);
      widget.currentStrokeListenable.clear();
      widget.onDrawingStrokeChanged?.call(null);
      _isDrawing = false;
    }
  }

  void _handleDrawingStart(Offset offset, Size canvasSize) {
    _isDrawing = true;
    final standardOffset = offset.scaleToStandard(canvasSize);

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

  // NEW: Unified image manipulation handler (combines selection and movement)
  void _handleImageManipulation(Offset offset, Size canvasSize) {
    // This combines the functionality of both pointer and selector tools
    _imageHandler.handlePointerDown(offset, canvasSize);
  }

  void _handleSelectorDown(Offset offset) {
    // Find which image was clicked
    final images = widget.imageNotifier.value.imageList;
    String? selectedId;

    for (final image in images.reversed) {
      if (_isPointInImage(offset, image)) {
        selectedId = image.id;
        break;
      }
    }

    // Update selection
    if (selectedId != null) {
      widget.imageNotifier.selectImage(selectedId);
      _selectedImageId = selectedId;
    } else {
      widget.imageNotifier.clearSelection();
      _selectedImageId = null;
    }
  }

  bool _isPointInImage(Offset point, CanvasImage image) {
    return image.containsPoint(point);
  }

  void _handleTextTool(Offset offset) async {
    _isTextMode = true;
    final standardOffset = offset.scaleToStandard(context.size ?? Size.zero);

    try {
      // Show text input dialog
      final text = await TextInputDialog.show(
        context,
        fontSize: widget.options.size * 2,
        color: widget.options.strokeColor,
      );

      if (text != null && text.isNotEmpty) {
        // Create text stroke
        widget.currentStrokeListenable.startStroke(
          standardOffset,
          color: widget.options.strokeColor,
          size: widget.options.size,
          opacity: widget.options.opacity,
          type: StrokeType.text,
        );

        // Update text content
        widget.currentStrokeListenable.updateText(text);

        // Add stroke to canvas
        if (widget.currentStrokeListenable.hasStroke) {
          widget.strokesListenable.value =
          List<Stroke>.from(widget.strokesListenable.value)
            ..add(widget.currentStrokeListenable.value!);
          widget.currentStrokeListenable.clear();
        }
      }
    } catch (e) {
      debugPrint('Error in text tool: $e');
    } finally {
      _isTextMode = false;
    }
  }

  MouseCursor _getCursor() {
    if (_imageHandler.state != InteractionState.idle) {
      return SystemMouseCursors.move;
    }
    return currentTool.cursor;
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          // Handle escape key for tool cancellation
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (_isDrawing) {
              widget.currentStrokeListenable.clear();
              _isDrawing = false;
            }
            if (_selectedImageId != null) {
              widget.imageNotifier.clearSelection();
              _selectedImageId = null;
            }
          }
        }
      },
      child: MouseRegion(
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
                    snapToGrid: widget.options.snapToGrid,
                    backgroundImage: widget.backgroundImageListenable?.value,
                    imageState: widget.imageNotifier.value,
                    interactionContext: _imageHandler.contextNotifier.value,
                    pictureCache: pictureCache,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Enhanced DrawingCanvasPainter with grid snapping and proper stroke rendering
class DrawingCanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? currentStroke;
  final Color backgroundColor;
  final bool showGrid;
  final bool snapToGrid;
  final ui.Image? backgroundImage;
  final ImageState imageState;
  final InteractionContext? interactionContext;
  final PictureCache pictureCache;

  DrawingCanvasPainter({
    required this.strokes,
    this.currentStroke,
    required this.backgroundColor,
    required this.showGrid,
    required this.snapToGrid,
    this.backgroundImage,
    required this.imageState,
    this.interactionContext,
    required this.pictureCache,
  });

  @override
  void paint(Canvas canvas, Size size) {
    try {
      if (size.width <= 0 || size.height <= 0) return;

      // 1. Background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = backgroundColor,
      );

      // 2. Background image
      if (backgroundImage != null) {
        try {
          canvas.drawImageRect(
            backgroundImage!,
            Rect.fromLTWH(0, 0, backgroundImage!.width.toDouble(),
                backgroundImage!.height.toDouble()),
            Rect.fromLTWH(0, 0, size.width, size.height),
            Paint()..filterQuality = FilterQuality.high,
          );
        } catch (e) {
          debugPrint('Error drawing background image: $e');
        }
      }

      // 3. Grid
      if (showGrid) {
        _drawGrid(canvas, size);
      }

      // 4. Completed strokes
      for (final stroke in strokes) {
        _drawStroke(canvas, size, stroke);
      }

      // 5. Current stroke
      if (currentStroke != null) {
        _drawStroke(canvas, size, currentStroke!);
      }

      // 6. Images
      _drawImages(canvas, size);

      // 7. Selection indicators
      _drawSelectionIndicators(canvas, size);

      // 8. Grid snap indicators
      if (snapToGrid && showGrid) {
        _drawSnapIndicators(canvas, size);
      }

    } catch (e, stackTrace) {
      debugPrint('Error in DrawingCanvasPainter.paint: $e\n$stackTrace');
    }
  }

  // ✅ UPDATED: Enhanced _drawStroke method with proper eraser handling
  void _drawStroke(Canvas canvas, Size canvasSize, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    try {
      final paint = Paint()
        ..color = stroke.color.withOpacity(stroke.opacity)
        ..strokeWidth = stroke.size
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      // ✅ CRITICAL FIX: Handle eraser strokes with BlendMode.clear
      if (stroke.strokeType == StrokeType.eraser || stroke is EraserStroke) {
        paint.blendMode = ui.BlendMode.clear;
      }

      // Scale points to canvas size
      final scaledPoints = stroke.points
          .map((p) => p.scaleFromStandard(canvasSize))
          .toList();

      if (stroke is RectangleStroke) {
        _drawRectangleStroke(canvas, scaledPoints, paint, stroke.filled);
      } else if (stroke is TextStroke) {
        _drawTextStroke(canvas, scaledPoints, stroke, canvasSize);
      } else if (stroke is CircleStroke) {
        _drawCircleStroke(canvas, scaledPoints, paint, stroke.filled);
      } else if (stroke is SquareStroke) {
        _drawSquareStroke(canvas, scaledPoints, paint, stroke.filled);
      } else if (stroke is LineStroke) {
        _drawLineStroke(canvas, scaledPoints, paint);
      } else if (stroke is PolygonStroke) {
        _drawPolygonStroke(canvas, scaledPoints, paint, stroke.sides, stroke.filled);
      } else {
        // Default stroke drawing for normal strokes and eraser strokes
        _drawDefaultStroke(canvas, scaledPoints, paint, stroke);
      }
    } catch (e) {
      debugPrint('Error drawing stroke: $e');
    }
  }

  void _drawRectangleStroke(Canvas canvas, List<Offset> points, Paint paint, bool filled) {
    if (points.isEmpty) return;

    paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;

    if (points.length == 1) {
      canvas.drawRect(
        Rect.fromCenter(
          center: points.first,
          width: paint.strokeWidth,
          height: paint.strokeWidth,
        ),
        paint,
      );
    } else {
      final rect = Rect.fromPoints(points.first, points.last);
      canvas.drawRect(rect, paint);
    }
  }

  void _drawTextStroke(Canvas canvas, List<Offset> points, TextStroke textStroke, Size canvasSize) {
    if (points.isEmpty || textStroke.text.isEmpty) return;

    final textPainter = TextPainter(
      text: TextSpan(
        text: textStroke.text,
        style: TextStyle(
          fontSize: textStroke.fontSize * (canvasSize.width / OffsetExtensions.standardWidth),
          fontFamily: textStroke.fontFamily,
          color: textStroke.color.withOpacity(textStroke.opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, points.first);
  }

  void _drawCircleStroke(Canvas canvas, List<Offset> points, Paint paint, bool filled) {
    if (points.isEmpty) return;

    paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;

    if (points.length == 1) {
      canvas.drawCircle(points.first, paint.strokeWidth / 2, paint);
    } else {
      final center = points.first;
      final radius = (points.last - points.first).distance;
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawSquareStroke(Canvas canvas, List<Offset> points, Paint paint, bool filled) {
    if (points.isEmpty) return;

    paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;

    if (points.length == 1) {
      canvas.drawRect(
        Rect.fromCenter(
          center: points.first,
          width: paint.strokeWidth,
          height: paint.strokeWidth,
        ),
        paint,
      );
    } else {
      final side = (points.last - points.first).distance;
      final rect = Rect.fromCenter(
        center: points.first,
        width: side,
        height: side,
      );
      canvas.drawRect(rect, paint);
    }
  }

  void _drawLineStroke(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;

    paint.style = PaintingStyle.stroke;
    canvas.drawLine(points.first, points.last, paint);
  }

  void _drawPolygonStroke(Canvas canvas, List<Offset> points, Paint paint, int sides, bool filled) {
    if (points.isEmpty || sides < 3) return;

    paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;

    if (points.length == 1) {
      _drawRegularPolygon(canvas, points.first, paint.strokeWidth, sides, paint);
    } else {
      final center = points.first;
      final radius = (points.last - points.first).distance;
      _drawRegularPolygon(canvas, center, radius, sides, paint);
    }
  }

  void _drawRegularPolygon(Canvas canvas, Offset center, double radius, int sides, Paint paint) {
    final path = Path();
    final angleStep = 2 * math.pi / sides;

    for (int i = 0; i < sides; i++) {
      final angle = i * angleStep - math.pi / 2; // Start from top
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  // ✅ UPDATED: Enhanced _drawDefaultStroke with proper eraser handling
  void _drawDefaultStroke(Canvas canvas, List<Offset> points, Paint paint, Stroke stroke) {
    if (points.length < 2) {
      if (points.isNotEmpty) {
        // ✅ Single point drawing (dots/taps)
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(
          points.first,
          paint.strokeWidth / 2,
          paint,
        );
      }
      return;
    }

    // ✅ Multi-point stroke drawing (lines/paths)
    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    paint.style = PaintingStyle.stroke;
    canvas.drawPath(path, paint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.gridMain
      ..strokeWidth = AppConstants.gridStrokeWidth;

    final subGridPaint = Paint()
      ..color = AppColors.gridSub
      ..strokeWidth = AppConstants.subGridStrokeWidth;

    // Draw sub-grid first
    for (double y = 0; y <= size.height; y += AppConstants.subGridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), subGridPaint);
    }
    for (double x = 0; x <= size.width; x += AppConstants.subGridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), subGridPaint);
    }

    // Draw main grid
    for (double y = 0; y <= size.height; y += AppConstants.gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (double x = 0; x <= size.width; x += AppConstants.gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  void _drawImages(Canvas canvas, Size canvasSize) {
    for (final image in imageState.imageList) {
      _drawImage(canvas, canvasSize, image);
    }
  }

  void _drawImage(Canvas canvas, Size canvasSize, CanvasImage image) {
    try {
      canvas.save();
      canvas.transform(image.transform.storage);
      canvas.drawImage(image.image, Offset.zero, Paint());
      canvas.restore();
    } catch (e) {
      debugPrint('Error drawing image ${image.id}: $e');
    }
  }

  void _drawSelectionIndicators(Canvas canvas, Size size) {
    final selectedImages = imageState.imageList
        .where((img) => imageState.selectedIds.contains(img.id));

    for (final image in selectedImages) {
      // Draw selection border around selected images
      final paint = Paint()
        ..color = AppColors.selectionBorder
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      canvas.save();
      canvas.transform(image.transform.storage);

      final bounds = Rect.fromLTWH(
        0,
        0,
        image.image.width.toDouble(),
        image.image.height.toDouble(),
      );
      canvas.drawRect(bounds, paint);

      canvas.restore();
    }
  }

  void _drawSnapIndicators(Canvas canvas, Size size) {
    // Draw subtle indicators at grid intersections when snap is enabled
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    for (double y = 0; y <= size.height; y += AppConstants.gridSpacing) {
      for (double x = 0; x <= size.width; x += AppConstants.gridSpacing) {
        canvas.drawCircle(Offset(x, y), 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) {
    return strokes != oldDelegate.strokes ||
        currentStroke != oldDelegate.currentStroke ||
        backgroundColor != oldDelegate.backgroundColor ||
        showGrid != oldDelegate.showGrid ||
        snapToGrid != oldDelegate.snapToGrid ||
        backgroundImage != oldDelegate.backgroundImage ||
        imageState != oldDelegate.imageState ||
        interactionContext != oldDelegate.interactionContext;
  }
}