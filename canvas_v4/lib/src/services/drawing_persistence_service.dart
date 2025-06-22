import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter_drawing_board/src/domain/domain.dart';
import 'package:flutter_drawing_board/src/domain/models/drawing_data.dart';
import 'package:flutter_drawing_board/src/extensions/extensions.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DrawingPersistenceService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();

  // Check if user can save drawings
  bool get canSave => _authService.isAuthenticated;

// Save drawing state - updated method
  Future<String?> saveDrawingState({
    String? drawingId,
    required String title,
    required List<Stroke> strokes,
    required List<CanvasImage> images,
    required DrawingCanvasOptions options,
    ui.Image? backgroundImage,
  })

  async {
    // Only save for authenticated users
    if (!_authService.isAuthenticated) {
      print('Cannot save: User not authenticated');
      return null;
    }

    final userId = _authService.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    try {
      final now = DateTime.now().toIso8601String();

      // Create or update drawing
      if (drawingId == null) {
        // Create new drawing
        final drawingResponse = await _supabase.from('drawings').insert({
          'user_id': userId,
          'title': title,
          'created_at': now,
          'updated_at': now,
          'last_opened_at': now, // Set last_opened_at on creation
        }).select().single();

        drawingId = drawingResponse['id'];
      } else {
        // Update existing drawing - always update both timestamps
        await _supabase.from('drawings').update({
          'title': title,
          'updated_at': now,
          'last_opened_at': now, // Update last_opened_at on every save
        }).eq('id', drawingId);
      }

      // Now drawingId is guaranteed to be non-null
      final nonNullDrawingId = drawingId!;

      // Save drawing state
      final stateData = {
        'drawing_id': nonNullDrawingId,
        'user_id': userId,
        'canvas_width': OffsetExtensions.standardWidth,
        'canvas_height': OffsetExtensions.standardHeight,
        'background_color': '#${options.backgroundColor.value
            .toRadixString(16)
            .substring(2)
            .toUpperCase()}',
        'show_grid': options.showGrid,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'current_tool': options.currentTool
            .toString()
            .split('.')
            .last,
        'stroke_color': '#${options.strokeColor.value
            .toRadixString(16)
            .substring(2)
            .toUpperCase()}',
        'stroke_size': options.size,
        'eraser_size': 30.0, // Get from actual value
        'fill_shape': options.fillShape,
        'polygon_sides': options.polygonSides,
        'background_image_url': backgroundImage != null
            ? await _uploadBackgroundImage(nonNullDrawingId, backgroundImage)
            : null,
        'updated_at': now, // Update state timestamp too
      };

      await _supabase.from('drawing_states').upsert(
        stateData,
        onConflict: 'drawing_id',
      );

      // Save images after drawing state is saved
      if (images.isNotEmpty) {
        await _saveImages(nonNullDrawingId, images);
      }

      // Generate and save thumbnail
      await _saveThumbnail(nonNullDrawingId);

      // Add to history (version control)
      await _addToHistory(nonNullDrawingId, stateData);

      return nonNullDrawingId;
    } catch (e) {
      print('Error saving drawing: $e');
      rethrow;
    }
  }

  Future<void> saveDrawing(String drawingId, DrawingData drawingData) async {
    await saveDrawingState(
      drawingId: drawingId,
      title: drawingData.title,
      strokes: drawingData.strokes,
      images: drawingData.images,
      options: drawingData.options,
    );
  }

  Future<DrawingData?> loadDrawing(String drawingId) async {
    return await loadDrawingState(drawingId);
  }

  Future<void> saveToLocalStorage(String title, DrawingData drawingData) async {
    await _saveToLocalStorage(
      drawingData.strokes,
      drawingData.images,
      drawingData.options,
    );
  }

  Future<List<Map<String, dynamic>>> _saveImages(
      String drawingId,
      List<CanvasImage> images,
      ) async {
    final imageData = <Map<String, dynamic>>[];

    for (final image in images) {
      try {
        // Convert image to bytes and upload to Supabase
        final bytes = await _imageToBytes(image.image);
        if (bytes != null) {
          final fileName = '${image.id}.png';
          final path = 'drawings/$drawingId/$fileName';

          await _supabase.storage
              .from('images')
              .uploadBinary(path, bytes);

          final url = _supabase.storage
              .from('images')
              .getPublicUrl(path);

          // Save image metadata to database
          final imageRecord = await _supabase
              .from('drawing_images')
              .insert({
            'drawing_id': drawingId,
            'url': url,
            'position_x': image.position.dx,
            'position_y': image.position.dy,
            'size_width': image.size.width,
            'size_height': image.size.height,
            'rotation': image.rotation,
          }).select().single();

          imageData.add(imageRecord);
        }
      } catch (e) {
        print('Error saving image ${image.id}: $e');
      }
    }

    return imageData;
  }

  // Upload background image to Supabase storage
  Future<String?> _uploadBackgroundImage(String drawingId,
      ui.Image backgroundImage) async {
    try {
      final bytes = await _imageToBytes(backgroundImage);
      if (bytes != null) {
        final fileName = '${drawingId}_background.png';
        final path = 'drawings/$drawingId/$fileName';

        await _supabase.storage
            .from('backgrounds')
            .uploadBinary(path, bytes);

        return _supabase.storage
            .from('backgrounds')
            .getPublicUrl(path);
      }
    } catch (e) {
      print('Error uploading background image: $e');
    }
    return null;
  }

  // Generate and save thumbnail
  Future<void> _saveThumbnail(String drawingId) async {
    try {
      // This would require rendering the canvas to a smaller image
      // For now, we'll skip the implementation
      // You can implement this by creating a small version of the canvas
      print('Thumbnail generation not implemented yet');
    } catch (e) {
      print('Error saving thumbnail: $e');
    }
  }

  // Add to drawing history for version control
  Future<void> _addToHistory(String drawingId,
      Map<String, dynamic> stateData) async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('drawing_history').insert({
        'drawing_id': drawingId,
        'user_id': userId,
        'state_data': stateData,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error adding to history: $e');
    }
  }

  // Convert ui.Image to bytes
  Future<Uint8List?> _imageToBytes(ui.Image image) async {
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print('Error converting image to bytes: $e');
      return null;
    }
  }

// Load drawing state - update the timestamp when loading
  Future<DrawingData?> loadDrawingState(String drawingId) async {
    if (!_authService.isAuthenticated) {
      print('Cannot load: User not authenticated');
      return null;
    }

    try {
      // Get drawing metadata
      final drawing = await _supabase
          .from('drawings')
          .select()
          .eq('id', drawingId)
          .single();

      // Get drawing state
      final state = await _supabase
          .from('drawing_states')
          .select()
          .eq('drawing_id', drawingId)
          .single();

      // Get images
      final images = await _supabase
          .from('images')
          .select()
          .eq('drawing_id', drawingId);

      // Update last opened timestamp - this is important!
      await _supabase.from('drawings').update({
        'last_opened_at': DateTime.now().toIso8601String(),
      }).eq('id', drawingId);

      return DrawingData.fromDatabase(drawing, state, images);
    } catch (e) {
      print('Error loading drawing: $e');
      return null;
    }
  }

  // Fix the getUserDrawings method to properly sort
  // Fix the getUserDrawings method to properly sort
  Future<List<DrawingMetadata>> getUserDrawings({
    int limit = 20,
    int offset = 0,
    String? searchQuery,
    String? folderId,
    bool starredOnly = false,
    String sortBy = 'last_used', // 'last_used' or 'last_modified'
  }) async {
    // Only authenticated users can retrieve drawings
    if (!_authService.isAuthenticated) {
      print('Cannot get drawings: User not authenticated');
      return [];
    }

    final userId = _authService.currentUser?.id;
    if (userId == null) return [];

    var query = _supabase
        .from('drawings')
        .select('''
        id,
        title,
        thumbnail_url,
        created_at,
        starred,
        is_public,
        tags,
        last_opened_at,
        updated_at,
        drawing_states!inner(
          updated_at
        )
      ''')
        .eq('user_id', userId);

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.ilike('title', '%$searchQuery%');
    }

    if (folderId != null) {
      query = query.eq('folder_id', folderId);
    }

    if (starredOnly) {
      query = query.eq('starred', true);
    }

    // Apply sorting, limit and range in the correct order
    List<Map<String, dynamic>> response;
    if (sortBy == 'last_used') {
      response = await query
          .order('last_opened_at', ascending: false)
          .limit(limit)
          .range(offset, offset + limit - 1);
    } else if (sortBy == 'last_modified') {
      // Note: Ordering by nested fields might not work directly
      // We'll sort by the drawing's updated_at instead
      response = await query
          .order('updated_at', ascending: false)
          .limit(limit)
          .range(offset, offset + limit - 1);
    } else {
      response = await query
          .limit(limit)
          .range(offset, offset + limit - 1);
    }

    // Convert to DrawingMetadata objects
    final drawings = response.map<DrawingMetadata>((data) {
      return DrawingMetadata.fromJson(data);
    }).toList();

    return drawings;
  }

  // Auto-save functionality
  Timer? _autoSaveTimer;
  Function? _currentSaveFunction;

  void startAutoSave(String drawingId, Duration interval,
      Function saveFunction) {
    // Only start auto-save for authenticated users
    if (!_authService.isAuthenticated) {
      print('Auto-save disabled: User not authenticated');
      return;
    }

    _autoSaveTimer?.cancel();
    _currentSaveFunction = saveFunction;
    _autoSaveTimer = Timer.periodic(interval, (_) {
      _performAutoSave(drawingId);
    });
  }

  void stopAutoSave() {
    _autoSaveTimer?.cancel();
    _currentSaveFunction = null;
  }

  void _performAutoSave(String drawingId) async {
    if (_currentSaveFunction != null) {
      await _currentSaveFunction!();
      print('Auto-saved drawing: $drawingId');
    }
  }

  // Local storage for guest users
  Future<void> _saveToLocalStorage(List<Stroke> strokes,
      List<CanvasImage> images,
      DrawingCanvasOptions options,) async {
    final prefs = await SharedPreferences.getInstance();

    final data = {
      'title': 'Untitled Drawing',
      'strokes': strokes.map((s) => s.toJson()).toList(),
      'images': images.map((img) =>
      {
        'id': img.id,
        'position': [img.position.dx, img.position.dy],
        'size': [img.size.width, img.size.height],
        'rotation': img.rotation,
      }).toList(),
      'options': {
        'strokeColor': '#${options.strokeColor.value
            .toRadixString(16)
            .substring(2)}',
        'size': options.size,
        'showGrid': options.showGrid,
        'fillShape': options.fillShape,
        'polygonSides': options.polygonSides,
        'backgroundColor': '#${options.backgroundColor.value
            .toRadixString(16)
            .substring(2)}',
        'currentTool': options.currentTool
            .toString()
            .split('.')
            .last,
        'opacity': options.opacity,
      },
    };

    await prefs.setString('guest_drawing', jsonEncode(data));
  }

  Future<DrawingData?> _loadFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final dataString = prefs.getString('guest_drawing');

    if (dataString == null) return null;

    try {
      final data = jsonDecode(dataString);

      // Parse strokes
      final strokesList = data['strokes'] as List;
      final strokes = strokesList.map((s) => Stroke.fromJson(s)).toList();

      // Parse options
      final optionsData = data['options'];
      final options = DrawingCanvasOptions(
        strokeColor: DrawingData.parseColor(optionsData['strokeColor']),
        size: optionsData['size'],
        opacity: optionsData['opacity'] ?? 1.0,
        currentTool: DrawingData.parseDrawingTool(optionsData['currentTool']),
        backgroundColor: DrawingData.parseColor(
            optionsData['backgroundColor'] ?? '#FFFFFF'),
        showGrid: optionsData['showGrid'],
        polygonSides: optionsData['polygonSides'],
        fillShape: optionsData['fillShape'],
      );

      // Note: Images are not loaded from local storage as they would need to be stored as base64
      // which is not practical for ui.Image objects

      return DrawingData(
        title: data['title'] ?? 'Untitled',
        strokes: strokes,
        images: [], // Images not persisted in local storage
        options: options,
      );
    } catch (e) {
      print('Error loading from local storage: $e');
      return null;
    }
  }

  // Get last opened drawing ID for user
  Future<String?> getLastOpenedDrawingId() async {
    if (!_authService.isAuthenticated) return null;

    final userId = _authService.currentUser?.id;
    if (userId == null) return null;

    try {
      final response = await _supabase
          .from('drawings')
          .select('id')
          .eq('user_id', userId)
          .order('last_opened_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return response?['id'] as String?;
    } catch (e) {
      print('Error getting last opened drawing: $e');
      return null;
    }
  }

// Create a new drawing - ensure all timestamps are set
  Future<String> createNewDrawing({
    required String title,
    required String userId,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();

      final response = await _supabase.from('drawings').insert({
        'user_id': userId,
        'title': title,
        'created_at': now,
        'updated_at': now,
        'last_opened_at': now, // Set all timestamps on creation
      }).select().single();

      final drawingId = response['id'] as String;

      // Create initial drawing state
      await _supabase.from('drawing_states').insert({
        'drawing_id': drawingId,
        'user_id': userId,
        'canvas_width': OffsetExtensions.standardWidth,
        'canvas_height': OffsetExtensions.standardHeight,
        'background_color': '#FFFFFF',
        'show_grid': false,
        'strokes': [],
        'current_tool': 'pencil',
        'stroke_color': '#000000',
        'stroke_size': 10.0,
        'eraser_size': 30.0,
        'fill_shape': false,
        'polygon_sides': 3,
        'created_at': now,
        'updated_at': now,
      });

      return drawingId;
    } catch (e) {
      print('Error creating new drawing: $e');
      rethrow;
    }
  }
}