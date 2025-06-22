// lib/src/config/liveblocks_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LiveblocksConfig {
  static String get publicKey =>
      dotenv.env['LIVEBLOCKS_PUBLIC_KEY'] ?? 'pk_dev_XXXXXXXXXXXXXXXXXXXXX';

  // ✅ FIXED: Changed port from 3000 to 3001
  static String get authServerUrl =>
      dotenv.env['BACKEND_URL'] ?? 'http://localhost:3001';

  // ✅ FIXED: Updated WebSocket URL to latest version
  static const String wsUrl = 'wss://liveblocks.net/v1/websocket';

  // ✅ FIXED: Changed path to match server endpoint
  static String get authEndpoint => '$authServerUrl/api/liveblocks-auth';
  static String get uploadEndpoint => '$authServerUrl/api/upload';

  // ✅ NEW: Add room creation endpoint
  static String get createRoomEndpoint => '$authServerUrl/api/rooms/create';
  static String get activeRoomsEndpoint => '$authServerUrl/api/rooms/active';
}

enum LiveblocksConnectionState {
  disconnected,
  connecting,
  authenticating,
  authenticated,
  connected,
  error,
}