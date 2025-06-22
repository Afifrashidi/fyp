// lib/src/presentation/widgets/canvas_side_bar.dart
// UPDATED: Enhanced clear canvas functionality

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/canvas_operations_enums.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:flutter_drawing_board/src/presentation/widgets/color_palette.dart';
import 'package:flutter_drawing_board/src/domain/domain.dart';
import 'package:flutter_drawing_board/src/presentation/presentation.dart';
import 'package:flutter_drawing_board/src/domain/models/stroke.dart';
import 'package:flutter_drawing_board/src/domain/models/unified_undo_redo_stack.dart';

// Add web-specific imports
import 'dart:html' as html show Blob, Url, document, AnchorElement;

class CanvasSideBar extends StatelessWidget {
  final ValueNotifier<DrawingTool> drawingTool;
  final ValueNotifier<Color> selectedColor;
  final ValueNotifier<double> strokeSize;
  final ValueNotifier<Stroke?> currentSketch;
  final ValueNotifier<List<Stroke>> allSketches;
  final GlobalKey canvasGlobalKey;
  final ValueNotifier<bool> filled;
  final ValueNotifier<int> polygonSides;
  final ValueNotifier<ui.Image?> backgroundImage;
  final UnifiedUndoRedoStack undoRedoStack;
  final ValueNotifier<bool> showGrid;
  final ValueNotifier<bool> snapToGrid;
  final ImageNotifier imageNotifier;

  const CanvasSideBar({
    Key? key,
    required this.drawingTool,
    required this.selectedColor,
    required this.strokeSize,
    required this.currentSketch,
    required this.allSketches,
    required this.canvasGlobalKey,
    required this.filled,
    required this.polygonSides,
    required this.backgroundImage,
    required this.undoRedoStack,
    required this.showGrid,
    required this.snapToGrid,
    required this.imageNotifier,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: MediaQuery.of(context).size.height - kToolbarHeight,
      color: Colors.white,
      child: SingleChildScrollView(
        child: ValueListenableBuilder<DrawingTool>(
          valueListenable: drawingTool,
          builder: (context, selectedTool, child) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Drawing Tools',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),

                  // Basic drawing tools
                  Wrap(
                    children: [
                      _IconBox(
                        iconData: FontAwesomeIcons.pencil,
                        selected: selectedTool == DrawingTool.pencil,
                        onTap: () => drawingTool.value = DrawingTool.pencil,
                        tooltip: 'Pencil',
                      ),
                      _IconBox(
                        iconData: FontAwesomeIcons.minus,
                        selected: selectedTool == DrawingTool.line,
                        onTap: () => drawingTool.value = DrawingTool.line,
                        tooltip: 'Line',
                      ),
                      _IconBox(
                        iconData: FontAwesomeIcons.square,
                        selected: selectedTool == DrawingTool.rectangle,
                        onTap: () => drawingTool.value = DrawingTool.rectangle,
                        tooltip: 'Rectangle',
                      ),
                      _IconBox(
                        iconData: FontAwesomeIcons.stop,
                        selected: selectedTool == DrawingTool.square,
                        onTap: () => drawingTool.value = DrawingTool.square,
                        tooltip: 'Square',
                      ),
                      _IconBox(
                        iconData: FontAwesomeIcons.circle,
                        selected: selectedTool == DrawingTool.circle,
                        onTap: () => drawingTool.value = DrawingTool.circle,
                        tooltip: 'Circle',
                      ),
                      _IconBox(
                        iconData: FontAwesomeIcons.drawPolygon,
                        selected: selectedTool == DrawingTool.polygon,
                        onTap: () => drawingTool.value = DrawingTool.polygon,
                        tooltip: 'Polygon',
                      ),
                      _IconBox(
                        iconData: FontAwesomeIcons.font,
                        selected: selectedTool == DrawingTool.text,
                        onTap: () => drawingTool.value = DrawingTool.text,
                        tooltip: 'Text',
                      ),
                      _IconBox(
                        iconData: FontAwesomeIcons.eraser,
                        selected: selectedTool == DrawingTool.eraser,
                        onTap: () => drawingTool.value = DrawingTool.eraser,
                        tooltip: 'Eraser',
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Selection and interaction tools
                  Wrap(
                    children: [
                      _IconBox(
                        iconData: FontAwesomeIcons.handPaper,
                        selected: selectedTool == DrawingTool.imageManipulator,
                        onTap: () => drawingTool.value = DrawingTool.imageManipulator,
                        tooltip: 'Select & Move Images\n• Tap to select\n• Drag to move\n• Pinch handles to scale\n• Rotate with corner handles',
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Grid and snap controls
                  const Text(
                    'Grid & Snap',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  ValueListenableBuilder<bool>(
                    valueListenable: showGrid,
                    builder: (context, showGridValue, child) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: snapToGrid,
                        builder: (context, snapToGridValue, child) {
                          return Wrap(
                            children: [
                              _IconBox(
                                iconData: FontAwesomeIcons.ruler,
                                selected: showGridValue,
                                onTap: () => showGrid.value = !showGrid.value,
                                tooltip: 'Toggle Grid',
                              ),
                              _IconBox(
                                iconData: FontAwesomeIcons.magnet,
                                selected: snapToGridValue,
                                onTap: () => snapToGrid.value = !snapToGrid.value,
                                tooltip: 'Snap to Grid',
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 8),

                  // Tool-specific options
                  if (selectedTool == DrawingTool.polygon)
                    _PolygonSidesSlider(polygonSides: polygonSides),

                  if (_toolSupportsFilledShapes(selectedTool))
                    _FilledShapeCheckbox(filled: filled),

                  const SizedBox(height: 10),
                  const Text(
                    'Colors',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  ColorPalette(selectedColor: selectedColor),

                  const SizedBox(height: 20),
                  const Text(
                    'Size',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _SizeSlider(strokeSize: strokeSize, selectedTool: selectedTool),

                  const SizedBox(height: 20),
                  const Text(
                    'Actions',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _ActionButtons(
                    allSketches: allSketches,
                    undoRedoStack: undoRedoStack,
                    canvasGlobalKey: canvasGlobalKey,
                    backgroundImage: backgroundImage,
                    imageNotifier: imageNotifier,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  bool _toolSupportsFilledShapes(DrawingTool tool) {
    return [
      DrawingTool.rectangle,
      DrawingTool.square,
      DrawingTool.circle,
      DrawingTool.polygon,
    ].contains(tool);
  }

  // Export functionality remains the same...
  Future<void> _exportCanvas(BuildContext context) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final boundary = canvasGlobalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        Navigator.of(context).pop();
        throw Exception('Canvas not found. Please try again.');
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        Navigator.of(context).pop();
        throw Exception('Failed to capture canvas image.');
      }

      final pngBytes = byteData.buffer.asUint8List();
      final jpgBytes = await _convertPngToJpg(pngBytes);

      Navigator.of(context).pop();

      if (kIsWeb) {
        await _saveToWeb(jpgBytes, context);
      } else {
        await _saveToDevice(jpgBytes, context);
      }

    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _exportCanvas(context),
            ),
          ),
        );
      }
    }
  }

  Future<Uint8List> _convertPngToJpg(Uint8List pngBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(pngBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.drawRect(
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Paint()..color = Colors.white,
      );

      canvas.drawImage(image, Offset.zero, Paint());

      final picture = recorder.endRecording();
      final img = await picture.toImage(image.width, image.height);

      final jpgData = await img.toByteData(format: ui.ImageByteFormat.png);
      return jpgData!.buffer.asUint8List();

    } catch (e) {
      return pngBytes;
    }
  }

  Future<void> _saveToWeb(Uint8List bytes, BuildContext context) async {
    try {
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = 'drawing_${DateTime.now().millisecondsSinceEpoch}.jpg';

      html.document.body?.children.add(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Drawing exported successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      throw Exception('Failed to save file on web: $e');
    }
  }

  Future<void> _saveToDevice(Uint8List bytes, BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        final permission = await Permission.storage.request();
        if (!permission.isGranted) {
          throw Exception('Storage permission denied');
        }
      }

      Directory directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        }
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'drawing_$timestamp.jpg';
      final file = File('${directory.path}/$fileName');

      await file.writeAsBytes(bytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Drawing saved to ${file.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () async {
                try {
                  await Share.shareXFiles([XFile(file.path)], text: 'My Drawing');
                } catch (e) {
                  debugPrint('Share failed: $e');
                }
              },
            ),
          ),
        );
      }

    } catch (e) {
      throw Exception('Failed to save file: $e');
    }
  }

  static Future<void> addImages(
      BuildContext context,
      ImageNotifier imageNotifier,
      ) async {
    try {
      final images = <ui.Image>[];

      if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: true,
        );

        if (result != null) {
          for (final file in result.files) {
            final bytes = file.bytes ??
                (file.path != null ? File(file.path!).readAsBytesSync() : null);
            if (bytes != null) {
              final image = await decodeImageFromList(bytes);
              images.add(image);
            }
          }
        }
      } else {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 4096,
          maxHeight: 4096,
          imageQuality: 90,
        );

        if (picked != null) {
          final bytes = await picked.readAsBytes();
          final image = await decodeImageFromList(bytes);
          images.add(image);
        }
      }

      final canvasImages = <CanvasImage>[];
      for (int i = 0; i < images.length; i++) {
        final position = Offset(100 + i * 30, 100 + i * 30);
        canvasImages.add(CanvasImage.withPosition(
          image: images[i],
          position: position,
        ));
      }

      if (canvasImages.isNotEmpty) {
        imageNotifier.addImages(canvasImages);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Added ${canvasImages.length} image${canvasImages.length > 1 ? 's' : ''}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading images: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

// Widget classes remain the same...
class _PolygonSidesSlider extends StatelessWidget {
  final ValueNotifier<int> polygonSides;

  const _PolygonSidesSlider({required this.polygonSides});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: polygonSides,
      builder: (context, sides, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Polygon Sides: $sides'),
            Slider(
              value: sides.toDouble(),
              min: 3,
              max: 12,
              divisions: 9,
              onChanged: (value) => polygonSides.value = value.toInt(),
            ),
          ],
        );
      },
    );
  }
}

class _FilledShapeCheckbox extends StatelessWidget {
  final ValueNotifier<bool> filled;

  const _FilledShapeCheckbox({required this.filled});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: filled,
      builder: (context, isFilled, child) {
        return CheckboxListTile(
          title: const Text('Filled'),
          value: isFilled,
          onChanged: (value) => filled.value = value ?? false,
          dense: true,
        );
      },
    );
  }
}

class _SizeSlider extends StatelessWidget {
  final ValueNotifier<double> strokeSize;
  final DrawingTool selectedTool;

  const _SizeSlider({
    required this.strokeSize,
    required this.selectedTool,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: strokeSize,
      builder: (context, size, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Size: ${size.toInt()}'),
            Slider(
              value: size,
              min: 1.0,
              max: 50.0,
              divisions: 49,
              onChanged: (value) => strokeSize.value = value,
            ),
          ],
        );
      },
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData iconData;
  final bool selected;
  final VoidCallback onTap;
  final String tooltip;

  const _IconBox({
    required this.iconData,
    required this.selected,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 35,
          width: 35,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? Colors.blue : Colors.grey,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(5),
            color: selected ? Colors.blue.withOpacity(0.1) : Colors.white,
          ),
          child: Icon(
            iconData,
            color: selected ? Colors.blue : Colors.grey[600],
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final ValueNotifier<List<Stroke>> allSketches;
  final UnifiedUndoRedoStack undoRedoStack;
  final GlobalKey canvasGlobalKey;
  final ValueNotifier<ui.Image?> backgroundImage;
  final ImageNotifier imageNotifier;

  const _ActionButtons({
    required this.allSketches,
    required this.undoRedoStack,
    required this.canvasGlobalKey,
    required this.backgroundImage,
    required this.imageNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Undo/Redo row
        Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: undoRedoStack.canUndo,
                builder: (context, canUndoValue, child) {
                  return ElevatedButton.icon(
                    onPressed: canUndoValue ? () => undoRedoStack.undo() : null,
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Undo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: undoRedoStack.canRedo,
                builder: (context, canRedoValue, child) {
                  return ElevatedButton.icon(
                    onPressed: canRedoValue ? () => undoRedoStack.redo() : null,
                    icon: const Icon(Icons.redo, size: 16),
                    label: const Text('Redo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Image actions row
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _addImage(context),
                icon: const Icon(Icons.image, size: 16),
                label: const Text('Add Image'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _resetImages(context),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reset'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Clear and Export row
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _clearCanvas(context),
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Clear'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _exportCanvas(context),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _resetImages(BuildContext context) {
    imageNotifier.removeAllImages();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Images reset'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // UPDATED: Enhanced clear canvas functionality
  void _clearCanvas(BuildContext context) {
    final strokeCount = allSketches.value.length;
    final imageCount = imageNotifier.value.imageList.length;

    if (strokeCount == 0 && imageCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Canvas is already empty'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _EnhancedClearDialog(
        strokeCount: strokeCount,
        imageCount: imageCount,
        onClear: (clearStrokes, clearImages) {
          _performClear(context, clearStrokes, clearImages);
        },
      ),
    );
  }

  // Perform the actual clearing with animation feedback
  void _performClear(BuildContext context, bool clearStrokes, bool clearImages) {
    try {
      // Store current state for potential undo
      final oldStrokes = List<Stroke>.from(allSketches.value);
      final oldImages = List<CanvasImage>.from(imageNotifier.value.imageList);

      // Perform clear operations
      if (clearStrokes) {
        allSketches.value = [];
      }

      if (clearImages) {
        imageNotifier.clearAll();
      }

      // Clear undo/redo stack since we're making a major change
      undoRedoStack.clear();

      // Show success with undo option
      final clearedItems = <String>[];
      if (clearStrokes) clearedItems.add('strokes');
      if (clearImages) clearedItems.add('images');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cleared ${clearedItems.join(' and ')}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Undo',
            textColor: Colors.white,
            onPressed: () {
              // Restore previous state
              if (clearStrokes) {
                allSketches.value = oldStrokes;
              }
              if (clearImages) {
                for (final image in oldImages) {
                  imageNotifier.addImage(image);
                }
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Clear action undone'),
                  backgroundColor: Colors.blue,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing canvas: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _addImage(BuildContext context) {
    CanvasSideBar.addImages(context, imageNotifier);
  }

  void _exportCanvas(BuildContext context) {
    final sideBar = CanvasSideBar(
      drawingTool: ValueNotifier(DrawingTool.pencil),
      selectedColor: ValueNotifier(Colors.black),
      strokeSize: ValueNotifier(2.0),
      currentSketch: ValueNotifier(null),
      allSketches: allSketches,
      canvasGlobalKey: canvasGlobalKey,
      filled: ValueNotifier(false),
      polygonSides: ValueNotifier(6),
      backgroundImage: backgroundImage,
      undoRedoStack: undoRedoStack,
      showGrid: ValueNotifier(false),
      snapToGrid: ValueNotifier(false),
      imageNotifier: imageNotifier,
    );
    sideBar._exportCanvas(context);
  }
}

// Enhanced clear dialog widget
class _EnhancedClearDialog extends StatefulWidget {
  final int strokeCount;
  final int imageCount;
  final Function(bool clearStrokes, bool clearImages) onClear;

  const _EnhancedClearDialog({
    required this.strokeCount,
    required this.imageCount,
    required this.onClear,
  });

  @override
  State<_EnhancedClearDialog> createState() => _EnhancedClearDialogState();
}

class _EnhancedClearDialogState extends State<_EnhancedClearDialog> {
  bool _clearStrokes = true;
  bool _clearImages = true;
  bool _requireConfirmation = false;
  final _confirmationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Require confirmation if there's a lot of content
    _requireConfirmation = (widget.strokeCount + widget.imageCount) > 20;
  }

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  bool get _isValidConfirmation {
    if (!_requireConfirmation) return true;
    return _confirmationController.text.toUpperCase() == 'CLEAR';
  }

  bool get _hasItemsTolear {
    return (_clearStrokes && widget.strokeCount > 0) ||
        (_clearImages && widget.imageCount > 0);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning, color: Colors.red, size: 24),
          SizedBox(width: 8),
          Text('Clear Canvas'),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose what to clear from your canvas:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),

            // Content summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current content:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.draw, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text('${widget.strokeCount} stroke${widget.strokeCount != 1 ? 's' : ''}'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.image, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text('${widget.imageCount} image${widget.imageCount != 1 ? 's' : ''}'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Clear options
            if (widget.strokeCount > 0)
              CheckboxListTile(
                title: Text('Clear strokes (${widget.strokeCount})'),
                subtitle: const Text('Remove all drawn lines and shapes'),
                value: _clearStrokes,
                onChanged: (value) => setState(() => _clearStrokes = value ?? false),
                contentPadding: EdgeInsets.zero,
              ),

            if (widget.imageCount > 0)
              CheckboxListTile(
                title: Text('Clear images (${widget.imageCount})'),
                subtitle: const Text('Remove all imported images'),
                value: _clearImages,
                onChanged: (value) => setState(() => _clearImages = value ?? false),
                contentPadding: EdgeInsets.zero,
              ),

            // Confirmation input for large content
            if (_requireConfirmation) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security, size: 16, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        const Text(
                          'Confirmation Required',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You have a lot of content. Type "CLEAR" to confirm:',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _confirmationController,
                      decoration: const InputDecoration(
                        hintText: 'Type CLEAR to confirm',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _hasItemsTolear && _isValidConfirmation
              ? () {
            Navigator.of(context).pop();
            widget.onClear(_clearStrokes, _clearImages);
          }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: Text(
            _hasItemsTolear
                ? 'Clear Selected'
                : 'Nothing to Clear',
          ),
        ),
      ],
    );
  }
}