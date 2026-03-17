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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../local/dao/sync_queue_dao.dart';
import '../local/dao/user_dao.dart';
import '../local/dao/post_dao.dart';
import '../local/dao/message_dao.dart';
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
  final MessageDao _messageDao;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  SyncService({
    required SyncQueueDao queueDao,
    required FirestoreService firestore,
    required UserDao userDao,
    required PostDao postDao,
    required MessageDao messageDao,
    Connectivity? connectivity,
  })  : _queueDao = queueDao,
        _firestore = firestore,
        _userDao = userDao,
        _postDao = postDao,
        _messageDao = messageDao,
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
    if (_isSyncing) {
      return const SyncResult(processed: 0, failed: 0, remaining: 0);
    }

    _isSyncing = true;
    int processed = 0;
    int failed = 0;

    try {
      final jobs = await _queueDao.getReadyJobs(limit: 50);

      for (final job in jobs) {
        final success = await _processJob(job);
        if (success) {
          await _queueDao.deleteJob(job.id);
          processed++;
        } else {
          await _queueDao.incrementAttempt(job.id);
          if (job.entityType == 'message') {
            final nextRetry = job.retryCount + 1;
            await _messageDao.markMessageSyncStatus(
              job.entityId,
              nextRetry >= job.maxRetries ? 2 : 0,
            );
          }
          failed++;
        }
      }

      final remaining = await _queueDao.getPendingCount();
      return SyncResult(
          processed: processed, failed: failed, remaining: remaining);
    } finally {
      _isSyncing = false;
    }
  }

  /// Pull a recent set of remote posts and authors into SQLite when online.
  Future<void> syncRemoteToLocal({int postLimit = 50}) async {
    try {
      final posts = await _firestore.getRecentPosts(limit: postLimit);
      if (posts.isEmpty) {
        return;
      }

      final authorIds = posts.map((post) => post.authorId).toSet();
      final users = await _firestore.getUsersByIds(authorIds);
      for (final user in users) {
        await _userDao.insertUser(user);
      }

      for (final post in posts) {
        await _postDao.insertPost(post);
      }
    } catch (error) {
      debugPrint('[SyncService] Remote-to-local sync failed: $error');
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
        default:
          // Unknown entity type — remove from queue to prevent blocking
          return true;
      }
    } catch (e) {
      // Log and return false to trigger backoff
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
            .update({
          'is_deleted': true,
          'deleted_at': FieldValue.serverTimestamp()
        });
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
        await _firestore.setPost(post);
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
        for (final doc in snap.docs) {
          doc.reference.delete();
        }
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
      createdAt: DateTime.tryParse(payload['created_at'] as String? ?? '') ??
          DateTime.now(),
    );

    await _firestore.sendMessage(msg);
    await _messageDao.markMessageSyncStatus(job.entityId, 1);
    return true;
  }

  // ── Follow sync ───────────────────────────────────────────────────────────

  Future<bool> _syncFollow(SyncJob job) async {
    final payload = job.payloadJson;
    final followerId = payload['follower_id'] as String?;
    final followingId = payload['following_id'] as String?;

    if (followerId == null || followingId == null) return true;

    if (job.operation == 'create') {
      await _firestore.follow(followerId: followerId, followingId: followingId);
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

    await _firestore.toggleLike(
      postId: postId,
      userId: userId,
      isLiking: isLiking,
    );
    return true;
  }

  // ── Queue depth metric (for super admin dashboard) ────────────────────────

  Future<int> getQueueDepth() => _queueDao.getPendingCount();

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
