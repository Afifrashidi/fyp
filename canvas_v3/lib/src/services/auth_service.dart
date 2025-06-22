// lib/src/services/auth_service.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

// Auth States
enum AuthStatus {
  initial,
  authenticated,
  unauthenticated,
  authenticating,
  error
}

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

  final SupabaseClient _supabase = Supabase.instance.client;
  final _authStatusController = StreamController<AuthStatus>.broadcast();

  // Getters
  User? get currentUser => _supabase.auth.currentUser;
  Session? get currentSession => _supabase.auth.currentSession;
  bool get isAuthenticated => currentUser != null;
  Stream<AuthStatus> get authStatusStream => _authStatusController.stream;
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Initialize auth listener
  void initializeAuthListener() {
    _supabase.auth.onAuthStateChange.listen((state) {
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

  // Sign Up with comprehensive error handling
  Future<CustomAuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    User? createdAuthUser;

    try {
      _authStatusController.add(AuthStatus.authenticating);

      print('🔄 Starting registration for: $email / $username');

      // Step 1: Validate inputs
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

      // Step 2: Check for existing profiles BEFORE creating auth user
      print('🔍 Checking for existing profiles...');

      // Check username availability
      final usernameCheck = await _checkUsernameAvailabilityDetailed(username);
      if (!usernameCheck['available']) {
        _authStatusController.add(AuthStatus.error);
        return CustomAuthResponse(errorMessage: usernameCheck['message']);
      }

      // Check email availability
      final emailCheck = await _checkEmailAvailabilityDetailed(email);
      if (!emailCheck['available']) {
        _authStatusController.add(AuthStatus.error);
        return CustomAuthResponse(errorMessage: emailCheck['message']);
      }

      print('✅ Username and email are available');

      // Step 3: Create auth user
      print('👤 Creating auth user...');
      AuthResponse authResponse;
      try {
        authResponse = await _supabase.auth.signUp(
          email: email.trim().toLowerCase(),
          password: password,
        );

        if (authResponse.user == null) {
          _authStatusController.add(AuthStatus.error);
          return CustomAuthResponse(errorMessage: 'Failed to create authentication account');
        }

        createdAuthUser = authResponse.user!;
        print('✅ Auth user created successfully: ${createdAuthUser.id}');

      } catch (e) {
        print('❌ Auth creation error: $e');
        _authStatusController.add(AuthStatus.error);

        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('already registered') || errorStr.contains('email')) {
          return CustomAuthResponse(errorMessage: 'Email is already registered');
        }

        return CustomAuthResponse(errorMessage: _parseAuthError(e.toString()));
      }

      // Step 4: Create user profile
      print('📝 Creating user profile...');
      try {
        await _createUserProfileSafe(
          userId: createdAuthUser.id,
          email: email.trim().toLowerCase(),
          username: username.trim(),
          displayName: displayName?.trim() ?? username.trim(),
        );
        print('✅ Profile created successfully');

      } catch (e) {
        print('❌ Profile creation failed: $e');

        // Clean up the auth user since profile creation failed
        await _cleanupFailedRegistration(createdAuthUser.id);

        _authStatusController.add(AuthStatus.error);
        return CustomAuthResponse(errorMessage: _parseProfileError(e.toString()));
      }

      // Step 5: Create preferences (optional)
      try {
        await _createUserPreferences(createdAuthUser.id);
        print('✅ Preferences created');
      } catch (e) {
        print('⚠️ Preferences creation failed (non-critical): $e');
      }

      // Success!
      print('🎉 Registration completed successfully');
      _authStatusController.add(AuthStatus.authenticated);

      return CustomAuthResponse(
        user: authResponse.user,
        session: authResponse.session,
      );

    } catch (e) {
      print('💥 Unexpected registration error: $e');

      // Clean up auth user if it was created
      if (createdAuthUser != null) {
        await _cleanupFailedRegistration(createdAuthUser.id);
      }

      _authStatusController.add(AuthStatus.error);
      return CustomAuthResponse(errorMessage: 'Registration failed. Please try again.');
    }
  }

  // Sign In
  Future<CustomAuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      _authStatusController.add(AuthStatus.authenticating);

      if (email.trim().isEmpty || password.isEmpty) {
        _authStatusController.add(AuthStatus.error);
        return CustomAuthResponse(errorMessage: 'Email and password are required');
      }

      final response = await _supabase.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      if (response.user == null) {
        _authStatusController.add(AuthStatus.error);
        return CustomAuthResponse(errorMessage: 'Invalid email or password');
      }

      // Update last login
      try {
        await _updateLastLogin(response.user!.id);
      } catch (e) {
        print('Failed to update last login: $e');
      }

      _authStatusController.add(AuthStatus.authenticated);

      return CustomAuthResponse(
        user: response.user,
        session: response.session,
      );

    } catch (e) {
      _authStatusController.add(AuthStatus.error);
      return CustomAuthResponse(errorMessage: _parseAuthError(e.toString()));
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      _authStatusController.add(AuthStatus.unauthenticated);
      print('✅ Sign-Out successful');
    } catch (e) {
      print('❌ Error signing out: $e');
    }
  }

  // Reset Password
  Future<CustomAuthResponse> resetPassword(String email) async {
    try {
      if (!_isValidEmail(email)) {
        return CustomAuthResponse(errorMessage: 'Invalid email format');
      }

      await _supabase.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: kIsWeb ? null : 'io.supabase.flutterquickstart://reset-callback/',
      );

      return CustomAuthResponse();

    } catch (e) {
      return CustomAuthResponse(errorMessage: _parseAuthError(e.toString()));
    }
  }

  // Update Password
  Future<CustomAuthResponse> updatePassword(String newPassword) async {
    try {
      if (!isAuthenticated) {
        return CustomAuthResponse(errorMessage: 'You must be logged in to change your password');
      }

      final passwordError = _validatePassword(newPassword);
      if (passwordError != null) {
        return CustomAuthResponse(errorMessage: passwordError);
      }

      final response = await _supabase.auth.updateUser(
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

  // Detailed username availability check
  Future<Map<String, dynamic>> _checkUsernameAvailabilityDetailed(String username) async {
    try {
      final trimmed = username.trim();

      if (trimmed.length < 3 || trimmed.length > 30) {
        return {'available': false, 'message': 'Username must be 3-30 characters long'};
      }

      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(trimmed)) {
        return {'available': false, 'message': 'Username can only contain letters, numbers, and underscores'};
      }

      // Check database - case insensitive
      final response = await _supabase
          .from('users')
          .select('username')
          .ilike('username', trimmed)
          .maybeSingle();

      if (response != null) {
        return {
          'available': false,
          'message': 'Username "$trimmed" is already taken. Please choose a different username.'
        };
      }

      print('✅ Username "$trimmed" is available');
      return {'available': true, 'message': 'Username is available'};

    } catch (e) {
      print('❌ Error checking username availability: $e');

      if (e.toString().contains('relation "users" does not exist')) {
        return {
          'available': false,
          'message': 'Database not properly configured. Please contact support.'
        };
      }

      return {
        'available': false,
        'message': 'Unable to verify username availability. Please try again.'
      };
    }
  }

  // Detailed email availability check
  Future<Map<String, dynamic>> _checkEmailAvailabilityDetailed(String email) async {
    try {
      final response = await _supabase
          .from('users')
          .select('email')
          .eq('email', email.trim().toLowerCase())
          .maybeSingle();

      if (response != null) {
        return {
          'available': false,
          'message': 'Email is already registered. Please use a different email or sign in.'
        };
      }

      print('✅ Email is available');
      return {'available': true, 'message': 'Email is available'};

    } catch (e) {
      print('⚠️ Error checking email availability: $e');

      if (e.toString().contains('relation "users" does not exist')) {
        return {
          'available': false,
          'message': 'Database not properly configured. Please contact support.'
        };
      }

      return {'available': true, 'message': 'Proceeding with registration'};
    }
  }

  // Safe profile creation
  Future<void> _createUserProfileSafe({
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

    print('📝 Creating profile: $profileData');

    try {
      // Check if profile already exists
      final existingProfile = await _supabase
          .from('users')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      if (existingProfile != null) {
        print('ℹ️ Profile already exists for this user ID, using existing profile');
        return;
      }

      // Insert the profile
      final result = await _supabase
          .from('users')
          .insert(profileData)
          .select()
          .single();

      print('✅ Profile created successfully: ${result['id']}');

    } catch (e) {
      print('❌ Profile creation error: $e');

      final errorStr = e.toString().toLowerCase();

      if (errorStr.contains('users_username_key') ||
          (errorStr.contains('duplicate') && errorStr.contains('username'))) {
        throw Exception('USERNAME_CONSTRAINT_VIOLATION');
      }

      if (errorStr.contains('users_email_key') ||
          (errorStr.contains('duplicate') && errorStr.contains('email'))) {
        throw Exception('EMAIL_CONSTRAINT_VIOLATION');
      }

      if (errorStr.contains('foreign key constraint') ||
          errorStr.contains('violates foreign key')) {
        throw Exception('AUTH_USER_REFERENCE_ERROR');
      }

      if (errorStr.contains('relation "users" does not exist')) {
        throw Exception('USERS_TABLE_NOT_EXISTS');
      }

      throw Exception('DATABASE_ERROR: ${e.toString()}');
    }
  }

  // Cleanup failed registration
  Future<void> _cleanupFailedRegistration(String userId) async {
    try {
      print('🧹 Cleaning up failed registration for user: $userId');

      await _supabase.auth.signOut();

      try {
        await _supabase
            .from('users')
            .delete()
            .eq('id', userId);
        print('✅ Cleaned up partial profile data');
      } catch (e) {
        print('⚠️ Could not clean up profile data: $e');
      }

      print('✅ Cleanup completed');
    } catch (e) {
      print('⚠️ Error during cleanup: $e');
    }
  }

  // Parse profile creation errors
  String _parseProfileError(String error) {
    final errorStr = error.toLowerCase();

    if (errorStr.contains('username_constraint_violation')) {
      return 'Username is already taken. Please choose a different username.';
    }

    if (errorStr.contains('email_constraint_violation')) {
      return 'Email is already registered. Please use a different email.';
    }

    if (errorStr.contains('auth_user_reference_error')) {
      return 'Account creation failed. Please try again.';
    }

    if (errorStr.contains('users_table_not_exists')) {
      return 'Database not properly configured. Please contact support.';
    }

    if (errorStr.contains('users_username_key') ||
        (errorStr.contains('duplicate') && errorStr.contains('username'))) {
      return 'Username is already taken. Please choose a different username.';
    }

    if (errorStr.contains('users_email_key') ||
        (errorStr.contains('duplicate') && errorStr.contains('email'))) {
      return 'Email is already registered. Please use a different email.';
    }

    if (errorStr.contains('violates foreign key constraint')) {
      return 'Account creation failed. Please try again.';
    }

    if (errorStr.contains('relation "users" does not exist')) {
      return 'Database not properly configured. Please contact support.';
    }

    final shortError = error.length > 100 ? error.substring(0, 100) + "..." : error;
    return 'Profile creation failed: $shortError';
  }

  // Get user profile
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .single();

      return response;
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  // Update user profile
  Future<void> updateProfile({
    String? username,
    String? displayName,
    String? avatarUrl,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (username != null) updates['username'] = username.trim();
    if (displayName != null) updates['display_name'] = displayName.trim();
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

    await _supabase
        .from('users')
        .update(updates)
        .eq('id', userId);
  }

  // DEBUG: Method to check database state
  Future<void> debugDatabaseState() async {
    try {
      print('🔍 === DATABASE DEBUG INFO ===');

      try {
        final usersData = await _supabase
            .from('users')
            .select('*');
        print('✅ Users table accessible. Count: ${usersData.length}');

        if (usersData.isNotEmpty) {
          print('📋 Sample users:');
          for (int i = 0; i < usersData.length && i < 3; i++) {
            final user = usersData[i];
            print('   ${user['username']} (${user['email']})');
          }
        }
      } catch (e) {
        print('❌ Users table error: $e');
      }

      try {
        final authUser = currentUser;
        if (authUser != null) {
          print('✅ Current auth user: ${authUser.email} (${authUser.id})');
        } else {
          print('ℹ️ No current auth user');
        }
      } catch (e) {
        print('❌ Auth user error: $e');
      }

      print('🔍 === END DEBUG INFO ===');
    } catch (e) {
      print('💥 Debug error: $e');
    }
  }

  // Private Helper Methods
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

  Future<void> _createUserPreferences(String userId) async {
    try {
      // Check if preferences already exist
      final existingPrefs = await _supabase
          .from('user_preferences')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (existingPrefs != null) {
        print('ℹ️ User preferences already exist, skipping creation');
        return;
      }

      await _supabase.from('user_preferences').insert({
        'user_id': userId,
        'theme': 'light',
        'language': 'en',
        'notifications_enabled': true,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      print('✅ User preferences created successfully');
    } catch (e) {
      print('⚠️ Preferences creation failed (non-critical): $e');
    }
  }

  Future<void> _updateLastLogin(String userId) async {
    try {
      await _supabase.from('users').update({
        'last_login': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (e) {
      print('Error updating last login: $e');
    }
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

    return 'Authentication error. Please try again';
  }

  void dispose() {
    _authStatusController.close();
  }
}