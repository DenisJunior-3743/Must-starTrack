// lib/core/network/connectivity_service.dart
//
// MUST StarTrack — Connectivity Service
//
// Provides a real-time stream of internet connectivity status.
// Used by the SyncRepository to trigger queue flushing when
// the device comes back online.
//
// Also used by the UI layer to show the offline banner
// (HCI Principle: Visibility / Feedback — the user always
// knows they're offline and that their actions are queued).
//
// Built on connectivity_plus which wraps platform-native APIs:
//   Android: ConnectivityManager
//   iOS: Network framework

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  /// Stream emitting true when online, false when offline.
  late final Stream<bool> onConnectivityChanged;

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  ConnectivityService() {
    onConnectivityChanged = _connectivity.onConnectivityChanged
        .map((result) => _mapResult(result))
        .distinct()
        .asBroadcastStream();

    // Update current state whenever it changes.
    onConnectivityChanged.listen((online) {
      _isOnline = online;
      debugPrint(online ? '🌐 Online' : '📴 Offline');
    });

    // Check current state on init.
    _checkInitial();
  }

  Future<void> _checkInitial() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = _mapResult(result);
    debugPrint('ConnectivityService init: ${_isOnline ? "online" : "offline"}');
  }

  bool _mapResult(List<ConnectivityResult> result) {
    return result.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
  }

  /// Manually checks current connectivity.
  Future<bool> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    return _mapResult(result);
  }
}
