import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/src.dart';

class DrawingPage extends StatefulWidget {
  const DrawingPage({Key? key}) : super(key: key);

  @override
  _DrawingPageState createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage> {
  Offset imagePosition = Offset(100, 100); // Initial position of image on canvas

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Drawing Canvas")),
      body: Stack(
        children: [
          // Your existing canvas code for drawing, background, grid, etc.
          // This would include the drawing tools, etc.

          // Draggable Image
          if (widget.backgroundImage.value != null)
            Draggable(
              data: widget.backgroundImage.value,
              child: Positioned(
                left: imagePosition.dx,
                top: imagePosition.dy,
                child: Image(image: widget.backgroundImage.value),
              ),
              feedback: Material(
                color: Colors.transparent,
                child: Image(image: widget.backgroundImage.value),
              ),
              childWhenDragging: Container(), // Optional placeholder when dragging
              onDraggableCanceled: (velocity, offset) {
                setState(() {
                  imagePosition = offset; // Update position when drag ends
                });
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
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
            setState(() {
              imagePosition = Offset(100, 100); // Set initial position when image is selected
            });
          }
        },
        child: const Icon(Icons.add_photo_alternate),
      ),
    );
  }
}

