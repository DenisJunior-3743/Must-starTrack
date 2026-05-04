import 'package:flutter/foundation.dart';

class FeedVideoPlaybackCoordinator {
  FeedVideoPlaybackCoordinator._();

  static final ValueNotifier<bool> playbackAllowed = ValueNotifier<bool>(true);
  static final Set<VoidCallback> _pauseCallbacks = <VoidCallback>{};

  static void setPlaybackAllowed(bool allowed, {String? reason}) {
    if (playbackAllowed.value == allowed) {
      if (!allowed) pauseAll(reason: reason);
      return;
    }

    playbackAllowed.value = allowed;
    if (!allowed) pauseAll(reason: reason);
  }

  static void registerPauseCallback(VoidCallback callback) {
    _pauseCallbacks.add(callback);
  }

  static void unregisterPauseCallback(VoidCallback callback) {
    _pauseCallbacks.remove(callback);
  }

  static void pauseAll({String? reason}) {
    final callbacks = List<VoidCallback>.from(_pauseCallbacks);
    for (final callback in callbacks) {
      callback();
    }
  }
}
