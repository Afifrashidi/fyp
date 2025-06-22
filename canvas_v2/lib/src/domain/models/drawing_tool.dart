// lib/src/domain/models/drawing_tool.dart
enum DrawingTool {
  pencil,
  fill,
  line,
  eraser,
  polygon,
  square,
  circle,
  pointer;

  bool get isEraser => this == DrawingTool.eraser;
  bool get isLine => this == DrawingTool.line;
  bool get isFill => this == DrawingTool.fill;
  bool get isPencil => this == DrawingTool.pencil;
  bool get isPolygon => this == DrawingTool.polygon;
  bool get isSquare => this == DrawingTool.square;
  bool get isCircle => this == DrawingTool.circle;
  bool get isPointer => this == DrawingTool.pointer;
}