/// Connection states for Liveblocks service
enum LiveblocksConnectionState {
  disconnected,
  connecting,
  connected,
  authenticating,
  authenticated,
  error,
  reconnecting;

  bool get isConnected => this == LiveblocksConnectionState.connected;
  bool get canSendMessages => this == LiveblocksConnectionState.connected ||
      this == LiveblocksConnectionState.authenticated;
}

/// General connection status for collaborative services
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
  reconnecting;

  bool get isOnline => this == ConnectionStatus.connected;
}

/// Authentication status for users
enum AuthStatus {
  initial,
  authenticated,
  unauthenticated,
  authenticating,
  error;

  bool get isAuthenticated => this == AuthStatus.authenticated;
}

/// Types of session events in collaborative drawing
enum SessionEventType {
  userJoined,
  userLeft,
  userUpdated,
  sessionStarted,
  sessionEnded,
  connectionLost,
  connectionRestored;
}

/// User roles in collaborative sessions
enum UserRole {
  owner,
  editor,
  viewer,
  guest;

  bool get canEdit => this == UserRole.owner || this == UserRole.editor;
  bool get canManage => this == UserRole.owner;
}