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