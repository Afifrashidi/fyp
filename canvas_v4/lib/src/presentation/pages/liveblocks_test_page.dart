// lib/src/presentation/pages/liveblocks_test_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/config/liveblocks_config.dart';
import 'package:flutter_drawing_board/src/services/liveblocks_service.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';

// Add this test page to your main.dart routes:
// '/liveblocks-test': (context) => const LiveblocksTestPage(),

class LiveblocksTestPage extends StatefulWidget {
  const LiveblocksTestPage({super.key});

  @override
  State<LiveblocksTestPage> createState() => _LiveblocksTestPageState();
}

class _LiveblocksTestPageState extends State<LiveblocksTestPage> {
  final _liveblocksService = LiveblocksService();
  final _authService = AuthService();

  String _status = 'Not connected';
  String _roomId = 'test-room-${DateTime.now().millisecondsSinceEpoch}';
  final List<String> _logs = [];
  bool _isConnecting = false;

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toLocal().toString().substring(11, 19)}] $message');
      if (_logs.length > 20) {
        _logs.removeAt(0);
      }
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _isConnecting = true;
      _logs.clear();
    });

    try {
      _addLog('🚀 Starting connection test...');
      _addLog('Server URL: ${LiveblocksConfig.authServerUrl}');
      _addLog('Room ID: $_roomId');

      final userName = _authService.currentUser?.email?.split('@').first ?? 'Test User';
      _addLog('User: $userName');

      // Test the connection
      await _liveblocksService.enterRoom(
        _roomId,
        userName: userName,
        userColor: Colors.blue,
      );

      _addLog('✅ Successfully connected to Liveblocks!');
      setState(() {
        _status = 'Connected to room: $_roomId';
      });

      // Listen to connection status
      _liveblocksService.connectionStream.listen((state) {
        _addLog('Connection state: $state');
        setState(() {
          _status = 'Connection: ${state.toString().split('.').last}';
        });
      });

      // Test presence update
      _liveblocksService.updatePresence({
        'status': 'testing',
        'timestamp': DateTime.now().toIso8601String(),
      });
      _addLog('📤 Sent presence update');

      // Test broadcast
      _liveblocksService.broadcastMessage({
        'type': 'test_event',
        'message': 'Hello from Flutter!',
        'timestamp': DateTime.now().toIso8601String(),
      });
      _addLog('📢 Sent broadcast event');

    } catch (e) {
      _addLog('❌ Error: $e');
      setState(() {
        _status = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  Future<void> _disconnect() async {
    _addLog('🔌 Disconnecting...');
    await _liveblocksService.leaveRoom();
    setState(() {
      _status = 'Disconnected';
    });
    _addLog('✅ Disconnected');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liveblocks Connection Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              color: _status.contains('Connected') ? Colors.green[50] :
              _status.contains('Error') ? Colors.red[50] :
              Colors.grey[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connection Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 16,
                        color: _status.contains('Connected') ? Colors.green :
                        _status.contains('Error') ? Colors.red :
                        Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Configuration Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configuration',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Server: ${LiveblocksConfig.authServerUrl}'),
                    Text('Room ID: $_roomId'),
                    Text('User: ${_authService.currentUser?.email ?? 'Guest'}'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnecting ? null : _testConnection,
                    icon: _isConnecting
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.wifi),
                    label: Text(_isConnecting ? 'Connecting...' : 'Test Connection'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.wifi_off),
                    label: const Text('Disconnect'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Logs
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Logs',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _logs.clear()),
                            tooltip: 'Clear logs',
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            return Text(
                              _logs[index],
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: _logs[index].contains('❌') ? Colors.red :
                                _logs[index].contains('✅') ? Colors.green :
                                Colors.black87,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _liveblocksService.leaveRoom();
    super.dispose();
  }
}