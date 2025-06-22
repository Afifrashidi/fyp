// server.js - Fixed Version
const express = require('express');
const cors = require('cors');
const { Liveblocks } = require('@liveblocks/node');
const { createClient } = require('@supabase/supabase-js');
const rateLimit = require('express-rate-limit');

console.log('🚀 Starting server...');

// Load environment variables
console.log('📁 Loading .env file...');
require('dotenv').config();

console.log('\n🔍 ENVIRONMENT VARIABLES DEBUG:');
console.log('================================');
console.log('Current working directory:', process.cwd());
console.log('LIVEBLOCKS_SECRET_KEY exists:', !!process.env.LIVEBLOCKS_SECRET_KEY);
console.log('LIVEBLOCKS_SECRET_KEY value:', process.env.LIVEBLOCKS_SECRET_KEY);
console.log('LIVEBLOCKS_SECRET_KEY length:', process.env.LIVEBLOCKS_SECRET_KEY?.length || 0);
console.log('LIVEBLOCKS_SECRET_KEY starts with sk_:', process.env.LIVEBLOCKS_SECRET_KEY?.startsWith('sk_'));
console.log('LIVEBLOCKS_SECRET_KEY first 10 chars:', process.env.LIVEBLOCKS_SECRET_KEY?.substring(0, 10));

console.log('\nOther environment variables:');
console.log('SUPABASE_URL exists:', !!process.env.SUPABASE_URL);
console.log('PORT:', process.env.PORT);
console.log('NODE_ENV:', process.env.NODE_ENV);

console.log('\nAll environment variables starting with LIVEBLOCKS:');
Object.keys(process.env).filter(key => key.startsWith('LIVEBLOCKS')).forEach(key => {
  console.log(`${key}:`, process.env[key]?.substring(0, 20) + '...');
});

console.log('================================\n');

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

// Initialize Liveblocks - FIXED: Single declaration
let liveblocks = null;

if (!process.env.LIVEBLOCKS_SECRET_KEY) {
  console.log('❌ LIVEBLOCKS_SECRET_KEY is undefined or empty');
  console.log('This means the .env file is not being loaded properly.');
  console.log('Please check:');
  console.log('1. .env file exists in:', process.cwd());
  console.log('2. .env file contains: LIVEBLOCKS_SECRET_KEY=sk_dev_...');
  console.log('3. No spaces around the equals sign');
  console.log('4. File is saved properly');
} else if (!process.env.LIVEBLOCKS_SECRET_KEY.startsWith('sk_')) {
  console.log('❌ LIVEBLOCKS_SECRET_KEY format is invalid');
  console.log('Expected format: sk_dev_... or sk_prod_...');
  console.log('Current value starts with:', process.env.LIVEBLOCKS_SECRET_KEY.substring(0, 10));
} else {
  console.log('✅ LIVEBLOCKS_SECRET_KEY found and appears valid');
  try {
    liveblocks = new Liveblocks({
      secret: process.env.LIVEBLOCKS_SECRET_KEY,
    });
    console.log('✅ Liveblocks initialized successfully');
  } catch (error) {
    console.log('❌ Failed to initialize Liveblocks:', error.message);
  }
}

// Initialize Supabase (optional)
let supabase = null;
if (process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY) {
  try {
    supabase = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_ANON_KEY
    );
    console.log('✅ Supabase initialized successfully');
  } catch (error) {
    console.log('❌ Failed to initialize Supabase:', error.message);
  }
} else {
  console.log('ℹ️ Supabase not configured (optional)');
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    liveblocks: !!liveblocks,
    supabase: !!supabase
  });
});

// Liveblocks authentication endpoint
app.post('/api/liveblocks-auth', async (req, res) => {
  console.log('\n🔐 AUTH REQUEST RECEIVED');
  console.log('Headers:', req.headers);
  console.log('Body:', req.body);

  if (!liveblocks) {
    console.log('❌ Liveblocks not initialized');
    return res.status(500).json({
      error: 'Liveblocks not properly configured',
      details: 'Server configuration issue'
    });
  }

  try {
    const { room, userId, userName, userColor, userRole, userToken } = req.body;

    // Validate required fields
    if (!room || !userId || !userName) {
      console.log('❌ Missing required fields');
      return res.status(400).json({
        error: 'Missing required fields',
        required: ['room', 'userId', 'userName']
      });
    }

    console.log(`📋 Auth request for user: ${userName} (${userId}) in room: ${room}`);

    // Create user info object
    const userInfo = {
      name: userName,
      color: userColor || '#000000',
      role: userRole || 'editor'
    };

    console.log('👤 User info:', userInfo);

    // Prepare session options
    const sessionOptions = {
      userId,
      userInfo,
    };

    console.log('🎫 Creating session with options:', sessionOptions);

    // Create Liveblocks session
    const session = liveblocks.prepareSession(userId, sessionOptions);

    // Grant access to the room
    session.allow(room, session.FULL_ACCESS);

    console.log('✅ Session prepared successfully');

    // Authorize and get token
    const { body, status } = await session.authorize();

    console.log('🎟️ Authorization status:', status);
    console.log('📦 Authorization body type:', typeof body);

    if (status === 200 && body) {
      const responseData = typeof body === 'string' ? JSON.parse(body) : body;
      console.log('✅ Token generated successfully');

      res.status(200).json(responseData);
    } else {
      console.log('❌ Authorization failed:', { status, body });
      res.status(status || 500).json({
        error: 'Authorization failed',
        details: body || 'Unknown error'
      });
    }

  } catch (error) {
    console.log('❌ Auth error:', error);
    res.status(500).json({
      error: 'Authentication failed',
      message: error.message || 'Unknown error'
    });
  }
});

// Error handling middleware
app.use((error, req, res, next) => {
  console.error('❌ Unhandled error:', error);
  res.status(500).json({
    error: 'Internal server error',
    message: error.message || 'Unknown error'
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not found',
    path: req.path
  });
});

// Start server
const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`\n🎨 Drawing App Backend Server`);
  console.log(`📡 Running on port ${PORT}`);
  console.log(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`\n🔗 Available Endpoints:`);
  console.log(`   GET  /health`);
  console.log(`   POST /api/liveblocks-auth`);
  console.log(`\n✅ Server is ready!\n`);
});