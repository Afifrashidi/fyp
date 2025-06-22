// lib/src/presentation/pages/room_management_page.dart
// UPDATED: Enhanced error handling and user feedback for room management

import 'dart:async';
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
        backgroundColor: Colors.blue[50],
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[50]!, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome text
              Text(
                'Welcome to Collaborative Drawing',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.blue[800],
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Create a new room or join an existing one to start collaborating',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Create Room Section
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.add_circle, color: Colors.green[600], size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Create New Room',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _roomNameController,
                        decoration: const InputDecoration(
                          labelText: 'Room Name',
                          hintText: 'My Collaborative Canvas',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.edit),
                        ),
                        maxLength: 50,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isCreating ? null : _createRoom,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[600],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: _isCreating
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Icon(Icons.add, color: Colors.white),
                          label: Text(
                            _isCreating ? 'Creating...' : 'Create Room',
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Join Room Section
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.login, color: Colors.blue[600], size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Join Existing Room',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.blue[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _roomIdController,
                        decoration: const InputDecoration(
                          labelText: 'Room ID',
                          hintText: 'room_1234567890_abcdefghi',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.key),
                          helperText: 'Ask the room host for the room ID',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isJoining ? null : () => _joinRoom('editor'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[600],
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: _isJoining
                                  ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                                  : const Icon(Icons.edit, color: Colors.white),
                              label: const Text(
                                'Join as Editor',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isJoining ? null : () => _joinRoom('viewer'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                side: BorderSide(color: Colors.blue[600]!),
                              ),
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

              const SizedBox(height: 24),

              // Info section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue[600], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'How it works',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Editors can draw, add images, and modify the canvas\n'
                          '• Viewers can see changes in real-time but cannot edit\n'
                          '• All changes are synced automatically across devices\n'
                          '• Room IDs are unique and required to join sessions',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // UPDATED: Enhanced join room with better feedback
  Future<void> _joinRoom(String role) async {
    final roomId = _roomIdController.text.trim();

    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a room ID'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validate room ID format
    if (!_liveblocksService.isValidRoomId(roomId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Invalid room ID format. Room IDs should look like: room_1234567890_abcdefghi',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _isJoining = true);

    try {
      // Show connection progress
      _showConnectionDialog('Connecting to room...');

      // Get user info using AuthService methods
      final userName = _authService.getDisplayName();
      final userId = _authService.getUserId();
      final userColor = _authService.getUserColor();

      debugPrint('Joining room $roomId as $userName ($userId)');

      // Connect to room with timeout
      await _liveblocksService.joinRoom(
        roomId,
        userName: userName,
        userColor: userColor,
        userId: userId,
        userRole: role,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Connection timeout'),
      );

      // Close progress dialog
      if (mounted) Navigator.of(context).pop();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully joined room $roomId'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate to drawing page
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LiveblocksCollaborativeDrawingPage(
              roomId: roomId,
              userName: userName,
              userColor: userColor,
              isHost: false,
            ),
          ),
        );
      }

    } on TimeoutException {
      _handleJoinError('Connection timeout. Please check your internet connection and try again.');
    } catch (e) {
      _handleJoinError(e.toString());
    } finally {
      if (mounted) {
        // Close any open dialogs
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
        setState(() => _isJoining = false);
      }
    }
  }

  void _handleJoinError(String error) {
    if (!mounted) return;

    String userFriendlyMessage;
    String actionText = 'Try Again';
    VoidCallback? action = () => _joinRoom('editor');

    if (error.contains('Backend server not responding') ||
        error.contains('Network error')) {
      userFriendlyMessage = 'Server is currently unavailable. Please try again in a few minutes.';
      actionText = 'Retry';
    } else if (error.contains('Invalid room ID')) {
      userFriendlyMessage = 'The room ID format is invalid. Please check and try again.';
      action = null; // No retry action for invalid format
    } else if (error.contains('Room not found') || error.contains('404')) {
      userFriendlyMessage = 'Room not found. Please check the room ID or ask the host for a new link.';
      action = null;
    } else if (error.contains('Authentication failed') || error.contains('401')) {
      userFriendlyMessage = 'Authentication failed. Please sign out and sign in again.';
      actionText = 'Sign Out';
      action = () {
        _authService.signOut();
        Navigator.pushReplacementNamed(context, '/login');
      };
    } else if (error.contains('Access denied') || error.contains('403')) {
      userFriendlyMessage = 'Access denied. You may not have permission to join this room.';
      action = null;
    } else {
      userFriendlyMessage = 'Failed to join room: ${error.replaceAll('Exception: ', '')}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Connection Failed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(userFriendlyMessage),
            if (error.contains('Backend server') || error.contains('Network'))
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'Troubleshooting tips:\n'
                      '• Check your internet connection\n'
                      '• Make sure the backend server is running\n'
                      '• Try refreshing the page',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (action != null)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                action!();
              },
              child: Text(actionText),
            ),
        ],
      ),
    );
  }

  void _showConnectionDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  // Enhanced create room with better feedback
  Future<void> _createRoom() async {
    if (_roomNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a room name'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      _showConnectionDialog('Creating room...');

      final userName = _authService.getDisplayName();
      final userId = _authService.getUserId();
      final userColor = _authService.getUserColor();

      // Create room through Liveblocks service
      final roomData = await _liveblocksService.createRoom(
        _roomNameController.text.trim(),
        userId,
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('Room creation timeout'),
      );

      if (roomData == null) {
        throw Exception('Room creation failed - no data returned');
      }

      final roomId = roomData['roomId'] as String;

      // Close progress dialog
      if (mounted) Navigator.of(context).pop();

      // Connect to the newly created room
      await _liveblocksService.enterRoom(
        roomId,
        userName: userName,
        userColor: userColor,
        userId: userId,
        userRole: 'owner',
      );

      // Show success dialog with room information
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Room Created Successfully'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Room: ${_roomNameController.text.trim()}'),
                const SizedBox(height: 8),
                const Text('Room ID:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    roomId,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: roomId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Room ID copied to clipboard!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy ID'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Share this room ID with others so they can join your collaborative session.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Navigate to drawing page
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LiveblocksCollaborativeDrawingPage(
                        roomId: roomId,
                        userName: userName,
                        userColor: userColor,
                        isHost: true,
                      ),
                    ),
                  );
                },
                child: const Text('Start Drawing'),
              ),
            ],
          ),
        );
      }

    } on TimeoutException {
      _handleCreateError('Room creation timeout. Please try again.');
    } catch (e) {
      _handleCreateError(e.toString());
    } finally {
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
        setState(() => _isCreating = false);
      }
    }
  }

  void _handleCreateError(String error) {
    if (!mounted) return;

    String userFriendlyMessage;
    if (error.contains('Backend server not responding')) {
      userFriendlyMessage = 'Server is currently unavailable. Please try again later.';
    } else if (error.contains('timeout')) {
      userFriendlyMessage = 'Room creation took too long. Please check your connection and try again.';
    } else {
      userFriendlyMessage = 'Failed to create room: ${error.replaceAll('Exception: ', '')}';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(userFriendlyMessage),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _createRoom,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    _roomIdController.dispose();
    super.dispose();
  }
}