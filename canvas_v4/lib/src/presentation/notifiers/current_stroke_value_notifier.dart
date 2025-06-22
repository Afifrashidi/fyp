import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/canvas_operations_enums.dart';
import 'package:flutter_drawing_board/src/domain/domain.dart';
import 'package:flutter_drawing_board/src/src.dart';

class CurrentStrokeValueNotifier extends ValueNotifier<Stroke?> {
  CurrentStrokeValueNotifier() : super(null);

  bool get hasStroke => value != null;

  void startStroke(
      Offset point, {
        Color color = Colors.blueAccent,
        double size = 10,
        double opacity = 1,
        StrokeType type = StrokeType.normal,
        int? sides,
        bool? filled,
      }) {
    // Ensure minimum stroke size to prevent invisible strokes
    final effectiveSize = size <= 0 ? 1.0 : size;

    value = () {
      switch (type) {
        case StrokeType.eraser:
          return EraserStroke(
            points: [point],
            color: color,
            size: effectiveSize,
            opacity: opacity,
          );

        case StrokeType.line:
          return LineStroke(
            points: [point],
            color: color,
            size: effectiveSize,
            opacity: opacity,
          );

        case StrokeType.polygon:
          return PolygonStroke(
            points: [point],
            color: color,
            size: effectiveSize,
            opacity: opacity,
            sides: sides ?? 3,
            filled: filled ?? false,
          );

        case StrokeType.circle:
          return CircleStroke(
            points: [point],
            color: color,
            size: effectiveSize,
            opacity: opacity,
            filled: filled ?? false,
          );

        case StrokeType.square:
          return SquareStroke(
            points: [point],
            color: color,
            size: effectiveSize,
            opacity: opacity,
            filled: filled ?? false,
          );

        case StrokeType.rectangle:
          return RectangleStroke(
            points: [point],
            color: color,
            size: effectiveSize,
            opacity: opacity,
            filled: filled ?? false,
          );

        case StrokeType.text:
          return TextStroke(
            points: [point],
            text: '', // Will be set later when user types
            fontSize: effectiveSize * 2, // Scale font size based on stroke size
            fontFamily: 'Inter',
            color: color,
            size: effectiveSize,
            opacity: opacity,
          );

        case StrokeType.normal:
        default:
          return NormalStroke(
            points: [point],
            color: color,
            size: effectiveSize,
            opacity: opacity,
          );
      }
    }();
  }

  void addPoint(Offset point) {
    final currentStroke = value;
    if (currentStroke == null) return;

    // For text strokes, don't add additional points
    if (currentStroke is TextStroke) return;

    final points = List<Offset>.from(currentStroke.points)..add(point);
    value = currentStroke.copyWith(points: points);
  }

  void updateText(String text) {
    final currentStroke = value;
    if (currentStroke is TextStroke) {
      value = currentStroke.copyWith(text: text);
    }
  }

  void clear() {
    value = null;
  }
}