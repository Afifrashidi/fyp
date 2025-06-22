import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_drawing_board/src/services/liveblocks_service.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';
import 'liveblocks_collaborative_drawing_page.dart';

class RoomManagementPage extends StatefulWidget {
  const RoomManagementPage({super.key});

  @override
  State<RoomManagementPage> createState() => _RoomManagementPageState();
}

class _RoomManagementPageState extends State<RoomManagementPage> {
  final _roomNameController = TextEditingController();
  final _roomIdController = TextEditingController();
  final _liveblocksService = LiveblocksService();
  final _authService = AuthService();

  bool _isCreating = false;
  bool _isJoining = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collaborative Drawing'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Create Room Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create New Room',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _roomNameController,
                      decoration: const InputDecoration(
                        labelText: 'Room Name',
                        hintText: 'My Collaborative Canvas',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isCreating ? null : _createRoom,
                      icon: _isCreating
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.add),
                      label: Text(_isCreating ? 'Creating...' : 'Create Room'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Join Room Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Join Existing Room',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _roomIdController,
                      decoration: const InputDecoration(
                        labelText: 'Room ID',
                        hintText: 'room_1234567890',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isJoining ? null : () => _joinRoom('editor'),
                            icon: const Icon(Icons.edit),
                            label: const Text('Join as Editor'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isJoining ? null : () => _joinRoom('viewer'),
                            icon: const Icon(Icons.visibility),
                            label: const Text('Join as Viewer'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createRoom() async {
    if (_roomNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room name')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      // Generate room ID
      final roomId = 'room_${DateTime.now().millisecondsSinceEpoch}';

      // Get user info
      final user = _authService.currentUser;
      final userName = user?.email?.split('@')[0] ?? 'User';
      final userId = user?.id ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';

      // Connect to room as owner
      await _liveblocksService.enterRoom(
        roomId,
        userName: userName,
        userColor: Colors.blue,
        userId: userId,
        userRole: 'owner',
      );

      // Show success dialog with room ID
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Room Created!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Share this Room ID with others:'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          roomId,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: roomId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Room ID copied!')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        // Navigate to drawing page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LiveblocksCollaborativeDrawingPage(
              sessionId: roomId,
              isHost: true,
            ),
          ),
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create room: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isCreating = false);
    }
  }

  Future<void> _joinRoom(String role) async {
    if (_roomIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room ID')),
      );
      return;
    }

    setState(() => _isJoining = true);

    try {
      // Get user info
      final user = _authService.currentUser;
      final userName = user?.email?.split('@')[0] ?? 'Guest';
      final userId = user?.id ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';

      // Generate random color for user
      final userColor = Colors.primaries[
      DateTime.now().millisecond % Colors.primaries.length
      ];

      // Connect to room
      await _liveblocksService.enterRoom(
        _roomIdController.text,
        userName: userName,
        userColor: userColor,
        userId: userId,
        userRole: role,
      );

      // Navigate to drawing page
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LiveblocksCollaborativeDrawingPage(
              sessionId: _roomIdController.text,
              isHost: false,
            ),
          ),
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to join room: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isJoining = false);
    }
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    _roomIdController.dispose();
    super.dispose();
  }
}