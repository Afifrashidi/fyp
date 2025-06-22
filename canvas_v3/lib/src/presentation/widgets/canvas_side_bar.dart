// lib/src/presentation/widgets/canvas_side_bar.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart' as models;
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart' as notifiers;
import 'package:flutter_drawing_board/src/src.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_html/html.dart' as html;

class CanvasSideBar extends StatefulWidget {
  final ValueNotifier<Color> selectedColor;
  final ValueNotifier<double> strokeSize;
  final ValueNotifier<DrawingTool> drawingTool;
  final CurrentStrokeValueNotifier currentSketch;
  final ValueNotifier<List<Stroke>> allSketches;
  final GlobalKey canvasGlobalKey;
  final ValueNotifier<bool> filled;
  final ValueNotifier<int> polygonSides;
  final ValueNotifier<ui.Image?> backgroundImage;
  final UndoRedoStack undoRedoStack;
  final ValueNotifier<bool> showGrid;
  final ImageNotifier imageNotifier;

  const CanvasSideBar({
    Key? key,
    required this.selectedColor,
    required this.strokeSize,
    required this.drawingTool,
    required this.currentSketch,
    required this.allSketches,
    required this.canvasGlobalKey,
    required this.filled,
    required this.polygonSides,
    required this.backgroundImage,
    required this.undoRedoStack,
    required this.showGrid,
    required this.imageNotifier,
  }) : super(key: key);

  @override
  State<CanvasSideBar> createState() => _CanvasSideBarState();
}

class _CanvasSideBarState extends State<CanvasSideBar> {
  UndoRedoStack get undoRedoStack => widget.undoRedoStack;
  final scrollController = ScrollController();

  Offset? _calculateSelectionCenter() {
    final selectedImages = widget.imageNotifier.value.selectedImages;
    if (selectedImages.isEmpty) return null;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final img in selectedImages) {
      final bounds = img.bounds;
      minX = math.min(minX, bounds.left);
      minY = math.min(minY, bounds.top);
      maxX = math.max(maxX, bounds.right);
      maxY = math.max(maxY, bounds.bottom);
    }

    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: MediaQuery.of(context).size.height < 680 ? 450 : 610,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 3,
            offset: const Offset(3, 3),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          widget.selectedColor,
          widget.strokeSize,
          widget.drawingTool,
          widget.filled,
          widget.polygonSides,
          widget.backgroundImage,
          widget.showGrid,
          widget.imageNotifier,
        ]),
        builder: (context, _) {
          return Scrollbar(
            controller: scrollController,
            thumbVisibility: true,
            trackVisibility: true,
            child: ListView(
              padding: const EdgeInsets.all(10.0),
              controller: scrollController,
              children: [
                const SizedBox(height: 10),
                const Text(
                  'Shapes',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    _IconBox(
                      iconData: FontAwesomeIcons.pencil,
                      selected: widget.drawingTool.value == DrawingTool.pencil,
                      onTap: () => widget.drawingTool.value = DrawingTool.pencil,
                      tooltip: 'Pencil',
                    ),
                    _IconBox(
                      selected: widget.drawingTool.value == DrawingTool.line,
                      onTap: () => widget.drawingTool.value = DrawingTool.line,
                      tooltip: 'Line',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 22,
                            height: 2,
                            color: widget.drawingTool.value == DrawingTool.line
                                ? Colors.grey[900]
                                : Colors.grey,
                          ),
                        ],
                      ),
                    ),
                    _IconBox(
                      iconData: Icons.hexagon_outlined,
                      selected: widget.drawingTool.value == DrawingTool.polygon,
                      onTap: () => widget.drawingTool.value = DrawingTool.polygon,
                      tooltip: 'Polygon',
                    ),
                    _IconBox(
                      iconData: FontAwesomeIcons.eraser,
                      selected: widget.drawingTool.value == DrawingTool.eraser,
                      onTap: () => widget.drawingTool.value = DrawingTool.eraser,
                      tooltip: 'Eraser',
                    ),
                    _IconBox(
                      iconData: FontAwesomeIcons.square,
                      selected: widget.drawingTool.value == DrawingTool.square,
                      onTap: () => widget.drawingTool.value = DrawingTool.square,
                      tooltip: 'Square',
                    ),
                    _IconBox(
                      iconData: FontAwesomeIcons.circle,
                      selected: widget.drawingTool.value == DrawingTool.circle,
                      onTap: () => widget.drawingTool.value = DrawingTool.circle,
                      tooltip: 'Circle',
                    ),
                    _IconBox(
                      iconData: FontAwesomeIcons.ruler,
                      selected: widget.showGrid.value,
                      onTap: () => widget.showGrid.value = !widget.showGrid.value,
                      tooltip: 'Guide Lines',
                    ),
                    _IconBox(
                      iconData: FontAwesomeIcons.handPointer,
                      selected: widget.drawingTool.value == DrawingTool.pointer,
                      onTap: () => widget.drawingTool.value = DrawingTool.pointer,
                      tooltip: 'Pointer',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Fill Shape: ',
                      style: TextStyle(fontSize: 12),
                    ),
                    Checkbox(
                      value: widget.filled.value,
                      onChanged: (val) {
                        widget.filled.value = val ?? false;
                      },
                    ),
                  ],
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: widget.drawingTool.value == DrawingTool.polygon
                      ? Row(
                    children: [
                      const Text(
                        'Polygon Sides: ',
                        style: TextStyle(fontSize: 12),
                      ),
                      Slider(
                        value: widget.polygonSides.value.toDouble(),
                        min: 3,
                        max: 8,
                        onChanged: (val) {
                          widget.polygonSides.value = val.toInt();
                        },
                        label: '${widget.polygonSides.value}',
                        divisions: 5,
                      ),
                    ],
                  )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Colors',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                ColorPalette(
                  selectedColorListenable: widget.selectedColor,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Size',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                Row(
                  children: [
                    const Text(
                      'Stroke Size: ',
                      style: TextStyle(fontSize: 12),
                    ),
                    Slider(
                      value: widget.strokeSize.value,
                      min: 0,
                      max: 50,
                      onChanged: (val) {
                        widget.strokeSize.value = val;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Actions',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: widget.allSketches.value.isNotEmpty
                          ? () => undoRedoStack.undo()
                          : null,
                      child: const Text('Undo'),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: undoRedoStack.canRedo,
                      builder: (_, canRedo, __) {
                        return TextButton(
                          onPressed: canRedo ? () => undoRedoStack.redo() : null,
                          child: const Text('Redo'),
                        );
                      },
                    ),
                    TextButton(
                      child: const Text('Clear'),
                      onPressed: () => undoRedoStack.clear(),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (widget.backgroundImage.value != null) {
                          widget.backgroundImage.value = null;
                        } else {
                          widget.backgroundImage.value = await _getImage();
                        }
                      },
                      child: Text(
                        widget.backgroundImage.value == null
                            ? 'Add Background'
                            : 'Remove Background',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Images',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                ValueListenableBuilder<ImageState>(
                  valueListenable: widget.imageNotifier,
                  builder: (context, state, child) {
                    return Row(
                      children: [
                        Text(
                          'Selected: ${state.selectedIds.length} / ${state.imageList.length}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<ImageState>(
                  valueListenable: widget.imageNotifier,
                  builder: (context, state, child) {
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Add Images
                        _ActionButton(
                          icon: Icons.add_photo_alternate,
                          label: 'Add Images',
                          onPressed: _addImages,
                          tooltip: 'Add multiple images',
                        ),
                        // Selection controls
                        _ActionButton(
                          icon: Icons.select_all,
                          label: 'Select All',
                          onPressed: state.imageList.isNotEmpty
                              ? () => widget.imageNotifier.selectAll()
                              : null,
                          tooltip: 'Ctrl+A',
                        ),
                        _ActionButton(
                          icon: Icons.deselect,
                          label: 'Deselect',
                          onPressed: state.hasSelection
                              ? () => widget.imageNotifier.deselectAll()
                              : null,
                          tooltip: 'Ctrl+D',
                        ),
                        // Edit operations
                        _ActionButton(
                          icon: Icons.copy,
                          label: 'Copy',
                          onPressed: state.hasSelection
                              ? () {
                            widget.imageNotifier.copy();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Images copied')),
                            );
                          }
                              : null,
                          tooltip: 'Ctrl+C',
                        ),
                        _ActionButton(
                          icon: Icons.paste,
                          label: 'Paste',
                          onPressed: state.clipboard.isNotEmpty
                              ? () {
                            widget.imageNotifier.paste(const Offset(400, 300));
                          }
                              : null,
                          tooltip: 'Ctrl+V',
                        ),
                        _ActionButton(
                          icon: Icons.delete,
                          label: 'Delete',
                          onPressed: state.hasSelection
                              ? () => widget.imageNotifier.removeSelectedImages()
                              : null,
                          tooltip: 'Delete',
                        ),
                        // Transform operations
                        _ActionButton(
                          icon: Icons.rotate_left,
                          label: 'Rotate -90°',
                          onPressed: state.hasSelection
                              ? () => widget.imageNotifier.transform(
                            rotation: -math.pi / 2, // -90 degrees in radians
                            scaleOrigin: _calculateSelectionCenter(), // Rotate around selection center
                          )
                              : null,
                        ),
                        _ActionButton(
                          icon: Icons.rotate_right,
                          label: 'Rotate 90°',
                          onPressed: state.hasSelection
                              ? () => widget.imageNotifier.transform(
                            rotation: math.pi / 2, // +90 degrees in radians
                            scaleOrigin: _calculateSelectionCenter(),
                          )
                              : null,
                        ),
                        _ActionButton(
                          icon: Icons.flip,
                          label: 'Flip',
                          onPressed: state.hasSelection
                              ? () => widget.imageNotifier.transform(flipHorizontal: true)
                              : null,
                        ),
                        // Z-order operations
                        _ActionButton(
                          icon: Icons.flip_to_front,
                          label: 'To Front',
                          onPressed: state.hasSelection
                              ? () => widget.imageNotifier.bringToFront(state.selectedIds.toList())
                              : null,
                        ),
                        _ActionButton(
                          icon: Icons.flip_to_back,
                          label: 'To Back',
                          onPressed: state.hasSelection
                              ? () => widget.imageNotifier.sendToBack(state.selectedIds.toList())
                              : null,
                        ),
                        // Clear all
                        _ActionButton(
                          icon: Icons.clear,
                          label: 'Clear All',
                          onPressed: state.imageList.isNotEmpty
                              ? () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Clear All Images?'),
                                content: const Text('This will remove all images from the canvas.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      widget.imageNotifier.removeAllImages();
                                      Navigator.pop(context);
                                    },
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                            );
                          }
                              : null,
                        ),
                      ],
                    );
                  },
                ),


// Alignment controls for multiple selected images
                ValueListenableBuilder<ImageState>(
                  valueListenable: widget.imageNotifier,
                  builder: (context, state, child) {
                    // Only show alignment controls when 2 or more images are selected
                    if (state.selectedIds.length <= 1) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        const Text(
                          'Align',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.align_horizontal_left, size: 20),
                              onPressed: () => widget.imageNotifier.align(AlignmentType.left),
                              tooltip: 'Align Left',
                            ),
                            IconButton(
                              icon: const Icon(Icons.align_horizontal_center, size: 20),
                              onPressed: () => widget.imageNotifier.align(AlignmentType.centerHorizontal),
                              tooltip: 'Align Center H',
                            ),
                            IconButton(
                              icon: const Icon(Icons.align_horizontal_right, size: 20),
                              onPressed: () => widget.imageNotifier.align(AlignmentType.right),
                              tooltip: 'Align Right',
                            ),
                            IconButton(
                              icon: const Icon(Icons.align_vertical_top, size: 20),
                              onPressed: () => widget.imageNotifier.align(AlignmentType.top),
                              tooltip: 'Align Top',
                            ),
                            IconButton(
                              icon: const Icon(Icons.align_vertical_center, size: 20),
                              onPressed: () => widget.imageNotifier.align(AlignmentType.centerVertical),
                              tooltip: 'Align Center V',
                            ),
                            IconButton(
                              icon: const Icon(Icons.align_vertical_bottom, size: 20),
                              onPressed: () => widget.imageNotifier.align(AlignmentType.bottom),
                              tooltip: 'Align Bottom',
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'Export',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: TextButton(
                        child: const Text('Export PNG'),
                        onPressed: () async {
                          Uint8List? pngBytes = await getBytes();
                          if (pngBytes != null) saveFile(pngBytes, 'png');
                        },
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextButton(
                        child: const Text('Export JPEG'),
                        onPressed: () async {
                          Uint8List? pngBytes = await getBytes();
                          if (pngBytes != null) saveFile(pngBytes, 'jpeg');
                        },
                      ),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    'Made with ❤️ by FTMK Student',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addImages() async {
    try {
      final completer = Completer<List<ui.Image>>();
      final images = <ui.Image>[];

      if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
        // Desktop - use file picker for multiple files
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
        );

        if (result != null) {
          for (final file in result.files) {
            final bytes = file.bytes ?? (file.path != null ? File(file.path!).readAsBytesSync() : null);
            if (bytes != null) {
              final image = await decodeImageFromList(bytes);
              images.add(image);
            }
          }
        }
      } else {
        // Web/Mobile - use image picker (single image)
        final image = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (image != null) {
          final bytes = await image.readAsBytes();
          final decodedImage = await decodeImageFromList(bytes);
          images.add(decodedImage);
        }
      }

      // Add images with cascading positions
      for (int i = 0; i < images.length; i++) {
        final offset = Offset(100 + i * 30, 100 + i * 30); // Standard coordinates
        widget.imageNotifier.addImage(
          CanvasImage.withPosition(
            image: images[i],
            position: offset,
          ),
        );
      }

      if (images.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${images.length} image(s)')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading images: $e')),
      );
    }
  }

  void saveFile(Uint8List bytes, String extension) async {
    if (kIsWeb) {
      html.AnchorElement()
        ..href = '${Uri.dataFromBytes(bytes, mimeType: 'image/$extension')}'
        ..download = 'FlutterLetsDraw-${DateTime.now().toIso8601String()}.$extension'
        ..style.display = 'none'
        ..click();
    } else {
      await FileSaver.instance.saveFile(
        name: 'FlutterLetsDraw-${DateTime.now().toIso8601String()}.$extension',
        bytes: bytes,
        ext: extension,
        mimeType: extension == 'png' ? MimeType.png : MimeType.jpeg,
      );
    }
  }

  Future<ui.Image?> _getImage() async {
    final completer = Completer<ui.Image>();
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      final file = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (file != null) {
        final filePath = file.files.single.path;
        final bytes = filePath == null
            ? file.files.first.bytes
            : File(filePath).readAsBytesSync();
        if (bytes != null) {
          completer.complete(decodeImageFromList(bytes));
        } else {
          completer.completeError('No image selected');
        }
      }
    } else {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        completer.complete(decodeImageFromList(bytes));
      } else {
        completer.completeError('No image selected');
      }
    }
    return completer.future;
  }

  Future<Uint8List?> getBytes() async {
    RenderRepaintBoundary boundary = widget.canvasGlobalKey.currentContext
        ?.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage();
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List? pngBytes = byteData?.buffer.asUint8List();
    return pngBytes;
  }
}

class _IconBox extends StatelessWidget {
  final IconData? iconData;
  final Widget? child;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  const _IconBox({
    Key? key,
    this.iconData,
    this.child,
    this.tooltip,
    required this.selected,
    required this.onTap,
  })  : assert(child != null || iconData != null),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 35,
          width: 35,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? Colors.grey[900]! : Colors.grey,
              width: 1.5,
            ),
            borderRadius: const BorderRadius.all(Radius.circular(5)),
          ),
          child: Tooltip(
            message: tooltip,
            preferBelow: false,
            child: child ??
                Icon(
                  iconData,
                  color: selected ? Colors.grey[900] : Colors.grey,
                  size: 20,
                ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;

  const _ActionButton({
    Key? key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? label,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 32),
        ),
      ),
    );
  }
}