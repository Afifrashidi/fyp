import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';
import 'package:flutter_drawing_board/src/presentation/theme/app_theme.dart';
import 'package:flutter_drawing_board/src/presentation/pages/home_page.dart';
import 'package:flutter_drawing_board/src/presentation/pages/drawing_page.dart';
import 'package:flutter_drawing_board/src/presentation/pages/auth/login_page.dart';
import 'package:flutter_drawing_board/src/presentation/pages/auth/register_page.dart';
import 'package:flutter_drawing_board/src/presentation/pages/liveblocks_collaborative_drawing_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool offlineMode = false;

  try {
    // Load environment variables
    await dotenv.load(fileName: ".env");

    // Initialize Supabase BEFORE creating any services or widgets
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      debug: kDebugMode,
    );

    if (kDebugMode) {
      debugPrint('✅ Supabase initialized successfully');
    }

  } catch (e, stackTrace) {
    debugPrint('❌ Failed to initialize Supabase: $e');
    debugPrint('Stack trace: $stackTrace');
    offlineMode = true;
  }

  // Run app
  runApp(LetsDrawApp(offlineMode: offlineMode));
}

class LetsDrawApp extends StatelessWidget {
  final bool offlineMode;

  LetsDrawApp({
    super.key,
    this.offlineMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: lightTheme,
      debugShowCheckedModeBanner: kDebugMode,

      // Start with auth check
      home: offlineMode ? _OfflineModeScreen() : _AuthWrapper(),

      routes: {
        '/home': (context) => HomePage(),
        '/login': (context) => LoginPage(),
        '/register': (context) => RegisterPage(),
        '/drawing': (context) => DrawingPage(),
        '/collaborative': (context) => LiveblocksCollaborativeDrawingPage(),
      },
    );
  }
}

/// Wrapper to check authentication status
class _AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Session?>(
      future: _checkAuthStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _LoadingScreen();
        }

        if (snapshot.hasError) {
          if (kDebugMode) {
            debugPrint('Auth check error: ${snapshot.error}');
          }
          return LoginPage(); // Default to login on error
        }

        // If user is authenticated, go to home
        if (snapshot.data != null) {
          return HomePage();
        }

        // Not authenticated, show login
        return LoginPage();
      },
    );
  }

  Future<Session?> _checkAuthStatus() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (kDebugMode) {
        debugPrint('Current session: ${session?.user?.email ?? 'No session'}');
      }
      return session;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking auth status: $e');
      }
      return null;
    }
  }
}

/// Loading screen while checking authentication
class _LoadingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading...',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen shown when app is in offline mode
class _OfflineModeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppConstants.appName),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off,
                size: 96,
                color: Colors.orange,
              ),
              SizedBox(height: 24),
              Text(
                'Offline Mode',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Database connection failed. Running in offline mode.\n'
                    'Some features like authentication and cloud sync are disabled.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => DrawingPage()),
                  );
                },
                icon: Icon(Icons.brush),
                label: Text('Start Drawing (Local Only)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
              SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Restart app
                  main();
                },
                child: Text('Retry Connection'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

