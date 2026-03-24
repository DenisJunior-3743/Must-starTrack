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
import 'dart:convert';
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
import '../local/services/notification_preferences_service.dart';
import '../local/database_helper.dart';
import '../local/schema/database_schema.dart';
import 'cloudinary_service.dart';
import 'firestore_service.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';

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
  final NotificationPreferencesService _preferences;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;
  bool _isHydrating = false;

  SyncService({
    required SyncQueueDao queueDao,
    required FirestoreService firestore,
    required UserDao userDao,
    required PostDao postDao,
    required CommentDao commentDao,
    required CloudinaryService cloudinary,
    required FlutterLocalNotificationsPlugin localNotif,
    required NotificationPreferencesService preferences,
    Connectivity? connectivity,
  })  : _queueDao = queueDao,
        _firestore = firestore,
        _userDao = userDao,
        _postDao = postDao,
        _commentDao = commentDao,
        _cloudinary = cloudinary,
        _localNotif = localNotif,
        _preferences = preferences,
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
      debugPrint('[SyncService] Starting sync loop with ${jobs.length} ready job(s).');

      for (final job in jobs) {
        debugPrint(
          '[SyncService] Processing job id=${job.id} entity=${job.entityType} '
          'operation=${job.operation} entityId=${job.entityId} retry=${job.retryCount}',
        );
        final success = await _processJob(job);
        if (success) {
          await _queueDao.deleteJob(job.id);
          debugPrint('[SyncService] Job id=${job.id} entity=${job.entityType} completed and removed from queue.');
          processed++;
        } else {
          await _queueDao.incrementAttempt(job.id);
          debugPrint('[SyncService] Job id=${job.id} entity=${job.entityType} failed and will retry.');
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
    if (_isHydrating) {
      debugPrint('[SyncService] Skipping remote hydration because a previous syncRemoteToLocal is still running.');
      return;
    }

    _isHydrating = true;
    final syncedPostIds = <String>[];
    try {
      await _runHydrationStep('posts', () async {
        final posts = await _firestore.getRecentPosts(limit: postLimit);
        syncedPostIds
          ..clear()
          ..addAll(posts.map((post) => post.id));
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
      });

      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) {
        await _runHydrationStep('messages', () => _syncRemoteMessages(currentUid));
        await _runHydrationStep('notifications', () async {
          debugPrint('[SyncService] Pulling remote notifications for user=$currentUid');
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
              columns: ['id', 'is_read', 'extra_json'],
              where: 'id = ?',
              whereArgs: [doc.id],
              limit: 1,
            );
            final localRead = existing.isNotEmpty && (existing.first['is_read'] as int? ?? 0) == 1;
            final remoteRead = d['is_read'] as bool? ?? false;
            final effectiveIsRead = localRead || remoteRead;
            final localExtraJson = existing.isNotEmpty ? existing.first['extra_json'] as String? : null;
            final remoteExtra = d['extra'];
            final remoteExtraJson = d['extra_json'] as String?
                ?? (remoteExtra is Map<String, dynamic>
                    ? jsonEncode(remoteExtra)
                    : remoteExtra is Map
                        ? jsonEncode(Map<String, dynamic>.from(remoteExtra))
                        : null);
            final row = <String, Object?>{
              'id': doc.id,
              'user_id': d['user_id'] as String? ?? currentUid,
              'type': d['type'] as String? ?? 'system',
              'sender_id': d['sender_id'] as String?,
              'sender_name': d['sender_name'] as String?,
              'sender_photo_url': d['sender_photo_url'] as String?,
              'body': d['body'] as String? ?? '',
              'detail': d['detail'] as String?,
              'entity_id': d['entity_id'] as String?,
              'created_at': createdAtMs,
              'is_read': effectiveIsRead ? 1 : 0,
              'extra_json': localExtraJson ?? remoteExtraJson,
            };
            await db.insert('notifications', row, conflictAlgorithm: ConflictAlgorithm.replace);
            if (existing.isEmpty && !notifSnap.metadata.isFromCache && !effectiveIsRead) {
              await _showLocalAlertForNotification(row);
            }
          }

          debugPrint(
            '[SyncService] Pulled ${notifSnap.docs.length} notification(s) '
            'for $currentUid fromCache=${notifSnap.metadata.isFromCache}',
          );
        });

        await _runHydrationStep('follows', () => _syncRemoteFollows(currentUid));
        await _runHydrationStep('likes', () => _syncRemoteLikes(currentUid, candidatePostIds: syncedPostIds));
        await _runHydrationStep('dislikes', () => _syncRemoteDislikes(currentUid, candidatePostIds: syncedPostIds));
        await _runHydrationStep('post_views', () => _syncRemotePostViews(currentUid));
        await _runHydrationStep('collab_requests', () => _syncRemoteCollabRequests(currentUid));
        await _runHydrationStep('post_joins', () => _syncRemoteOpportunityJoins(currentUid));
      }
    } finally {
      _isHydrating = false;
    }
  }

  Future<void> markConversationReadRemote({
    required String conversationId,
    required String userId,
  }) async {
    try {
      await _firestore.markConversationRead(
        conversationId: conversationId,
        userId: userId,
      );
    } catch (error) {
      debugPrint('[SyncService] markConversationReadRemote failed for conversation=$conversationId user=$userId: $error');
    }
  }

  Future<void> _runHydrationStep(String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      debugPrint('[SyncService] $label remote-to-local sync failed: $error');
      debugPrint('[SyncService] $label remote-to-local stacktrace: $stackTrace');
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
        case 'conversation':
          return await _syncConversation(job);
        case 'message':
          return await _syncMessage(job);
        case 'follows':
          return await _syncFollow(job);
        case 'notifications':
          return await _syncNotification(job);
        case 'likes':
          return await _syncLike(job);
        case 'dislikes':
          return await _syncDislike(job);
        case 'comments':
          return await _syncComment(job);
        case 'post_views':
          return await _syncPostView(job);
        case 'collab_requests':
          return await _syncCollabRequest(job);
        case 'opportunity_joins':
          return await _syncOpportunityJoin(job);
        case 'moderation_queue':
          return await _syncModerationReport(job);
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

  Future<bool> _syncConversation(SyncJob job) async {
    if (job.operation != 'delete') {
      return true;
    }

    await _firestore.deleteConversation(job.entityId);
    return true;
  }

  Future<bool> _syncMessage(SyncJob job) async {
    debugPrint('[SyncMessage] Processing job id=${job.id} operation=${job.operation} entityId=${job.entityId}');

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
    if (payload.isEmpty) {
      debugPrint('[SyncMessage] ⚠️ Empty payload for job id=${job.id} — skipping');
      return true;
    }

    debugPrint('[SyncMessage] Payload: conversationId=${payload['conversation_id']} '
        'senderId=${payload['sender_id']} content="${payload['content']}"');

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

    debugPrint('[SyncMessage] Writing to Firestore conversations/${msg.conversationId}/messages/${msg.id}');
    await _firestore.sendMessage(msg);
    debugPrint('[SyncMessage] ✅ Message ${msg.id} written to Firestore successfully');
    return true;
  }

  // ── Follow sync ───────────────────────────────────────────────────────────

  Future<bool> _syncFollow(SyncJob job) async {
    final payload = job.payloadJson;
    final followerId = payload['follower_id'] as String?;
    final followingId = payload['following_id'] as String?;

    if (followerId == null || followingId == null) {
      debugPrint('[SyncFollow] Skipping malformed job id=${job.id} payload=$payload');
      return true;
    }

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
      debugPrint('[SyncFollow] Writing follow follower=$followerId followee=$followingId');
      await _firestore.follow(
          followerId: followerId, followingId: followingId);
      final followerName = payload['follower_name'] as String? ?? 'Someone';
      if (followingId != followerId) {
        await _bestEffortUserNotification(
          source: 'follow',
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
      debugPrint('[SyncFollow] Removing follow follower=$followerId followee=$followingId');
      await _firestore.unfollow(
          followerId: followerId, followingId: followingId);
    }
    return true;
  }

  // ── Notification sync ─────────────────────────────────────────────────────

  Future<bool> _syncNotification(SyncJob job) async {
    final payload = job.payloadJson;
    final notificationId = payload['notification_id'] as String? ?? job.entityId;
    if (notificationId.isEmpty) {
      return true;
    }

    final updates = <String, Object?>{};
    if (payload.containsKey('is_read')) {
      updates['is_read'] = payload['is_read'] == true;
    }
    if (payload.containsKey('extra_json')) {
      final raw = payload['extra_json'] as String?;
      if (raw == null || raw.isEmpty) {
        updates['extra'] = null;
      } else {
        try {
          updates['extra'] = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          debugPrint('[SyncNotification] Unable to decode extra_json for notification=$notificationId raw=$raw');
        }
      }
    }
    if (updates.isEmpty) {
      return true;
    }

    debugPrint('[SyncNotification] Updating notification=$notificationId keys=${updates.keys.toList()}');

    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId)
        .set(updates, SetOptions(merge: true));
    return true;
  }

  // ── Like sync ─────────────────────────────────────────────────────────────

  Future<bool> _syncLike(SyncJob job) async {
    final payload = job.payloadJson;
    final userId = payload['user_id'] as String?;
    final postId = payload['post_id'] as String?;
    final isLiking = payload['is_liking'] as bool? ?? true;

    if (userId == null || postId == null) {
      debugPrint('[SyncLike] Skipping malformed job id=${job.id} payload=$payload');
      return true;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != userId) {
      debugPrint(
        '[SyncService] ⚠️ Skipping like job ${job.id}: '
        'payload user=$userId but current uid=$currentUid — removing from queue.',
      );
      return true;
    }

    debugPrint('[SyncLike] Writing remote like post=$postId user=$userId isLiking=$isLiking');
    await _firestore.toggleLike(
      postId: postId,
      userId: userId,
      isLiking: isLiking,
    );

    final authorId = payload['author_id'] as String?;
    if (isLiking && authorId != null && authorId != userId) {
      final actorName = payload['actor_name'] as String? ?? 'Someone';
      final postTitle = payload['post_title'] as String? ?? 'your project';
      await _bestEffortUserNotification(
        source: 'like',
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

  Future<bool> _syncDislike(SyncJob job) async {
    final payload = job.payloadJson;
    final userId = payload['user_id'] as String?;
    final postId = payload['post_id'] as String?;
    final isDisliking = payload['is_disliking'] as bool? ?? true;

    if (userId == null || postId == null) {
      debugPrint('[SyncDislike] Skipping malformed job id=${job.id} payload=$payload');
      return true;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != userId) {
      debugPrint(
        '[SyncService] ⚠️ Skipping dislike job ${job.id}: '
        'payload user=$userId but current uid=$currentUid — removing from queue.',
      );
      return true;
    }

    final dislikeRef = FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('dislikes')
        .doc(userId);

    if (isDisliking) {
      await dislikeRef.set({
        'user_id': userId,
        'created_at': FieldValue.serverTimestamp(),
      });
    } else {
      await dislikeRef.delete();
    }

    return true;
  }

  Future<bool> _syncComment(SyncJob job) async {
    final payload = job.payloadJson;
    final authorId = payload['author_id'] as String?;
    final postId = payload['post_id'] as String?;
    final content = payload['content'] as String? ?? '';
    final parentCommentId = payload['parent_comment_id'] as String?;

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
      'parent_comment_id': parentCommentId,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final receiverId = payload['receiver_id'] as String?;
    if (receiverId != null && receiverId != authorId) {
      final commenterName = payload['commenter_name'] as String? ?? 'Someone';
      final postTitle = payload['post_title'] as String? ?? 'your project';
      await _bestEffortUserNotification(
        source: 'comment',
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
      debugPrint('[SyncView] Skipping malformed view job id=${job.id} payload=$payload');
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

    final docRef = FirebaseFirestore.instance.collection('post_views').doc(job.entityId);
    final existing = await docRef.get(const GetOptions(source: Source.serverAndCache));
    await docRef.set({
      'id': job.entityId,
      'viewer_id': viewerId,
      'viewer_name': payload['viewer_name'] as String?,
      'author_id': payload['author_id'] as String?,
      'post_id': postId,
      'post_title': payload['post_title'] as String?,
      'updated_at': FieldValue.serverTimestamp(),
      if (!existing.exists) 'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint(
      '[SyncView] Remote view upserted viewId=${job.entityId} post=$postId viewer=$viewerId existing=${existing.exists}',
    );

    final authorId = payload['author_id'] as String?;
    if (authorId != null && authorId != viewerId) {
      final viewerName = payload['viewer_name'] as String? ?? 'Someone';
      final postTitle = payload['post_title'] as String? ?? 'your project';
      await _bestEffortUserNotification(
        source: 'view',
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

  Future<bool> _syncOpportunityJoin(SyncJob job) async {
    final payload = job.payloadJson;
    final userId = payload['user_id'] as String?;
    final postId = payload['post_id'] as String?;

    if (userId == null || postId == null) {
      debugPrint('[SyncJoin] Skipping malformed job id=${job.id} payload=$payload');
      return true;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != userId) {
      debugPrint(
        '[SyncService] ⚠️ Skipping opportunity join job ${job.id}: '
        'payload user=$userId but current uid=$currentUid — removing from queue.',
      );
      return true;
    }

    final docRef = FirebaseFirestore.instance.collection('post_joins').doc(job.entityId);

    if (job.operation == 'delete') {
      await docRef.delete();
      return true;
    }

    await docRef.set({
      'id': payload['id'] as String? ?? job.entityId,
      'user_id': userId,
      'post_id': postId,
      'post_title': payload['post_title'] as String?,
      'author_id': payload['author_id'] as String?,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  Future<bool> _syncModerationReport(SyncJob job) async {
    final payload = job.payloadJson;
    final reporterId = payload['reporter_id'] as String?;
    final postId = payload['post_id'] as String?;
    final reason = payload['reason'] as String?;

    if (reporterId == null || postId == null || reason == null || reason.trim().isEmpty) {
      debugPrint('[SyncModeration] Skipping malformed job id=${job.id} payload=$payload');
      return true;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != reporterId) {
      debugPrint(
        '[SyncService] ⚠️ Skipping moderation report job ${job.id}: '
        'reporter=$reporterId but current uid=$currentUid — removing from queue.',
      );
      return true;
    }

    await FirebaseFirestore.instance.collection('moderation_queue').doc(job.entityId).set({
      'id': job.entityId,
      'post_id': postId,
      'reporter_id': reporterId,
      'reason': reason,
      'post_title': payload['post_title'] as String?,
      'author_id': payload['author_id'] as String?,
      'status': 'pending',
      'suspicion_score': 0.0,
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  // ── Collab request sync ──────────────────────────────────────────────────

  Future<bool> _syncCollabRequest(SyncJob job) async {
    debugPrint('[SyncCollab] Processing job id=${job.id} entityId=${job.entityId} retryCount=${job.retryCount}');
    final payload = job.payloadJson;

    if (job.operation == 'update') {
      final status = payload['status'] as String?;
      final responderId = payload['responder_id'] as String?;
      if (status == null || responderId == null) {
        debugPrint('[SyncCollab] ⚠️ Malformed update payload for ${job.entityId}: $payload');
        return true;
      }

      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != responderId) {
        debugPrint(
          '[SyncCollab] ⚠️ Skipping collab update ${job.id}: responder=$responderId current uid=$currentUid',
        );
        return true;
      }

      final update = <String, Object?>{
        'status': status,
        'updated_at': payload['updated_at'] ?? FieldValue.serverTimestamp(),
        'responded_at': payload['responded_at'] ?? FieldValue.serverTimestamp(),
      };
      debugPrint('[SyncCollab] Updating Firestore collab_requests/${job.entityId} with status=$status');
      await FirebaseFirestore.instance
          .collection('collab_requests')
          .doc(job.entityId)
          .set(update, SetOptions(merge: true));
      return true;
    }

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
    await _bestEffortUserNotification(
      source: 'collaboration',
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

  Future<void> _bestEffortUserNotification({
    required String source,
    required String notificationId,
    required String receiverId,
    required String senderId,
    required String type,
    required String body,
    String? detail,
    String? entityId,
    String? senderName,
  }) async {
    try {
      await _upsertUserNotification(
        notificationId: notificationId,
        receiverId: receiverId,
        senderId: senderId,
        type: type,
        body: body,
        detail: detail,
        entityId: entityId,
        senderName: senderName,
      );
    } on FirebaseException catch (error) {
      debugPrint(
        '[SyncNotification] Skipping fan-out for source=$source notification=$notificationId '
        'receiver=$receiverId because Firestore rejected it: ${error.code}',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SyncNotification] Skipping fan-out for source=$source notification=$notificationId '
        'receiver=$receiverId due to unexpected error: $error',
      );
      debugPrint('[SyncNotification] Fan-out stacktrace: $stackTrace');
    }
  }

  Future<void> _syncRemoteFollows(String currentUid) async {
    final db = await DatabaseHelper.instance.database;
    final outgoing = await FirebaseFirestore.instance
        .collection('follows')
        .where('follower_id', isEqualTo: currentUid)
        .get(const GetOptions(source: Source.serverAndCache));
    final incoming = await FirebaseFirestore.instance
        .collection('follows')
        .where('following_id', isEqualTo: currentUid)
        .get(const GetOptions(source: Source.serverAndCache));

    final docs = [...outgoing.docs, ...incoming.docs];
    final userIds = <String>{};
    for (final doc in docs) {
      final data = doc.data();
      final followerId = data['follower_id'] as String?;
      final followingId = data['following_id'] as String?;
      if (followerId != null) userIds.add(followerId);
      if (followingId != null) userIds.add(followingId);
    }
    if (userIds.isNotEmpty) {
      final users = await _firestore.getUsersByIds(userIds);
      for (final user in users) {
        await _userDao.insertUser(user);
      }
    }

    var upserted = 0;
    for (final doc in docs) {
      final data = doc.data();
      final followerId = data['follower_id'] as String?;
      final followingId = data['following_id'] as String?;
      if (followerId == null || followingId == null) {
        continue;
      }
      final createdAt = data['created_at'];
      await db.insert(
        DatabaseSchema.tableFollows,
        {
          'id': doc.id,
          'follower_id': followerId,
          'followee_id': followingId,
          'created_at': createdAt is Timestamp ? createdAt.toDate().toIso8601String() : DateTime.now().toIso8601String(),
          'sync_status': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      upserted++;
    }
    debugPrint('[SyncService] Hydrated $upserted follow row(s) for user=$currentUid');
  }

  Future<void> _syncRemoteMessages(String currentUid) async {
    final db = await DatabaseHelper.instance.database;
    final outgoing = await FirebaseFirestore.instance
        .collection('conversations')
        .where('user_id', isEqualTo: currentUid)
        .get(const GetOptions(source: Source.serverAndCache));
    final incoming = await FirebaseFirestore.instance
        .collection('conversations')
        .where('peer_id', isEqualTo: currentUid)
        .get(const GetOptions(source: Source.serverAndCache));

    final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final doc in outgoing.docs) doc.id: doc,
      for (final doc in incoming.docs) doc.id: doc,
    };

    final counterpartIds = <String>{};
    for (final doc in docsById.values) {
      final data = doc.data();
      final userId = data['user_id'] as String?;
      final peerId = data['peer_id'] as String?;
      if (userId == null || peerId == null) {
        continue;
      }
      counterpartIds.add(userId == currentUid ? peerId : userId);
    }

    final usersById = <String, UserModel>{};
    if (counterpartIds.isNotEmpty) {
      final users = await _firestore.getUsersByIds(counterpartIds);
      for (final user in users) {
        usersById[user.id] = user;
        await _userDao.insertUser(user);
      }
    }

    var upsertedConversations = 0;
    var upsertedMessages = 0;
    for (final doc in docsById.values) {
      final data = doc.data();
      final userId = data['user_id'] as String?;
      final peerId = data['peer_id'] as String?;
      if (userId == null || peerId == null) {
        continue;
      }

      final counterpartId = userId == currentUid ? peerId : userId;
      final counterpart = usersById[counterpartId];
      final lastMessageAt = data['last_message_at'];

      await db.insert(
        DatabaseSchema.tableConversations,
        {
          'id': doc.id,
          'user_id': currentUid,
          'peer_id': counterpartId,
          'peer_name': counterpart?.displayName?.trim().isNotEmpty == true
              ? counterpart!.displayName!.trim()
              : counterpart?.email ?? 'Conversation',
          'peer_photo_url': counterpart?.photoUrl,
          'last_message': data['last_message'] as String? ?? '',
          'last_message_at': lastMessageAt is Timestamp
              ? lastMessageAt.millisecondsSinceEpoch
              : DateTime.now().millisecondsSinceEpoch,
          'unread_count': 0,
          'is_peer_lecturer': counterpart?.isLecturer == true ? 1 : 0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'sync_status': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await db.insert(
        DatabaseSchema.tableMessageThreads,
        {
          'id': doc.id,
          'participant_ids': '[$currentUid,$counterpartId]',
          'last_message_id': null,
          'last_message_text': data['last_message'] as String? ?? '',
          'last_message_at': lastMessageAt is Timestamp
              ? lastMessageAt.toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
          'unread_count': 0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'sync_status': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      upsertedConversations++;

      final msgSnap = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(doc.id)
          .collection('messages')
          .orderBy('created_at', descending: false)
          .limit(100)
          .get(const GetOptions(source: Source.serverAndCache));

      var unreadCount = 0;
      for (final msgDoc in msgSnap.docs) {
        final msg = msgDoc.data();
        final createdAt = msg['created_at'];
        final isRead = msg['is_read'] as bool? ?? false;
        final senderId = msg['sender_id'] as String? ?? '';
        if (senderId != currentUid && !isRead) {
          unreadCount++;
        }
        await db.insert(
          DatabaseSchema.tableMessages,
          {
            'id': msgDoc.id,
            'thread_id': doc.id,
            'conversation_id': doc.id,
            'sender_id': senderId,
            'content': msg['content'] as String? ?? '',
            'message_type': msg['message_type'] as String? ?? 'text',
            'file_url': msg['file_url'] as String?,
            'file_name': msg['file_name'] as String?,
            'file_size': msg['file_size'] as String?,
            'media_url': msg['file_url'] as String?,
            'status': isRead ? 'read' : 'sent',
            'created_at': createdAt is Timestamp
                ? createdAt.millisecondsSinceEpoch
                : DateTime.now().millisecondsSinceEpoch,
            'sent_at': createdAt is Timestamp
                ? createdAt.toDate().toIso8601String()
                : DateTime.now().toIso8601String(),
            'is_read': isRead ? 1 : 0,
            'is_deleted': 0,
            'is_queued': 0,
            'sync_status': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        upsertedMessages++;
      }

      await db.update(
        DatabaseSchema.tableConversations,
        {
          'unread_count': unreadCount,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [doc.id],
      );
    }

    debugPrint('[SyncService] Hydrated $upsertedConversations conversation(s) and $upsertedMessages message(s) for user=$currentUid');
  }

  Future<void> _syncRemoteLikes(
    String currentUid, {
    Iterable<String> candidatePostIds = const [],
  }) async {
    final db = await DatabaseHelper.instance.database;
    final ensuredUserIds = <String>{};

    Future<void> ensureUserPresent(String userId) async {
      if (userId.isEmpty || ensuredUserIds.contains(userId)) {
        return;
      }
      final existing = await db.query(
        DatabaseSchema.tableUsers,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (existing.isEmpty) {
        final remoteUser = await _firestore.getUser(userId);
        if (remoteUser != null) {
          await _userDao.insertUser(remoteUser);
          debugPrint('[SyncService] Inserted missing local user dependency user=$userId for like hydration');
        }
      }
      ensuredUserIds.add(userId);
    }

    Future<bool> ensurePostPresent(String postId) async {
      final existing = await db.query(
        DatabaseSchema.tablePosts,
        columns: ['id', 'author_id'],
        where: 'id = ?',
        whereArgs: [postId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final authorId = existing.first['author_id'] as String?;
        if (authorId != null && authorId.isNotEmpty) {
          await ensureUserPresent(authorId);
        }
        return true;
      }

      final remotePost = await FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .get(const GetOptions(source: Source.serverAndCache));
      if (!remotePost.exists || remotePost.data() == null) {
        return false;
      }

      final post = PostModel.fromJson({'id': remotePost.id, ...remotePost.data()!});
      await ensureUserPresent(post.authorId);
      await _postDao.insertPost(post);
      debugPrint('[SyncService] Inserted missing local post dependency post=$postId for like hydration');
      return true;
    }

    await ensureUserPresent(currentUid);

    final postIds = <String>{...candidatePostIds.where((id) => id.isNotEmpty)};
    if (postIds.isEmpty) {
      final localRows = await db.query(
        DatabaseSchema.tablePosts,
        columns: ['id'],
        orderBy: 'created_at DESC',
        limit: 150,
      );
      postIds.addAll(localRows.map((row) => row['id'] as String? ?? '').where((id) => id.isNotEmpty));
    }

    var inserted = 0;
    var removed = 0;
    var skippedMissingPosts = 0;
    for (final postId in postIds) {
      final likeDoc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .collection('likes')
          .doc(currentUid)
          .get(const GetOptions(source: Source.serverAndCache));

      if (likeDoc.exists) {
        final postReady = await ensurePostPresent(postId);
        if (!postReady) {
          skippedMissingPosts++;
          debugPrint('[SyncService] Skipping like hydration for post=$postId because the post is unavailable remotely.');
          continue;
        }
        final createdAt = likeDoc.data()?['created_at'];
        await db.insert(
          DatabaseSchema.tableLikes,
          {
            'id': likeDoc.id,
            'post_id': postId,
            'user_id': currentUid,
            'created_at': createdAt is Timestamp ? createdAt.millisecondsSinceEpoch : DateTime.now().millisecondsSinceEpoch,
            'sync_status': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        inserted++;
      } else {
        removed += await db.delete(
          DatabaseSchema.tableLikes,
          where: 'post_id = ? AND user_id = ?',
          whereArgs: [postId, currentUid],
        );
      }
    }
    debugPrint(
      '[SyncService] Hydrated like flags for user=$currentUid checkedPosts=${postIds.length} '
      'insertedOrUpdated=$inserted removed=$removed skippedMissingPosts=$skippedMissingPosts',
    );
  }

  Future<void> _syncRemoteDislikes(
    String currentUid, {
    Iterable<String> candidatePostIds = const [],
  }) async {
    final db = await DatabaseHelper.instance.database;

    Future<bool> ensurePostPresent(String postId) async {
      final existing = await db.query(
        DatabaseSchema.tablePosts,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [postId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return true;
      }

      final remotePost = await FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .get(const GetOptions(source: Source.serverAndCache));
      if (!remotePost.exists || remotePost.data() == null) {
        return false;
      }

      final post = PostModel.fromJson({'id': remotePost.id, ...remotePost.data()!});
      final author = await _firestore.getUser(post.authorId);
      if (author != null) {
        await _userDao.insertUser(author);
      }
      await _postDao.insertPost(post);
      return true;
    }

    final postIds = <String>{...candidatePostIds.where((id) => id.isNotEmpty)};
    if (postIds.isEmpty) {
      final localRows = await db.query(
        DatabaseSchema.tablePosts,
        columns: ['id'],
        orderBy: 'created_at DESC',
        limit: 150,
      );
      postIds.addAll(localRows.map((row) => row['id'] as String? ?? '').where((id) => id.isNotEmpty));
    }

    var inserted = 0;
    var removed = 0;
    for (final postId in postIds) {
      final dislikeDoc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .collection('dislikes')
          .doc(currentUid)
          .get(const GetOptions(source: Source.serverAndCache));

      if (dislikeDoc.exists) {
        final postReady = await ensurePostPresent(postId);
        if (!postReady) {
          continue;
        }
        final createdAt = dislikeDoc.data()?['created_at'];
        await db.insert(
          DatabaseSchema.tableDislikes,
          {
            'id': dislikeDoc.id,
            'post_id': postId,
            'user_id': currentUid,
            'created_at': createdAt is Timestamp ? createdAt.millisecondsSinceEpoch : DateTime.now().millisecondsSinceEpoch,
            'sync_status': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        inserted++;
      } else {
        removed += await db.delete(
          DatabaseSchema.tableDislikes,
          where: 'post_id = ? AND user_id = ?',
          whereArgs: [postId, currentUid],
        );
      }
    }

    debugPrint(
      '[SyncService] Hydrated dislike flags for user=$currentUid checkedPosts=${postIds.length} '
      'insertedOrUpdated=$inserted removed=$removed',
    );
  }

  Future<void> _syncRemotePostViews(String currentUid) async {
    final db = await DatabaseHelper.instance.database;

    final viewerSnapshot = await FirebaseFirestore.instance
        .collection('post_views')
        .where('viewer_id', isEqualTo: currentUid)
        .get(const GetOptions(source: Source.serverAndCache));

    var hydratedViewerLogs = 0;
    for (final doc in viewerSnapshot.docs) {
      final postId = doc.data()['post_id'] as String?;
      if (postId == null) {
        continue;
      }
      final existing = await db.query(
        DatabaseSchema.tableActivityLogs,
        columns: ['id'],
        where: 'user_id = ? AND action = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [currentUid, 'view_post', DatabaseSchema.tablePosts, postId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        continue;
      }
      final createdAt = doc.data()['created_at'];
      await db.insert(DatabaseSchema.tableActivityLogs, {
        'id': doc.id,
        'user_id': currentUid,
        'action': 'view_post',
        'entity_type': DatabaseSchema.tablePosts,
        'entity_id': postId,
        'metadata': jsonEncode({'source': 'remote_post_view'}),
        'created_at': createdAt is Timestamp ? createdAt.toDate().toIso8601String() : DateTime.now().toIso8601String(),
      });
      hydratedViewerLogs++;
    }

    final authorSnapshot = await FirebaseFirestore.instance
        .collection('post_views')
        .where('author_id', isEqualTo: currentUid)
        .get(const GetOptions(source: Source.serverAndCache));

    final counts = <String, int>{};
    for (final doc in authorSnapshot.docs) {
      final postId = doc.data()['post_id'] as String?;
      if (postId == null) {
        continue;
      }
      counts[postId] = (counts[postId] ?? 0) + 1;
    }

    var updatedPosts = 0;
    for (final entry in counts.entries) {
      final currentRows = await db.query(
        DatabaseSchema.tablePosts,
        columns: ['view_count'],
        where: 'id = ?',
        whereArgs: [entry.key],
        limit: 1,
      );
      if (currentRows.isEmpty) {
        continue;
      }
      final localCount = currentRows.first['view_count'] as int? ?? 0;
      if (entry.value > localCount) {
        await db.update(
          DatabaseSchema.tablePosts,
          {'view_count': entry.value},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
        updatedPosts++;
      }
    }

    debugPrint(
      '[SyncService] Hydrated remote post views for user=$currentUid '
      'viewerLogs=$hydratedViewerLogs authorPostUpdates=$updatedPosts',
    );
  }

  Future<void> _syncRemoteCollabRequests(String currentUid) async {
    final db = await DatabaseHelper.instance.database;
    final sent = await FirebaseFirestore.instance
        .collection('collab_requests')
        .where('sender_id', isEqualTo: currentUid)
        .get(const GetOptions(source: Source.serverAndCache));
    final received = await FirebaseFirestore.instance
        .collection('collab_requests')
        .where('receiver_id', isEqualTo: currentUid)
        .get(const GetOptions(source: Source.serverAndCache));

    final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final doc in sent.docs) doc.id: doc,
      for (final doc in received.docs) doc.id: doc,
    };

    final userIds = <String>{};
    for (final doc in docsById.values) {
      final data = doc.data();
      final senderId = data['sender_id'] as String?;
      final receiverId = data['receiver_id'] as String?;
      if (senderId != null) userIds.add(senderId);
      if (receiverId != null) userIds.add(receiverId);
    }
    if (userIds.isNotEmpty) {
      final users = await _firestore.getUsersByIds(userIds);
      for (final user in users) {
        await _userDao.insertUser(user);
      }
    }

    var upserted = 0;
    for (final doc in docsById.values) {
      final data = doc.data();
      final senderId = data['sender_id'] as String?;
      final receiverId = data['receiver_id'] as String?;
      if (senderId == null || receiverId == null) {
        continue;
      }
      final createdAt = data['created_at'];
      final updatedAt = data['updated_at'];
      final respondedAt = data['responded_at'];
      await db.insert(
        DatabaseSchema.tableCollabRequests,
        {
          'id': doc.id,
          'sender_id': senderId,
          'receiver_id': receiverId,
          'post_id': data['post_id'] as String?,
          'message': data['message'] as String?,
          'status': data['status'] as String? ?? 'pending',
          'responded_at': respondedAt is Timestamp ? respondedAt.toDate().toIso8601String() : respondedAt as String?,
          'created_at': createdAt is Timestamp ? createdAt.toDate().toIso8601String() : DateTime.now().toIso8601String(),
          'updated_at': updatedAt is Timestamp ? updatedAt.toDate().toIso8601String() : DateTime.now().toIso8601String(),
          'sync_status': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      upserted++;
    }
    debugPrint('[SyncService] Hydrated $upserted collaboration request row(s) for user=$currentUid');
  }

  Future<void> _syncRemoteOpportunityJoins(String currentUid) async {
    final db = await DatabaseHelper.instance.database;
    final snapshot = await FirebaseFirestore.instance
        .collection('post_joins')
        .where('user_id', isEqualTo: currentUid)
        .get(const GetOptions(source: Source.serverAndCache));

    final remoteByPostId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in snapshot.docs) {
      final postId = doc.data()['post_id'] as String?;
      if (postId != null && postId.isNotEmpty) {
        remoteByPostId[postId] = doc;
      }
    }

    Future<void> ensurePostPresent(String postId, String? authorId) async {
      final existing = await db.query(
        DatabaseSchema.tablePosts,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [postId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return;
      }

      final remotePost = await FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .get(const GetOptions(source: Source.serverAndCache));
      if (!remotePost.exists || remotePost.data() == null) {
        return;
      }

      final post = PostModel.fromJson({'id': remotePost.id, ...remotePost.data()!});
      final resolvedAuthorId = authorId ?? post.authorId;
      final author = await _firestore.getUser(resolvedAuthorId);
      if (author != null) {
        await _userDao.insertUser(author);
      }
      await _postDao.insertPost(post);
    }

    final localRows = await db.query(
      DatabaseSchema.tablePostJoins,
      columns: ['post_id'],
      where: 'user_id = ?',
      whereArgs: [currentUid],
    );
    final localPostIds = localRows
        .map((row) => row['post_id'] as String? ?? '')
        .where((postId) => postId.isNotEmpty)
        .toSet();

    var upserted = 0;
    for (final entry in remoteByPostId.entries) {
      final data = entry.value.data();
      final authorId = data['author_id'] as String?;
      await ensurePostPresent(entry.key, authorId);
      final createdAt = data['created_at'];
      await db.insert(
        DatabaseSchema.tablePostJoins,
        {
          'id': entry.value.id,
          'post_id': entry.key,
          'user_id': currentUid,
          'created_at': createdAt is Timestamp ? createdAt.toDate().toIso8601String() : DateTime.now().toIso8601String(),
          'sync_status': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      upserted++;
    }

    final stalePostIds = localPostIds.difference(remoteByPostId.keys.toSet());
    var removed = 0;
    for (final postId in stalePostIds) {
      removed += await db.delete(
        DatabaseSchema.tablePostJoins,
        where: 'user_id = ? AND post_id = ?',
        whereArgs: [currentUid, postId],
      );
    }

    debugPrint('[SyncService] Hydrated $upserted post join row(s) for user=$currentUid and removed $removed stale row(s)');
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
          parentCommentId: data['parent_comment_id'] as String?,
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
    final docRef = FirebaseFirestore.instance.collection('notifications').doc(notificationId);
    final updateData = <String, Object?>{
      'sender_name': senderName,
      'body': body,
      'detail': detail,
      'entity_id': entityId,
    };

    try {
      await docRef.update(updateData);
      debugPrint('[SyncNotification] Updated existing notification=$notificationId for receiver=$receiverId');
      return;
    } on FirebaseException catch (error) {
      if (error.code != 'not-found') {
        rethrow;
      }
    }

    final createData = <String, Object?>{
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
    };

    await docRef.set(createData);
    debugPrint('[SyncNotification] Created notification=$notificationId for receiver=$receiverId type=$type');
  }

  Future<void> _showLocalAlertForNotification(Map<String, Object?> row) async {
    final type = row['type'] as String? ?? 'system';
    if (!_preferences.shouldPresentAlert(type: type)) {
      return;
    }

    final title = _notificationTitle(type);
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
