import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../data/remote/firestore_service.dart';
import '../network/connectivity_service.dart';

class UserPresenceService with WidgetsBindingObserver {
  static const _deviceIdKey = 'startrack_presence_device_id';

  final FirestoreService _firestore;
  final FlutterSecureStorage _secureStorage;
  final ConnectivityService _connectivity;

  StreamSubscription<bool>? _connectivitySub;
  Timer? _heartbeat;

  String? _userId;
  String? _deviceId;
  bool _inApp = false;
  bool _networkOnline = false;
  bool _started = false;

  UserPresenceService({
    required FirestoreService firestore,
    required FlutterSecureStorage secureStorage,
    required ConnectivityService connectivity,
  })  : _firestore = firestore,
        _secureStorage = secureStorage,
        _connectivity = connectivity;

  Future<String> _ensureDeviceId() async {
    final existing = await _secureStorage.read(key: _deviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }

    final generated = const Uuid().v4();
    await _secureStorage.write(key: _deviceIdKey, value: generated);
    return generated;
  }

  Future<void> start(String userId) async {
    if (userId.trim().isEmpty) return;

    if (_started && _userId == userId) {
      _inApp = true;
      await _publish();
      return;
    }

    await stop();

    _userId = userId;
    _deviceId = await _ensureDeviceId();
    _networkOnline = await _connectivity.checkConnectivity();
    _inApp = true;

    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = _connectivity.onConnectivityChanged.listen((online) {
      _networkOnline = online;
      unawaited(_publish());
    });

    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_publish());
    });

    _started = true;
    await _publish();
  }

  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;

    if (_started) {
      await _publish(forceOffline: true);
      WidgetsBinding.instance.removeObserver(this);
    }

    _started = false;
    _inApp = false;
    _userId = null;
    _deviceId = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;

    if (state == AppLifecycleState.resumed) {
      _inApp = true;
      unawaited(_publish());
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _inApp = false;
      unawaited(_publish(forceOffline: true));
    }
  }

  Future<void> _publish({bool forceOffline = false}) async {
    final uid = _userId;
    final did = _deviceId;
    if (uid == null || did == null) return;

    await _firestore.setDevicePresence(
      userId: uid,
      deviceId: did,
      isInApp: forceOffline ? false : _inApp,
      isNetworkOnline: forceOffline ? false : _networkOnline,
    );
  }
}
