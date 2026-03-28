// lib/core/services/session_timeout_service.dart
//
// MUST StarTrack — Session Timeout Service
//
// Prevents sessions from overstaying by enforcing two expiry policies:
//
//   1. Inactivity timeout (30 min)
//      A Dart Timer resets on every user gesture (PointerDown event).
//      If the device sits idle for 30 minutes while the app is open,
//      the session is terminated.
//
//   2. Background / restart stale check (8 h)
//      The last-active timestamp is persisted in SharedPreferences.
//      On app launch (restart) and on foreground resume, if more than
//      8 hours have elapsed since the last gesture, the session is
//      considered stale and is immediately expired.
//
// Integration points:
//   • InjectionContainer registers it as a singleton.
//   • main.dart checks isStale() after checkAuthStatus() on launch.
//   • app.dart (_StarTrackAppState):
//       - Calls startTracking() when AuthAuthenticated.
//       - Calls stopTracking() when AuthUnauthenticated.
//       - Calls resetActivity() on AppLifecycleState.resumed.
//       - Checks isStale() on resumed and expires if true.
//   • A Listener widget in app.dart calls resetActivity() on every touch.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionTimeoutService {
  // ── Configuration constants ───────────────────────────────────────────────

  /// Screen-idle time before automatic sign-out.
  static const inactivityTimeout = Duration(minutes: 30);

  /// Maximum elapsed time while the app is backgrounded / device is off
  /// before the session is treated as stale on next foreground/launch.
  static const backgroundTimeout = Duration(hours: 8);

  static const _kLastActiveKey = 'session_last_active_ms';

  // ── State ─────────────────────────────────────────────────────────────────

  final SharedPreferences _prefs;
  VoidCallback? _onExpired;
  Timer? _timer;

  SessionTimeoutService({required SharedPreferences prefs}) : _prefs = prefs;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Begin tracking inactivity. Call when the user becomes authenticated.
  /// [onExpired] is invoked on the main isolate when the session should end.
  void startTracking({required VoidCallback onExpired}) {
    _onExpired = onExpired;
    resetActivity();
  }

  /// Stamp the current time as last-active and restart the inactivity
  /// countdown. Idempotent — safe to call from every pointer-down event.
  /// No-op when not currently tracking (i.e. user not authenticated).
  void resetActivity() {
    if (_onExpired == null) return;
    _prefs.setInt(_kLastActiveKey, DateTime.now().millisecondsSinceEpoch);
    _timer?.cancel();
    _timer = Timer(inactivityTimeout, _expire);
  }

  /// Stop tracking and clear the persisted timestamp.
  /// Call on explicit user logout so the next login starts clean.
  void stopTracking() {
    _timer?.cancel();
    _timer = null;
    _onExpired = null;
    _prefs.remove(_kLastActiveKey);
  }

  /// Returns true if enough time has passed since the last recorded
  /// activity to consider the session stale. Used on launch and resume.
  /// Returns false if the timestamp is absent (fresh install / logged out).
  bool isStale() {
    final lastMs = _prefs.getInt(_kLastActiveKey);
    if (lastMs == null) return false;
    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastMs),
    );
    return elapsed > backgroundTimeout;
  }

  /// Cancel timers. Call from the root widget's dispose().
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _expire() {
    _timer = null;
    // Capture and clear before calling to prevent re-entrancy.
    final cb = _onExpired;
    _onExpired = null;
    _prefs.remove(_kLastActiveKey);
    cb?.call();
  }
}
