import 'dart:ui';
import 'package:flutter/material.dart';

/// Types of errors that can occur in the application
enum ErrorType {
  network,
  file,
  auth,
  canvas,
  collaborative,
  flutter,
  uncaught;

  String get displayName {
    switch (this) {
      case ErrorType.network: return 'Network Error';
      case ErrorType.file: return 'File Error';
      case ErrorType.auth: return 'Authentication Error';
      case ErrorType.canvas: return 'Canvas Error';
      case ErrorType.collaborative: return 'Collaboration Error';
      case ErrorType.flutter: return 'App Error';
      case ErrorType.uncaught: return 'Unexpected Error';
    }
  }
}

/// Severity levels for errors
enum ErrorSeverity {
  low,
  warning,
  high,
  critical;

  Color get color {
    switch (this) {
      case ErrorSeverity.low: return Colors.blue;
      case ErrorSeverity.warning: return Colors.orange;
      case ErrorSeverity.high: return Colors.red;
      case ErrorSeverity.critical: return Colors.red.shade900;
    }
  }
}