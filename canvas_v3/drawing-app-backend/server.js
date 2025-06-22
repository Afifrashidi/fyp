// server.js
const express = require('express');
const cors = require('cors');
const { Liveblocks } = require('@liveblocks/node');
const { createClient } = require('@supabase/supabase-js');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

const app = express();

// Middleware
app.use(cors({
  origin: process.env.NODE_ENV === 'production'
    ? ['https://your-flutter-web-app.com']
    : true,
  credentials: true
}));
app.use(express.json());

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use('/api/', limiter);

// Initialize Liveblocks
const liveblocks = new Liveblocks({
  secret: process.env.LIVEBLOCKS_SECRET_KEY,
});

// Initialize Supabase (optional - for user verification)
const supabase = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_KEY
  ? createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY)
  : null;

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    services: {
      liveblocks: !!process.env.LIVEBLOCKS_SECRET_KEY,
      supabase: !!supabase
    }
  });
});

// Main authentication endpoint
app.post('/api/liveblocks-auth', async (req, res) => {
  try {
    const { roomId, userId, userName, userColor, userRole, userToken } = req.body;

    // Validate required fields
    if (!roomId || !userId || !userName) {
      return res.status(400).json({
        error: 'Missing required fields: roomId, userId, userName'
      });
    }

    // Log the request (remove in production)
    console.log('Auth request:', {
      roomId,
      userId,
      userName,
      userRole,
      hasToken: !!userToken
    });

    let verifiedUserId = userId;
    let verifiedUserName = userName;

    // Optional: Verify authenticated user with Supabase
    if (userToken && supabase) {
      try {
        const { data: { user }, error } = await supabase.auth.getUser(userToken);
        if (!error && user) {
          verifiedUserId = user.id;
          verifiedUserName = user.email?.split('@')[0] || userName;
          console.log('Verified user:', verifiedUserId);
        }
      } catch (verifyError) {
        console.warn('User verification failed:', verifyError);
        // Continue with unverified user
      }
    }

    // Create a Liveblocks session
    const session = liveblocks.prepareSession(verifiedUserId, {
      userInfo: {
        name: verifiedUserName,
        color: userColor || '#000000',
        role: userRole || 'editor',
        avatar: `https://ui-avatars.com/api/?name=${encodeURIComponent(verifiedUserName)}&background=random`,
      },
    });

    // Set permissions based on role
    const role = userRole || 'editor';

    if (role === 'owner') {
      // Owner has full access
      session.allow(roomId, session.FULL_ACCESS);
    } else if (role === 'editor') {
      // Editor can read and write
      session.allow(roomId, [
        'room:read',
        'room:presence:write',
        'room:write'
      ]);
    } else {
      // Viewer can only read and update their presence
      session.allow(roomId, [
        'room:read',
        'room:presence:write'
      ]);
    }

    // Authorize and return the token
    const { status, body } = await session.authorize();

    console.log('Auth response status:', status);
    return res.status(status).send(body);

  } catch (error) {
    console.error('Auth error:', error);
    return res.status(500).json({
      error: 'Authentication failed',
      message: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

// Room management endpoints
app.post('/api/rooms/create', async (req, res) => {
  try {
    const { roomName, userId, userToken } = req.body;

    if (!roomName || !userId) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Generate room ID
    const roomId = `room_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    // Optional: Store room info in your database
    if (supabase) {
      try {
        await supabase.from('collaborative_rooms').insert({
          id: roomId,
          name: roomName,
          created_by: userId,
          created_at: new Date().toISOString(),
          is_active: true
        });
      } catch (dbError) {
        console.warn('Failed to store room info:', dbError);
      }
    }

    res.json({
      roomId,
      roomName,
      createdAt: new Date().toISOString()
    });

  } catch (error) {
    console.error('Room creation error:', error);
    res.status(500).json({ error: 'Failed to create room' });
  }
});

// Get active rooms (optional - if using database)
app.get('/api/rooms/active', async (req, res) => {
  try {
    if (!supabase) {
      return res.json({ rooms: [] });
    }

    const { data, error } = await supabase
      .from('collaborative_rooms')
      .select('*')
      .eq('is_active', true)
      .order('created_at', { ascending: false })
      .limit(20);

    if (error) throw error;

    res.json({ rooms: data || [] });

  } catch (error) {
    console.error('Failed to fetch rooms:', error);
    res.status(500).json({ error: 'Failed to fetch rooms' });
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// Start server
const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`\n🎨 Drawing App Backend Server`);
  console.log(`📡 Running on port ${PORT}`);
  console.log(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`\n🔗 Endpoints:`);
  console.log(`   GET  /health`);
  console.log(`   POST /api/liveblocks-auth`);
  console.log(`   POST /api/rooms/create`);
  console.log(`   GET  /api/rooms/active`);
  console.log(`\n✅ Server is ready!\n`);
});