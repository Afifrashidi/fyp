// lib/src/presentation/widgets/image_toolbar.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/canvas_operations_enums.dart';
import 'package:flutter_drawing_board/src/constants/interaction_enums.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';
import 'package:flutter_drawing_board/src/presentation/notifiers/image_notifier.dart';
import 'package:image_picker/image_picker.dart';

class ImageToolbar extends StatelessWidget {
  final ImageNotifier imageNotifier;
  final VoidCallback? onAddImage;

  const ImageToolbar({
    Key? key,
    required this.imageNotifier,
    this.onAddImage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ImageState>(
      valueListenable: imageNotifier,
      builder: (context, state, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Images',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _buildMainActions(context, state),
            if (state.hasSelection) ...[
              const SizedBox(height: 8),
              _buildSelectionInfo(state),
              const Divider(),
              _buildSelectionActions(state),
              if (state.selectedIds.length > 1) ...[
                const Divider(),
                _buildAlignmentActions(),
              ],
            ],
            if (state.imageList.isNotEmpty) ...[
              const Divider(),
              _buildLayerActions(state),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMainActions(BuildContext context, ImageState state) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionButton(
          icon: Icons.add_photo_alternate,
          label: 'Add Images',
          onPressed: () => _addImages(context),
          primary: true,
        ),
        _ActionButton(
          icon: Icons.select_all,
          label: 'Select All',
          onPressed: state.imageList.isNotEmpty
              ? () => imageNotifier.selectAll()
              : null,
        ),
        _ActionButton(
          icon: Icons.deselect,
          label: 'Deselect',
          onPressed: state.hasSelection
              ? () => imageNotifier.clearSelection()
              : null,
        ),
      ],
    );
  }

  Widget _buildSelectionInfo(ImageState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${state.selectedIds.length} image${state.selectedIds.length > 1 ? 's' : ''} selected',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildSelectionActions(ImageState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Edit actions
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ActionButton(
              icon: Icons.content_copy,
              label: 'Copy',
              onPressed: () => imageNotifier.copy(),
            ),
            _ActionButton(
              icon: Icons.content_paste,
              label: 'Paste',
              onPressed: state.clipboard.isNotEmpty
                  ? () => imageNotifier.paste(offset: const Offset(400, 300))                  : null,
            ),
            _ActionButton(
              icon: Icons.delete,
              label: 'Delete',
              onPressed: () => imageNotifier.removeSelectedImages(),
              color: Colors.red,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Transform actions
        Row(
          children: [
            Expanded(
              child: _TransformControls(imageNotifier: imageNotifier),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlignmentActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Alignment',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _AlignButton(
              icon: Icons.align_horizontal_left,
              tooltip: 'Align Left',
              onPressed: () => imageNotifier.align(AlignmentType.left),
            ),
            _AlignButton(
              icon: Icons.align_horizontal_center,
              tooltip: 'Center Horizontally',
              onPressed: () => imageNotifier.align(AlignmentType.centerHorizontal),
            ),
            _AlignButton(
              icon: Icons.align_horizontal_right,
              tooltip: 'Align Right',
              onPressed: () => imageNotifier.align(AlignmentType.right),
            ),
            const SizedBox(width: 8),
            _AlignButton(
              icon: Icons.align_vertical_top,
              tooltip: 'Align Top',
              onPressed: () => imageNotifier.align(AlignmentType.top),
            ),
            _AlignButton(
              icon: Icons.align_vertical_center,
              tooltip: 'Center Vertically',
              onPressed: () => imageNotifier.align(AlignmentType.centerVertical),
            ),
            _AlignButton(
              icon: Icons.align_vertical_bottom,
              tooltip: 'Align Bottom',
              onPressed: () => imageNotifier.align(AlignmentType.bottom),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _ActionButton(
              icon: Icons.view_week,
              label: 'Distribute H',
              onPressed: () => imageNotifier.distribute(DistributeType.horizontal),
              small: true,
            ),
            _ActionButton(
              icon: Icons.view_agenda,
              label: 'Distribute V',
              onPressed: () => imageNotifier.distribute(DistributeType.vertical),
              small: true,
            ),
          ],
        ),
      ],
    );
  }


  Widget _buildLayerActions(ImageState state) {
    return Builder(
      builder: (context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ActionButton(
            icon: Icons.flip_to_front,
            label: 'To Front',
            onPressed: state.hasSelection
                ? () => imageNotifier.bringToFront([])
                : null,
            small: true,
          ),
          _ActionButton(
            icon: Icons.flip_to_back,
            label: 'To Back',
            onPressed: state.hasSelection
                ? () => imageNotifier.sendToBack([])
                : null,
            small: true,
          ),
          _ActionButton(
            icon: Icons.clear,
            label: 'Clear All',
            onPressed: () => _confirmClearAll(context), // ✅ Now context is available
            color: Colors.orange,
            small: true,
          ),
        ],
      ),
    );
  }

  Future<void> _addImages(BuildContext context) async {
    try {
      final images = <ui.Image>[];

      if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
        // Desktop - multiple file selection
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
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
        // Mobile/Web - single image
        final picker = ImagePicker();
        final picked = await picker.pickImage(source: ImageSource.gallery);

        if (picked != null) {
          final bytes = await picked.readAsBytes();
          final image = await decodeImageFromList(bytes);
          images.add(image);
        }
      }

      // Add images with cascading positions
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${canvasImages.length} image${canvasImages.length > 1 ? 's' : ''}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading images: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _confirmClearAll(BuildContext context) {
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
              imageNotifier.removeAllImages();
              Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// Transform controls widget
class _TransformControls extends StatelessWidget {
  final ImageNotifier imageNotifier;

  const _TransformControls({
    Key? key,
    required this.imageNotifier,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _TransformButton(
              icon: Icons.rotate_left,
              tooltip: 'Rotate Left',
              onPressed: () => imageNotifier.transform(rotation: -math.pi / 2),
            ),
            _TransformButton(
              icon: Icons.rotate_right,
              tooltip: 'Rotate Right',
              onPressed: () => imageNotifier.transform(rotation: math.pi / 2),
            ),
            _TransformButton(
              icon: Icons.flip,
              tooltip: 'Flip Horizontal',
              onPressed: () => imageNotifier.transform(flipHorizontal: true),
            ),
            _TransformButton(
              icon: Icons.flip_camera_android,
              tooltip: 'Flip Vertical',
              onPressed: () => imageNotifier.transform(flipVertical: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool primary;
  final bool small;

  const _ActionButton({
    Key? key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.color,
    this.primary = false,
    this.small = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final buttonStyle = small
        ? OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minimumSize: const Size(0, 32),
    )
        : primary
        ? ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    )
        : OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: small ? 16 : 20, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: small ? 12 : 14, color: color)),
      ],
    );

    if (primary) {
      return ElevatedButton(
        onPressed: onPressed,
        style: buttonStyle,
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: buttonStyle,
      child: child,
    );
  }
}

class _AlignButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _AlignButton({
    Key? key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 20,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}

class _TransformButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _TransformButton({
    Key? key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 20,
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}

// Quick access floating toolbar
class QuickImageToolbar extends StatelessWidget {
  final ImageNotifier imageNotifier;

  const QuickImageToolbar({
    Key? key,
    required this.imageNotifier,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ImageState>(
      valueListenable: imageNotifier,
      builder: (context, state, _) {
        if (!state.hasSelection) return const SizedBox.shrink();

        return Card(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${state.selectedIds.length} selected',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.rotate_left),
                      iconSize: 20,
                      onPressed: () => imageNotifier.transform(rotation: -math.pi / 2),
                      tooltip: 'Rotate Left',
                    ),
                    IconButton(
                      icon: const Icon(Icons.rotate_right),
                      iconSize: 20,
                      onPressed: () => imageNotifier.transform(rotation: math.pi / 2),
                      tooltip: 'Rotate Right',
                    ),
                    IconButton(
                      icon: const Icon(Icons.flip_to_front),
                      iconSize: 20,
                      onPressed: () => imageNotifier.bringToFront([]),
                      tooltip: 'Bring to Front',
                    ),
                    IconButton(
                      icon: const Icon(Icons.flip_to_back),
                      iconSize: 20,
                      onPressed: () => imageNotifier.sendToBack([]),
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
      },
    );
  }
}