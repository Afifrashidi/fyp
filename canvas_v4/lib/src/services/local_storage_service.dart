// lib/src/services/local_storage_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/canvas_operations_enums.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_drawing_board/src/domain/domain.dart';

class LocalStorageService {
  static const String _guestDrawingKey = 'guest_drawing';
  static const String _guestDrawingsListKey = 'guest_drawings_list';
  static const String _settingsKey = 'app_settings';
  static const String _lastSessionKey = 'last_session';

  // Singleton pattern
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  late SharedPreferences _prefs;
  bool _initialized = false;

  /// Initialize the service
  Future<void> initialize() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }

  /// Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  /// Save guest drawing
  Future<bool> saveGuestDrawing({
    required String title,
    required List<Stroke> strokes,
    required DrawingCanvasOptions options,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _ensureInitialized();

      final drawingData = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': title,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'strokes': strokes.map((s) => s.toJson()).toList(),
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
        'metadata': metadata ?? {},
      };

      // Save to current drawing slot
      await _prefs.setString(_guestDrawingKey, jsonEncode(drawingData));

      // Add to drawings list
      await _addToGuestDrawingsList(drawingData);

      return true;
    } catch (e) {
      debugPrint('Error saving guest drawing: $e');
      return false;
    }
  }

  /// Load guest drawing
  Future<GuestDrawingData?> loadGuestDrawing() async {
    try {
      await _ensureInitialized();

      final dataString = _prefs.getString(_guestDrawingKey);
      if (dataString == null) return null;

      final data = jsonDecode(dataString);
      return GuestDrawingData.fromJson(data);
    } catch (e) {
      debugPrint('Error loading guest drawing: $e');
      return null;
    }
  }

  /// Get all guest drawings
  Future<List<GuestDrawingMetadata>> getGuestDrawings() async {
    try {
      await _ensureInitialized();

      final listString = _prefs.getString(_guestDrawingsListKey);
      if (listString == null) return [];

      final List<dynamic> list = jsonDecode(listString);
      return list
          .map((item) => GuestDrawingMetadata.fromJson(item))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Error getting guest drawings: $e');
      return [];
    }
  }

  /// Add drawing to list
  Future<void> _addToGuestDrawingsList(Map<String, dynamic> drawingData) async {
    try {
      final listString = _prefs.getString(_guestDrawingsListKey);
      final List<dynamic> list = listString != null ? jsonDecode(listString) : [];

      // Create metadata entry
      final metadata = {
        'id': drawingData['id'],
        'title': drawingData['title'],
        'created_at': drawingData['created_at'],
        'updated_at': drawingData['updated_at'],
        'stroke_count': (drawingData['strokes'] as List).length,
      };

      // Remove if already exists (update case)
      list.removeWhere((item) => item['id'] == metadata['id']);

      // Add to beginning of list
      list.insert(0, metadata);

      // Keep only last 10 drawings for guest users
      if (list.length > 10) {
        list.removeRange(10, list.length);
      }

      await _prefs.setString(_guestDrawingsListKey, jsonEncode(list));
    } catch (e) {
      debugPrint('Error adding to guest drawings list: $e');
    }
  }

  /// Load specific guest drawing by ID
  Future<GuestDrawingData?> loadGuestDrawingById(String id) async {
    try {
      await _ensureInitialized();

      // For simplicity, we're only storing the current drawing
      // In a real app, you might want to store multiple drawings
      final current = await loadGuestDrawing();
      if (current?.id == id) return current;

      return null;
    } catch (e) {
      debugPrint('Error loading guest drawing by ID: $e');
      return null;
    }
  }

  /// Delete guest drawing
  Future<bool> deleteGuestDrawing(String id) async {
    try {
      await _ensureInitialized();

      // Clear current drawing if it matches
      final current = await loadGuestDrawing();
      if (current?.id == id) {
        await _prefs.remove(_guestDrawingKey);
      }

      // Remove from list
      final listString = _prefs.getString(_guestDrawingsListKey);
      if (listString != null) {
        final List<dynamic> list = jsonDecode(listString);
        list.removeWhere((item) => item['id'] == id);
        await _prefs.setString(_guestDrawingsListKey, jsonEncode(list));
      }

      return true;
    } catch (e) {
      debugPrint('Error deleting guest drawing: $e');
      return false;
    }
  }

  /// Clear all guest data
  Future<bool> clearAllGuestData() async {
    try {
      await _ensureInitialized();
      await _prefs.remove(_guestDrawingKey);
      await _prefs.remove(_guestDrawingsListKey);
      return true;
    } catch (e) {
      debugPrint('Error clearing guest data: $e');
      return false;
    }
  }

  /// Save app settings
  Future<bool> saveSettings(Map<String, dynamic> settings) async {
    try {
      await _ensureInitialized();
      await _prefs.setString(_settingsKey, jsonEncode(settings));
      return true;
    } catch (e) {
      debugPrint('Error saving settings: $e');
      return false;
    }
  }

  /// Load app settings
  Future<Map<String, dynamic>?> loadSettings() async {
    try {
      await _ensureInitialized();
      final settingsString = _prefs.getString(_settingsKey);
      if (settingsString == null) return null;
      return jsonDecode(settingsString);
    } catch (e) {
      debugPrint('Error loading settings: $e');
      return null;
    }
  }

  /// Save last session info
  Future<void> saveLastSession({
    required String type,
    String? sessionId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _ensureInitialized();
      await _prefs.setString(_lastSessionKey, jsonEncode({
        'type': type,
        'sessionId': sessionId,
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': metadata ?? {},
      }));
    } catch (e) {
      debugPrint('Error saving last session: $e');
    }
  }

  /// Get last session info
  Future<Map<String, dynamic>?> getLastSession() async {
    try {
      await _ensureInitialized();
      final sessionString = _prefs.getString(_lastSessionKey);
      if (sessionString == null) return null;
      return jsonDecode(sessionString);
    } catch (e) {
      debugPrint('Error getting last session: $e');
      return null;
    }
  }
}

/// Data model for guest drawings
class GuestDrawingData {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Stroke> strokes;
  final DrawingCanvasOptions options;
  final Map<String, dynamic> metadata;

  GuestDrawingData({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.strokes,
    required this.options,
    this.metadata = const {},
  });

  factory GuestDrawingData.fromJson(Map<String, dynamic> json) {
    // Parse strokes
    final strokesList = json['strokes'] as List;
    final strokes = strokesList.map((s) => Stroke.fromJson(s)).toList();

    // Parse options
    final optionsData = json['options'];
    final options = DrawingCanvasOptions(
      strokeColor: _parseColor(optionsData['strokeColor']),
      size: optionsData['size']?.toDouble() ?? 10.0,
      opacity: optionsData['opacity']?.toDouble() ?? 1.0,
      currentTool: _parseDrawingTool(optionsData['currentTool']),
      backgroundColor: _parseColor(optionsData['backgroundColor'] ?? '#FFFFFF'),
      showGrid: optionsData['showGrid'] ?? false,
      polygonSides: optionsData['polygonSides'] ?? 3,
      fillShape: optionsData['fillShape'] ?? false,
    );

    return GuestDrawingData(
      id: json['id'],
      title: json['title'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      strokes: strokes,
      options: options,
      metadata: json['metadata'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'strokes': strokes.map((s) => s.toJson()).toList(),
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
      'metadata': metadata,
    };
  }

  static Color _parseColor(String colorString) {
    final hex = colorString.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  static DrawingTool _parseDrawingTool(String toolName) {
    switch (toolName) {
      case 'pencil':
        return DrawingTool.pencil;
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
        return DrawingTool.imageManipulator;
      default:
        return DrawingTool.pencil;
    }
  }
}

/// Metadata for guest drawing list
class GuestDrawingMetadata {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int strokeCount;

  GuestDrawingMetadata({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.strokeCount,
  });

  factory GuestDrawingMetadata.fromJson(Map<String, dynamic> json) {
    return GuestDrawingMetadata(
      id: json['id'],
      title: json['title'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      strokeCount: json['stroke_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'stroke_count': strokeCount,
    };
  }
}

// Guest mode reminder dialog
class GuestModeReminder {
  static void showReminder(BuildContext context, {VoidCallback? onSignIn}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('Guest Mode Reminder'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You\'re using the app in guest mode. Your drawings:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Are saved locally on this device only'),
            const Text('• Cannot be accessed from other devices'),
            const Text('• May be lost if you clear app data'),
            const Text('• Are limited to 10 drawings'),
            const SizedBox(height: 16),
            const Text('Sign in to save unlimited drawings to the cloud!'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue as Guest'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onSignIn?.call();
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }
}

// Guest exit dialog
class GuestExitDialog extends StatelessWidget {
  const GuestExitDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unsaved Guest Drawing'),
      content: const Text(
        'You have unsaved changes in guest mode. '
            'These changes will be lost if you exit. '
            'Sign in to save your work permanently.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Exit Anyway', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}