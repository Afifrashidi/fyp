import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_drawing_board/main.dart';
import 'package:flutter_drawing_board/src/src.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';

class CanvasSideBar extends StatefulWidget {
  final ValueNotifier<Color> selectedColor;
  final ValueNotifier<double> strokeSize;
  final ValueNotifier<double> eraserSize;
  final ValueNotifier<DrawingTool> drawingTool;
  final CurrentStrokeValueNotifier currentSketch;
  final ValueNotifier<List<Stroke>> allSketches;
  final GlobalKey canvasGlobalKey;
  final ValueNotifier<bool> filled;
  final ValueNotifier<int> polygonSides;
  final ValueNotifier<ui.Image?> backgroundImage;
  final UndoRedoStack undoRedoStack;
  final ValueNotifier<bool> showGrid;

  const CanvasSideBar({
    Key? key,
    required this.selectedColor,
    required this.strokeSize,
    required this.eraserSize,
    required this.drawingTool,
    required this.currentSketch,
    required this.allSketches,
    required this.canvasGlobalKey,
    required this.filled,
    required this.polygonSides,
    required this.backgroundImage,
    required this.undoRedoStack,
    required this.showGrid,
  }) : super(key: key);

  @override
  _CanvasSideBarState createState() => _CanvasSideBarState();
}

class _CanvasSideBarState extends State<CanvasSideBar> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Other buttons here

        // Add Image Button
        TextButton(
          onPressed: () async {
            final imagePicker = ImagePicker();
            final pickedFile = await imagePicker.pickImage(source: ImageSource.gallery);
            if (pickedFile != null) {
              final imageBytes = await pickedFile.readAsBytes();
              final codec = await ui.instantiateImageCodec(imageBytes);
              final frame = await codec.getNextFrame();
              final uiImage = frame.image;

              // Store the selected image in the state
              widget.backgroundImage.value = uiImage;

              // Optionally, store the image position for dragging
              widget.canvasGlobalKey.currentState?.setState(() {
                widget.canvasGlobalKey.currentState?.imagePosition = Offset(100, 100); // initial position (example)
              });
            }
          },
          child: const Text('Add Image'),
        ),
      ],
    );
  }
}
