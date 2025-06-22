import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';

/// Memory-safe picture cache with proper disposal and LRU eviction
class PictureCache {
  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};
  final int _maxCacheSize;
  final Duration _cacheExpiration;
  Timer? _cleanupTimer;

  static const int defaultMaxSize = 20; // Reduced from 50 to prevent memory issues
  static const Duration defaultExpiration = Duration(minutes: 3);

  PictureCache({
    int maxCacheSize = defaultMaxSize,
    Duration cacheExpiration = defaultExpiration,
  }) : _maxCacheSize = maxCacheSize,
        _cacheExpiration = cacheExpiration {
    _startCleanupTimer();
  }

  /// Get picture from cache and update access time
  ui.Picture? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    // Check if expired
    if (DateTime.now().difference(entry.lastAccessed) > _cacheExpiration) {
      remove(key);
      return null;
    }

    // Update access time for LRU
    entry.updateAccess();
    return entry.picture;
  }

  /// Add picture to cache with automatic eviction
  void put(String key, ui.Picture picture) {
    // Remove existing entry if present
    if (_cache.containsKey(key)) {
      remove(key);
    }

    // Evict least recently used entries if cache is full
    while (_cache.length >= _maxCacheSize) {
      _evictLeastRecentlyUsed();
    }

    // Add new entry
    _cache[key] = _CacheEntry(picture);
  }

  /// Remove specific entry and dispose picture
  void remove(String key) {
    final entry = _cache.remove(key);
    if (entry != null) {
      try {
        entry.picture.dispose();
      } catch (e) {
        debugPrint('Error disposing picture for key $key: $e');
      }
    }
  }

  /// Clear all entries and dispose all pictures
  void clear() {
    for (final entry in _cache.values) {
      try {
        entry.picture.dispose();
      } catch (e) {
        debugPrint('Error disposing picture during clear: $e');
      }
    }
    _cache.clear();
  }

  /// Dispose cache and cleanup timer
  void dispose() {
    _cleanupTimer?.cancel();
    clear();
  }

  /// Get current cache size
  int get size => _cache.length;

  /// Check if cache contains key
  bool containsKey(String key) => _cache.containsKey(key);

  /// Get cache statistics for debugging
  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    final expiredCount = _cache.values
        .where((entry) => now.difference(entry.lastAccessed) > _cacheExpiration)
        .length;

    return {
      'totalEntries': _cache.length,
      'maxSize': _maxCacheSize,
      'expiredEntries': expiredCount,
      'memoryUsageEstimate': '${(_cache.length * 0.5).toStringAsFixed(1)}MB', // Rough estimate
    };
  }

  /// Evict least recently used entry
  void _evictLeastRecentlyUsed() {
    if (_cache.isEmpty) return;

    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _cache.entries) {
      if (oldestTime == null || entry.value.lastAccessed.isBefore(oldestTime)) {
        oldestTime = entry.value.lastAccessed;
        oldestKey = entry.key;
      }
    }

    if (oldestKey != null) {
      remove(oldestKey);
    }
  }

  /// Start periodic cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _cleanupExpiredEntries();
    });
  }

  /// Remove expired entries
  void _cleanupExpiredEntries() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _cache.entries) {
      if (now.difference(entry.value.lastAccessed) > _cacheExpiration) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      remove(key);
    }

    // Log cleanup if debugging
    if (expiredKeys.isNotEmpty) {
      debugPrint('PictureCache: Cleaned up ${expiredKeys.length} expired entries');
    }
  }
}

/// Cache entry with access tracking
class _CacheEntry {
  final ui.Picture picture;
  DateTime lastAccessed;

  _CacheEntry(this.picture) : lastAccessed = DateTime.now();

  void updateAccess() {
    lastAccessed = DateTime.now();
  }
}

/// Mixin for widgets that use picture cache to ensure proper disposal
mixin PictureCacheLifecycle<T extends StatefulWidget> on State<T> {
  late PictureCache _pictureCache;

  PictureCache get pictureCache => _pictureCache;

  @override
  void initState() {
    super.initState();
    _pictureCache = PictureCache();
  }

  @override
  void dispose() {
    _pictureCache.dispose();
    super.dispose();
  }
}

/// Debug widget to display cache statistics
class PictureCacheDebugInfo extends StatelessWidget {
  final PictureCache cache;

  const PictureCacheDebugInfo({
    Key? key,
    required this.cache,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final stats = cache.getStats();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Picture Cache Stats', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Entries: ${stats['totalEntries']}/${stats['maxSize']}'),
            Text('Expired: ${stats['expiredEntries']}'),
            Text('Est. Memory: ${stats['memoryUsageEstimate']}'),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () => cache.clear(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    minimumSize: const Size(60, 30),
                  ),
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}