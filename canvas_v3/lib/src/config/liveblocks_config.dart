// lib/src/config/liveblocks_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LiveblocksConfig {
  static String get publicKey =>
      dotenv.env['LIVEBLOCKS_PUBLIC_KEY'] ?? 'pk_dev_XXXXXXXXXXXXXXXXXXXXX';

  static String get authServerUrl =>
      dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';

  static const String wsUrl = 'wss://api.liveblocks.io/v7';

  static String get authEndpoint => '$authServerUrl/api/liveblocks/auth';
  static String get uploadEndpoint => '$authServerUrl/api/upload';
}

enum LiveblocksConnectionState {
  disconnected,
  connecting,
  authenticating,
  authenticated,
  connected,
  error,
}