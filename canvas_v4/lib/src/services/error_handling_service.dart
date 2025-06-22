// lib/src/services/error_handling_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';

/// Comprehensive error handling service with logging, user feedback, and recovery
class ErrorHandlingService {
  static final ErrorHandlingService _instance = ErrorHandlingService._internal();
  factory ErrorHandlingService() => _instance;
  ErrorHandlingService._internal();

  final StreamController<AppError> _errorController = StreamController<AppError>.broadcast();
  final List<AppError> _errorHistory = [];
  BuildContext? _context;

  /// Stream of errors for listening to error events
  Stream<AppError> get errorStream => _errorController.stream;

  /// Initialize error handling with context for showing dialogs/snackbars
  void initialize(BuildContext context) {
    _context = context;

    // Set up global error handlers
    FlutterError.onError = (FlutterErrorDetails details) {
      handleError(
        AppError.flutter(details.exception, details.stack),
        showToUser: !kReleaseMode, // Only show in debug mode
      );
    };

    // Handle uncaught async errors
    PlatformDispatcher.instance.onError = (error, stack) {
      handleError(
        AppError.uncaught(error, stack),
        showToUser: false, // Don't show raw uncaught errors to users
      );
      return true;
    };
  }

  /// Handle any error with optional user notification and recovery
  Future<void> handleError(
      AppError error, {
        bool showToUser = true,
        bool logError = true,
        VoidCallback? onRetry,
      }) async {
    try {
      // Log error
      if (logError) {
        _logError(error);
      }

      // Add to history
      _errorHistory.add(error);

      // Limit history size
      if (_errorHistory.length > 100) {
        _errorHistory.removeAt(0);
      }

      // Emit error event
      _errorController.add(error);

      // Show to user if requested and context available
      if (showToUser && _context != null) {
        await _showErrorToUser(error, onRetry);
      }

      // Attempt automatic recovery
      await _attemptRecovery(error);

    } catch (e, stack) {
      // Fallback error handling
      debugPrint('Error in error handler: $e\n$stack');
    }
  }

  /// Handle specific error types with appropriate responses
  Future<void> handleNetworkError(dynamic error, {VoidCallback? onRetry}) async {
    final appError = AppError.network(error);
    await handleError(appError, onRetry: onRetry);
  }

  Future<void> handleFileError(dynamic error, {String? filePath}) async {
    final appError = AppError.file(error, filePath: filePath);
    await handleError(appError);
  }

  Future<void> handleCanvasError(dynamic error, {String? operation}) async {
    final appError = AppError.canvas(error, operation: operation);
    await handleError(appError);
  }

  Future<void> handleAuthError(dynamic error) async {
    final appError = AppError.auth(error);
    await handleError(appError);
  }

  Future<void> handleCollaborativeError(dynamic error, {String? sessionId}) async {
    final appError = AppError.collaborative(error, sessionId: sessionId);
    await handleError(appError);
  }

  /// Log error with appropriate level and formatting
  void _logError(AppError error) {
    final timestamp = DateTime.now().toIso8601String();
    final message = '[${error.type.name.toUpperCase()}] $timestamp: ${error.message}';

    if (error.isRecoverable) {
      debugPrint('⚠️ $message');
    } else {
      debugPrint('❌ $message');
    }

    if (error.stackTrace != null) {
      debugPrint('Stack trace:\n${error.stackTrace}');
    }

    if (error.context.isNotEmpty) {
      debugPrint('Context: ${error.context}');
    }
  }

  /// Show error to user via appropriate UI mechanism
  Future<void> _showErrorToUser(AppError error, VoidCallback? onRetry) async {
    if (_context == null) return;

    final message = _getUserFriendlyMessage(error);

    if (error.severity == ErrorSeverity.critical) {
      await _showErrorDialog(error, message, onRetry);
    } else {
      _showErrorSnackBar(message, onRetry);
    }
  }

  /// Show critical error dialog
  Future<void> _showErrorDialog(AppError error, String message, VoidCallback? onRetry) async {
    if (_context == null) return;

    return showDialog<void>(
      context: _context!,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              error.severity == ErrorSeverity.critical ? Icons.error : Icons.warning,
              color: error.severity == ErrorSeverity.critical ? Colors.red : Colors.orange,
            ),
            const SizedBox(width: 8),
            const Text('Error'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (error.isRecoverable) ...[
              const SizedBox(height: 8),
              Text(
                'This error might be temporary. You can try again.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (error.isRecoverable && onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onRetry();
              },
              child: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show error snackbar for less critical errors
  void _showErrorSnackBar(String message, VoidCallback? onRetry) {
    if (_context == null) return;

    ScaffoldMessenger.of(_context!).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: AppConstants.errorDisplayDuration,
        action: onRetry != null
            ? SnackBarAction(
          label: 'Retry',
          onPressed: onRetry,
        )
            : null,
        backgroundColor: AppColors.error,
      ),
    );
  }

  /// Convert technical error to user-friendly message
  String _getUserFriendlyMessage(AppError error) {
    switch (error.type) {
      case ErrorType.network:
        if (error.originalError is SocketException) {
          return 'No internet connection. Please check your network and try again.';
        }
        return ErrorMessages.networkError;

      case ErrorType.file:
        if (error.message.contains('not found')) {
          return ErrorMessages.fileNotFound;
        } else if (error.message.contains('too large')) {
          return ErrorMessages.fileTooLarge;
        }
        return 'File operation failed. Please try again.';

      case ErrorType.auth:
        return ErrorMessages.loginFailed;

      case ErrorType.canvas:
        return 'Drawing operation failed. Please try again.';

      case ErrorType.collaborative:
        return ErrorMessages.collaborativeError;

      case ErrorType.flutter:
      case ErrorType.uncaught:
      default:
        if (kDebugMode) {
          return error.message;
        }
        return ErrorMessages.unknownError;
    }
  }

  /// Attempt automatic error recovery
  Future<void> _attemptRecovery(AppError error) async {
    if (!error.isRecoverable) return;

    try {
      switch (error.type) {
        case ErrorType.network:
        // Could implement network retry logic
          break;
        case ErrorType.file:
        // Could implement file operation retry
          break;
        case ErrorType.canvas:
        // Could implement canvas state recovery
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('Recovery attempt failed: $e');
    }
  }

  /// Get error statistics for debugging
  Map<String, dynamic> getErrorStats() {
    final typeCount = <ErrorType, int>{};
    final severityCount = <ErrorSeverity, int>{};

    for (final error in _errorHistory) {
      typeCount[error.type] = (typeCount[error.type] ?? 0) + 1;
      severityCount[error.severity] = (severityCount[error.severity] ?? 0) + 1;
    }

    return {
      'totalErrors': _errorHistory.length,
      'errorsByType': typeCount.map((k, v) => MapEntry(k.name, v)),
      'errorsBySeverity': severityCount.map((k, v) => MapEntry(k.name, v)),
      'recentErrors': _errorHistory.take(10).map((e) => {
        'type': e.type.name,
        'message': e.message,
        'timestamp': e.timestamp.toIso8601String(),
      }).toList(),
    };
  }

  /// Clear error history
  void clearHistory() {
    _errorHistory.clear();
  }

  /// Dispose resources
  void dispose() {
    _errorController.close();
    _errorHistory.clear();
  }
}

/// Structured error class for better error handling
class AppError {
  final ErrorType type;
  final ErrorSeverity severity;
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;
  final DateTime timestamp;
  final Map<String, dynamic> context;
  final bool isRecoverable;

  AppError({
    required this.type,
    required this.severity,
    required this.message,
    this.originalError,
    this.stackTrace,
    DateTime? timestamp,
    Map<String, dynamic>? context,
    this.isRecoverable = true,
  }) : timestamp = timestamp ?? DateTime.now(),
        context = context ?? {};

  // Factory constructors for different error types
  factory AppError.network(dynamic error, {StackTrace? stack}) {
    return AppError(
      type: ErrorType.network,
      severity: ErrorSeverity.warning,
      message: 'Network error: ${error.toString()}',
      originalError: error,
      stackTrace: stack,
      isRecoverable: true,
    );
  }

  factory AppError.file(dynamic error, {String? filePath, StackTrace? stack}) {
    return AppError(
      type: ErrorType.file,
      severity: ErrorSeverity.warning,
      message: 'File error: ${error.toString()}',
      originalError: error,
      stackTrace: stack,
      context: filePath != null ? {'filePath': filePath} : {},
      isRecoverable: true,
    );
  }

  factory AppError.auth(dynamic error, {StackTrace? stack}) {
    return AppError(
      type: ErrorType.auth,
      severity: ErrorSeverity.high,
      message: 'Authentication error: ${error.toString()}',
      originalError: error,
      stackTrace: stack,
      isRecoverable: false,
    );
  }

  factory AppError.canvas(dynamic error, {String? operation, StackTrace? stack}) {
    return AppError(
      type: ErrorType.canvas,
      severity: ErrorSeverity.warning,
      message: 'Canvas error: ${error.toString()}',
      originalError: error,
      stackTrace: stack,
      context: operation != null ? {'operation': operation} : {},
      isRecoverable: true,
    );
  }

  factory AppError.collaborative(dynamic error, {String? sessionId, StackTrace? stack}) {
    return AppError(
      type: ErrorType.collaborative,
      severity: ErrorSeverity.high,
      message: 'Collaborative error: ${error.toString()}',
      originalError: error,
      stackTrace: stack,
      context: sessionId != null ? {'sessionId': sessionId} : {},
      isRecoverable: true,
    );
  }

  factory AppError.flutter(dynamic error, StackTrace? stack) {
    return AppError(
      type: ErrorType.flutter,
      severity: ErrorSeverity.critical,
      message: 'Flutter error: ${error.toString()}',
      originalError: error,
      stackTrace: stack,
      isRecoverable: false,
    );
  }

  factory AppError.uncaught(dynamic error, StackTrace? stack) {
    return AppError(
      type: ErrorType.uncaught,
      severity: ErrorSeverity.critical,
      message: 'Uncaught error: ${error.toString()}',
      originalError: error,
      stackTrace: stack,
      isRecoverable: false,
    );
  }
}

enum ErrorType {
  network,
  file,
  auth,
  canvas,
  collaborative,
  flutter,
  uncaught,
}

enum ErrorSeverity {
  low,
  warning,
  high,
  critical,
}