// lib/src/domain/models/drawing_data.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_drawing_board/src/domain/domain.dart';

class DrawingData {
  final String? id;
  final String title;
  final List<Stroke> strokes;
  final List<CanvasImage> images;
  final DrawingCanvasOptions options;
  final ui.Image? backgroundImage;
  final DateTime? lastSaved;
  final bool isCollaborative; // Added for collaborative support
  final String? sessionId; // Added for collaborative support

  DrawingData({
    this.id,
    required this.title,
    required this.strokes,
    required this.images,
    required this.options,
    this.backgroundImage,
    this.lastSaved,
    this.isCollaborative = false, // Default to non-collaborative
    this.sessionId,
  });

  // This now returns a Future because we need to load images asynchronously
  static Future<DrawingData> fromDatabase(
      Map<String, dynamic> drawing,
      Map<String, dynamic> state,
      List<Map<String, dynamic>> images,
      ) async {
    // Parse strokes from JSON
    final strokesJson = state['strokes'] as List;
    final strokes = strokesJson.map((s) => Stroke.fromJson(s)).toList();

    // Load images asynchronously from Supabase
    final canvasImages = <CanvasImage>[];
    for (final img in images) {
      // Use the 'url' column instead of 'image_url'
      final uiImage = await _loadImageFromSupabaseUrl(img['url']);
      if (uiImage != null) {
        // Create transform matrix from position, size, and rotation
        final transform = Matrix4.identity();

        // Apply translation (position)
        transform.translate(img['position_x'], img['position_y']);

        // Apply rotation if needed
        if (img['rotation'] != 0) {
          transform.rotateZ(img['rotation']);
        }

        // Apply scaling (size)
        final scaleX = img['size_width'] / uiImage.width;
        final scaleY = img['size_height'] / uiImage.height;
        transform.scale(scaleX, scaleY);

        canvasImages.add(CanvasImage(
          id: img['id'].toString(),
          image: uiImage,
          transform: transform,
        ));
      }
    }

    // Create options with all required fields
    final options = DrawingCanvasOptions(
      strokeColor: _parseColor(state['stroke_color']),
      size: state['stroke_size'],
      opacity: 1.0, // Default opacity since it's not in database
      currentTool: _parseDrawingTool(state['current_tool']),
      backgroundColor: _parseColor(state['background_color']),
      showGrid: state['show_grid'],
      polygonSides: state['polygon_sides'],
      fillShape: state['fill_shape'],
    );

    return DrawingData(
      id: drawing['id'],
      title: drawing['title'],
      strokes: strokes,
      images: canvasImages,
      options: options,
      lastSaved: DateTime.parse(state['updated_at']),
      isCollaborative: drawing['is_collaborative'] ?? false,
      sessionId: drawing['session_id'],
    );
  }

// Update image loading in drawing_data.dart
  static Future<ui.Image?> _loadImageFromSupabaseUrl(String url) async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      final headers = <String, String>{};

      if (session != null) {
        headers['Authorization'] = 'Bearer ${session.accessToken}';
      }

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(response.bodyBytes);
        final frame = await codec.getNextFrame();
        return frame.image;
      } else {
        debugPrint('Failed to load image: HTTP ${response.statusCode}');
        return null;
      }
    } on TimeoutException {
      debugPrint('Image loading timeout: $url');
      return null;
    } catch (e) {
      debugPrint('Error loading image from Supabase URL: $e');
      return null;
    }
  }

  // Add this method to parse the drawing tool from string
  static DrawingTool _parseDrawingTool(String toolName) {
    switch (toolName) {
      case 'pencil':
        return DrawingTool.pencil;
      case 'fill':
        return DrawingTool.fill;
      case 'line':
        return DrawingTool.line;
      case 'eraser':
        return DrawingTool.eraser;
      case 'polygon':
        return DrawingTool.polygon;
      case 'square':
        return DrawingTool.square;
      case 'circle':
        return DrawingTool.circle;
      case 'pointer':
        return DrawingTool.pointer;
      default:
        return DrawingTool.pencil; // Default to pencil if unknown
    }
  }

  // Helper method to parse color from #FFFFFF format
  static Color _parseColor(String colorString) {
    // Remove the # if present and parse the hex value
    final hex = colorString.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  // Public static methods for external use
  static DrawingTool parseDrawingTool(String toolName) => _parseDrawingTool(toolName);
  static Color parseColor(String colorString) => _parseColor(colorString);

  // Add copyWith method for easy updates
  DrawingData copyWith({
    String? id,
    String? title,
    List<Stroke>? strokes,
    List<CanvasImage>? images,
    DrawingCanvasOptions? options,
    ui.Image? backgroundImage,
    DateTime? lastSaved,
    bool? isCollaborative,
    String? sessionId,
  }) {
    return DrawingData(
      id: id ?? this.id,
      title: title ?? this.title,
      strokes: strokes ?? this.strokes,
      images: images ?? this.images,
      options: options ?? this.options,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      lastSaved: lastSaved ?? this.lastSaved,
      isCollaborative: isCollaborative ?? this.isCollaborative,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  // Add toJson method for serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'strokes': strokes.map((s) => s.toJson()).toList(),
      'images': images.map((img) => {
        'id': img.id,
        'position': [img.position.dx, img.position.dy],
        'size': [img.size.width, img.size.height],
        'rotation': img.rotation,
      }).toList(),
      'options': {
        'strokeColor': '#${options.strokeColor.value.toRadixString(16).substring(2)}',
        'size': options.size,
        'opacity': options.opacity,
        'currentTool': options.currentTool.toString().split('.').last,
        'backgroundColor': '#${options.backgroundColor.value.toRadixString(16).substring(2)}',
        'showGrid': options.showGrid,
        'polygonSides': options.polygonSides,
        'fillShape': options.fillShape,
      },
      'lastSaved': lastSaved?.toIso8601String(),
      'isCollaborative': isCollaborative,
      'sessionId': sessionId,
    };
  }
}

class DrawingMetadata {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastOpenedAt;
  final bool starred;
  final bool isPublic;
  final List<String> tags;
  final bool isCollaborative; // Added for collaborative support
  final String? sessionId; // Added for collaborative support

  DrawingMetadata({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.lastOpenedAt,
    this.starred = false,
    this.isPublic = false,
    this.tags = const [],
    this.isCollaborative = false,
    this.sessionId,
  });

  factory DrawingMetadata.fromJson(Map<String, dynamic> json) {
    // Handle the nested drawing_states data
    final drawingStatesData = json['drawing_states'];
    String updatedAt;

    if (drawingStatesData is Map) {
      updatedAt = drawingStatesData['updated_at'];
    } else if (drawingStatesData is List && drawingStatesData.isNotEmpty) {
      updatedAt = drawingStatesData.first['updated_at'];
    } else {
      // Fallback to last_opened_at or created_at
      updatedAt = json['last_opened_at'] ?? json['created_at'];
    }

    return DrawingMetadata(
      id: json['id'],
      title: json['title'] ?? 'Untitled',
      thumbnailUrl: json['thumbnail_url'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(updatedAt),
      lastOpenedAt: DateTime.parse(json['last_opened_at'] ?? json['created_at']),
      starred: json['starred'] ?? false,
      isPublic: json['is_public'] ?? false,
      tags: List<String>.from(json['tags'] ?? []),
      isCollaborative: json['is_collaborative'] ?? false,
      sessionId: json['session_id'],
    );
  }

  // Add copyWith method for easy updates
  DrawingMetadata copyWith({
    String? id,
    String? title,
    String? thumbnailUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastOpenedAt,
    bool? starred,
    bool? isPublic,
    List<String>? tags,
    bool? isCollaborative,
    String? sessionId,
  }) {
    return DrawingMetadata(
      id: id ?? this.id,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      starred: starred ?? this.starred,
      isPublic: isPublic ?? this.isPublic,
      tags: tags ?? this.tags,
      isCollaborative: isCollaborative ?? this.isCollaborative,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  // Add toJson method for serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'thumbnail_url': thumbnailUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_opened_at': lastOpenedAt.toIso8601String(),
      'starred': starred,
      'is_public': isPublic,
      'tags': tags,
      'is_collaborative': isCollaborative,
      'session_id': sessionId,
    };
  }
}