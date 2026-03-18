// lib/data/remote/sync_service.dart
//
// MUST StarTrack — Sync Service (Phase 5)
//
// Processes the SQLite sync_queue table and pushes pending writes
// to Firestore when connectivity is available.
//
// Architecture (panel defence):
//   1. Every mutation (create/update/delete) writes to SQLite first
//   2. SyncQueueDao.enqueue() adds a job to sync_queue table:
//        (entity_type, entity_id, operation, payload_json, attempts, next_retry_at)
//   3. SyncService.processPendingSync() runs:
//        a) On app foreground
//        b) When connectivity restored (ConnectivityService stream)
//        c) Every 5 minutes in background (WorkManager on Android)
//   4. Jobs are processed in order (oldest first)
//   5. Failed jobs use exponential backoff:
//        attempt 1 → retry in 30s
//        attempt 2 → retry in 2 min
//        attempt 3 → retry in 10 min
//        attempt 4 → retry in 1 hr
//        attempt 5 → retry in 6 hr
//        attempt 6+ → dead-letter (shown in admin sync monitor)
//
// Conflict resolution: last-write-wins using Firestore server timestamp.
// For collaborative posts (Phase 6), Operational Transformation is planned.

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/utils/media_path_utils.dart';
import '../local/dao/comment_dao.dart';
import '../local/dao/sync_queue_dao.dart';
import '../local/dao/user_dao.dart';
import '../local/dao/post_dao.dart';
import '../local/dao/message_dao.dart';
import '../local/database_helper.dart';
import 'cloudinary_service.dart';
import 'firestore_service.dart';
import '../models/post_model.dart';

// ── Sync result ───────────────────────────────────────────────────────────────

class SyncResult {
  final int processed;
  final int failed;
  final int remaining;

  const SyncResult({
    required this.processed,
    required this.failed,
    required this.remaining,
  });

  @override
  String toString() =>
      'SyncResult(processed: $processed, failed: $failed, remaining: $remaining)';
}

// ── Service ───────────────────────────────────────────────────────────────────

class SyncService {
  final SyncQueueDao _queueDao;
  final FirestoreService _firestore;
  final UserDao _userDao;
  final PostDao _postDao;
  final CommentDao _commentDao;
  final Connectivity _connectivity;
  final CloudinaryService _cloudinary;
  final FlutterLocalNotificationsPlugin _localNotif;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  SyncService({
    required SyncQueueDao queueDao,
    required FirestoreService firestore,
    required UserDao userDao,
    required PostDao postDao,
    required CommentDao commentDao,
    required CloudinaryService cloudinary,
    required FlutterLocalNotificationsPlugin localNotif,
    Connectivity? connectivity,
  })  : _queueDao = queueDao,
        _firestore = firestore,
        _userDao = userDao,
        _postDao = postDao,
        _commentDao = commentDao,
        _cloudinary = cloudinary,
        _localNotif = localNotif,
        _connectivity = connectivity ?? Connectivity();

  // ── Start listening for connectivity changes ───────────────────────────────

  /// Call once in InjectionContainer.init() or on app foreground.
  void startListening() {
    _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);

      if (isOnline) {
        unawaited(processPendingSync());
        unawaited(syncRemoteToLocal());
      }
    });
  }

  void stopListening() => _connectivitySub?.cancel();

  // ── Process sync queue ────────────────────────────────────────────────────

  /// Main sync loop — drains ready jobs from the queue.
  Future<SyncResult> processPendingSync() async {
    if (_isSyncing) return const SyncResult(processed: 0, failed: 0, remaining: 0);

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      debugPrint('[SyncService] Skipping sync: no active FirebaseAuth session');
      final remaining = await _queueDao.getPendingCount();
      return SyncResult(processed: 0, failed: 0, remaining: remaining);
    }

    _isSyncing = true;
    int processed = 0;
    int failed = 0;

    try {
      try {
        await authUser.getIdToken(true);
      } catch (error) {
        debugPrint('[SyncService] Unable to refresh auth token before sync: $error');
      }

      final jobs = await _queueDao.getReadyJobs(limit: 50);

      for (final job in jobs) {
        final success = await _processJob(job);
        if (success) {
          await _queueDao.deleteJob(job.id);
          processed++;
        } else {
          await _queueDao.incrementAttempt(job.id);
          failed++;
        }
      }

      final remaining = await _queueDao.getPendingCount();
      return SyncResult(processed: processed, failed: failed, remaining: remaining);
    } finally {
      _isSyncing = false;
    }
  }

  /// Pull a recent set of remote posts and authors into SQLite when online.
  Future<void> syncRemoteToLocal({int postLimit = 50}) async {
    try {
      final posts = await _firestore.getRecentPosts(limit: postLimit);
      if (posts.isNotEmpty) {
        final authorIds = posts.map((post) => post.authorId).toSet();
        final users = await _firestore.getUsersByIds(authorIds);
        for (final user in users) {
          await _userDao.insertUser(user);
        }

        for (final post in posts) {
          await _postDao.insertPost(post);
        }
      }
    } catch (error) {
      debugPrint('[SyncService] Post remote-to-local sync failed: $error');
    }

    try {
      // Pull notifications for the current signed-in user from Firestore
      // and upsert into local SQLite so the receiver sees them.
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) {
        final notifSnap = await FirebaseFirestore.instance
            .collection('notifications')
            .where('user_id', isEqualTo: currentUid)
            .orderBy('created_at', descending: true)
            .limit(50)
            .get(const GetOptions(source: Source.serverAndCache));

        final db = await DatabaseHelper.instance.database;
        for (final doc in notifSnap.docs) {
          final d = doc.data();
          final ts = d['created_at'];
          final createdAtMs = ts is Timestamp
              ? ts.millisecondsSinceEpoch
              : DateTime.now().millisecondsSinceEpoch;
          final existing = await db.query(
            'notifications',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [doc.id],
            limit: 1,
          );
          final row = <String, Object?>{
            'id':              doc.id,
            'user_id':         d['user_id']         as String? ?? currentUid,
            'type':            d['type']            as String? ?? 'system',
            'sender_id':       d['sender_id']       as String?,
            'sender_name':     d['sender_name']     as String?,
            'sender_photo_url':d['sender_photo_url'] as String?,
            'body':            d['body']            as String? ?? '',
            'detail':          d['detail']          as String?,
            'entity_id':       d['entity_id']       as String?,
            'created_at':      createdAtMs,
            'is_read':         (d['is_read'] as bool? ?? false) ? 1 : 0,
            'extra_json':      d['extra_json']      as String?,
          };
          await db.insert('notifications', row, conflictAlgorithm: ConflictAlgorithm.replace);
          if (existing.isEmpty && !notifSnap.metadata.isFromCache) {
            await _showLocalAlertForNotification(row);
          }
        }

        debugPrint(
          '[SyncService] Pulled ${notifSnap.docs.length} notification(s) '
          'for $currentUid fromCache=${notifSnap.metadata.isFromCache}',
        );
      }
    } catch (error) {
      debugPrint('[SyncService] Notification remote-to-local sync failed: $error');
    }
  }

  // ── Process a single job ──────────────────────────────────────────────────

  Future<bool> _processJob(SyncJob job) async {
    try {
      switch (job.entityType) {
        case 'users':
          return await _syncUser(job);
        case 'posts':
          return await _syncPost(job);
        case 'message':
          return await _syncMessage(job);
        case 'follows':
          return await _syncFollow(job);
        case 'notifications':
          return await _syncNotification(job);
        case 'likes':
          return await _syncLike(job);
        case 'comments':
          return await _syncComment(job);
        case 'post_views':
          return await _syncPostView(job);
        case 'collab_requests':
          return await _syncCollabRequest(job);
        default:
          // Unknown entity type — remove from queue to prevent blocking
          return true;
      }
    } catch (e, st) {
      // Log and return false to trigger backoff
      debugPrint('[SyncService] ❌ Job id=${job.id} type=${job.entityType} failed: $e\n$st');
      return false;
    }
  }

  // ── User sync ─────────────────────────────────────────────────────────────

  Future<bool> _syncUser(SyncJob job) async {
    final user = await _userDao.getUserById(job.entityId);
    if (user == null) return true; // deleted locally → nothing to sync

    switch (job.operation) {
      case 'create':
      case 'update':
        await _firestore.setUser(user);
        return true;
      case 'delete':
        // Users are never hard-deleted from Firestore — soft delete only
        await FirebaseFirestore.instance
            .collection('users')
            .doc(job.entityId)
            .update({'is_deleted': true, 'deleted_at': FieldValue.serverTimestamp()});
        return true;
      default:
        return true;
    }
  }

  // ── Post sync ─────────────────────────────────────────────────────────────

  Future<bool> _syncPost(SyncJob job) async {
    switch (job.operation) {
      case 'create':
      case 'update':
        final payload = job.payloadJson;
        PostModel? postFromPayload;
        if (payload.isNotEmpty) {
          try {
            postFromPayload = PostModel.fromJson({
              'id': job.entityId,
              ...payload,
            });
          } catch (_) {}
        }

        final localPost = await _postDao.getPostById(job.entityId);
        final post = localPost == null
            ? postFromPayload
            : (postFromPayload != null &&
                    postFromPayload.mediaUrls.isNotEmpty &&
                    localPost.mediaUrls.isEmpty)
                ? localPost.copyWith(
                    mediaUrls: postFromPayload.mediaUrls,
                    youtubeUrl: postFromPayload.youtubeUrl,
                    externalLinks: postFromPayload.externalLinks,
                  )
                : localPost;

        if (post == null) return true;
        final syncedPost = await _uploadPendingPostMedia(post);
        await _firestore.setPost(syncedPost);
        return true;
      case 'archive':
        await _firestore.archivePost(job.entityId);
        return true;
      case 'delete':
        await _firestore.deletePost(job.entityId);
        return true;
      default:
        return true;
    }
  }

  // ── Message sync ──────────────────────────────────────────────────────────

  Future<bool> _syncMessage(SyncJob job) async {
    if (job.operation == 'delete') {
      await FirebaseFirestore.instance
          .collectionGroup('messages')
          .where('id', isEqualTo: job.entityId)
          .get()
          .then((snap) {
        for (final doc in snap.docs) { doc.reference.delete(); }
      });
      return true;
    }

    // Create — build MessageModel from payload JSON
    final payload = job.payloadJson;
    if (payload.isEmpty) return true;

    final msg = MessageModel(
      id: job.entityId,
      conversationId: payload['conversation_id'] as String,
      senderId: payload['sender_id'] as String,
      content: payload['content'] as String,
      messageType: payload['message_type'] as String? ?? 'text',
      createdAt: DateTime.tryParse(
              payload['created_at'] as String? ?? '') ??
          DateTime.now(),
    );

    await _firestore.sendMessage(msg);
    return true;
  }

  // ── Follow sync ───────────────────────────────────────────────────────────

  Future<bool> _syncFollow(SyncJob job) async {
    final payload = job.payloadJson;
    final followerId = payload['follower_id'] as String?;
    final followingId = payload['following_id'] as String?;

    if (followerId == null || followingId == null) return true;

    // Guard: Firestore rule requires follower_id == uid(). If this job was
    // queued under a different account (e.g. during testing), skip it so it
    // doesn't block the queue or generate misleading PERMISSION_DENIED logs.
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != followerId) {
      debugPrint(
          '[SyncService] ⚠️ Skipping follow job ${job.id}: '
          'follower=$followerId but current uid=$currentUid — removing from queue.');
      return true; // drop the job; it can never succeed for this session
    }

    if (job.operation == 'create') {
      await _firestore.follow(
          followerId: followerId, followingId: followingId);
      final followerName = payload['follower_name'] as String? ?? 'Someone';
      if (followingId != followerId) {
        await _upsertUserNotification(
          notificationId: 'follow_${followerId}_$followingId',
          receiverId: followingId,
          senderId: followerId,
          senderName: followerName,
          type: 'follow',
          body: '$followerName started following you',
          entityId: followingId,
        );
      }
    } else if (job.operation == 'delete') {
      await _firestore.unfollow(
          followerId: followerId, followingId: followingId);
    }
    return true;
  }

  // ── Notification sync ─────────────────────────────────────────────────────

  Future<bool> _syncNotification(SyncJob job) async {
    // Phase 6: Cloud Functions will handle notification fan-out.
    // For now, mark as done.
    return true;
  }

  // ── Like sync ─────────────────────────────────────────────────────────────

  Future<bool> _syncLike(SyncJob job) async {
    final payload = job.payloadJson;
    final userId = payload['user_id'] as String?;
    final postId = payload['post_id'] as String?;
    final isLiking = payload['is_liking'] as bool? ?? true;

    if (userId == null || postId == null) return true;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != userId) {
      debugPrint(
        '[SyncService] ⚠️ Skipping like job ${job.id}: '
        'payload user=$userId but current uid=$currentUid — removing from queue.',
      );
      return true;
    }

    await _firestore.toggleLike(
      postId: postId,
      userId: userId,
      isLiking: isLiking,
    );

    final authorId = payload['author_id'] as String?;
    if (isLiking && authorId != null && authorId != userId) {
      final actorName = payload['actor_name'] as String? ?? 'Someone';
      final postTitle = payload['post_title'] as String? ?? 'your project';
      await _upsertUserNotification(
        notificationId: 'like_${userId}_$postId',
        receiverId: authorId,
        senderId: userId,
        senderName: actorName,
        type: 'like',
        body: '$actorName liked "$postTitle"',
        entityId: postId,
      );
    }
    return true;
  }

  Future<bool> _syncComment(SyncJob job) async {
    final payload = job.payloadJson;
    final authorId = payload['author_id'] as String?;
    final postId = payload['post_id'] as String?;
    final content = payload['content'] as String? ?? '';

    if (authorId == null || postId == null || content.trim().isEmpty) {
      return true;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != authorId) {
      debugPrint(
        '[SyncService] ⚠️ Skipping comment job ${job.id}: '
        'author=$authorId but current uid=$currentUid — removing from queue.',
      );
      return true;
    }

    final hasValidSession = await _hasValidMustSession(
      context: 'comment write',
    );
    if (!hasValidSession) {
      return false;
    }

    await _logCommentPermissionContext(
      context: 'comment write',
      authorId: authorId,
      postId: postId,
      jobId: job.id,
    );

    await FirebaseFirestore.instance.collection('comments').doc(job.entityId).set({
      'id': job.entityId,
      'post_id': postId,
      'author_id': authorId,
      'content': content,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final receiverId = payload['receiver_id'] as String?;
    if (receiverId != null && receiverId != authorId) {
      final commenterName = payload['commenter_name'] as String? ?? 'Someone';
      final postTitle = payload['post_title'] as String? ?? 'your project';
      await _upsertUserNotification(
        notificationId: 'comment_${job.entityId}',
        receiverId: receiverId,
        senderId: authorId,
        senderName: commenterName,
        type: 'comment',
        body: '$commenterName commented on "$postTitle"',
        detail: content,
        entityId: postId,
      );
    }

    return true;
  }

  Future<bool> _syncPostView(SyncJob job) async {
    final payload = job.payloadJson;
    final viewerId = payload['viewer_id'] as String?;
    final postId = payload['post_id'] as String?;

    if (viewerId == null || postId == null) {
      return true;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != viewerId) {
      debugPrint(
        '[SyncService] ⚠️ Skipping post view job ${job.id}: '
        'viewer=$viewerId but current uid=$currentUid — removing from queue.',
      );
      return true;
    }

    final authorId = payload['author_id'] as String?;
    if (authorId != null && authorId != viewerId) {
      final viewerName = payload['viewer_name'] as String? ?? 'Someone';
      final postTitle = payload['post_title'] as String? ?? 'your project';
      await _upsertUserNotification(
        notificationId: 'view_${job.entityId}',
        receiverId: authorId,
        senderId: viewerId,
        senderName: viewerName,
        type: 'view',
        body: '$viewerName viewed "$postTitle"',
        entityId: postId,
      );
    }

    return true;
  }

  // ── Collab request sync ──────────────────────────────────────────────────

  Future<bool> _syncCollabRequest(SyncJob job) async {
    debugPrint('[SyncCollab] Processing job id=${job.id} entityId=${job.entityId} retryCount=${job.retryCount}');
    final payload = job.payloadJson;
    final senderId   = payload['sender_id']   as String?;
    final receiverId = payload['receiver_id'] as String?;
    final postId     = payload['post_id']     as String?;
    final message    = payload['message']     as String? ?? '';
    final status     = payload['status']      as String? ?? 'pending';

    debugPrint('[SyncCollab] Payload — sender=$senderId receiver=$receiverId postId=$postId status=$status');

    if (senderId == null || receiverId == null) {
      debugPrint('[SyncCollab] ⚠️ Missing sender or receiver — skipping job');
      return true;
    }

    final authUser = FirebaseAuth.instance.currentUser;
    final currentUid = authUser?.uid;
    if (currentUid != senderId) {
      debugPrint(
        '[SyncCollab] ⚠️ Skipping collab job ${job.id}: '
        'sender=$senderId but current uid=$currentUid — removing from queue.',
      );
      return true;
    }

    debugPrint(
      '[SyncCollab] Auth session uid=$currentUid email=${authUser?.email} '
      'for sender=$senderId',
    );

    debugPrint('[SyncCollab] Writing to Firestore collab_requests/${job.entityId}');
    await FirebaseFirestore.instance
        .collection('collab_requests')
        .doc(job.entityId)
        .set({
      'id':          job.entityId,
      'sender_id':   senderId,
      'receiver_id': receiverId,
      'post_id':     postId,
      'message':     message,
      'status':      status,
      'created_at':  FieldValue.serverTimestamp(),
      'updated_at':  FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('[SyncCollab] ✅ Firestore write OK for ${job.entityId}');

    final collabVerify = await FirebaseFirestore.instance
        .collection('collab_requests')
        .doc(job.entityId)
        .get(const GetOptions(source: Source.serverAndCache));
    debugPrint(
      '[SyncCollab] Verify collab_requests/${job.entityId} '
      'exists=${collabVerify.exists} fromCache=${collabVerify.metadata.isFromCache}',
    );

    // Also write a notification document for the receiver so their device
    // picks it up on the next syncRemoteToLocal pull.
    final senderName = payload['sender_name']  as String? ?? 'Someone';
    final postTitle  = payload['post_title']   as String? ?? 'a project';
    final notifId = 'collab_notif_${job.entityId}';
    await _upsertUserNotification(
      notificationId: notifId,
      receiverId: receiverId,
      senderId: senderId,
      senderName: senderName,
      type: 'collaboration',
      body: '$senderName sent you a collaboration request for "$postTitle"',
      detail: message.isNotEmpty ? message : null,
      entityId: job.entityId,
    );
    debugPrint('[SyncCollab] ✅ Receiver notification written for $notifId');
    return true;
  }

  Future<void> syncCommentsForPost(String postId) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint('[SyncService] Skipping comment sync: no active FirebaseAuth session');
      return;
    }

    final hasValidSession = await _hasValidMustSession(
      context: 'comment read',
    );
    if (!hasValidSession) {
      return;
    }

    await _logCommentPermissionContext(
      context: 'comment read',
      postId: postId,
    );

    try {
      final snap = await FirebaseFirestore.instance
          .collection('comments')
          .where('post_id', isEqualTo: postId)
          .limit(100)
          .get(const GetOptions(source: Source.serverAndCache));

      final docs = [...snap.docs]
        ..sort((a, b) {
          final aTs = a.data()['created_at'];
          final bTs = b.data()['created_at'];
          final aMs = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
          final bMs = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
          return bMs.compareTo(aMs);
        });

      for (final doc in docs) {
        final data = doc.data();
        final createdAt = data['created_at'] is Timestamp
            ? (data['created_at'] as Timestamp).toDate()
            : DateTime.now();
        await _commentDao.upsertRemoteComment(
          commentId: doc.id,
          postId: data['post_id'] as String? ?? postId,
          authorId: data['author_id'] as String? ?? '',
          content: data['content'] as String? ?? '',
          createdAt: createdAt,
        );
      }
    } catch (error) {
      debugPrint('[SyncService] Comment remote-to-local sync failed: $error');
    }
  }

  Future<void> _upsertUserNotification({
    required String notificationId,
    required String receiverId,
    required String senderId,
    required String type,
    required String body,
    String? detail,
    String? entityId,
    String? senderName,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').doc(notificationId).set({
      'id': notificationId,
      'user_id': receiverId,
      'type': type,
      'sender_id': senderId,
      'sender_name': senderName,
      'body': body,
      'detail': detail,
      'entity_id': entityId,
      'is_read': false,
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _showLocalAlertForNotification(Map<String, Object?> row) async {
    final title = _notificationTitle(row['type'] as String? ?? 'system');
    final body = row['body'] as String? ?? 'You have a new notification.';
    await _localNotif.show(
      row['id'].hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'must_startrack_events',
          'Activity Alerts',
          channelDescription: 'Alerts for follows, comments, views, likes, and collaborations.',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  String _notificationTitle(String type) {
    switch (type) {
      case 'follow':
        return 'New follower';
      case 'like':
        return 'New like';
      case 'comment':
        return 'New comment';
      case 'view':
        return 'New view';
      case 'collaboration':
        return 'Collaboration request';
      default:
        return 'MUST StarTrack';
    }
  }

  Future<bool> _hasValidMustSession({required String context}) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      debugPrint('[SyncService] Skipping $context: no active FirebaseAuth session');
      return false;
    }

    final email = authUser.email ?? '';

    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .get(const GetOptions(source: Source.serverAndCache));

      if (!userSnap.exists) {
        debugPrint(
          '[SyncService] Delaying $context: users/${authUser.uid} is missing in Firestore.',
        );
        return false;
      }

      final role = (userSnap.data()?['role'] as String? ?? '').toLowerCase();
      final allowed = _emailMatchesRole(role: role, email: email);
      if (!allowed) {
        debugPrint(
          '[SyncService] Delaying $context: email=$email does not match role=$role.',
        );
      }
      return allowed;
    } catch (error) {
      debugPrint('[SyncService] Unable to validate MUST session for $context: $error');
      return false;
    }
  }

  bool _emailMatchesRole({required String role, required String email}) {
    if (role == 'student') {
      return email.endsWith('@std.must.ac.ug');
    }
    if (role == 'staff' || role == 'lecturer') {
      return email.endsWith('@staff.must.ac.ug');
    }
    if (role == 'admin' || role == 'super_admin') {
      return email.endsWith('@must.ac.ug');
    }
    return false;
  }

  Future<void> _logCommentPermissionContext({
    required String context,
    required String postId,
    String? authorId,
    String? jobId,
  }) async {
    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null) {
        debugPrint('[SyncService] $context diagnostic: no auth user');
        return;
      }

      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .get(const GetOptions(source: Source.serverAndCache));

      final role = userSnap.data()?['role'];
      debugPrint(
        '[SyncService] $context diagnostic: '
        'jobId=$jobId uid=${authUser.uid} email=${authUser.email} '
        'firestoreRole=$role authorId=$authorId postId=$postId',
      );
    } catch (error) {
      debugPrint('[SyncService] $context diagnostic failed: $error');
    }
  }

  // ── Queue depth metric (for super admin dashboard) ────────────────────────

  Future<int> getQueueDepth() => _queueDao.getPendingCount();

  Future<PostModel> _uploadPendingPostMedia(PostModel post) async {
    final pendingPaths = post.mediaUrls.where(isLocalMediaPath).toList();
    if (pendingPaths.isEmpty) {
      return post;
    }

    if (!_cloudinary.isConfigured) {
      throw Exception('Cloudinary is not configured for deferred media sync.');
    }

    final uploadedUrls = <String>[];
    for (final mediaPath in post.mediaUrls) {
      if (!isLocalMediaPath(mediaPath)) {
        uploadedUrls.add(mediaPath);
        continue;
      }

      final file = File(mediaPath);
      if (!await file.exists()) {
        throw Exception('Pending media file is missing: $mediaPath');
      }

      final uploadedUrl = await _cloudinary.uploadFile(file);
      uploadedUrls.add(uploadedUrl);
    }

    final syncedPost = post.copyWith(
      mediaUrls: uploadedUrls,
      updatedAt: DateTime.now(),
    );
    await _postDao.updatePost(syncedPost);

    for (final mediaPath in pendingPaths) {
      final file = File(mediaPath);
      if (await file.exists()) {
        await file.delete().catchError((_) => file);
      }
    }

    return syncedPost;
  }

  /// Returns sync health as a map for the engineering metrics panel.
  Future<Map<String, dynamic>> getSyncMetrics() async {
    final pending = await _queueDao.getPendingCount();
    final deadLetter = await _queueDao.getDeadLetterCount();

    return {
      'queue_depth': pending,
      'dead_letter_count': deadLetter,
      'is_syncing': _isSyncing,
    };
  }
}
