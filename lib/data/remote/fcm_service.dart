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

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

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

  // Android notification channel (must match AndroidManifest.xml)
  static const _channelId = 'startrack_main';
  static const _channelName = 'StarTrack Notifications';
  static const _channelDesc = 'Collaboration requests, messages, and updates';

  FcmService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FlutterLocalNotificationsPlugin? localNotif,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _localNotif = localNotif ?? FlutterLocalNotificationsPlugin();

  // ── Initialise ────────────────────────────────────────────────────────────

  /// Call once in main() after Firebase.initializeApp().
  Future<void> init(BuildContext context, GoRouter router) async {
    // Register background handler (must be top-level function)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Set up local notification plugin
    await _initLocalNotifications();

    // Request permissions
    await _requestPermission();

    // Subscribe to foreground messages
    FirebaseMessaging.onMessage.listen(
        (msg) => _handleForegroundMessage(msg));

    // Handle notification taps when app is in background (not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen(
        (msg) => _routeFromMessage(msg, router));

    // Handle notification tap when app was terminated
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _routeFromMessage(initial, router);
    }
  }

  // ── Request permissions ───────────────────────────────────────────────────

  Future<void> _requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
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
      const InitializationSettings(
          android: androidSettings, iOS: iosSettings),
    );

    // Create high-importance channel for Android
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ),
        );
  }

  // ── Get and save device token ─────────────────────────────────────────────

  /// Gets the FCM token and saves it to Firestore under users/{uid}/tokens.
  /// Call on every login so token refreshes are captured.
  Future<void> saveTokenForUser(String userId) async {
    final token = await _messaging.getToken();
    if (token == null) return;

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('tokens')
        .doc(token)
        .set({
      'token': token,
      'platform': _platform(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    // Listen for token refreshes
    _messaging.onTokenRefresh.listen((newToken) async {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('tokens')
          .doc(newToken)
          .set({
        'token': newToken,
        'platform': _platform(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Removes the device token on logout (prevents push to signed-out devices).
  Future<void> removeTokenForUser(String userId) async {
    final token = await _messaging.getToken();
    if (token == null) return;

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('tokens')
        .doc(token)
        .delete();

    await _messaging.deleteToken();
  }

  // ── Handle foreground messages ────────────────────────────────────────────

  /// Shows an in-app local notification banner when app is in foreground.
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotif.show(
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
    );
  }

  // ── Route from notification tap ───────────────────────────────────────────

  void _routeFromMessage(RemoteMessage message, GoRouter router) {
    final data = message.data;
    final type = data['type'] as String?;
    final entityId = data['entity_id'] as String?;

    switch (type) {
      case 'message':
        if (entityId != null) {
          router.push('${RouteNames.chatDetail}/$entityId');
        }
        break;
      case 'opportunity':
      case 'collaboration':
        if (entityId != null) {
          router.push('/project/$entityId');
        } else {
          router.push(RouteNames.notifications);
        }
        break;
      case 'endorsement':
        if (entityId != null) {
          router.push('${RouteNames.profile}/$entityId');
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
      return 'android'; // Platform.isIOS ? 'ios' : 'android'
    } catch (_) {
      return 'unknown';
    }
  }
}
