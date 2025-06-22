// lib/src/presentation/widgets/canvas_side_bar_collaborative.dart
// Extension to CanvasSideBar for collaborative features

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/network_enums.dart';
import 'package:flutter_drawing_board/src/domain/models/image_model.dart';
import 'package:flutter_drawing_board/src/presentation/presentation.dart';
import 'package:flutter_drawing_board/src/services/liveblocks_service.dart';
import 'package:image_picker/image_picker.dart';

extension CollaborativeCanvasSideBar on CanvasSideBar {
  // Add this method to handle collaborative image additions
  static Future<void> addImagesCollaborative(
      BuildContext context,
      ImageNotifier imageNotifier, {
        LiveblocksService? liveblocksService,
      }) async {
    try {
      final images = <ui.Image>[];

      if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
        // Desktop - use file picker for multiple files
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: true, // Ensure we get bytes
        );

        if (result != null) {
          for (final file in result.files) {
            if (file.bytes != null) {
              final image = await decodeImageFromList(file.bytes!);
              images.add(image);
            } else if (file.path != null) {
              final bytes = await File(file.path!).readAsBytes();
              final image = await decodeImageFromList(bytes);
              images.add(image);
            }
          }
        }
      } else {
        // Web/Mobile - use image picker (single image)
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 4096, // Limit size for web
          maxHeight: 4096,
        );

        if (picked != null) {
          final bytes = await picked.readAsBytes();
          final image = await decodeImageFromList(bytes);
          images.add(image);
        }
      }

      // Add images with cascading positions
      for (int i = 0; i < images.length; i++) {
        final offset = Offset(100 + i * 30, 100 + i * 30);
        final canvasImage = CanvasImage.withPosition(
          image: images[i],
          position: offset,
        );

        // Add locally
        imageNotifier.addImage(canvasImage);

        // Broadcast if in collaborative mode
        if (liveblocksService != null && liveblocksService.isConnected) {
          // Convert CanvasImage to LiveblocksImage before broadcasting
          final imageUrl = await liveblocksService.uploadImageToSupabase(
            canvasImage.image,
            liveblocksService.roomId ?? 'default',
          );

          // Replace the LiveblocksImage creation (around line 67) with:
          final liveblocksImage = LiveblocksImage(
            id: canvasImage.id,
            url: imageUrl,
            userId: liveblocksService.userId ?? 'unknown',
            userName: liveblocksService.userName ?? 'Unknown',
            transform: canvasImage.transform.storage,
            width: canvasImage.image.width.toDouble(),
            height: canvasImage.image.height.toDouble(),
            timestamp: DateTime.now().millisecondsSinceEpoch,
            addedBy: liveblocksService.userName ?? 'Unknown', // ✅ Add missing parameter
          );

          liveblocksService.broadcastImageAdd(liveblocksImage);
        }
      }

      if (images.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${images.length} image${images.length > 1 ? 's' : ''}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading images: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// Collaborative drawing toolbar wrapper
class CollaborativeDrawingToolbar extends StatelessWidget {
  final Widget child;
  final LiveblocksService? liveblocksService;
  final VoidCallback? onClearCanvas;

  const CollaborativeDrawingToolbar({
    Key? key,
    required this.child,
    this.liveblocksService,
    this.onClearCanvas,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Wrap the original toolbar with collaborative features
    return Stack(
      children: [
        child,

        // Collaborative status indicator
        if (liveblocksService != null)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: StreamBuilder<LiveblocksConnectionState>(
              stream: liveblocksService!.connectionStream,
              builder: (context, snapshot) {
                final state = snapshot.data ?? LiveblocksConnectionState.disconnected;

                if (state == LiveblocksConnectionState.authenticated) {
                  return const SizedBox.shrink();
                }

                String message;
                Color color;
                IconData icon;

                switch (state) {
                  case LiveblocksConnectionState.connecting:
                  case LiveblocksConnectionState.authenticating:
                    message = 'Connecting...';
                    color = Colors.orange;
                    icon = Icons.sync;
                    break;
                  case LiveblocksConnectionState.error:
                    message = 'Connection error';
                    color = Colors.red;
                    icon = Icons.error_outline;
                    break;
                  case LiveblocksConnectionState.connected:
                    message = 'Connected';
                    color = Colors.green;
                    icon = Icons.cloud_done;
                    break;
                  default:
                    message = 'Disconnected';
                    color = Colors.grey;
                    icon = Icons.cloud_off;
                    break;
                }

                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    border: Border.all(color: color),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// Helper widget for image operations in collaborative mode
class CollaborativeImageHandler {
  final ImageNotifier imageNotifier;
  final LiveblocksService liveblocksService;

  // Track ongoing transforms to batch updates
  final Map<String, Timer> _transformTimers = {};

  CollaborativeImageHandler({
    required this.imageNotifier,
    required this.liveblocksService,
  }) {
    // Listen to image transform events
    imageNotifier.addListener(_handleImageChanges);
  }

  void _handleImageChanges() {
    // This would need to track specific transform events
    // For now, we'll handle this in the UI layer
  }

  // Debounced transform broadcast
  void broadcastTransformDebounced(String imageId, Matrix4 transform) {
    // Cancel existing timer
    _transformTimers[imageId]?.cancel();

    // Set new timer
    _transformTimers[imageId] = Timer(const Duration(milliseconds: 100), () {
      liveblocksService.broadcastImageUpdate(imageId, transform);
      _transformTimers.remove(imageId);
    });
  }

  void dispose() {
    // Cancel all timers
    for (final timer in _transformTimers.values) {
      timer.cancel();
    }
    _transformTimers.clear();

    imageNotifier.removeListener(_handleImageChanges);
  }
}

// Modified clear canvas dialog for collaborative mode
class CollaborativeClearCanvasDialog extends StatelessWidget {
  final VoidCallback onClear;
  final bool isCollaborative;

  const CollaborativeClearCanvasDialog({
    Key? key,
    required this.onClear,
    this.isCollaborative = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clear Canvas?'),
      content: Text(
        isCollaborative
            ? 'This will clear the canvas for ALL participants. This action cannot be undone.'
            : 'This will clear the entire canvas. This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onClear();
          },
          child: const Text(
            'Clear',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}