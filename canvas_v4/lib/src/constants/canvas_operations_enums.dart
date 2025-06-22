// lib/src/constants/canvas_operations_enums.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Drawing tools available in the canvas
enum DrawingTool {
  pencil,
  fill,
  line,
  eraser,
  polygon,
  square,
  circle,
  imageManipulator, // Unified image selection, move, scale, rotate tool
  rectangle,
  text;

  bool get isEraser => this == DrawingTool.eraser;
  bool get isLine => this == DrawingTool.line;
  bool get isFill => this == DrawingTool.fill;
  bool get isPencil => this == DrawingTool.pencil;
  bool get isPolygon => this == DrawingTool.polygon;
  bool get isSquare => this == DrawingTool.square;
  bool get isCircle => this == DrawingTool.circle;
  bool get isImageManipulator => this == DrawingTool.imageManipulator;
}

/// Types of strokes that can be drawn
enum StrokeType {
  normal,
  eraser,
  line,
  polygon,
  square,
  circle,
  rectangle,
  text;

  static StrokeType fromString(String value) {
    switch (value) {
      case 'normal': return StrokeType.normal;
      case 'eraser': return StrokeType.eraser;
      case 'line': return StrokeType.line;
      case 'polygon': return StrokeType.polygon;
      case 'square': return StrokeType.square;
      case 'circle': return StrokeType.circle;
      case 'rectangle': return StrokeType.rectangle;
      case 'text': return StrokeType.text;
      default: return StrokeType.normal;
    }
  }

  @override
  String toString() {
    switch (this) {
      case StrokeType.normal: return 'normal';
      case StrokeType.eraser: return 'eraser';
      case StrokeType.line: return 'line';
      case StrokeType.polygon: return 'polygon';
      case StrokeType.square: return 'square';
      case StrokeType.circle: return 'circle';
      case StrokeType.rectangle: return 'rectangle';
      case StrokeType.text: return 'text';
    }
  }
}

/// Legacy tool type enum (kept for backward compatibility)
@Deprecated('Use DrawingTool instead')
enum ToolType {
  pencil,
  stamp,
  spray,
  fill,
  line,
  eraser,
  ruler;

  @override
  String toString() => name;
}

/// Canvas operation modes
enum CanvasMode {
  drawing,
  selection,
  panning,
  zooming;

  bool get isInteractive => this != CanvasMode.drawing;
}

/// Canvas grid types
enum GridType {
  none,
  dots,
  lines,
  squares;

  String get displayName {
    switch (this) {
      case GridType.none: return 'No Grid';
      case GridType.dots: return 'Dot Grid';
      case GridType.lines: return 'Line Grid';
      case GridType.squares: return 'Square Grid';
    }
  }
}

/// Canvas background types
enum BackgroundType {
  solid,
  gradient,
  image,
  pattern;

  String get displayName {
    switch (this) {
      case BackgroundType.solid: return 'Solid Color';
      case BackgroundType.gradient: return 'Gradient';
      case BackgroundType.image: return 'Image';
      case BackgroundType.pattern: return 'Pattern';
    }
  }
}

/// Export formats supported by the canvas
enum ExportFormat {
  png,
  jpg,
  svg,
  pdf;

  String get extension {
    switch (this) {
      case ExportFormat.png: return 'png';
      case ExportFormat.jpg: return 'jpg';
      case ExportFormat.svg: return 'svg';
      case ExportFormat.pdf: return 'pdf';
    }
  }

  String get mimeType {
    switch (this) {
      case ExportFormat.png: return 'image/png';
      case ExportFormat.jpg: return 'image/jpeg';
      case ExportFormat.svg: return 'image/svg+xml';
      case ExportFormat.pdf: return 'application/pdf';
    }
  }

  String get displayName {
    switch (this) {
      case ExportFormat.png: return 'PNG Image';
      case ExportFormat.jpg: return 'JPEG Image';
      case ExportFormat.svg: return 'SVG Vector';
      case ExportFormat.pdf: return 'PDF Document';
    }
  }
}

/// Blend modes for drawing operations
enum BlendMode {
  normal,
  multiply,
  screen,
  overlay,
  softLight,
  hardLight,
  colorDodge,
  colorBurn,
  darken,
  lighten,
  difference,
  exclusion;

  String get displayName {
    switch (this) {
      case BlendMode.normal: return 'Normal';
      case BlendMode.multiply: return 'Multiply';
      case BlendMode.screen: return 'Screen';
      case BlendMode.overlay: return 'Overlay';
      case BlendMode.softLight: return 'Soft Light';
      case BlendMode.hardLight: return 'Hard Light';
      case BlendMode.colorDodge: return 'Color Dodge';
      case BlendMode.colorBurn: return 'Color Burn';
      case BlendMode.darken: return 'Darken';
      case BlendMode.lighten: return 'Lighten';
      case BlendMode.difference: return 'Difference';
      case BlendMode.exclusion: return 'Exclusion';
    }
  }
}