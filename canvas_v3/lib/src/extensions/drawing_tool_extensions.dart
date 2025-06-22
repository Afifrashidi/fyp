// lib/src/extensions/drawing_tool_extensions.dart
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/src.dart';

extension DrawingToolExtensions on DrawingTool {
  StrokeType get strokeType {
    switch (this) {
      case DrawingTool.pencil:
        return StrokeType.normal;
      case DrawingTool.fill:
        return StrokeType.normal;
      case DrawingTool.eraser:
        return StrokeType.eraser;
      case DrawingTool.line:
        return StrokeType.line;
      case DrawingTool.polygon:
        return StrokeType.polygon;
      case DrawingTool.square:
        return StrokeType.square;
      case DrawingTool.circle:
        return StrokeType.circle;
      case DrawingTool.pointer:
        return StrokeType.normal; // Pointer doesn't draw
      case DrawingTool.rectangle:
        return StrokeType.rectangle;
      case DrawingTool.text:
        return StrokeType.text;
      case DrawingTool.selector:
        return StrokeType.normal; // Selector doesn't draw, just selects
    }
  }

  MouseCursor get cursor {
    switch (this) {
      case DrawingTool.pencil:
      case DrawingTool.line:
      case DrawingTool.polygon:
      case DrawingTool.square:
      case DrawingTool.circle:
      case DrawingTool.eraser:
        return SystemMouseCursors.precise;
      case DrawingTool.fill:
        return SystemMouseCursors.click;
      case DrawingTool.pointer:
        return SystemMouseCursors.move;
      case DrawingTool.rectangle:
        return SystemMouseCursors.precise;
      case DrawingTool.text:
        return SystemMouseCursors.text;
      case DrawingTool.selector:
        return SystemMouseCursors.click;
    }
  }
}