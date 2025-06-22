// lib/src/services/storage_service.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_drawing_board/src/domain/domain.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';
import 'package:flutter_drawing_board/src/services/drawing_persistence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // Upload canvas image to storage
  Future<String> uploadCanvasImage({
    required String drawingId,
    required Uint8List imageBytes,
    required String filename,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final path = '$userId/$drawingId/images/$filename';

    final response = await _supabase.storage
        .from('user-images')
        .uploadBinary(path, imageBytes);

    if (response.isEmpty) {
      throw Exception('Failed to upload image');
    }

    // Get public URL
    final url = _supabase.storage
        .from('user-images')
        .getPublicUrl(path);

    return url;
  }

  // Upload background image
  Future<String> uploadBackgroundImage({
    required String drawingId,
    required ui.Image image,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    // Convert ui.Image to bytes
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Failed to convert image');

    final bytes = byteData.buffer.asUint8List();
    final filename = 'background_${DateTime.now().millisecondsSinceEpoch}.png';
    final path = '$userId/$drawingId/$filename';

    await _supabase.storage
        .from('drawings')
        .uploadBinary(path, bytes);

    return _supabase.storage
        .from('drawings')
        .getPublicUrl(path);
  }

  // Generate and upload thumbnail
  Future<String> generateAndUploadThumbnail({
    required String drawingId,
    required GlobalKey canvasKey,
  }) async {
    try {
      // Get the canvas render
      final boundary = canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Canvas not found');

      // Create thumbnail at lower resolution
      final image = await boundary.toImage(pixelRatio: 0.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to generate thumbnail');

      final bytes = byteData.buffer.asUint8List();
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final path = '$userId/$drawingId/thumbnail.png';

      await _supabase.storage
          .from('thumbnails')
          .uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'image/png',
        ),
      );

      final url = _supabase.storage
          .from('thumbnails')
          .getPublicUrl(path);

      // Update drawing with thumbnail URL
      await _supabase.from('drawings').update({
        'thumbnail_url': url,
      }).eq('id', drawingId);

      return url;
    } catch (e) {
      print('Error generating thumbnail: $e');
      rethrow;
    }
  }

  // Delete drawing storage
  Future<void> deleteDrawingStorage(String drawingId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    try {
      // Delete all files in drawing folder
      final paths = await _supabase.storage
          .from('drawings')
          .list(path: '$userId/$drawingId');

      if (paths.isNotEmpty) {
        final filePaths = paths.map((file) => '$userId/$drawingId/${file.name}').toList();
        await _supabase.storage
            .from('drawings')
            .remove(filePaths);
      }

      // Delete thumbnail
      await _supabase.storage
          .from('thumbnails')
          .remove(['$userId/$drawingId/thumbnail.png']);

      // Delete user images
      final imagePaths = await _supabase.storage
          .from('user-images')
          .list(path: '$userId/$drawingId/images');

      if (imagePaths.isNotEmpty) {
        final imageFilePaths = imagePaths
            .map((file) => '$userId/$drawingId/images/${file.name}')
            .toList();
        await _supabase.storage
            .from('user-images')
            .remove(imageFilePaths);
      }
    } catch (e) {
      print('Error deleting storage: $e');
    }
  }

  // Load image from URL
  Future<ui.Image> loadImageFromUrl(String url) async {
    final response = await _supabase.storage
        .from('user-images')
        .download(url);

    final codec = await ui.instantiateImageCodec(response);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // Get storage usage for user
  Future<StorageUsage> getStorageUsage() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    // This would need a custom PostgreSQL function to calculate
    // For now, return mock data
    return StorageUsage(
      used: 50 * 1024 * 1024, // 50MB
      total: 500 * 1024 * 1024, // 500MB limit for free tier
    );
  }
}

class StorageUsage {
  final int used; // in bytes
  final int total; // in bytes

  StorageUsage({required this.used, required this.total});

  double get percentage => (used / total) * 100;

  String get usedFormatted => _formatBytes(used);
  String get totalFormatted => _formatBytes(total);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// Extension to help with image persistence
extension DrawingPersistenceExtension on DrawingPersistenceService {
  // Save images to storage and return metadata
  Future<List<Map<String, dynamic>>> _saveImages(
      String drawingId,
      List<CanvasImage> images,
      ) async {
    final storageService = StorageService();
    final savedImages = <Map<String, dynamic>>[];

    for (final image in images) {
      try {
        // Convert ui.Image to bytes
        final byteData = await image.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (byteData == null) continue;

        final bytes = byteData.buffer.asUint8List();
        final filename = 'img_${image.id}_${DateTime.now().millisecondsSinceEpoch}.png';

        // Upload to storage
        final url = await storageService.uploadCanvasImage(
          drawingId: drawingId,
          imageBytes: bytes,
          filename: filename,
        );

        // Save metadata to database
        final metadata = {
          'id': image.id,
          'drawing_id': drawingId,
          'user_id': AuthService().currentUser!.id,
          'storage_path': url,
          'url': url,
          'original_filename': filename,
          'file_size': bytes.length,
          'width': image.image.width,
          'height': image.image.height,
          'mime_type': 'image/png',
          'position_x': image.position.dx,
          'position_y': image.position.dy,
          'size_width': image.size.width,
          'size_height': image.size.height,
          'rotation': image.rotation,
        };

        // Insert or update in database
        await Supabase.instance.client
            .from('images')
            .upsert(metadata, onConflict: 'id');

        savedImages.add({
          'id': image.id,
          'position': [image.position.dx, image.position.dy],
          'size': [image.size.width, image.size.height],
          'rotation': image.rotation,
          'url': url,
        });
      } catch (e) {
        print('Error saving image ${image.id}: $e');
      }
    }

    return savedImages;
  }

  // Upload background image
  Future<String?> _uploadBackgroundImage(
      String drawingId,
      ui.Image backgroundImage,
      ) async {
    try {
      final storageService = StorageService();
      return await storageService.uploadBackgroundImage(
        drawingId: drawingId,
        image: backgroundImage,
      );
    } catch (e) {
      print('Error uploading background image: $e');
      return null;
    }
  }

  // Save thumbnail after each save
  Future<void> _saveThumbnail(String drawingId) async {
    try {
      // This would need access to the canvas global key
      // Usually passed from the drawing page
      // For now, this is a placeholder
    } catch (e) {
      print('Error saving thumbnail: $e');
    }
  }
}

// Example usage in a settings page
class StorageIndicator extends StatelessWidget {
  final StorageUsage usage;

  const StorageIndicator({
    Key? key,
    required this.usage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Storage Used'),
            Text('${usage.usedFormatted} / ${usage.totalFormatted}'),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: usage.percentage / 100,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(
            usage.percentage > 80 ? Colors.red : Colors.blue,
          ),
        ),
        if (usage.percentage > 80)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Running low on storage!',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}