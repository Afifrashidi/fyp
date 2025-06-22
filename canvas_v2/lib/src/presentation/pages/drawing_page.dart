// lib/src/presentation/pages/drawing_page.dart
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/src.dart';

class DrawingPage extends StatefulWidget {
  const DrawingPage({super.key});

  @override
  State<DrawingPage> createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController animationController;
  final ValueNotifier<Color> selectedColor = ValueNotifier(Colors.black);
  final ValueNotifier<double> strokeSize = ValueNotifier(10.0);
  final ValueNotifier<double> eraserSize = ValueNotifier(30.0);
  final ValueNotifier<DrawingTool> drawingTool = ValueNotifier(DrawingTool.pencil);
  final GlobalKey canvasGlobalKey = GlobalKey();
  final ValueNotifier<bool> filled = ValueNotifier(false);
  final ValueNotifier<int> polygonSides = ValueNotifier(3);
  final ValueNotifier<ui.Image?> backgroundImage = ValueNotifier(null);
  final CurrentStrokeValueNotifier currentStroke = CurrentStrokeValueNotifier();
  final ValueNotifier<List<Stroke>> allStrokes = ValueNotifier([]);
  late final UndoRedoStack undoRedoStack;
  final ValueNotifier<bool> showGrid = ValueNotifier(false);
  final ImageNotifier imageNotifier = ImageNotifier();

  @override
  void initState() {
    super.initState();
    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    undoRedoStack = UndoRedoStack(
      currentStrokeNotifier: currentStroke,
      strokesNotifier: allStrokes,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvasColor,
      body: HotkeyListener(
        onRedo: undoRedoStack.redo,
        onUndo: undoRedoStack.undo,
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([
                currentStroke,
                allStrokes,
                selectedColor,
                strokeSize,
                eraserSize,
                drawingTool,
                filled,
                polygonSides,
                backgroundImage,
                showGrid,
                imageNotifier,
              ]),
              builder: (context, _) {
                return DrawingCanvas(
                  options: DrawingCanvasOptions(
                    currentTool: drawingTool.value,
                    size: strokeSize.value,
                    strokeColor: selectedColor.value,
                    backgroundColor: kCanvasColor,
                    polygonSides: polygonSides.value,
                    showGrid: showGrid.value,
                    fillShape: filled.value,
                  ),
                  canvasKey: canvasGlobalKey,
                  currentStrokeListenable: currentStroke,
                  strokesListenable: allStrokes,
                  backgroundImageListenable: backgroundImage,
                  imageNotifier: imageNotifier,
                );
              },
            ),
            Positioned(
              top: kToolbarHeight + 10,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(-1, 0),
                  end: Offset.zero,
                ).animate(animationController),
                child: CanvasSideBar(
                  drawingTool: drawingTool,
                  selectedColor: selectedColor,
                  strokeSize: strokeSize,
                  eraserSize: eraserSize,
                  currentSketch: currentStroke,
                  allSketches: allStrokes,
                  canvasGlobalKey: canvasGlobalKey,
                  filled: filled,
                  polygonSides: polygonSides,
                  backgroundImage: backgroundImage,
                  undoRedoStack: undoRedoStack,
                  showGrid: showGrid,
                  imageNotifier: imageNotifier,
                ),
              ),
            ),
            _CustomAppBar(animationController: animationController),
            // Quick access toolbar for image operations
            if (imageNotifier.hasSelection)
              Positioned(
                top: kToolbarHeight + 10,
                right: 10,
                child: _QuickImageToolbar(
                  imageNotifier: imageNotifier,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    animationController.dispose();
    selectedColor.dispose();
    strokeSize.dispose();
    eraserSize.dispose();
    drawingTool.dispose();
    currentStroke.dispose();
    allStrokes.dispose();
    undoRedoStack.dispose();
    filled.dispose();
    polygonSides.dispose();
    backgroundImage.dispose();
    showGrid.dispose();
    imageNotifier.dispose();
    super.dispose();
  }
}

class _CustomAppBar extends StatelessWidget {
  final AnimationController animationController;
  const _CustomAppBar({Key? key, required this.animationController})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kToolbarHeight,
      width: double.maxFinite,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () {
                if (animationController.value == 0) {
                  animationController.forward();
                } else {
                  animationController.reverse();
                }
              },
              icon: const Icon(Icons.menu),
            ),
            const Text(
              'Let\'s Draw',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
            ),
            const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

// Quick access toolbar for selected images
class _QuickImageToolbar extends StatelessWidget {
  final ImageNotifier imageNotifier;

  const _QuickImageToolbar({
    Key? key,
    required this.imageNotifier,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${imageNotifier.selectedImageIds.length} selected',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.rotate_left),
                  iconSize: 20,
                  onPressed: () => imageNotifier.rotateSelectedImages(-math.pi / 2),
                  tooltip: 'Rotate Left',
                ),
                IconButton(
                  icon: const Icon(Icons.rotate_right),
                  iconSize: 20,
                  onPressed: () => imageNotifier.rotateSelectedImages(math.pi / 2),
                  tooltip: 'Rotate Right',
                ),
                IconButton(
                  icon: const Icon(Icons.flip_to_front),
                  iconSize: 20,
                  onPressed: () => imageNotifier.bringSelectedToFront(),
                  tooltip: 'Bring to Front',
                ),
                IconButton(
                  icon: const Icon(Icons.flip_to_back),
                  iconSize: 20,
                  onPressed: () => imageNotifier.sendSelectedToBack(),
                  tooltip: 'Send to Back',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  iconSize: 20,
                  onPressed: () => imageNotifier.removeSelectedImages(),
                  tooltip: 'Delete',
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}