import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/network_enums.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:math' as math;

// Custom Auth Response
class CustomAuthResponse {
  final User? user;
  final Session? session;
  final String? errorMessage;

  CustomAuthResponse({
    this.user,
    this.session,
    this.errorMessage,
  });

  bool get hasError => errorMessage != null;
  bool get isSuccess => user != null && !hasError;
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // ✅ Safe getter for Supabase client
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Supabase not initialized: $e');
      }
      return null;
    }
  }

  final _authStatusController = StreamController<AuthStatus>.broadcast();

  // ✅ Check if Supabase is available
  bool get isSupabaseAvailable => _supabase != null;

  // Getters with null safety
  User? get currentUser => isSupabaseAvailable ? _supabase!.auth.currentUser : null;
  Session? get currentSession => isSupabaseAvailable ? _supabase!.auth.currentSession : null;
  bool get isAuthenticated => currentUser != null && isSupabaseAvailable;
  Stream<AuthStatus> get authStatusStream => _authStatusController.stream;

  Stream<AuthState>? get authStateChanges =>
      isSupabaseAvailable ? _supabase!.auth.onAuthStateChange : null;

  // ✅ Collaborative Drawing Integration Methods (Simplified)

  /// Get display name for UI
  String getDisplayName() {
    if (!isAuthenticated) return 'Guest User';

    final user = currentUser!;

    // Try user metadata first
    final userMetadata = user.userMetadata;
    if (userMetadata?['display_name'] != null) {
      return userMetadata!['display_name'] as String;
    }

    if (userMetadata?['username'] != null) {
      return userMetadata!['username'] as String;
    }

    // Fallback to email prefix
    if (user.email != null) {
      return user.email!.split('@')[0];
    }

    return 'User ${user.id.substring(0, 8)}';
  }

  /// Get consistent user ID
  String getUserId() {
    return currentUser?.id ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Get user color for collaborative sessions
  Color getUserColor() {
    const availableColors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.purple,
      Colors.orange,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
    ];

    final userId = getUserId();
    final hash = userId.hashCode.abs();
    return availableColors[hash % availableColors.length];
  }

  /// Get user initials for avatar
  String getUserInitials() {
    final displayName = getDisplayName();
    if (displayName.isEmpty || displayName == 'Guest User') return 'GU';

    final words = displayName.trim().split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    } else {
      return words[0].substring(0, math.min(2, words[0].length)).toUpperCase();
    }
  }

  /// Get user role
  String getUserRole() {
    if (!isAuthenticated) return 'guest';

    final userMetadata = currentUser!.userMetadata;
    return userMetadata?['role'] as String? ?? 'user';
  }

  /// Check if user can create rooms
  bool canCreateRooms() {
    return isAuthenticated; // Simplified - all authenticated users can create rooms
  }

  // ✅ Initialize auth listener safely
  void initializeAuthListener() {
    if (!isSupabaseAvailable) {
      debugPrint('Cannot initialize auth listener - Supabase not available');
      return;
    }

    _supabase!.auth.onAuthStateChange.listen((state) {
      switch (state.event) {
        case AuthChangeEvent.signedIn:
          _authStatusController.add(AuthStatus.authenticated);
          break;
        case AuthChangeEvent.signedOut:
          _authStatusController.add(AuthStatus.unauthenticated);
          break;
        case AuthChangeEvent.userUpdated:
          _authStatusController.add(AuthStatus.authenticated);
          break;
        default:
          break;
      }
    });
  }

  // ✅ Sign Up with safe error handling
  Future<CustomAuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    if (!isSupabaseAvailable) {
      return CustomAuthResponse(
        errorMessage: 'Authentication service not available. Please check your connection.',
      );
    }

    try {
      _authStatusController.add(AuthStatus.authenticating);

      // Validate inputs
      if (!_isValidEmail(email)) {
        _authStatusController.add(AuthStatus.error);
        return CustomAuthResponse(errorMessage: 'Invalid email format');
      }

      final passwordError = _validatePassword(password);
      if (passwordError != null) {
        _authStatusController.add(AuthStatus.error);
        return CustomAuthResponse(errorMessage: passwordError);
      }

      final usernameError = _validateUsernameFormat(username);
      if (usernameError != null) {
        _authStatusController.add(AuthStatus.error);
        return CustomAuthResponse(errorMessage: usernameError);
      }

      // Create user metadata
      final userMetadata = {
        'username': username.trim(),
        'display_name': displayName?.trim() ?? username.trim(),
        'role': 'user',
      };

      // Sign up with Supabase
      final response = await _supabase!.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: userMetadata,
      );

      if (response.user == null) {
        _authStatusController.add(AuthStatus.error);
        return CustomAuthResponse(errorMessage: 'Failed to create account');
      }

      // Try to create user profile (optional - won't fail if table doesn't exist)
      try {
        await _createUserProfile(
          userId: response.user!.id,
          email: email.trim().toLowerCase(),
          username: username.trim(),
          displayName: displayName?.trim() ?? username.trim(),
        );
      } catch (e) {
        debugPrint('Profile creation failed (non-critical): $e');
      }

      _authStatusController.add(AuthStatus.authenticated);
      return CustomAuthResponse(
        user: response.user,
        session: response.session,
      );

    } catch (e) {
      debugPrint('Sign up error: $e');
      _authStatusController.add(AuthStatus.error);
      return CustomAuthResponse(errorMessage: _parseAuthError(e.toString()));
    }
  }

  // ✅ Sign In
  Future<CustomAuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    if (!isSupabaseAvailable) {
      return CustomAuthResponse(
        errorMessage: 'Authentication service not available. Please check your connection.',
      );
    }

    try {
      _authStatusController.add(AuthStatus.authenticating);

      if (email.trim().isEmpty || password.isEmpty) {
        _authStatusController.add(AuthStatus.error);
        return CustomAuthResponse(errorMessage: 'Email and password are required');
      }

      final response = await _supabase!.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      if (response.user == null) {
        _authStatusController.add(AuthStatus.error);
        return CustomAuthResponse(errorMessage: 'Invalid email or password');
      }

      _authStatusController.add(AuthStatus.authenticated);
      return CustomAuthResponse(
        user: response.user,
        session: response.session,
      );

    } catch (e) {
      debugPrint('Sign in error: $e');
      _authStatusController.add(AuthStatus.error);
      return CustomAuthResponse(errorMessage: _parseAuthError(e.toString()));
    }
  }

  // ✅ Sign Out
  Future<void> signOut() async {
    if (!isSupabaseAvailable) {
      debugPrint('Cannot sign out - Supabase not available');
      return;
    }

    try {
      await _supabase!.auth.signOut();
      _authStatusController.add(AuthStatus.unauthenticated);
      debugPrint('✅ Sign out successful');
    } catch (e) {
      debugPrint('❌ Error signing out: $e');
    }
  }

  // ✅ Reset Password
  Future<CustomAuthResponse> resetPassword(String email) async {
    if (!isSupabaseAvailable) {
      return CustomAuthResponse(
        errorMessage: 'Authentication service not available. Please check your connection.',
      );
    }

    try {
      if (!_isValidEmail(email)) {
        return CustomAuthResponse(errorMessage: 'Invalid email format');
      }

      await _supabase!.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
      );

      return CustomAuthResponse();

    } catch (e) {
      return CustomAuthResponse(errorMessage: _parseAuthError(e.toString()));
    }
  }

  // ✅ Update Password
  Future<CustomAuthResponse> updatePassword(String newPassword) async {
    if (!isSupabaseAvailable) {
      return CustomAuthResponse(
        errorMessage: 'Authentication service not available.',
      );
    }

    if (!isAuthenticated) {
      return CustomAuthResponse(
        errorMessage: 'You must be logged in to change your password',
      );
    }

    try {
      final passwordError = _validatePassword(newPassword);
      if (passwordError != null) {
        return CustomAuthResponse(errorMessage: passwordError);
      }

      final response = await _supabase!.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      return CustomAuthResponse(
        user: response.user,
        session: currentSession,
      );

    } catch (e) {
      return CustomAuthResponse(errorMessage: _parseAuthError(e.toString()));
    }
  }

  // ✅ Get user profile (safe)
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    if (!isSupabaseAvailable) return null;

    try {
      final response = await _supabase!
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Error getting user profile: $e');
      return null;
    }
  }

  // ✅ Update user profile (safe)
  Future<bool> updateProfile({
    String? username,
    String? displayName,
    String? avatarUrl,
  }) async {
    if (!isSupabaseAvailable || !isAuthenticated) return false;

    try {
      final userId = currentUser!.id;
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (username != null) updates['username'] = username.trim();
      if (displayName != null) updates['display_name'] = displayName.trim();
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      await _supabase!
          .from('users')
          .update(updates)
          .eq('id', userId);

      // Also update auth user metadata
      final currentMetadata = currentUser!.userMetadata ?? {};
      final updatedMetadata = Map<String, dynamic>.from(currentMetadata);

      if (username != null) updatedMetadata['username'] = username.trim();
      if (displayName != null) updatedMetadata['display_name'] = displayName.trim();

      await _supabase!.auth.updateUser(
        UserAttributes(data: updatedMetadata),
      );

      return true;
    } catch (e) {
      debugPrint('Error updating profile: $e');
      return false;
    }
  }

  // ✅ Private helper methods

  Future<void> _createUserProfile({
    required String userId,
    required String email,
    required String username,
    required String displayName,
  }) async {
    final profileData = {
      'id': userId,
      'email': email,
      'username': username,
      'display_name': displayName,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    await _supabase!
        .from('users')
        .insert(profileData);
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email.trim());
  }

  String? _validatePassword(String password) {
    if (password.length < 6) {
      return 'Password must be at least 6 characters';
    }
    if (password.length > 72) {
      return 'Password must be less than 72 characters';
    }
    return null;
  }

  String? _validateUsernameFormat(String username) {
    final trimmed = username.trim();

    if (trimmed.isEmpty) {
      return 'Username is required';
    }

    if (trimmed.length < 3) {
      return 'Username must be at least 3 characters';
    }

    if (trimmed.length > 30) {
      return 'Username must be less than 30 characters';
    }

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(trimmed)) {
      return 'Username can only contain letters, numbers, and underscores';
    }

    return null;
  }

  String _parseAuthError(String error) {
    final errorMessage = error.toLowerCase();

    if (errorMessage.contains('email') && errorMessage.contains('already registered')) {
      return 'This email is already registered';
    }
    if (errorMessage.contains('invalid login credentials')) {
      return 'Invalid email or password';
    }
    if (errorMessage.contains('user not found')) {
      return 'No account found with this email';
    }
    if (errorMessage.contains('network')) {
      return 'Network error. Please check your connection';
    }
    if (errorMessage.contains('weak password')) {
      return 'Password is too weak. Please use a stronger password';
    }
    if (errorMessage.contains('signup disabled')) {
      return 'New user registration is currently disabled';
    }

    return 'Authentication error. Please try again';
  }

  void dispose() {
    _authStatusController.close();
  }
}