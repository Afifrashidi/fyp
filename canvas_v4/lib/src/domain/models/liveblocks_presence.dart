import 'package:flutter/material.dart';

/// Represents user presence in a collaborative session
/// Combines all properties from both collaborative drawing implementations
class LiveblocksPresence {
  final String userId;
  final String userName;
  final Offset? cursor;
  final int? color; // Integer color value (from liveblocks_collaborative_drawing_page)
  final String? userColor; // String color value (from collaborative_drawing_page)
  final bool isDrawing;
  final String selectedTool;
  final double strokeSize;
  final String strokeColor;
  final DateTime? lastSeen;
  final Map<String, dynamic>? metadata;

  const LiveblocksPresence({
    required this.userId,
    required this.userName,
    this.cursor,
    this.color,
    this.userColor,
    this.isDrawing = false,
    this.selectedTool = 'pencil',
    this.strokeSize = 10.0,
    this.strokeColor = '#000000',
    this.lastSeen,
    this.metadata,
  });

  /// Factory constructor that handles both JSON formats
  factory LiveblocksPresence.fromJson(Map<String, dynamic> json) {
    return LiveblocksPresence(
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? 'Anonymous',
      cursor: json['cursor'] != null
          ? Offset(
        (json['cursor']['x'] as num).toDouble(),
        (json['cursor']['y'] as num).toDouble(),
      )
          : null,
      color: json['color'] as int?,
      userColor: json['userColor'] as String?,
      isDrawing: json['isDrawing'] ?? false,
      selectedTool: json['selectedTool'] ?? 'pencil',
      strokeSize: (json['strokeSize'] as num?)?.toDouble() ?? 10.0,
      strokeColor: json['strokeColor'] ?? '#000000',
      lastSeen: json['lastSeen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Convert to JSON with all properties
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'cursor': cursor != null ? {'x': cursor!.dx, 'y': cursor!.dy} : null,
      'color': color,
      'userColor': userColor,
      'isDrawing': isDrawing,
      'selectedTool': selectedTool,
      'strokeSize': strokeSize,
      'strokeColor': strokeColor,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
      'metadata': metadata,
    };
  }

  /// Create a copy with updated properties
  LiveblocksPresence copyWith({
    String? userId,
    String? userName,
    Offset? cursor,
    int? color,
    String? userColor,
    bool? isDrawing,
    String? selectedTool,
    double? strokeSize,
    String? strokeColor,
    DateTime? lastSeen,
    Map<String, dynamic>? metadata,
  }) {
    return LiveblocksPresence(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      cursor: cursor ?? this.cursor,
      color: color ?? this.color,
      userColor: userColor ?? this.userColor,
      isDrawing: isDrawing ?? this.isDrawing,
      selectedTool: selectedTool ?? this.selectedTool,
      strokeSize: strokeSize ?? this.strokeSize,
      strokeColor: strokeColor ?? this.strokeColor,
      lastSeen: lastSeen ?? this.lastSeen,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Get the effective color (prioritizes color over userColor)
  Color getEffectiveColor() {
    if (color != null) {
      return Color(color!);
    }

    if (userColor != null) {
      return _parseColorString(userColor!);
    }

    return Colors.grey;
  }

  /// Parse color string to Color object
  Color _parseColorString(String colorString) {
    try {
      if (colorString.startsWith('#')) {
        final hex = colorString.replaceFirst('#', '');
        return Color(int.parse('FF$hex', radix: 16));
      }

      // Handle integer color values as strings
      final intValue = int.tryParse(colorString);
      if (intValue != null) {
        return Color(intValue);
      }
    } catch (e) {
      // Fallback to grey if parsing fails
    }

    return Colors.grey;
  }

  /// Check if user is currently active
  bool get isActive {
    if (lastSeen == null) return true;
    final now = DateTime.now();
    final difference = now.difference(lastSeen!);
    return difference.inSeconds < 30; // Consider active if seen within 30 seconds
  }

  /// Get display name with fallback
  String get displayName {
    if (userName.isNotEmpty && userName != 'Anonymous') {
      return userName;
    }
    return 'User ${userId.substring(0, 8)}';
  }

  @override
  String toString() {
    return 'LiveblocksPresence(userId: $userId, userName: $userName, isDrawing: $isDrawing, cursor: $cursor)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LiveblocksPresence &&
        other.userId == userId &&
        other.userName == userName &&
        other.cursor == cursor &&
        other.color == color &&
        other.userColor == userColor &&
        other.isDrawing == isDrawing &&
        other.selectedTool == selectedTool &&
        other.strokeSize == strokeSize &&
        other.strokeColor == strokeColor;
  }

  @override
  int get hashCode {
    return Object.hash(
      userId,
      userName,
      cursor,
      color,
      userColor,
      isDrawing,
      selectedTool,
      strokeSize,
      strokeColor,
    );
  }
}