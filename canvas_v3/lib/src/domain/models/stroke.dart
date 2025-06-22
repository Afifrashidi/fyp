import 'package:flutter/material.dart';

abstract class Stroke {
  final List<Offset> points;
  final Color color;
  final double size;
  final double opacity;
  final StrokeType strokeType;
  final DateTime createdAt = DateTime.now();

  Stroke({
    required this.points,
    this.color = Colors.black,
    this.size = 1,
    this.opacity = 1,
    this.strokeType = StrokeType.normal,
  });

  Stroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
  });

  Map<String, dynamic> toJson();

  factory Stroke.fromJson(Map<String, dynamic> json) {
    final points = (json['points'] as List<dynamic>)
        .map(
          (point) =>
          Offset((point as List<dynamic>)[0] as double, point[1] as double),
    )
        .toList();
    final color = Color(json['color'] as int);
    final size = double.parse(json['size'].toString());
    final opacity = double.parse(json['opacity'].toString());
    final strokeType = StrokeType.fromString(json['strokeType'] as String);

    switch (strokeType) {
      case StrokeType.normal:
        return NormalStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
        );
      case StrokeType.eraser:
        return EraserStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
        );
      case StrokeType.line:
        return LineStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
        );
      case StrokeType.polygon:
        return PolygonStroke(
          points: points,
          sides: (json['sides'] as int?) ?? 3,
          color: color,
          size: size,
          opacity: opacity,
          filled: (json['filled'] as bool?) ?? false,
        );
      case StrokeType.circle:
        return CircleStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
          filled: (json['filled'] as bool?) ?? false,
        );
      case StrokeType.square:
        return SquareStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
          filled: (json['filled'] as bool?) ?? false,
        );
      case StrokeType.rectangle:
        return RectangleStroke(
          points: points,
          color: color,
          size: size,
          opacity: opacity,
          filled: (json['filled'] as bool?) ?? false,
        );
      case StrokeType.text:
        return TextStroke(
          points: points,
          text: (json['text'] as String?) ?? '',
          fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16.0,
          fontFamily: json['fontFamily'] as String?,
          color: color,
          size: size,
          opacity: opacity,
        );
    }
  }

  bool get isEraser => strokeType == StrokeType.eraser;
  bool get isLine => strokeType == StrokeType.line;
  bool get isNormal => strokeType == StrokeType.normal;
}

class NormalStroke extends Stroke {
  NormalStroke({
    required super.points,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.normal);

  @override
  NormalStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
  }) {
    return NormalStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((point) => [point.dx, point.dy]).toList(),
      'color': color.value,
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
    };
  }
}

class EraserStroke extends Stroke {
  EraserStroke({
    required super.points,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.eraser);

  @override
  EraserStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
  }) {
    return EraserStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((point) => [point.dx, point.dy]).toList(),
      'color': color.value,
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
    };
  }
}

class LineStroke extends Stroke {
  LineStroke({
    required super.points,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.line);

  @override
  LineStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
  }) {
    return LineStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((point) => [point.dx, point.dy]).toList(),
      'color': color.value,
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
    };
  }
}

class PolygonStroke extends Stroke {
  final int sides;
  final bool filled;

  PolygonStroke({
    required super.points,
    required this.sides,
    this.filled = false,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.polygon);

  @override
  PolygonStroke copyWith({
    List<Offset>? points,
    int? sides,
    Color? color,
    double? size,
    double? opacity,
    bool? filled,
  }) {
    return PolygonStroke(
      points: points ?? this.points,
      sides: sides ?? this.sides,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      filled: filled ?? this.filled,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((point) => [point.dx, point.dy]).toList(),
      'sides': sides,
      'filled': filled,
      'color': color.value,
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
    };
  }
}

class CircleStroke extends Stroke {
  final bool filled;

  CircleStroke({
    required super.points,
    this.filled = false,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.circle);

  @override
  CircleStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
    bool? filled,
  }) {
    return CircleStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      filled: filled ?? this.filled,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((point) => [point.dx, point.dy]).toList(),
      'filled': filled,
      'color': color.value,
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
    };
  }
}

class SquareStroke extends Stroke {
  final bool filled;

  SquareStroke({
    required super.points,
    this.filled = false,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.square);

  @override
  SquareStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
    bool? filled,
  }) {
    return SquareStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      filled: filled ?? this.filled,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((point) => [point.dx, point.dy]).toList(),
      'filled': filled,
      'color': color.value,
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
    };
  }
}

class RectangleStroke extends Stroke {
  final bool filled;

  RectangleStroke({
    required super.points,
    this.filled = false,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.rectangle);

  @override
  RectangleStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? size,
    double? opacity,
    bool? filled,
  }) {
    return RectangleStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      filled: filled ?? this.filled,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((point) => [point.dx, point.dy]).toList(),
      'filled': filled,
      'color': color.value,
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
    };
  }
}

class TextStroke extends Stroke {
  final String text;
  final double fontSize;
  final String? fontFamily;

  TextStroke({
    required super.points,
    required this.text,
    this.fontSize = 16.0,
    this.fontFamily,
    super.color,
    super.size,
    super.opacity,
  }) : super(strokeType: StrokeType.text);

  @override
  TextStroke copyWith({
    List<Offset>? points,
    String? text,
    double? fontSize,
    String? fontFamily,
    Color? color,
    double? size,
    double? opacity,
  }) {
    return TextStroke(
      points: points ?? this.points,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((point) => [point.dx, point.dy]).toList(),
      'text': text,
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'color': color.value,
      'size': size,
      'opacity': opacity,
      'strokeType': strokeType.toString(),
    };
  }
}

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
      case 'normal':
        return StrokeType.normal;
      case 'eraser':
        return StrokeType.eraser;
      case 'line':
        return StrokeType.line;
      case 'polygon':
        return StrokeType.polygon;
      case 'square':
        return StrokeType.square;
      case 'circle':
        return StrokeType.circle;
      case 'rectangle':
        return StrokeType.rectangle;
      case 'text':
        return StrokeType.text;
      default:
        return StrokeType.normal;
    }
  }

  @override
  String toString() {
    switch (this) {
      case StrokeType.normal:
        return 'normal';
      case StrokeType.eraser:
        return 'eraser';
      case StrokeType.line:
        return 'line';
      case StrokeType.polygon:
        return 'polygon';
      case StrokeType.square:
        return 'square';
      case StrokeType.circle:
        return 'circle';
      case StrokeType.rectangle:
        return 'rectangle';
      case StrokeType.text:
        return 'text';
    }
  }
}