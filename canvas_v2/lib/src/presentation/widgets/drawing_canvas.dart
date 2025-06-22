// lib/src/presentation/widgets/drawing_canvas.dart
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/src.dart';

enum CanvasInteractionMode {
  none,
  drawing,
  draggingImage,
  resizingImage,
  rotatingImage,
  selectingArea,
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
  final _showGrid = ValueNotifier<bool>(false);

  // Interaction state
  CanvasInteractionMode _interactionMode = CanvasInteractionMode.none;
  Offset? _dragStartPoint;
  Map<String, Offset> _initialImagePositions = {};
  String? _resizeHandle;
  CanvasImage? _resizingImage;
  Size? _initialImageSize;
  Offset? _initialImagePosition;
  double? _initialRotation;
  Offset? _rotationStartPoint;

  // Selection rectangle
  Rect? _selectionRect;

  // Keyboard state
  bool _isShiftPressed = false;
  bool _isCtrlPressed = false;
  bool _isAltPressed = false;

  Color get strokeColor => widget.options.strokeColor;
  double get size => widget.options.size;
  double get opacity => widget.options.opacity;
  DrawingTool get currentTool => widget.options.currentTool;
  ValueNotifier<List<Stroke>> get _strokes => widget.strokesListenable;
  CurrentStrokeValueNotifier get _currentStroke => widget.currentStrokeListenable;

  @override
  void initState() {
    super.initState();
    // Setup keyboard listeners for web
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    setState(() {
      _isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      _isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      _isAltPressed = HardwareKeyboard.instance.isAltPressed;
    });

    // Handle keyboard shortcuts
    if (event is KeyDownEvent) {
      if (_isCtrlPressed) {
        switch (event.logicalKey) {
          case LogicalKeyboardKey.keyA:
            widget.imageNotifier.selectAll();
            return true;
          case LogicalKeyboardKey.keyC:
            widget.imageNotifier.copySelectedImages();
            return true;
          case LogicalKeyboardKey.keyX:
            widget.imageNotifier.cutSelectedImages();
            return true;
          case LogicalKeyboardKey.keyV:
            final box = context.findRenderObject() as RenderBox?;
            if (box != null) {
              // Paste at center of canvas in standard coordinates
              final center = Offset(400, 300); // Center of 800x600 standard canvas
              widget.imageNotifier.pasteImages(center);
            }
            return true;
          case LogicalKeyboardKey.keyD:
            widget.imageNotifier.deselectAll();
            return true;
        }
      }

      // Delete selected images
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        widget.imageNotifier.removeSelectedImages();
        return true;
      }

      // Arrow keys for nudging
      if (widget.imageNotifier.hasSelection) {
        Offset nudge = Offset.zero;
        final nudgeAmount = _isShiftPressed ? 10.0 : 1.0;

        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            nudge = Offset(-nudgeAmount, 0);
            break;
          case LogicalKeyboardKey.arrowRight:
            nudge = Offset(nudgeAmount, 0);
            break;
          case LogicalKeyboardKey.arrowUp:
            nudge = Offset(0, -nudgeAmount);
            break;
          case LogicalKeyboardKey.arrowDown:
            nudge = Offset(0, nudgeAmount);
            break;
        }

        if (nudge != Offset.zero) {
          widget.imageNotifier.moveSelectedImages(nudge);
          return true;
        }
      }
    }

    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final offset = box.globalToLocal(event.position);
    final standardOffset = offset.scaleToStandard(box.size);

    if (currentTool == DrawingTool.pointer) {
      // Check for resize handles first (only if single selection)
      if (widget.imageNotifier.selectedImageIds.length == 1) {
        final selectedId = widget.imageNotifier.selectedImageIds.first;
        final selectedImage = widget.imageNotifier.value.firstWhere((img) => img.id == selectedId);

        // Check resize handles
        final handles = selectedImage.getResizeHandles();
        for (final entry in handles.entries) {
          final handleRect = Rect.fromCenter(
            center: entry.value,
            width: 16,
            height: 16,
          );
          if (handleRect.contains(standardOffset)) {
            setState(() {
              _interactionMode = CanvasInteractionMode.resizingImage;
              _resizeHandle = entry.key;
              _resizingImage = selectedImage;
              _initialImageSize = selectedImage.size;
              _initialImagePosition = selectedImage.position;
              _dragStartPoint = standardOffset;
            });
            return;
          }
        }

        // Check rotation handle
        final rotationHandle = selectedImage.getRotationHandle();
        final rotationRect = Rect.fromCenter(center: rotationHandle, width: 20, height: 20);
        if (rotationRect.contains(standardOffset)) {
          setState(() {
            _interactionMode = CanvasInteractionMode.rotatingImage;
            _resizingImage = selectedImage;
            _initialRotation = selectedImage.rotation;
            _rotationStartPoint = standardOffset;
          });
          return;
        }
      }

      // Check for image selection
      CanvasImage? clickedImage;
      for (int i = widget.imageNotifier.value.length - 1; i >= 0; i--) {
        if (widget.imageNotifier.value[i].containsPoint(standardOffset)) {
          clickedImage = widget.imageNotifier.value[i];
          break;
        }
      }

      if (clickedImage != null) {
        if (_isCtrlPressed) {
          // Toggle selection
          widget.imageNotifier.toggleImageSelection(clickedImage.id);
        } else if (!widget.imageNotifier.selectedImageIds.contains(clickedImage.id)) {
          // Select only this image
          widget.imageNotifier.deselectAll();
          widget.imageNotifier.selectImage(clickedImage.id);
        }

        // Start dragging
        setState(() {
          _interactionMode = CanvasInteractionMode.draggingImage;
          _dragStartPoint = standardOffset;
          _initialImagePositions = {};
          for (final image in widget.imageNotifier.value) {
            if (widget.imageNotifier.selectedImageIds.contains(image.id)) {
              _initialImagePositions[image.id] = image.position;
            }
          }
        });
      } else {
        // Start selection rectangle
        if (!_isCtrlPressed) {
          widget.imageNotifier.deselectAll();
        }
        setState(() {
          _interactionMode = CanvasInteractionMode.selectingArea;
          _dragStartPoint = standardOffset;
          _selectionRect = Rect.fromPoints(standardOffset, standardOffset);
        });
      }
    } else {
      // Handle drawing tools
      setState(() {
        _interactionMode = CanvasInteractionMode.drawing;
      });
      _currentStroke.startStroke(
        standardOffset,
        color: strokeColor,
        size: size,
        opacity: opacity,
        type: currentTool.strokeType,
        sides: widget.options.polygonSides,
        filled: widget.options.fillShape,
      );
      widget.onDrawingStrokeChanged?.call(_currentStroke.value);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final offset = box.globalToLocal(event.position);
    final standardOffset = offset.scaleToStandard(box.size);

    switch (_interactionMode) {
      case CanvasInteractionMode.draggingImage:
        if (_dragStartPoint != null) {
          final delta = standardOffset - _dragStartPoint!;
          for (final entry in _initialImagePositions.entries) {
            final image = widget.imageNotifier.value.firstWhere((img) => img.id == entry.key);
            widget.imageNotifier.updateImagePosition(image, entry.value + delta);
          }
        }
        break;

      case CanvasInteractionMode.resizingImage:
        if (_resizingImage != null && _resizeHandle != null && _dragStartPoint != null) {
          _handleResize(standardOffset);
        }
        break;

      case CanvasInteractionMode.rotatingImage:
        if (_resizingImage != null && _rotationStartPoint != null) {
          final center = _resizingImage!.center;
          final startAngle = math.atan2(
            _rotationStartPoint!.dy - center.dy,
            _rotationStartPoint!.dx - center.dx,
          );
          final currentAngle = math.atan2(
            standardOffset.dy - center.dy,
            standardOffset.dx - center.dx,
          );
          var rotation = _initialRotation! + (currentAngle - startAngle);

          // Snap to 45 degree increments if Alt is pressed
          if (_isAltPressed) {
            final snapAngle = math.pi / 4; // 45 degrees
            rotation = (rotation / snapAngle).round() * snapAngle;
          }

          widget.imageNotifier.updateImageRotation(_resizingImage!, rotation);
        }
        break;

      case CanvasInteractionMode.selectingArea:
        if (_dragStartPoint != null) {
          setState(() {
            _selectionRect = Rect.fromPoints(_dragStartPoint!, standardOffset);
          });
          widget.imageNotifier.selectImagesInRect(_selectionRect!);
        }
        break;

      case CanvasInteractionMode.drawing:
        _currentStroke.addPoint(standardOffset);
        widget.onDrawingStrokeChanged?.call(_currentStroke.value);
        break;

      case CanvasInteractionMode.none:
        break;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_interactionMode == CanvasInteractionMode.drawing && _currentStroke.hasStroke) {
      _strokes.value = List<Stroke>.from(_strokes.value)..add(_currentStroke.value!);
      _currentStroke.clear();
      widget.onDrawingStrokeChanged?.call(null);
    }

    setState(() {
      _interactionMode = CanvasInteractionMode.none;
      _dragStartPoint = null;
      _initialImagePositions.clear();
      _resizeHandle = null;
      _resizingImage = null;
      _initialImageSize = null;
      _initialImagePosition = null;
      _initialRotation = null;
      _rotationStartPoint = null;
      _selectionRect = null;
    });
  }

  void _handleResize(Offset currentPoint) {
    if (_resizingImage == null || _initialImageSize == null || _dragStartPoint == null) return;

    final delta = currentPoint - _dragStartPoint!;
    final image = _resizingImage!;
    final aspectRatio = _initialImageSize!.width / _initialImageSize!.height;

    Size newSize = _initialImageSize!;
    Offset newPosition = _initialImagePosition ?? image.position;

    // Apply rotation to delta for accurate resizing
    final cos = math.cos(-image.rotation);
    final sin = math.sin(-image.rotation);
    final rotatedDelta = Offset(
      delta.dx * cos - delta.dy * sin,
      delta.dx * sin + delta.dy * cos,
    );

    switch (_resizeHandle) {
      case 'br': // Bottom right
        newSize = Size(
          (_initialImageSize!.width + rotatedDelta.dx).clamp(20, double.infinity),
          (_initialImageSize!.height + rotatedDelta.dy).clamp(20, double.infinity),
        );
        break;

      case 'tl': // Top left
        newSize = Size(
          (_initialImageSize!.width - rotatedDelta.dx).clamp(20, double.infinity),
          (_initialImageSize!.height - rotatedDelta.dy).clamp(20, double.infinity),
        );
        newPosition = _initialImagePosition! + Offset(
          _initialImageSize!.width - newSize.width,
          _initialImageSize!.height - newSize.height,
        );
        break;

      case 'tr': // Top right
        newSize = Size(
          (_initialImageSize!.width + rotatedDelta.dx).clamp(20, double.infinity),
          (_initialImageSize!.height - rotatedDelta.dy).clamp(20, double.infinity),
        );
        newPosition = _initialImagePosition! + Offset(
          0,
          _initialImageSize!.height - newSize.height,
        );
        break;

      case 'bl': // Bottom left
        newSize = Size(
          (_initialImageSize!.width - rotatedDelta.dx).clamp(20, double.infinity),
          (_initialImageSize!.height + rotatedDelta.dy).clamp(20, double.infinity),
        );
        newPosition = _initialImagePosition! + Offset(
          _initialImageSize!.width - newSize.width,
          0,
        );
        break;

      case 'tm': // Top middle
        newSize = Size(
          _initialImageSize!.width,
          (_initialImageSize!.height - rotatedDelta.dy).clamp(20, double.infinity),
        );
        newPosition = _initialImagePosition! + Offset(
          0,
          _initialImageSize!.height - newSize.height,
        );
        break;

      case 'bm': // Bottom middle
        newSize = Size(
          _initialImageSize!.width,
          (_initialImageSize!.height + rotatedDelta.dy).clamp(20, double.infinity),
        );
        break;

      case 'ml': // Middle left
        newSize = Size(
          (_initialImageSize!.width - rotatedDelta.dx).clamp(20, double.infinity),
          _initialImageSize!.height,
        );
        newPosition = _initialImagePosition! + Offset(
          _initialImageSize!.width - newSize.width,
          0,
        );
        break;

      case 'mr': // Middle right
        newSize = Size(
          (_initialImageSize!.width + rotatedDelta.dx).clamp(20, double.infinity),
          _initialImageSize!.height,
        );
        break;
    }

    // Maintain aspect ratio if Shift is pressed
    if (_isShiftPressed) {
      if (newSize.width / newSize.height > aspectRatio) {
        newSize = Size(newSize.width, newSize.width / aspectRatio);
      } else {
        newSize = Size(newSize.height * aspectRatio, newSize.height);
      }

      // Adjust position for corner handles when maintaining aspect ratio
      if (_resizeHandle == 'tl') {
        newPosition = _initialImagePosition! + Offset(
          _initialImageSize!.width - newSize.width,
          _initialImageSize!.height - newSize.height,
        );
      } else if (_resizeHandle == 'tr') {
        newPosition = _initialImagePosition! + Offset(
          0,
          _initialImageSize!.height - newSize.height,
        );
      } else if (_resizeHandle == 'bl') {
        newPosition = _initialImagePosition! + Offset(
          _initialImageSize!.width - newSize.width,
          0,
        );
      }
    }

    widget.imageNotifier.updateImage(
      image,
      image.copyWith(position: newPosition, size: newSize),
    );
  }

  @override
  Widget build(BuildContext context) {
    _showGrid.value = widget.options.showGrid;

    return MouseRegion(
      cursor: _getCursor(),
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        child: RepaintBoundary(
          key: widget.canvasKey,
          child: CustomPaint(
            size: Size.infinite,
            painter: _DrawingCanvasPainter(
              strokesListenable: _strokes,
              currentStrokeListenable: _currentStroke,
              backgroundColor: widget.options.backgroundColor,
              showGridListenable: _showGrid,
              backgroundImageListenable: widget.backgroundImageListenable,
              imageListenable: widget.imageNotifier,
              selectedImageIds: widget.imageNotifier.selectedImageIds,
              selectionRect: _selectionRect,
            ),
          ),
        ),
      ),
    );
  }

  MouseCursor _getCursor() {
    if (currentTool != DrawingTool.pointer) {
      return currentTool.cursor;
    }

    switch (_interactionMode) {
      case CanvasInteractionMode.resizingImage:
        switch (_resizeHandle) {
          case 'tl':
          case 'br':
            return SystemMouseCursors.resizeUpLeftDownRight;
          case 'tr':
          case 'bl':
            return SystemMouseCursors.resizeUpRightDownLeft;
          case 'tm':
          case 'bm':
            return SystemMouseCursors.resizeUpDown;
          case 'ml':
          case 'mr':
            return SystemMouseCursors.resizeLeftRight;
          default:
            return SystemMouseCursors.resizeUpDown;
        }
      case CanvasInteractionMode.rotatingImage:
        return SystemMouseCursors.click;
      case CanvasInteractionMode.draggingImage:
        return SystemMouseCursors.move;
      case CanvasInteractionMode.selectingArea:
        return SystemMouseCursors.cell;
      default:
        return SystemMouseCursors.basic;
    }
  }
}

class _DrawingCanvasPainter extends CustomPainter {
  final ValueNotifier<List<Stroke>>? strokesListenable;
  final CurrentStrokeValueNotifier? currentStrokeListenable;
  final Color backgroundColor;
  final ValueNotifier<bool>? showGridListenable;
  final ValueNotifier<ui.Image?>? backgroundImageListenable;
  final ImageNotifier imageListenable;
  final Set<String> selectedImageIds;
  final Rect? selectionRect;

  _DrawingCanvasPainter({
    this.strokesListenable,
    this.currentStrokeListenable,
    this.backgroundColor = Colors.white,
    this.showGridListenable,
    this.backgroundImageListenable,
    required this.imageListenable,
    required this.selectedImageIds,
    this.selectionRect,
  }) : super(
    repaint: Listenable.merge([
      strokesListenable,
      currentStrokeListenable,
      showGridListenable,
      backgroundImageListenable,
      imageListenable,
    ]),
  );

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw background color
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    // 2. Draw background image if exists
    if (backgroundImageListenable != null) {
      final backgroundImage = backgroundImageListenable!.value;
      if (backgroundImage != null) {
        canvas.drawImageRect(
          backgroundImage,
          Rect.fromLTWH(0, 0, backgroundImage.width.toDouble(), backgroundImage.height.toDouble()),
          Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..filterQuality = FilterQuality.high,
        );
      }
    }

    // 3. Draw all completed strokes
    final strokes = strokesListenable?.value ?? [];
    for (final stroke in strokes) {
      _drawStroke(canvas, size, stroke);
    }

    // 4. Draw current stroke if any
    if (currentStrokeListenable?.hasStroke ?? false) {
      _drawStroke(canvas, size, currentStrokeListenable!.value!);
    }

    // 5. Draw images
    final images = imageListenable.value;
    for (final image in images) {
      _drawImage(canvas, size, image, selectedImageIds.contains(image.id));
    }

    // 6. Draw selection rectangle
    if (selectionRect != null) {
      _drawSelectionRect(canvas, size, selectionRect!);
    }

    // 7. Draw grid on top if enabled
    if (showGridListenable?.value ?? false) {
      _drawGrid(size, canvas);
    }
  }

  void _drawImage(Canvas canvas, Size canvasSize, CanvasImage image, bool isSelected) {
    canvas.save();

    // Convert from standard coordinates to canvas coordinates
    final scaledPosition = image.position.scaleFromStandard(canvasSize);
    final scaledSize = Size(
      image.size.width * canvasSize.width / OffsetExtensions.standardWidth,
      image.size.height * canvasSize.height / OffsetExtensions.standardHeight,
    );
    final scaledBounds = Rect.fromLTWH(
      scaledPosition.dx,
      scaledPosition.dy,
      scaledSize.width,
      scaledSize.height,
    );
    final scaledCenter = scaledBounds.center;

    // Apply rotation if needed
    if (image.rotation != 0) {
      canvas.translate(scaledCenter.dx, scaledCenter.dy);
      canvas.rotate(image.rotation);
      canvas.translate(-scaledCenter.dx, -scaledCenter.dy);
    }

    // Draw shadow for selected images
    if (isSelected) {
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRect(scaledBounds.shift(const Offset(2, 2)), shadowPaint);
    }

    // Draw the image with high quality
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    canvas.drawImageRect(
      image.image,
      Rect.fromLTWH(0, 0, image.image.width.toDouble(), image.image.height.toDouble()),
      scaledBounds,
      paint,
    );

    // Draw selection indicators if selected
    if (isSelected) {
      _drawImageSelectionIndicators(canvas, canvasSize, image, scaledBounds);
    }

    canvas.restore();
  }

  void _drawImageSelectionIndicators(Canvas canvas, Size canvasSize, CanvasImage image, Rect bounds) {
    // Draw border
    final borderPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawRect(bounds, borderPaint);

    // Only draw detailed controls for single selection
    if (selectedImageIds.length == 1) {
      // Draw resize handles
      const handleRadius = 4.0;
      final handlePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      final handleBorderPaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      // Get handle positions and scale them to canvas coordinates
      final standardHandles = image.getResizeHandles();
      final handles = <String, Offset>{};

      standardHandles.forEach((key, standardOffset) {
        handles[key] = standardOffset.scaleFromStandard(canvasSize);
      });

      // Draw corner and edge handles
      handles.forEach((key, position) {
        canvas.drawCircle(position, handleRadius, handlePaint);
        canvas.drawCircle(position, handleRadius, handleBorderPaint);
      });

      // Draw rotation handle
      final standardRotationHandle = image.getRotationHandle();
      final rotationHandlePos = standardRotationHandle.scaleFromStandard(canvasSize);

      // Draw rotation line
      canvas.drawLine(
        handles['tm'] ?? bounds.topCenter,
        rotationHandlePos + const Offset(0, 8),
        Paint()
          ..color = Colors.blue
          ..strokeWidth = 1.0
      );

      // Draw rotation handle circle
      final rotationHandlePath = Path()
        ..addOval(Rect.fromCircle(center: rotationHandlePos, radius: 8));

      canvas.drawPath(rotationHandlePath, handlePaint);
      canvas.drawPath(rotationHandlePath, handleBorderPaint);

      // Draw rotation icon
      final rotationIcon = Icons.rotate_right;
      final textPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(rotationIcon.codePoint),
          style: TextStyle(
            fontSize: 12,
            fontFamily: rotationIcon.fontFamily,
            color: Colors.blue,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        rotationHandlePos - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    } else if (selectedImageIds.length > 1) {
      // For multiple selection, just show a simple border
      final multiSelectPaint = Paint()
        ..color = Colors.blue.withOpacity(0.5)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      canvas.drawRect(bounds, multiSelectPaint);
    }
  }

  void _drawSelectionRect(Canvas canvas, Size canvasSize, Rect standardRect) {
    final topLeft = Offset(standardRect.left, standardRect.top).scaleFromStandard(canvasSize);
    final bottomRight = Offset(standardRect.right, standardRect.bottom).scaleFromStandard(canvasSize);

    final scaledRect = Rect.fromLTRB(
      topLeft.dx,
      topLeft.dy,
      bottomRight.dx,
      bottomRight.dy,
    );

    // Fill
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    canvas.drawRect(scaledRect, paint);

    // Border
    final borderPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw border (for true dashed effect, you would need a custom implementation)
    canvas.drawRect(scaledRect, borderPaint);

    // Draw corner handles
    const cornerSize = 6.0;
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final corners = [
      scaledRect.topLeft,
      scaledRect.topRight,
      scaledRect.bottomLeft,
      scaledRect.bottomRight,
    ];

    for (final corner in corners) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: cornerSize, height: cornerSize),
        cornerPaint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: cornerSize, height: cornerSize),
        borderPaint,
      );
    }
  }

  void _drawStroke(Canvas canvas, Size size, Stroke stroke) {
    final points = stroke.points;
    if (points.isEmpty) return;

    final strokeSize = math.max(stroke.size, 1.0);
    final paint = Paint()
      ..color = stroke.color.withOpacity(stroke.opacity)
      ..strokeWidth = strokeSize
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

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
    } else if (stroke is LineStroke) {
      final firstPoint = points.first.scaleFromStandard(size);
      final lastPoint = points.last.scaleFromStandard(size);
      canvas.drawLine(firstPoint, lastPoint, paint);
    } else if (stroke is CircleStroke) {
      final firstPoint = points.first.scaleFromStandard(size);
      final lastPoint = points.last.scaleFromStandard(size);
      final rect = Rect.fromPoints(firstPoint, lastPoint);
      if (stroke.filled) paint.style = PaintingStyle.fill;
      canvas.drawOval(rect, paint);
    } else if (stroke is SquareStroke) {
      final firstPoint = points.first.scaleFromStandard(size);
      final lastPoint = points.last.scaleFromStandard(size);
      final rect = Rect.fromPoints(firstPoint, lastPoint);
      if (stroke.filled) paint.style = PaintingStyle.fill;
      canvas.drawRect(rect, paint);
    } else if (stroke is PolygonStroke) {
      _drawPolygon(canvas, size, stroke, paint);
    }
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
    final radius = (firstPoint - lastPoint).distance / 2;

    final path = Path();
    const startAngle = -math.pi / 2;
    final angleStep = (2 * math.pi) / stroke.sides;

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

  Path _getStrokePath(Stroke stroke, Size size) {
    final path = Path();
    final points = stroke.points;

    if (points.isNotEmpty) {
      final firstPoint = points.first.scaleFromStandard(size);
      path.moveTo(firstPoint.dx, firstPoint.dy);

      if (points.length == 2) {
        final lastPoint = points.last.scaleFromStandard(size);
        path.lineTo(lastPoint.dx, lastPoint.dy);
      } else {
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

        if (points.length > 2) {
          final lastPoint = points.last.scaleFromStandard(size);
          path.lineTo(lastPoint.dx, lastPoint.dy);
        }
      }
    }

    return path;
  }

  void _drawGrid(Size size, Canvas canvas) {
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
  bool shouldRepaint(covariant _DrawingCanvasPainter oldDelegate) {
    return oldDelegate.selectedImageIds != selectedImageIds ||
        oldDelegate.selectionRect != selectionRect;
  }
}

// Extension to add dash pattern support (simplified version)
extension DashPath on Path {
  Path dashPath(List<double> pattern) {
    // This is a simplified version
    // For full implementation, you'd need to calculate dashes along the path
    return this;
  }
}