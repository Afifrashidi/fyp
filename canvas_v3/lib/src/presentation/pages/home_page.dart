// lib/src/presentation/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/domain/models/drawing_data.dart';
import 'package:flutter_drawing_board/src/presentation/pages/liveblocks_collaborative_drawing_page.dart';
import 'package:flutter_drawing_board/src/presentation/pages/room_management_page.dart';
import 'package:flutter_drawing_board/src/services/auth_service.dart';
import 'package:flutter_drawing_board/src/services/drawing_persistence_service.dart';
import 'package:flutter_drawing_board/src/services/collaborative_drawing_service.dart';
import 'package:flutter_drawing_board/src/presentation/pages/drawing_page.dart';
import 'package:flutter_drawing_board/src/presentation/pages/collaborative_drawing_page.dart';
import 'package:flutter_drawing_board/src/presentation/pages/auth/login_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});


  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _authService = AuthService();
  final _persistenceService = DrawingPersistenceService();
  final _collaborativeService = CollaborativeDrawingService();

  final _searchController = TextEditingController();
  String _selectedFilter = 'all';
  bool _isGridView = true;

  // Add a key to force refresh
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  // Use a Future variable to control refresh
  late Future<List<DrawingMetadata>> _drawingsFuture;

  // Tab selection
  int _selectedTab = 0; // 0 = My Drawings, 1 = Collaborative

  @override
  void initState() {
    super.initState();
    // Initialize the future
    _drawingsFuture = _loadDrawings();

    // Check authentication status on init
    if (!_authService.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      });
    }
  }

  // Method to refresh drawings
  void _refreshDrawings() {
    setState(() {
      _drawingsFuture = _loadDrawings();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: _selectedTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Let\'s Draw'),
          bottom: TabBar(
            onTap: (index) => setState(() => _selectedTab = index),
            tabs: const [
              Tab(text: 'My Drawings', icon: Icon(Icons.person)),
              Tab(text: 'Collaborative', icon: Icon(Icons.groups)),
            ],
          ),
          actions: [
            // View toggle
            IconButton(
              icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
              onPressed: () {
                setState(() => _isGridView = !_isGridView);
              },
            ),
            // In your HomePage, add this to the app bar actions:
            IconButton(
              icon: const Icon(Icons.group_work),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RoomManagementPage(),
                  ),
                );
              },
              tooltip: 'Collaborative Drawing',
            ),
            // Refresh button (for debugging)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshDrawings,
              tooltip: 'Refresh',
            ),
            // User menu
            PopupMenuButton<String>(
              icon: CircleAvatar(
                backgroundColor: Theme.of(context).primaryColor,
                child: Text(
                  _authService.currentUser?.email?.substring(0, 1).toUpperCase() ?? 'U',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'profile',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _authService.currentUser?.email ?? 'User',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text('Manage account', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'signout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Sign Out'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'signout') {
                  _handleSignOut();
                }
              },
            ),
          ],
        ),
        body: IndexedStack(
          index: _selectedTab,
          children: [
            // My Drawings Tab
            _buildMyDrawingsTab(),
            // Collaborative Tab
            _buildCollaborativeTab(),
          ],
        ),
        floatingActionButton: _buildFAB(),
      ),
    );
  }

  Widget _buildMyDrawingsTab() {
    return Column(
      children: [
        // Search and filters
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search drawings...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (_) => _refreshDrawings(),
                ),
              ),
              const SizedBox(width: 16),
              // Filter dropdown
              DropdownButton<String>(
                value: _selectedFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'starred', child: Text('Starred')),
                  DropdownMenuItem(value: 'recent', child: Text('Recent')),
                ],
                onChanged: (value) {
                  setState(() => _selectedFilter = value!);
                  _refreshDrawings();
                },
              ),
            ],
          ),
        ),

        // Drawings list/grid
        Expanded(
          child: RefreshIndicator(
            key: _refreshKey,
            onRefresh: () async {
              _refreshDrawings();
              await _drawingsFuture;
            },
            child: FutureBuilder<List<DrawingMetadata>>(
              future: _drawingsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        const Text('Error loading drawings'),
                        Text(
                          snapshot.error.toString(),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _refreshDrawings,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final drawings = snapshot.data ?? [];

                if (drawings.isEmpty) {
                  return _buildEmptyState();
                }

                return _isGridView
                    ? _buildGridView(drawings)
                    : _buildListView(drawings);
              },
            ),
          ),
        ),
      ],
    );
  }

  // Fixed method to load drawings with proper sorting
  Future<List<DrawingMetadata>> _loadDrawings() async {
    try {
      print('Loading drawings at ${DateTime.now()}');

      // Build the query
      var query = Supabase.instance.client
          .from('drawings')
          .select('''
            id,
            title,
            thumbnail_url,
            created_at,
            starred,
            is_public,
            tags,
            last_opened_at,
            updated_at,
            drawing_states!inner(
              updated_at
            )
          ''')
          .eq('user_id', _authService.currentUser!.id);

      // Apply filters
      if (_searchController.text.isNotEmpty) {
        query = query.ilike('title', '%${_searchController.text}%');
      }

      if (_selectedFilter == 'starred') {
        query = query.eq('starred', true);
      }

// Execute query with ordering
      final data = await query.order('last_opened_at', ascending: false);

      print('Loaded ${data.length} drawings');

      // Convert to DrawingMetadata objects
      final drawings = data.map<DrawingMetadata>((item) {
        return DrawingMetadata.fromJson(item);
      }).toList();

      return drawings;
    } catch (e) {
      print('Error loading drawings: $e');
      throw e;
    }
  }

  Widget _buildCollaborativeTab() {
    return Column(
      children: [
        // Quick actions
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _createCollaborativeSession,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Session'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _joinCollaborativeSession,
                  icon: const Icon(Icons.group_add),
                  label: const Text('Join Session'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Active sessions
        Expanded(
          child: FutureBuilder<List<CollaborativeSession>>(
            future: _collaborativeService.getActiveSessions(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final sessions = snapshot.data ?? [];

              if (sessions.isEmpty) {
                return _buildEmptyCollaborativeState();
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return _SessionCard(
                    session: session,
                    onJoin: () => _joinSession(session.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFAB() {
    if (_selectedTab == 0) {
      // My Drawings tab
      return FloatingActionButton.extended(
        onPressed: _createNewDrawing,
        icon: const Icon(Icons.add),
        label: const Text('New Drawing'),
      );
    } else {
      // Collaborative tab
      return FloatingActionButton.extended(
        onPressed: _createCollaborativeSession,
        icon: const Icon(Icons.group_add),
        label: const Text('New Session'),
        backgroundColor: Colors.green,
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.brush,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No drawings yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          const Text('Create your first masterpiece!'),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createNewDrawing,
            icon: const Icon(Icons.add),
            label: const Text('Create Drawing'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCollaborativeState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.groups,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No active sessions',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          const Text('Create a session to draw with others!'),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _createCollaborativeSession,
                icon: const Icon(Icons.add),
                label: const Text('Create Session'),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _joinCollaborativeSession,
                icon: const Icon(Icons.group_add),
                label: const Text('Join Session'),

              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(List<DrawingMetadata> drawings) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _calculateGridColumns(context),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1,
      ),
      itemCount: drawings.length,
      itemBuilder: (context, index) {
        final drawing = drawings[index];
        return _DrawingCard(
          drawing: drawing,
          onTap: () => _openDrawing(drawing.id),
          onStarToggle: () => _toggleStar(drawing),
          onDelete: () => _deleteDrawing(drawing),
        );
      },
    );
  }

  int _calculateGridColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return 2;
    if (width < 900) return 3;
    if (width < 1200) return 4;
    return 5;
  }

  Widget _buildListView(List<DrawingMetadata> drawings) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: drawings.length,
      itemBuilder: (context, index) {
        final drawing = drawings[index];
        return _DrawingListTile(
          drawing: drawing,
          onTap: () => _openDrawing(drawing.id),
          onStarToggle: () => _toggleStar(drawing),
          onDelete: () => _deleteDrawing(drawing),
        );
      },
    );
  }

  void _createNewDrawing() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DrawingPage(isNewDrawing: true),
      ),
    );

    // Refresh when returning
    _refreshDrawings();
  }

  void _openDrawing(String drawingId) async {
    print('Opening drawing: $drawingId');

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrawingPage(
          drawingId: drawingId,
          isNewDrawing: false,
        ),
      ),
    );

    // Refresh immediately when returning
    print('Returned from drawing, refreshing list...');
    _refreshDrawings();
  }

  void _createCollaborativeSession() async {
    // Show dialog to choose between Supabase and Liveblocks
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Collaboration Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud),
              title: const Text('Supabase Realtime'),
              subtitle: const Text('Uses Supabase for real-time collaboration'),
              onTap: () => Navigator.pop(context, 'supabase'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Liveblocks'),
              subtitle: const Text('Uses Liveblocks for real-time collaboration'),
              onTap: () => Navigator.pop(context, 'liveblocks'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (choice == 'liveblocks') {
      // Navigate directly to Liveblocks collaborative drawing
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LiveblocksCollaborativeDrawingPage(
            isHost: true,
          ),
        ),
      );
    } else if (choice == 'supabase') {
      // Original Supabase flow
      final title = await showDialog<String>(
        context: context,
        builder: (context) => _CreateSessionDialog(),
      );

      if (title != null && title.isNotEmpty) {
        final sessionId = await _collaborativeService.createSession(
          hostUserId: _authService.currentUser?.id ?? 'guest',
          title: title,
        );

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CollaborativeDrawingPage(
                sessionId: sessionId,
                isHost: true,
              ),
            ),
          );
        }
      }
    }
  }

  void _joinCollaborativeSession() async {
    final sessionId = await showDialog<String>(
      context: context,
      builder: (context) => _JoinSessionDialog(),
    );

    if (sessionId != null && sessionId.isNotEmpty) {
      _joinSession(sessionId);
    }
  }

  void _joinSession(String sessionId) async {
    try {
      await _collaborativeService.joinExistingSession(sessionId: sessionId);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollaborativeDrawingPage(sessionId: sessionId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join session: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleStar(DrawingMetadata drawing) async {
    try {
      await Supabase.instance.client
          .from('drawings')
          .update({'starred': !drawing.starred})
          .eq('id', drawing.id);

      _refreshDrawings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteDrawing(DrawingMetadata drawing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Drawing?'),
        content: Text('Are you sure you want to delete "${drawing.title}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Delete drawing and related data
        await Supabase.instance.client
            .from('drawings')
            .delete()
            .eq('id', drawing.id);

        _refreshDrawings();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Drawing deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _handleSignOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// Session Card Widget
class _SessionCard extends StatelessWidget {
  final CollaborativeSession session;
  final VoidCallback onJoin;

  const _SessionCard({
    required this.session,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor,
          child: const Icon(Icons.groups, color: Colors.white),
        ),
        title: Text(session.title),
        subtitle: Text('Host: ${session.hostName} • ${_formatTime(session.createdAt)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (session.requiresPassword)
              const Icon(Icons.lock, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onJoin,
              child: const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}

// Create Session Dialog
class _CreateSessionDialog extends StatefulWidget {
  @override
  State<_CreateSessionDialog> createState() => _CreateSessionDialogState();
}

class _CreateSessionDialogState extends State<_CreateSessionDialog> {
  final _titleController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _requirePassword = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Collaborative Session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Session Title',
              hintText: 'e.g., Math Class Whiteboard',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('Require password'),
            value: _requirePassword,
            onChanged: (value) {
              setState(() => _requirePassword = value ?? false);
            },
            contentPadding: EdgeInsets.zero,
          ),
          if (_requirePassword) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Session Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_titleController.text.trim().isNotEmpty) {
              Navigator.pop(context, _titleController.text.trim());
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// Join Session Dialog
class _JoinSessionDialog extends StatefulWidget {
  @override
  State<_JoinSessionDialog> createState() => _JoinSessionDialogState();
}

class _JoinSessionDialogState extends State<_JoinSessionDialog> {
  final _sessionIdController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join Session'),
      content: TextField(
        controller: _sessionIdController,
        decoration: const InputDecoration(
          labelText: 'Session ID',
          hintText: 'Enter the session ID shared with you',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_sessionIdController.text.trim().isNotEmpty) {
              Navigator.pop(context, _sessionIdController.text.trim());
            }
          },
          child: const Text('Join'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pushNamed(context, '/liveblocks-test');
          },
          icon: const Icon(Icons.bug_report),
          label: const Text('Test Liveblocks Connection'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _sessionIdController.dispose();
    super.dispose();
  }
}

// Drawing card widget
class _DrawingCard extends StatelessWidget {
  final DrawingMetadata drawing;
  final VoidCallback onTap;
  final VoidCallback onStarToggle;
  final VoidCallback onDelete;

  const _DrawingCard({
    required this.drawing,
    required this.onTap,
    required this.onStarToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  drawing.thumbnailUrl != null
                      ? Image.network(
                    drawing.thumbnailUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildPlaceholder(),
                  )
                      : _buildPlaceholder(),

                  // Star indicator
                  if (drawing.starred)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Title and actions
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          drawing.title,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Opened ${_formatDate(drawing.lastOpenedAt)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'share',
                        child: Text('Share'),
                      ),
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: Text('Duplicate'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Icon(
        Icons.image,
        size: 50,
        color: Colors.grey[400],
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    // Ensure we're working with local time
    final localDateTime = dateTime.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localDateTime);

    // Debug print
    print('Formatting date - UTC: $dateTime, Local: $localDateTime, Now: $now, Diff: ${difference.inMinutes} minutes');

    if (difference.isNegative) {
      // Future date (clock sync issue)
      return 'just now';
    }

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else {
      // Format as date
      return '${localDateTime.day}/${localDateTime.month}/${localDateTime.year}';
    }
  }
}

// Drawing list tile widget
class _DrawingListTile extends StatelessWidget {
  final DrawingMetadata drawing;
  final VoidCallback onTap;
  final VoidCallback onStarToggle;
  final VoidCallback onDelete;

  const _DrawingListTile({
    required this.drawing,
    required this.onTap,
    required this.onStarToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 60,
            height: 60,
            child: drawing.thumbnailUrl != null
                ? Image.network(
              drawing.thumbnailUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey[200],
                child: Icon(Icons.image, color: Colors.grey[400]),
              ),
            )
                : Container(
              color: Colors.grey[200],
              child: Icon(Icons.image, color: Colors.grey[400]),
            ),
          ),
        ),
        title: Text(
          drawing.title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Opened ${_formatDate(drawing.lastOpenedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (drawing.updatedAt != drawing.lastOpenedAt)
              Text(
                'Modified ${_formatDate(drawing.updatedAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                  fontSize: 11,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                drawing.starred ? Icons.star : Icons.star_border,
                color: drawing.starred ? Colors.amber : null,
              ),
              onPressed: onStarToggle,
            ),
            PopupMenuButton<String>(
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.share),
                    title: Text('Share'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'duplicate',
                  child: ListTile(
                    leading: Icon(Icons.copy),
                    title: Text('Duplicate'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('Delete', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'delete') onDelete();
              },
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    // Ensure we're working with local time
    final localDateTime = dateTime.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localDateTime);

    if (difference.isNegative) {
      return 'just now';
    }

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${localDateTime.day}/${localDateTime.month}/${localDateTime.year}';
    }
  }
}