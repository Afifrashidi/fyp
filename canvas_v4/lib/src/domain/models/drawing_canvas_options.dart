// lib/src/domain/models/drawing_canvas_options.dart

import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/canvas_operations_enums.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';

/// Configuration options for the drawing canvas
class DrawingCanvasOptions {
  final DrawingTool currentTool;
  final double size;
  final Color strokeColor;
  final Color backgroundColor;
  final double opacity;
  final int polygonSides;
  final bool showGrid;
  final bool snapToGrid;
  final bool fillShape;

  const DrawingCanvasOptions({
    this.currentTool = DrawingTool.pencil,
    this.size = AppConstants.defaultStrokeSize,
    this.strokeColor = Colors.black,
    this.backgroundColor = AppColors.canvasBackground,
    this.opacity = AppConstants.defaultOpacity,
    this.polygonSides = AppConstants.defaultPolygonSides,
    this.showGrid = false,
    this.snapToGrid = false,
    this.fillShape = false,
  });

  DrawingCanvasOptions copyWith({
    DrawingTool? currentTool,
    double? size,
    Color? strokeColor,
    Color? backgroundColor,
    double? opacity,
    int? polygonSides,
    bool? showGrid,
    bool? snapToGrid,
    bool? fillShape,
  }) {
    return DrawingCanvasOptions(
      currentTool: currentTool ?? this.currentTool,
      size: size ?? this.size,
      strokeColor: strokeColor ?? this.strokeColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      opacity: opacity ?? this.opacity,
      polygonSides: polygonSides ?? this.polygonSides,
      showGrid: showGrid ?? this.showGrid,
      snapToGrid: snapToGrid ?? this.snapToGrid,
      fillShape: fillShape ?? this.fillShape,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currentTool': currentTool.toString(),
      'size': size,
      'strokeColor': strokeColor.value,
      'backgroundColor': backgroundColor.value,
      'opacity': opacity,
      'polygonSides': polygonSides,
      'showGrid': showGrid,
      'snapToGrid': snapToGrid,
      'fillShape': fillShape,
    };
  }

  factory DrawingCanvasOptions.fromJson(Map<String, dynamic> json) {
    return DrawingCanvasOptions(
      currentTool: _parseDrawingTool(json['currentTool']),
      size: (json['size'] as num?)?.toDouble() ?? AppConstants.defaultStrokeSize,
      strokeColor: Color(json['strokeColor'] as int? ?? Colors.black.value),
      backgroundColor: Color(json['backgroundColor'] as int? ?? AppColors.canvasBackground.value),
      opacity: (json['opacity'] as num?)?.toDouble() ?? AppConstants.defaultOpacity,
      polygonSides: json['polygonSides'] as int? ?? AppConstants.defaultPolygonSides,
      showGrid: json['showGrid'] as bool? ?? false,
      snapToGrid: json['snapToGrid'] as bool? ?? false,
      fillShape: json['fillShape'] as bool? ?? false,
    );
  }

  static DrawingTool _parseDrawingTool(dynamic toolString) {
    if (toolString == null) return DrawingTool.pencil;

    final toolName = toolString.toString().split('.').last;
    return DrawingTool.values.firstWhere(
          (tool) => tool.toString().split('.').last == toolName,
      orElse: () => DrawingTool.pencil,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DrawingCanvasOptions &&
        other.currentTool == currentTool &&
        other.size == size &&
        other.strokeColor == strokeColor &&
        other.backgroundColor == backgroundColor &&
        other.opacity == opacity &&
        other.polygonSides == polygonSides &&
        other.showGrid == showGrid &&
        other.snapToGrid == snapToGrid &&
        other.fillShape == fillShape;
  }

  @override
  int get hashCode {
    return Object.hash(
      currentTool,
      size,
      strokeColor,
      backgroundColor,
      opacity,
      polygonSides,
      showGrid,
      snapToGrid,
      fillShape,
    );
  }

  @override
  String toString() {
    return 'DrawingCanvasOptions('
        'currentTool: $currentTool, '
        'size: $size, '
        'strokeColor: $strokeColor, '
        'backgroundColor: $backgroundColor, '
        'opacity: $opacity, '
        'polygonSides: $polygonSides, '
        'showGrid: $showGrid, '
        'snapToGrid: $snapToGrid, '
        'fillShape: $fillShape'
        ')';
  }
}