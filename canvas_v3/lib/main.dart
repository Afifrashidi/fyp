// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/presentation/pages/liveblocks_test_page.dart';
import 'package:flutter_drawing_board/src/presentation/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_drawing_board/src/src.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';
import 'package:flutter_drawing_board/src/presentation/pages/auth/login_page.dart';
import 'package:flutter_drawing_board/src/presentation/pages/auth/register_page.dart';
import 'package:flutter_drawing_board/src/presentation/pages/home_page.dart';
import 'package:flutter_drawing_board/src/presentation/pages/drawing_page.dart';
import 'package:flutter_drawing_board/src/presentation/pages/liveblocks_collaborative_drawing_page.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Load environment variables
    await dotenv.load(fileName: ".env");

    // Initialize Supabase with error handling
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    );

    if (dotenv.env['SUPABASE_URL'] == null || dotenv.env['SUPABASE_ANON_KEY'] == null) {
      debugPrint('Warning: Supabase credentials not properly configured');
    }

  } catch (e) {
    debugPrint('Error initializing app: $e');
  }

  runApp(const LetsDrawApp());
}
