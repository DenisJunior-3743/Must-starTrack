// lib/data/remote/fcm_service.dart
//
// MUST StarTrack — FCM Service (Phase 5)
//
// Handles Firebase Cloud Messaging for push notifications.
//
// Responsibilities:
//   1. Request notification permissions (iOS + Android 13+)
//   2. Get and refresh FCM device token → save to Firestore user doc
//   3. Handle foreground messages (show in-app banner)
//   4. Handle background/terminated messages (via background handler)
//   5. Handle notification tap → navigate to correct screen
//
// Notification types and their navigation targets:
//   collaboration  → /notifications
//   message        → /chat/:conversationId
//   opportunity    → /project/:postId
//   achievement    → /notifications
//   endorsement    → /profile/:userId
//   system         → /notifications
//
// Panel defence:
//   "FCM delivers to Firebase servers, which fan out to all registered
//    device tokens for a user. We store the device token in Firestore
//    on login and remove it on logout. Our Dart Cloud Functions
//    (Phase 6) trigger when a message/like/collab event occurs and
//    call the FCM Admin SDK to send the push. The app receives it via
//    this service and routes to the right screen."

import 'dart:async';

import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

import '../local/services/notification_preferences_service.dart';
import '../../core/router/route_names.dart';

// ── Background message handler (top-level function required by FCM) ───────────

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages are shown by FCM system automatically.
  // We only need to handle data-only messages here (no notification payload).
  debugPrint('[FCM Background] ${message.messageId}: ${message.data}');
}

// ── Service ───────────────────────────────────────────────────────────────────

class FcmService {
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FlutterLocalNotificationsPlugin _localNotif;
  final NotificationPreferencesService _preferences;

  // Stored so local-notification taps can navigate without a BuildContext.
  GoRouter? _router;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _tokenRefreshUserId;

  // Android notification channel (must match AndroidManifest.xml)
  static const _channelId = 'startrack_main';
  static const _channelName = 'StarTrack Notifications';
  static const _channelDesc = 'Collaboration requests, messages, and updates';

  FcmService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FlutterLocalNotificationsPlugin? localNotif,
    required NotificationPreferencesService preferences,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _localNotif = localNotif ?? FlutterLocalNotificationsPlugin(),
        _preferences = preferences;

  // ── Initialise ────────────────────────────────────────────────────────────

  /// Call once in main() after Firebase.initializeApp().
  Future<void> init(BuildContext context, GoRouter router) async {
    _router = router;

    // Register background handler (must be top-level function)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Set up local notification plugin
    await _initLocalNotifications();

    // Request permissions
    await _requestPermission();

    // Ensure foreground delivery behavior is explicit on Apple platforms.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Warm up token generation early so login can persist it immediately.
    final startupToken = await _messaging.getToken();
    if (startupToken != null && startupToken.isNotEmpty) {
      debugPrint('[FCM] token ready');
    }

    // Subscribe to foreground messages
    FirebaseMessaging.onMessage
        .listen((msg) => unawaited(_handleForegroundMessage(msg)));

    // Handle notification taps when app is in background (not terminated)
    FirebaseMessaging.onMessageOpenedApp
        .listen((msg) => _routeFromMessage(msg, router));

    // Handle notification tap when app was terminated
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _routeFromMessage(initial, router);
    }
  }

  // ── Request permissions ───────────────────────────────────────────────────

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
    debugPrint('[FCM] permission=${settings.authorizationStatus.name}');
  }

  // ── Local notifications setup ─────────────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotif.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      // Wire up tap-to-navigate for local notifications shown while
      // the app is open or in the background.
      onDidReceiveNotificationResponse: _onLocalNotifTap,
    );

    final androidPlugin = _localNotif.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Channel for FCM foreground messages.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );

    // Channel used by SyncService for realtime activity alerts.
    // Must be created here so it exists before SyncService.startListening()
    // triggers its first notification show() call.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'must_startrack_events',
        'Activity Alerts',
        description:
            'Alerts for follows, comments, views, likes, and collaborations.',
        importance: Importance.max,
      ),
    );
  }

  // ── Get and save device token ─────────────────────────────────────────────

  /// Gets the FCM token and saves it to Firestore under users/{uid}/tokens.
  /// Call on every login so token refreshes are captured.
  Future<void> saveTokenForUser(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[FCM] token unavailable for user=$normalizedUserId');
        return;
      }

      await _firestore
          .collection('users')
          .doc(normalizedUserId)
          .collection('tokens')
          .doc(token)
          .set({
        'token': token,
        'platform': _platform(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('[FCM] token saved for user=$normalizedUserId');

      if (_tokenRefreshUserId != normalizedUserId) {
        await _tokenRefreshSub?.cancel();
        _tokenRefreshUserId = normalizedUserId;
        _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
          try {
            await _firestore
                .collection('users')
                .doc(normalizedUserId)
                .collection('tokens')
                .doc(newToken)
                .set({
              'token': newToken,
              'platform': _platform(),
              'updated_at': FieldValue.serverTimestamp(),
            });
            debugPrint(
                '[FCM] refreshed token saved for user=$normalizedUserId');
          } catch (error) {
            debugPrint('[FCM] token refresh save failed: $error');
          }
        });
      }
    } catch (error) {
      debugPrint('[FCM] token save failed for user=$normalizedUserId: $error');
    }
  }

  /// Removes the device token on logout (prevents push to signed-out devices).
  Future<void> removeTokenForUser(String userId) async {
    final token = await _messaging.getToken();
    if (token == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('tokens')
          .doc(token)
          .delete();
    } catch (_) {
      // Firestore cleanup is best-effort; still clear the device token locally.
    } finally {
      if (_tokenRefreshUserId == userId.trim()) {
        await _tokenRefreshSub?.cancel();
        _tokenRefreshSub = null;
        _tokenRefreshUserId = null;
      }
      await _messaging.deleteToken();
    }
  }

  // ── Handle foreground messages ────────────────────────────────────────────

  /// Shows an in-app local notification banner when app is in foreground.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final type = message.data['type'] as String? ?? 'system';
    if (!_preferences.shouldPresentAlert(
        type: type, requirePushEnabled: true)) {
      return;
    }

    await _localNotif.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: Color(0xFF1152D4), // AppColors.primary
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode({
        'type': type,
        'entity_id': message.data['entity_id'],
        'peer_id': message.data['peer_id'],
      }),
    );
  }

  // ── Route from notification tap ───────────────────────────────────────────

  void _routeFromMessage(RemoteMessage message, GoRouter router) {
    final data = message.data;
    final type = data['type'] as String?;
    final entityId = data['entity_id'] as String?;
    final peerId = data['peer_id'] as String?;
    _routeToScreen(
      type: type,
      entityId: entityId,
      peerId: peerId,
      router: router,
    );
  }

  // ── Local notification tap ────────────────────────────────────────────────

  void _onLocalNotifTap(NotificationResponse response) {
    final router = _router;
    if (router == null) return;
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _routeToScreen(
        type: data['type'] as String?,
        entityId: data['entity_id'] as String?,
        peerId: data['peer_id'] as String?,
        router: router,
      );
    } catch (_) {}
  }

  void _routeToScreen({
    required String? type,
    required String? entityId,
    String? peerId,
    required GoRouter router,
  }) {
    switch (type) {
      case 'message':
        final chatPeerId = peerId ?? entityId;
        if (chatPeerId != null) {
          router.push(
            RouteNames.chatDetail.replaceFirst(':threadId', chatPeerId),
          );
        }
        break;
      case 'opportunity':
      case 'like':
      case 'comment':
      case 'view':
      case 'rating':
      case 'moderation':
        if (entityId != null) {
          router.push('/project/$entityId');
        } else {
          router.push(RouteNames.notifications);
        }
        break;
      case 'collaboration':
        router.push(RouteNames.notifications);
        break;
      case 'group_invite':
        if (entityId != null) {
          router
              .push(RouteNames.groupDetail.replaceFirst(':groupId', entityId));
        } else {
          router.push(RouteNames.notifications);
        }
        break;
      case 'follow':
        if (entityId != null) {
          router.push(RouteNames.profile.replaceFirst(':userId', entityId));
        }
        break;
      case 'endorsement':
        if (entityId != null) {
          router.push(RouteNames.profile.replaceFirst(':userId', entityId));
        }
        break;
      default:
        router.push(RouteNames.notifications);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _platform() {
    // Returns platform identifier for token doc
    try {
      return Platform.isIOS ? 'ios' : 'android';
    } catch (_) {
      return 'unknown';
    }
  }
}
