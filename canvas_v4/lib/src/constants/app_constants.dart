// lib/src/constants/app_constants.dart

import 'package:flutter/material.dart';

/// Application-wide constants to eliminate magic numbers and centralize configuration
class AppConstants {
  // Prevent instantiation
  AppConstants._();

  // App Information
  static const String appName = "Let's Draw";
  static const String appVersion = "1.0.0";

  // Canvas Configuration
  static const double standardCanvasWidth = 800.0;
  static const double standardCanvasHeight = 600.0;

  // Stroke Configuration
  static const double minStrokeSize = 1.0;
  static const double maxStrokeSize = 50.0;
  static const double defaultStrokeSize = 10.0;
  static const double defaultOpacity = 1.0;

  // Text Configuration
  static const double minFontSize = 8.0;
  static const double maxFontSize = 72.0;
  static const double defaultFontSize = 16.0;
  static const String defaultFontFamily = 'Inter';

  // Eraser Configuration
  static const double minEraserSize = 5.0;
  static const double maxEraserSize = 100.0;
  static const double defaultEraserSize = 30.0;

  // Grid Configuration
  static const double gridSpacing = 50.0;
  static const double subGridSpacing = 10.0;
  static const double gridOpacity = 0.1;
  static const double subGridOpacity = 0.05;
  static const double gridStrokeWidth = 1.0;
  static const double subGridStrokeWidth = 0.5;
  static const double gridSnapTolerance = 10.0;

  // Polygon Configuration
  static const int minPolygonSides = 3;
  static const int maxPolygonSides = 8;
  static const int defaultPolygonSides = 3;

  // Cache Configuration
  static const int maxPictureCacheSize = 20;
  static const Duration pictureCacheExpiration = Duration(minutes: 3);
  static const Duration cacheCleanupInterval = Duration(seconds: 30);

  // Network Configuration - ADDED MISSING CONSTANTS
  static const Duration networkTimeout = Duration(seconds: 10);
  static const int maxRetryAttempts = 3;
  static const Duration retryDelay = Duration(seconds: 1);

  // Collaborative Configuration - ADDED MISSING CONSTANTS
  static const Duration cursorThrottleDuration = Duration(milliseconds: 50);
  static const Duration strokeBroadcastDebounce = Duration(milliseconds: 16);
  static const Duration presenceUpdateInterval = Duration(milliseconds: 100);
  static const Duration sideBarAnimationDuration = Duration(milliseconds: 300);
  static const int maxCollaborativeUsers = 20;

  // Animation and UI Constants
  static const Duration defaultAnimationDuration = Duration(milliseconds: 250);
  static const Duration shortAnimationDuration = Duration(milliseconds: 150);
  static const Duration longAnimationDuration = Duration(milliseconds: 500);

  // Collaborative Session Constants
  static const int maxCollaborators = 10;
  static const int maxRoomNameLength = 50;
  static const int maxMessageQueueSize = 100;
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration heartbeatInterval = Duration(seconds: 45);
  static const Duration reconnectDelay = Duration(seconds: 2);
  static const int maxReconnectAttempts = 5;

  // Image Upload Constants
  static const int maxImageSizeMB = 10;
  static const int maxImageWidth = 4096;
  static const int maxImageHeight = 4096;
  static const int thumbnailSize = 200;
  static const double imageCompressionQuality = 0.8;

  // Real-time Update Constants
  static const Duration strokeSyncInterval = Duration(milliseconds: 50);
  static const Duration imageSyncInterval = Duration(milliseconds: 200);
  static const Duration presenceSyncInterval = Duration(milliseconds: 300);
  static const int maxStrokesPerBatch = 10;

  // Cache and Performance Constants
  static const int maxCachedImages = 50;
  static const int maxUndoSteps = 100;
  static const int maxMemoryUsageMB = 200;

  // Network and Retry Constants
  static const Duration uploadTimeout = Duration(seconds: 30);
  static const Duration downloadTimeout = Duration(seconds: 15);
  static const Duration retryBaseDelay = Duration(seconds: 1);

  // Gesture Recognition Constants
  static const double tapTolerance = 5.0;
  static const double dragThreshold = 10.0;
  static const double pinchThreshold = 0.1;
  static const Duration longPressDelay = Duration(milliseconds: 500);
  static const Duration doubleTapTimeout = Duration(milliseconds: 300); // milliseconds

  // Canvas Limits and Validation
  static const double maxCanvasWidth = 8192.0;
  static const double maxCanvasHeight = 8192.0;
  static const int maxStrokesPerCanvas = 10000;
  static const int maxImagesPerCanvas = 100;

  // Text Tool Constants
  static const double minTextSize = 8.0;
  static const double maxTextSize = 128.0;
  static const double defaultTextSize = 16.0;
  static const int maxTextLength = 1000;

  // Export and Save Constants
  static const double exportQuality = 1.0;
  static const String defaultExportFormat = 'png';
  static const List<String> supportedExportFormats = ['png', 'jpg', 'pdf', 'svg'];
  static const Duration autoSaveInterval = Duration(minutes: 2);

  // Collaborative Room Constants
  static const String defaultRoomPrefix = 'room_';
  static const int roomIdLength = 8;
  static const Duration roomInactivityTimeout = Duration(hours: 24);
  static const int maxRoomsPerUser = 10;

  // WebSocket Constants
  static const Duration websocketPingInterval = Duration(seconds: 30);
  static const Duration websocketReconnectTimeout = Duration(seconds: 5);
  static const int maxWebsocketMessageSize = 1048576; // 1MB

  // Performance Monitoring Constants
  static const int performanceMetricsBufferSize = 100;
  static const Duration metricsReportInterval = Duration(minutes: 1);
  static const double targetFrameRate = 60.0;

  // Collaborative Cursor Constants
  static const double cursorSize = 20.0;
  static const double cursorLabelPadding = 8.0;
  static const Duration cursorFadeoutDelay = Duration(seconds: 3);
  static const double cursorOpacity = 0.8;

  // Stroke Optimization Constants
  static const double strokeSimplificationTolerance = 1.0;
  static const int maxPointsPerStroke = 1000;
  static const double minStrokeDistance = 0.5;

  // Image Processing Constants
  static const double maxImageScaleFactor = 5.0;
  static const double minImageScaleFactor = 0.1;
  static const int imageLoadingBufferSize = 4;

  // Error Recovery Constants
  static const Duration errorRecoveryDelay = Duration(seconds: 1);
  static const int maxErrorRetries = 3;
  static const Duration errorDisplayDuration = Duration(seconds: 5);

  // Validation Constants
  static const int minPasswordLength = 8;
  static const int maxUsernameLength = 30;
  static const int maxRoomDescriptionLength = 200;

  // Interaction Configuration
  static const double imageSelectionTolerance = 5.0;

  // Performance Limits
  static const int maxVisibleStrokes = 5000;
  static const double minZoom = 0.1;
  static const double maxZoom = 10.0;
  static const int maxUndoOperations = 100;

  // Storage Keys
  static const String guestDrawingKey = 'guest_drawing';
  static const String guestDrawingsListKey = 'guest_drawings_list';
  static const String settingsKey = 'app_settings';
  static const String userPreferencesKey = 'user_preferences';
  static const String customColorsKey = 'custom_colors';
}

/// Color constants for consistent theming
class AppColors {
  AppColors._();

  // Canvas colors
  static const Color canvasBackground = Color(0xFFFAFAFA);
  static const Color canvasBorder = Color(0xFFE0E0E0);

  // Tool selection colors
  static const Color selectedTool = Color(0xFFE3F2FD);
  static const Color selectedToolBorder = Color(0xFF1976D2);
  static const Color unselectedTool = Colors.transparent;
  static const Color unselectedToolBorder = Color(0xFFBDBDBD);

  // Grid colors
  static Color gridMain = Colors.black.withOpacity(AppConstants.gridOpacity);
  static Color gridSub = Colors.grey.withOpacity(AppConstants.subGridOpacity);

  // Selection colors
  static const Color selectionBorder = Color(0xFF2196F3);
  static const Color selectionBackground = Color(0x1A2196F3);
  static const Color selectionHandle = Color(0xFF1976D2);

  // Status colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Text colors
  static const Color primaryText = Color(0xFF212121);
  static const Color secondaryText = Color(0xFF757575);
  static const Color hintText = Color(0xFFBDBDBD);

  // Default stroke colors palette
  static const List<Color> defaultPalette = [
    Colors.black,
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.cyan,
    Colors.brown,
    Colors.grey,
    Colors.white,
  ];
}

/// Keyboard shortcuts mapping
class AppShortcuts {
  AppShortcuts._();

  // Drawing tools
  static const String pencil = 'P';
  static const String line = 'L';
  static const String rectangle = 'R';
  static const String square = 'S';
  static const String circle = 'C';
  static const String text = 'T';
  static const String eraser = 'E';
  static const String selector = 'V';
  static const String pointer = 'M';

  // Actions
  static const String undo = 'Ctrl+Z';
  static const String redo = 'Ctrl+Y';
  static const String save = 'Ctrl+S';
  static const String open = 'Ctrl+O';
  static const String newDrawing = 'Ctrl+N';
  static const String export = 'Ctrl+E';
  static const String clearAll = 'Ctrl+Delete';
  static const String resetImage = 'Ctrl+R';

  // View
  static const String toggleGrid = 'G';
  static const String toggleSnapToGrid = 'Shift+G';
  static const String zoomIn = 'Ctrl++';
  static const String zoomOut = 'Ctrl+-';
  static const String resetZoom = 'Ctrl+0';

  // Selection
  static const String selectAll = 'Ctrl+A';
  static const String delete = 'Delete';
  static const String escape = 'Esc';
}

/// Error messages for consistent error handling
class ErrorMessages {
  ErrorMessages._();

  // Authentication errors
  static const String authRequired = 'Authentication required to perform this action';
  static const String loginFailed = 'Login failed. Please check your credentials.';
  static const String sessionExpired = 'Session expired. Please log in again.';

  // File operation errors
  static const String fileNotFound = 'File not found';
  static const String fileTooLarge = 'File size exceeds maximum limit';
  static const String unsupportedFormat = 'Unsupported file format';
  static const String saveError = 'Failed to save drawing';
  static const String loadError = 'Failed to load drawing';

  // Network errors
  static const String networkError = 'Network connection error';
  static const String serverError = 'Server error occurred';
  static const String timeoutError = 'Operation timed out';

  // Canvas errors
  static const String canvasError = 'Canvas rendering error';
  static const String strokeError = 'Failed to create stroke';
  static const String imageError = 'Failed to load image';

  // Collaborative errors
  static const String collaborativeError = 'Collaborative session error';
  static const String connectionLost = 'Connection to collaborative session lost';
  static const String sessionNotFound = 'Collaborative session not found';
  static const String roomIdNull = 'Cannot upload image: Not connected to a collaborative session';

  // General errors
  static const String unknownError = 'An unknown error occurred';
  static const String operationCancelled = 'Operation cancelled';
  static const String insufficientPermissions = 'Insufficient permissions';
}

/// Success messages for user feedback
class SuccessMessages {
  SuccessMessages._();

  static const String drawingSaved = 'Drawing saved successfully';
  static const String drawingLoaded = 'Drawing loaded successfully';
  static const String drawingExported = 'Drawing exported successfully';
  static const String imageAdded = 'Image added to canvas';
  static const String imageReset = 'Image reset to original transform';
  static const String canvasCleared = 'Canvas cleared';
  static const String collaborativeJoined = 'Joined collaborative session';
  static const String settingsSaved = 'Settings saved';
  static const String colorAdded = 'Custom color added';
}

/// Development and debugging constants - ADDED MISSING CLASS
class DebugConfig {
  DebugConfig._();

  static const bool enablePerformanceOverlay = false;
  static const bool enableMemoryDebugging = false;
  static const bool enableNetworkLogging = false;
  static const bool enableCacheDebugging = false;
  static const bool showDebugInfo = false;

  // Logging levels - ADDED MISSING logVerbose
  static const bool logErrors = true;
  static const bool logWarnings = true;
  static const bool logInfo = false;
  static const bool logVerbose = false;
}

