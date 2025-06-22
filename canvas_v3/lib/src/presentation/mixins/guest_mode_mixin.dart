// lib/src/presentation/mixins/guest_mode_mixin.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/services/local_storage_service.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';

/// Mixin to handle guest mode warnings and reminders
mixin GuestModeWarningMixin<T extends StatefulWidget> on State<T> {
  Timer? _reminderTimer;
  final AuthService _authService = AuthService();
  bool _hasUnsavedWork = false;

  // Track if guest has made any changes
  void markGuestWorkAsUnsaved() {
    if (!_authService.isAuthenticated) {
      _hasUnsavedWork = true;
    }
  }

  // Reset unsaved work flag
  void resetGuestWork() {
    _hasUnsavedWork = false;
  }

  // Show warning when starting as guest
  void showInitialGuestWarning() {
    if (!_authService.isAuthenticated && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('⚠️ Guest Mode: Your work won\'t be saved'),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Sign In',
              textColor: Colors.white,
              onPressed: () => navigateToLogin(),
            ),
          ),
        );
      });
    }
  }

  // Start periodic reminders for guest users
  void startGuestReminders() {
    if (!_authService.isAuthenticated) {
      _reminderTimer?.cancel();

      // Show reminder every 10 minutes
      _reminderTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
        if (!_authService.isAuthenticated && mounted) {
          GuestModeReminder.showReminder(
            context,
            onSignIn: navigateToLogin,
          );
        } else {
          timer.cancel();
        }
      });
    }
  }

  // Stop reminders
  void stopGuestReminders() {
    _reminderTimer?.cancel();
  }

  // Navigate to login page
  void navigateToLogin() {
    stopGuestReminders();
    Navigator.pushReplacementNamed(context, '/login');
  }

  // Show warning when user tries to perform save action
  void showSaveWarning() {
    if (!_authService.isAuthenticated) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sign In Required'),
          content: const Text(
            'You need to sign in to save your drawing. '
                'Guest drawings are not saved and will be lost when you close the app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                navigateToLogin();
              },
              child: const Text('Sign In'),
            ),
          ],
        ),
      );
    }
  }

  // Show warning when app is about to close
  Future<bool> onWillPop() async {
    if (!_authService.isAuthenticated && _hasUnsavedWork) {
      final shouldExit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const GuestExitDialog(),
      );
      return shouldExit ?? false;
    }
    return true;
  }

  @override
  void dispose() {
    stopGuestReminders();
    super.dispose();
  }
}