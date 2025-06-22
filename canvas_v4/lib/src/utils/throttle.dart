// lib/src/utils/throttle.dart
import 'dart:async';

/// A utility class for throttling function calls
///
/// This is useful for limiting the frequency of expensive operations
/// like network requests or canvas updates.
class Throttle {
  final Duration duration;
  final void Function(dynamic) onCall;
  Timer? _timer;
  dynamic _lastArgs;
  bool _shouldCallAfterCooldown = false;

  Throttle({
    required this.duration,
    required this.onCall,
  });

  /// Call the function with throttling
  void call(dynamic args) {
    _lastArgs = args;

    if (_timer == null || !_timer!.isActive) {
      // Call immediately if not in cooldown
      onCall(args);
      _startCooldown();
    } else {
      // Mark that we should call after cooldown
      _shouldCallAfterCooldown = true;
    }
  }

  void _startCooldown() {
    _timer?.cancel();
    _timer = Timer(duration, () {
      if (_shouldCallAfterCooldown) {
        _shouldCallAfterCooldown = false;
        onCall(_lastArgs);
        _startCooldown(); // Start another cooldown
      }
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// A debounce utility for delaying function calls until after a period of inactivity
class Debounce {
  final Duration duration;
  final void Function(dynamic) onCall;
  Timer? _timer;

  Debounce({
    required this.duration,
    required this.onCall,
  });

  /// Call the function with debouncing
  void call(dynamic args) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      onCall(args);
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// Rate limiter for controlling the number of calls within a time window
class RateLimiter {
  final int maxCalls;
  final Duration window;
  final List<DateTime> _callTimestamps = [];

  RateLimiter({
    required this.maxCalls,
    required this.window,
  });

  /// Check if a call is allowed based on rate limits
  bool allowCall() {
    final now = DateTime.now();

    // Remove old timestamps outside the window
    _callTimestamps.removeWhere((timestamp) {
      return now.difference(timestamp) > window;
    });

    // Check if we're within the limit
    if (_callTimestamps.length < maxCalls) {
      _callTimestamps.add(now);
      return true;
    }

    return false;
  }

  /// Get the time until the next call is allowed
  Duration? timeUntilNextAllowedCall() {
    if (_callTimestamps.isEmpty || _callTimestamps.length < maxCalls) {
      return Duration.zero;
    }

    final oldestCall = _callTimestamps.first;
    final timeSinceOldest = DateTime.now().difference(oldestCall);

    if (timeSinceOldest >= window) {
      return Duration.zero;
    }

    return window - timeSinceOldest;
  }

  void reset() {
    _callTimestamps.clear();
  }
}