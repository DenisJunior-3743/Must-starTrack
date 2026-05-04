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

import '../../core/constants/app_enums.dart';
import '../../core/utils/media_path_utils.dart';
import '../local/dao/comment_dao.dart';
import '../local/dao/sync_queue_dao.dart';
import '../local/dao/user_dao.dart';
import '../local/dao/post_dao.dart';
import '../local/dao/message_dao.dart';
import '../local/dao/notification_dao.dart';
import '../local/dao/faculty_dao.dart';
import '../local/dao/course_dao.dart';
import '../local/dao/group_dao.dart';
import '../local/dao/group_member_dao.dart';
import '../local/services/notification_preferences_service.dart';
import '../local/database_helper.dart';
import '../local/schema/database_schema.dart';
import 'cloudinary_service.dart';
import 'firestore_service.dart';
import 'recommender_service.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/group_member_model.dart';
import '../../core/router/route_guards.dart';

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
  final FacultyDao _facultyDao;
  final CourseDao _courseDao;
  final GroupDao _groupDao;
  final GroupMemberDao _groupMemberDao;
  final NotificationDao _notificationDao;
  final Connectivity _connectivity;
  final CloudinaryService _cloudinary;
  final FlutterLocalNotificationsPlugin _localNotif;
  final NotificationPreferencesService _preferences;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  bool _isSyncing = false;
  StreamSubscription<User?>? _authSub;
  bool _isHydrating = false;
  Future<void>? _hydrationFuture;
  String _lastJobError = 'sync_failed';

  void _syncTrace(String message, {Map<String, Object?> details = const {}}) {
    debugPrint('****  SYNC         **** $message');
    if (details.isNotEmpty) {
      debugPrint('****  SYNC         **** details=$details');
    }
  }

  void _uplinkTrace(String message, {Map<String, Object?> details = const {}}) {
    debugPrint('** UPLINK ** $message');
    if (details.isNotEmpty) {
      debugPrint('** UPLINK ** details=$details');
    }
  }

  String _uplinkUserLabel({String? name, String? id}) {
    final cleanName = (name ?? '').trim();
    if (cleanName.isNotEmpty) {
      return cleanName;
    }
    final cleanId = (id ?? '').trim();
    if (cleanId.isNotEmpty) {
      return cleanId;
    }
    return 'unknown';
  }

  void _notificationDebugBlock({
    required String activity,
    required String user,
    required String receiver,
    required String notificationId,
    required String status,
    String recordStatus = 'saved',
    String? error,
  }) {
    final normalized = activity.trim().isEmpty ? 'unknown' : activity.trim();
    debugPrint('========= $normalized ========');
    debugPrint('user: $user');
    debugPrint('receiver: $receiver');
    debugPrint('notification_id: $notificationId');
    debugPrint('record status: $recordStatus');
    debugPrint('notification status: $status');
    if (error != null && error.trim().isNotEmpty) {
      debugPrint('error: $error');
    }
    debugPrint('====================');
  }

  Future<void> _verifyUplinkDoc({
    required String action,
    required DocumentReference<Map<String, dynamic>> docRef,
    required bool expectedExists,
    Map<String, Object?> details = const {},
  }) async {
    try {
      final snap = await docRef.get(const GetOptions(source: Source.server));
      _uplinkTrace('VERIFY_$action', details: {
        ...details,
        'path': docRef.path,
        'expected_exists': expectedExists,
        'actual_exists': snap.exists,
        'from_cache': snap.metadata.isFromCache,
      });
    } on FirebaseException catch (error) {
      _uplinkTrace('VERIFY_${action}_FAILED', details: {
        ...details,
        'path': docRef.path,
        'code': error.code,
        'message': error.message ?? '',
      });
    } catch (error) {
      _uplinkTrace('VERIFY_${action}_FAILED', details: {
        ...details,
        'path': docRef.path,
        'error': error.toString(),
      });
    }
  }

  Future<Map<String, int>> _readLocalInteractionCounts(String postId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      DatabaseSchema.tablePosts,
      columns: ['like_count', 'dislike_count', 'comment_count', 'view_count'],
      where: 'id = ?',
      whereArgs: [postId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const {
        'like_count': 0,
        'dislike_count': 0,
        'comment_count': 0,
        'view_count': 0,
      };
    }
    final row = rows.first;
    return {
      'like_count': row['like_count'] as int? ?? 0,
      'dislike_count': row['dislike_count'] as int? ?? 0,
      'comment_count': row['comment_count'] as int? ?? 0,
      'view_count': row['view_count'] as int? ?? 0,
    };
  }

  SyncService({
    required SyncQueueDao queueDao,
    required FirestoreService firestore,
    required UserDao userDao,
    required PostDao postDao,
    required CommentDao commentDao,
    required FacultyDao facultyDao,
    required CourseDao courseDao,
    required GroupDao groupDao,
    required GroupMemberDao groupMemberDao,
    required NotificationDao notificationDao,
    required CloudinaryService cloudinary,
    required FlutterLocalNotificationsPlugin localNotif,
    required NotificationPreferencesService preferences,
    Connectivity? connectivity,
  })  : _queueDao = queueDao,
        _firestore = firestore,
        _userDao = userDao,
        _postDao = postDao,
        _commentDao = commentDao,
        _facultyDao = facultyDao,
        _courseDao = courseDao,
        _groupDao = groupDao,
        _groupMemberDao = groupMemberDao,
        _notificationDao = notificationDao,
        _cloudinary = cloudinary,
        _localNotif = localNotif,
        _preferences = preferences,
        _connectivity = connectivity ?? Connectivity();

  // ── Start listening for connectivity changes ───────────────────────────────

  /// Call once in InjectionContainer.init() or on app foreground.
  void startListening() {
    _connectivitySub?.cancel();
    unawaited(_runInitialOnlineSync());
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = _isOnline(results);

      if (isOnline) {
        unawaited(processPendingSync());
        unawaited(syncRemoteToLocal());
      }
    });
    // Re-start the Firestore notification watcher whenever auth state
    // changes (login, logout, token refresh).  On fresh app start the
    // current user is null, so we must wait for authStateChanges rather
    // than reading FirebaseAuth.instance.currentUser once at startup.
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      _startWatchingNotifications();
    });
    _startWatchingNotifications();
  }

  /// Starts a real-time Firestore listener on the current user's unread
  /// notifications. Shows a local push alert immediately when a new unread
  /// notification arrives — no need to wait for the next sync cycle.
  void _startWatchingNotifications() {
    _notifSub?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    var isInitialSnapshot = true;
    _notifSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('user_id', isEqualTo: uid)
        .where('is_read', isEqualTo: false)
        .orderBy('created_at', descending: true)
        .limit(20)
        .snapshots()
        .listen(
      (snapshot) {
        final shouldShowAlertsForSnapshot =
            !isInitialSnapshot && !snapshot.metadata.isFromCache;
        debugPrint(
          '[SyncDownlink] notification snapshot docs=${snapshot.docs.length} '
          'changes=${snapshot.docChanges.length} fromCache=${snapshot.metadata.isFromCache}',
        );
        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          final d = change.doc.data();
          if (d == null) continue;
          final notificationId = change.doc.id;
          if (_preferences.wasNotificationDelivered(notificationId)) continue;
          final ts = d['created_at'];
          final createdAtMs = ts is Timestamp
              ? ts.millisecondsSinceEpoch
              : DateTime.now().millisecondsSinceEpoch;
          final remoteExtra = d['extra'];
          final remoteExtraJson = d['extra_json'] as String? ??
              (remoteExtra is Map
                  ? jsonEncode(Map<String, dynamic>.from(remoteExtra))
                  : null);
          var parsedExtra = <String, dynamic>{};
          if (remoteExtra is Map) {
            parsedExtra = Map<String, dynamic>.from(remoteExtra);
          } else if (remoteExtraJson != null && remoteExtraJson.isNotEmpty) {
            try {
              parsedExtra = jsonDecode(remoteExtraJson) as Map<String, dynamic>;
            } catch (_) {}
          }
          final row = <String, Object?>{
            'id': notificationId,
            'user_id': d['user_id'] as String? ?? uid,
            'type': d['type'] as String? ?? 'system',
            'sender_id': d['sender_id'] as String?,
            'sender_name': d['sender_name'] as String?,
            'sender_photo_url': d['sender_photo_url'] as String?,
            'body': d['body'] as String? ?? 'You have a new notification.',
            'detail': d['detail'] as String?,
            'entity_id': d['entity_id'] as String?,
            'created_at': createdAtMs,
            'is_read': 0,
            'extra_json': remoteExtraJson,
          };
          final rowUserId = row['user_id'] as String;
          final rowSenderId = row['sender_id'] as String?;
          if (rowSenderId != null &&
              rowSenderId.isNotEmpty &&
              rowSenderId == rowUserId) {
            debugPrint(
              '[SyncDownlink] Skipping self notification=$notificationId user=$rowUserId',
            );
            unawaited(_preferences.markNotificationDelivered(notificationId));
            continue;
          }

          // Persist immediately so receiver device notification center updates
          // in real time without waiting for the next hydration pass.
          unawaited(_notificationDao.insertNotification(
            NotificationModel(
              id: notificationId,
              userId: row['user_id'] as String,
              type: row['type'] as String,
              senderId: row['sender_id'] as String?,
              senderName: row['sender_name'] as String?,
              senderPhotoUrl: row['sender_photo_url'] as String?,
              body: row['body'] as String,
              detail: row['detail'] as String?,
              entityId: row['entity_id'] as String?,
              createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
              isRead: false,
              extra: parsedExtra,
            ),
          ));
          debugPrint(
            '[SyncDownlink] receiver_local_upsert notification=$notificationId '
            'type=${row['type']} user=${row['user_id']}',
          );

          if (shouldShowAlertsForSnapshot) {
            unawaited(_showLocalAlertForNotification(row));
          }
          unawaited(_preferences.markNotificationDelivered(notificationId));
        }
        isInitialSnapshot = false;
      },
      onError: (dynamic error) {
        debugPrint('[SyncService] Notification watcher error: $error');
      },
    );
  }

  bool _isOnline(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
  }

  Future<void> _runInitialOnlineSync() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (!_isOnline(results)) {
        return;
      }

      await processPendingSync();
      await syncRemoteToLocal();
    } catch (error) {
      debugPrint(
          '[SyncService] Initial connectivity sync probe failed: $error');
    }
  }

  void stopListening() {
    _connectivitySub?.cancel();
    _notifSub?.cancel();
    _authSub?.cancel();
  }

  // ── Process sync queue ────────────────────────────────────────────────────

  /// Main sync loop — drains ready jobs from the queue.
  Future<SyncResult> processPendingSync() async {
    if (_isSyncing) {
      _syncTrace('QUEUE_ALREADY_RUNNING');
      return const SyncResult(processed: 0, failed: 0, remaining: 0);
    }

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      debugPrint('[SyncService] Skipping sync: no active FirebaseAuth session');
      final remaining = await _queueDao.getPendingCount();
      _syncTrace('QUEUE_SKIPPED_NO_AUTH', details: {'remaining': remaining});
      return SyncResult(processed: 0, failed: 0, remaining: remaining);
    }

    _isSyncing = true;
    int processed = 0;
    int failed = 0;

    _syncTrace('QUEUE_START', details: {
      'uid': authUser.uid,
      'email': authUser.email,
    });

    try {
      try {
        await authUser.getIdToken(true);
      } catch (error) {
        debugPrint(
            '[SyncService] Unable to refresh auth token before sync: $error');
      }

      final jobs = await _queueDao.getReadyJobs(limit: 50);
      debugPrint(
          '[SyncService] Starting sync loop with ${jobs.length} ready job(s).');
      final jobMix = <String, int>{};
      for (final job in jobs) {
        jobMix[job.entityType] = (jobMix[job.entityType] ?? 0) + 1;
      }
      _syncTrace('QUEUE_JOBS_FETCHED', details: {'jobs': jobs.length});
      _syncTrace('QUEUE_JOBS_MIX', details: jobMix);

      for (final job in jobs) {
        final actorId = (job.payloadJson['user_id'] ??
                job.payloadJson['author_id'] ??
                job.payloadJson['sender_id'] ??
                job.payloadJson['from_user_id'] ??
                job.payloadJson['follower_id'] ??
                job.payloadJson['viewer_id'])
            ?.toString();
        debugPrint(
          '=========== sync_pickup user=${actorId ?? 'unknown'} entity=${job.entityType} op=${job.operation} ===========',
        );
        debugPrint(
          '[SyncService] Processing job id=${job.id} entity=${job.entityType} '
          'operation=${job.operation} entityId=${job.entityId} retry=${job.retryCount}',
        );
        _syncTrace('JOB_PICKED', details: {
          'jobId': job.id,
          'entity': job.entityType,
          'op': job.operation,
          'entityId': job.entityId,
          'retry': job.retryCount,
        });
        final success = await _processJob(job);
        if (success) {
          await _queueDao.deleteJob(job.id);
          debugPrint(
            '=========== sync_result job=${job.id} status=success entity=${job.entityType} ===========',
          );
          debugPrint(
              '[SyncService] Job id=${job.id} entity=${job.entityType} completed and removed from queue.');
          _syncTrace('JOB_SUCCESS', details: {
            'jobId': job.id,
            'entity': job.entityType,
            'op': job.operation,
          });
          processed++;
        } else {
          await _queueDao.incrementAttempt(job.id, errorMessage: _lastJobError);
          debugPrint(
            '=========== sync_result job=${job.id} status=retry entity=${job.entityType} ===========',
          );
          debugPrint(
              '[SyncService] Job id=${job.id} entity=${job.entityType} failed and will retry. reason=$_lastJobError');
          _syncTrace('JOB_RETRY', details: {
            'jobId': job.id,
            'entity': job.entityType,
            'op': job.operation,
            'reason': _lastJobError,
          });
          failed++;
        }
      }

      final remaining = await _queueDao.getPendingCount();
      final deadLetters = await _queueDao.getDeadLetterCount();
      debugPrint(
        '[SyncService] Queue summary processed=$processed failed=$failed '
        'remaining=$remaining deadLetters=$deadLetters',
      );
      _syncTrace('QUEUE_DONE', details: {
        'processed': processed,
        'failed': failed,
        'remaining': remaining,
        'deadLetters': deadLetters,
      });
      await _logSyncSnapshot(label: 'after_queue_push');
      return SyncResult(
          processed: processed, failed: failed, remaining: remaining);
    } finally {
      _isSyncing = false;
    }
  }

  /// Pull a recent set of remote posts and authors into SQLite when online.
  /// Pull a recent set of remote posts and authors into SQLite when online.
  ///
  /// If a hydration is already in progress the caller joins it (awaits the
  /// same Future) rather than returning early with stale data. This prevents
  /// the race where [loadFeed] queries SQLite before the ongoing sync has
  /// finished inserting posts.
  Future<void> syncRemoteToLocal({
    int postLimit = 50,
    bool forceIncludePendingForAdmin = false,
    bool suppressNotificationAlerts = false,
  }) {
    if (_isHydrating) {
      debugPrint(
          '[SyncService] syncRemoteToLocal already running — joining existing hydration');
      return _hydrationFuture ?? Future<void>.value();
    }
    _isHydrating = true;
    _hydrationFuture = _runHydration(
      postLimit: postLimit,
      forceIncludePendingForAdmin: forceIncludePendingForAdmin,
      suppressNotificationAlerts: suppressNotificationAlerts,
    );
    return _hydrationFuture!;
  }

  Future<void> _runHydration({
    int postLimit = 50,
    bool forceIncludePendingForAdmin = false,
    bool suppressNotificationAlerts = false,
  }) async {
    final syncedPostIds = <String>[];
    try {
      // When called from admin dashboard, pre-hydrate ALL users first so that
      // every group, follow, and post row can satisfy its FK constraints.
      if (forceIncludePendingForAdmin) {
        await _runHydrationStep('all_users', _syncAllUsers);
      }
      await _runHydrationStep('posts', () async {
        debugPrint(
            '[SyncService] posts hydration starting, postLimit=$postLimit');

        final includePendingForAdmin = forceIncludePendingForAdmin
            ? true
            : await _currentUserCanReviewPendingPosts();
        final posts = await _firestore.getRecentPosts(
          limit: postLimit,
          includePendingForAdmin: includePendingForAdmin,
        );

        debugPrint(
            '[SyncService] posts hydration fetched ${posts.length} posts');

        syncedPostIds
          ..clear()
          ..addAll(posts.map((post) => post.id));

        if (posts.isEmpty) {
          debugPrint('[SyncService] posts hydration returned zero posts');
          return;
        }

        final authorIds = posts.map((post) => post.authorId).toSet();
        debugPrint(
            '[SyncService] posts hydration unique authorIds=${authorIds.length}');

        final placeholderUsers = <String, UserModel>{
          for (final post in posts)
            if (post.authorId.isNotEmpty)
              post.authorId: _buildPlaceholderUser(
                userId: post.authorId,
                displayName: post.authorName,
                photoUrl: post.authorPhotoUrl,
                role: post.authorRole,
              ),
        };
        final existingAuthorIds = await _cacheUsersAndGetExistingIds(
          authorIds,
          placeholderUsers: placeholderUsers,
          logContext: 'post_authors',
        );
        debugPrint(
            '[SyncService] posts hydration resolved authors local=${existingAuthorIds.length}/${authorIds.length}');

        for (final post in posts) {
          try {
            if (!existingAuthorIds.contains(post.authorId)) {
              debugPrint(
                  '[SyncService] deferring post=${post.id} because author=${post.authorId} is still missing locally');
              continue;
            }
            await _postDao.insertPost(post);
            debugPrint(
              '[SyncService] inserted post=${post.id} author=${post.authorId} '
              'type=${post.type} mediaCount=${post.mediaUrls.length}',
            );
          } catch (error, stackTrace) {
            debugPrint(
              '[SyncService] failed inserting post=${post.id} author=${post.authorId}: $error',
            );
            debugPrint('$stackTrace');
          }
        }

        final db = await DatabaseHelper.instance.database;
        await db.rawQuery('PRAGMA wal_checkpoint(PASSIVE)');
        final rows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM posts');
        debugPrint(
            '[SyncService] local posts count after hydration=${rows.first['cnt']}');

        final verifyQuery =
            await db.rawQuery('SELECT id, type FROM posts LIMIT 3');
        debugPrint('[SyncService] verify posts in DB: $verifyQuery');
      });

      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null && currentUid.isNotEmpty) {
        await _runHydrationStep('groups', () => _syncRemoteGroups(currentUid));
      } else {
        debugPrint(
            '[SyncService] skipping groups hydration (no authenticated user)');
      }
      if (currentUid != null && currentUid.isNotEmpty) {
        await _runHydrationStep(
            'messages', () => _syncRemoteMessages(currentUid));
        await _runHydrationStep('notifications', () async {
          debugPrint(
              '[SyncService] Pulling remote notifications for user=$currentUid');
          final notifSnap = await FirebaseFirestore.instance
              .collection('notifications')
              .where('user_id', isEqualTo: currentUid)
              .orderBy('created_at', descending: true)
              .limit(50)
              .get(const GetOptions(source: Source.serverAndCache));

          final db = await DatabaseHelper.instance.database;
          for (final doc in notifSnap.docs) {
            final notificationId = doc.id;
            final d = doc.data();
            final ts = d['created_at'];
            final createdAtMs = ts is Timestamp
                ? ts.millisecondsSinceEpoch
                : DateTime.now().millisecondsSinceEpoch;
            final existing = await db.query(
              'notifications',
              columns: ['id', 'is_read', 'extra_json'],
              where: 'id = ?',
              whereArgs: [notificationId],
              limit: 1,
            );
            final alreadyDelivered =
                _preferences.wasNotificationDelivered(notificationId);
            final localRead = existing.isNotEmpty &&
                (existing.first['is_read'] as int? ?? 0) == 1;
            final remoteRead = d['is_read'] as bool? ?? false;
            final effectiveIsRead = localRead || remoteRead;
            final localExtraJson = existing.isNotEmpty
                ? existing.first['extra_json'] as String?
                : null;
            final remoteExtra = d['extra'];
            final remoteExtraJson = d['extra_json'] as String? ??
                (remoteExtra is Map<String, dynamic>
                    ? jsonEncode(remoteExtra)
                    : remoteExtra is Map
                        ? jsonEncode(Map<String, dynamic>.from(remoteExtra))
                        : null);
            final row = <String, Object?>{
              'id': notificationId,
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
            final rowUserId = row['user_id'] as String;
            final rowSenderId = row['sender_id'] as String?;
            if (rowSenderId != null &&
                rowSenderId.isNotEmpty &&
                rowSenderId == rowUserId) {
              debugPrint(
                '[SyncService] Skipping self notification hydration id=$notificationId user=$rowUserId',
              );
              if (!alreadyDelivered) {
                await _preferences.markNotificationDelivered(notificationId);
              }
              continue;
            }
            await db.insert('notifications', row,
                conflictAlgorithm: ConflictAlgorithm.replace);
            if (!alreadyDelivered && !notifSnap.metadata.isFromCache) {
              if (!effectiveIsRead && !suppressNotificationAlerts) {
                await _showLocalAlertForNotification(row);
              }
              await _preferences.markNotificationDelivered(notificationId);
            }
          }

          debugPrint(
            '[SyncService] Pulled ${notifSnap.docs.length} notification(s) '
            'for $currentUid fromCache=${notifSnap.metadata.isFromCache}',
          );
        });

        await _runHydrationStep(
            'follows', () => _syncRemoteFollows(currentUid));
        await _runHydrationStep(
            'likes',
            () =>
                _syncRemoteLikes(currentUid, candidatePostIds: syncedPostIds));
        await _runHydrationStep(
            'dislikes',
            () => _syncRemoteDislikes(currentUid,
                candidatePostIds: syncedPostIds));
        await _runHydrationStep(
          'interaction_counts',
          () => _refreshRemoteInteractionCounts(
            candidatePostIds: syncedPostIds,
          ),
        );
        await _runHydrationStep(
          'comments_for_visible_posts',
          () => _syncRemoteCommentsForPosts(
            candidatePostIds: syncedPostIds,
          ),
        );
        await _runHydrationStep(
            'post_views', () => _syncRemotePostViews(currentUid));
        await _runHydrationStep(
            'collab_requests', () => _syncRemoteCollabRequests(currentUid));
        await _runHydrationStep(
            'post_joins', () => _syncRemoteOpportunityJoins(currentUid));
      }
    } finally {
      await _logSyncSnapshot(label: 'after_remote_pull');
      _isHydrating = false;
      _hydrationFuture = null;
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
      debugPrint(
          '[SyncService] markConversationReadRemote failed for conversation=$conversationId user=$userId: $error');
    }
  }

  Future<void> markCollaborationRequestViewedRemote(String requestId) async {
    try {
      final now = DateTime.now().toIso8601String();
      await FirebaseFirestore.instance
          .collection('collab_requests')
          .doc(requestId)
          .update({
        'receiver_viewed_at': now,
        'updated_at': now,
      });
    } catch (error) {
      debugPrint(
          '[SyncService] markCollaborationRequestViewedRemote failed for request=$requestId: $error');
    }
  }

  Future<void> markAllIncomingRequestsViewedRemote(String userId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('collab_requests')
          .where('receiver_id', isEqualTo: userId)
          .where('receiver_viewed_at', isNull: true)
          .get();

      if (snap.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      final now = DateTime.now().toIso8601String();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'receiver_viewed_at': now,
          'updated_at': now,
        });
      }
      await batch.commit();
    } catch (error) {
      debugPrint(
          '[SyncService] markAllIncomingRequestsViewedRemote failed for user=$userId: $error');
    }
  }

  /// Fast path used by realtime inbox listeners.
  /// Pulls only conversation/message/collaboration slices instead of a full
  /// hydration pass.
  Future<void> syncRealtimeInboxSlices() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      return;
    }

    try {
      await processPendingSync();
      await _syncRemoteMessages(currentUid);
      await _syncRemoteCollabRequests(currentUid);
    } catch (error) {
      debugPrint('[SyncService] syncRealtimeInboxSlices failed: $error');
    }
  }

  /// Fast path used by realtime feed listeners for likes/dislikes/comments/
  /// ratings updates without forcing a full remote hydration.
  Future<void> syncRealtimeInteractionSlices({
    Iterable<String> candidatePostIds = const [],
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    try {
      await _refreshRemoteInteractionCounts(
        candidatePostIds: candidatePostIds,
      );
      await _syncRemoteCommentsForPosts(
        candidatePostIds: candidatePostIds,
      );
      if (currentUid != null && currentUid.isNotEmpty) {
        await _syncRemoteLikes(
          currentUid,
          candidatePostIds: candidatePostIds,
        );
        await _syncRemoteDislikes(
          currentUid,
          candidatePostIds: candidatePostIds,
        );
      }
    } catch (error) {
      debugPrint('[SyncService] syncRealtimeInteractionSlices failed: $error');
    }
  }

  Future<void> _runHydrationStep(
      String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      debugPrint('[SyncService] $label remote-to-local sync failed: $error');
      debugPrint(
          '[SyncService] $label remote-to-local stacktrace: $stackTrace');
    }
  }

  /// Fetches every user document from Firestore and upserts into local SQLite.
  /// Called at the top of admin hydration so all FK dependencies are satisfied
  /// before posts / groups / follows are written.
  Future<void> _syncAllUsers() async {
    debugPrint(
        '[SyncService][UserSync] ── _syncAllUsers starting ──────────────');

    // ── Remote count ──────────────────────────────────────────────────────
    final users = await _firestore.getAllUsersFromRemote(limit: 500);
    debugPrint(
        '[SyncService][UserSync] remote Firestore user count = ${users.length}');
    for (final user in users) {
      debugPrint('[SyncService][UserSync]   remote uid=${user.id} '
          'email=${user.email} role=${user.role.name}');
    }

    // ── Local count before upsert ─────────────────────────────────────────
    final localBefore = await _userDao.getUserCount();
    debugPrint(
        '[SyncService][UserSync] local SQLite count BEFORE upsert = $localBefore');

    // ── Upsert ────────────────────────────────────────────────────────────
    var upserted = 0;
    var failed = 0;
    for (final user in users) {
      try {
        await _userDao.insertUser(user);
        upserted++;
      } catch (error) {
        failed++;
        debugPrint('[SyncService][UserSync] ⚠ failed upserting uid=${user.id} '
            'email=${user.email} role=${user.role.name}: $error');
      }
    }

    // ── Local count after upsert ──────────────────────────────────────────
    final localAfter = await _userDao.getUserCount();
    debugPrint(
        '[SyncService][UserSync] local SQLite count AFTER upsert  = $localAfter');
    debugPrint('[SyncService][UserSync] summary  remote=${users.length} '
        'upserted=$upserted failed=$failed '
        'localBefore=$localBefore localAfter=$localAfter '
        'delta=${localAfter - localBefore}');
    if (localAfter < users.length) {
      debugPrint('[SyncService][UserSync] ⚠ CONSISTENCY GAP: '
          'remote=${users.length} but local=$localAfter '
          '— ${users.length - localAfter} user(s) missing locally. '
          'Check failed upserts above for FK/constraint errors.');
    } else {
      debugPrint('[SyncService][UserSync] ✓ local count matches remote.');
    }
    debugPrint(
        '[SyncService][UserSync] ── _syncAllUsers done ───────────────────');
  }

  Future<Set<String>> _getExistingLocalUserIds(Iterable<String> userIds) async {
    final existing = <String>{};
    for (final userId in userIds.where((id) => id.isNotEmpty)) {
      final user = await _userDao.getUserById(userId);
      if (user != null) {
        existing.add(userId);
      }
    }
    return existing;
  }

  String _placeholderEmailForUser(String userId) {
    return 'placeholder+$userId@must-startrack.invalid';
  }

  UserModel _buildPlaceholderUser({
    required String userId,
    String? displayName,
    String? photoUrl,
    String? role,
    String? email,
  }) {
    final now = DateTime.now();
    final normalizedEmail = (email ?? '').trim().toLowerCase();
    return UserModel(
      id: userId,
      firebaseUid: userId,
      email: normalizedEmail.isNotEmpty
          ? normalizedEmail
          : _placeholderEmailForUser(userId),
      role: UserRole.fromString(role),
      displayName:
          (displayName ?? '').trim().isEmpty ? null : displayName?.trim(),
      photoUrl: (photoUrl ?? '').trim().isEmpty ? null : photoUrl?.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _insertPlaceholderUser(
    UserModel user, {
    required String logContext,
  }) async {
    try {
      await _userDao.insertUser(user);
      debugPrint('[SyncService] inserted placeholder user=${user.id} '
          'email=${user.email} role=${user.role.name} context=$logContext');
    } catch (error, stackTrace) {
      debugPrint('[SyncService] failed inserting placeholder user=${user.id} '
          'email=${user.email} context=$logContext: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<Set<String>> _cacheUsersAndGetExistingIds(
    Iterable<String> userIds, {
    Map<String, UserModel>? placeholderUsers,
    String logContext = 'dependencies',
  }) async {
    final normalizedIds = userIds.where((id) => id.isNotEmpty).toSet();
    if (normalizedIds.isEmpty) {
      return const <String>{};
    }

    try {
      final users = await _firestore.getUsersByIds(normalizedIds);
      for (final user in users) {
        try {
          await _userDao.insertUser(user);
        } catch (error, stackTrace) {
          debugPrint(
              '[SyncService] failed inserting dependency user=${user.id}: $error');
          debugPrint('$stackTrace');
        }
      }
    } catch (error, stackTrace) {
      debugPrint('[SyncService] failed fetching dependency users: $error');
      debugPrint('$stackTrace');
    }

    var existingIds = await _getExistingLocalUserIds(normalizedIds);
    final missingIds = normalizedIds.difference(existingIds);
    if (missingIds.isNotEmpty) {
      debugPrint(
          '[SyncService] unresolved user dependencies context=$logContext '
          'missing=${missingIds.length} ids=$missingIds');
      for (final userId in missingIds) {
        final placeholder =
            placeholderUsers?[userId] ?? _buildPlaceholderUser(userId: userId);
        await _insertPlaceholderUser(placeholder, logContext: logContext);
      }
      existingIds = await _getExistingLocalUserIds(normalizedIds);
    }

    return existingIds;
  }

  Future<bool> _localGroupExists(String groupId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      DatabaseSchema.tableGroups,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _syncRemoteGroups(String? currentUid) async {
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint('[SyncService] skipping _syncRemoteGroups (empty user id)');
      return;
    }

    final recentGroups = await _firestore.getRecentGroups(limit: 120);
    final personalMemberships =
        await _firestore.getGroupMembersForUser(currentUid);

    final allGroupIds = <String>{
      ...recentGroups.map((group) => group.id),
      ...personalMemberships.map((member) => member.groupId),
    };

    final groups = allGroupIds.isEmpty
        ? recentGroups
        : await _firestore.getGroupsByIds(allGroupIds);

    final referencedUserIds = <String>{
      ...groups.map((group) => group.creatorId),
      ...personalMemberships.map((member) => member.userId),
    };

    final groupMembers = allGroupIds.isEmpty
        ? personalMemberships
        : await _firestore.getGroupMembersByGroupIds(allGroupIds);
    referencedUserIds.addAll(groupMembers.map((member) => member.userId));

    final placeholderUsers = <String, UserModel>{
      for (final group in groups)
        if (group.creatorId.isNotEmpty)
          group.creatorId: _buildPlaceholderUser(
            userId: group.creatorId,
            displayName: group.creatorName,
          ),
      for (final member in groupMembers)
        if (member.userId.isNotEmpty)
          member.userId: _buildPlaceholderUser(
            userId: member.userId,
            displayName: member.userName,
            photoUrl: member.userPhotoUrl,
          ),
    };
    final existingUserIds = await _cacheUsersAndGetExistingIds(
      referencedUserIds,
      placeholderUsers: placeholderUsers,
      logContext: 'group_dependencies',
    );

    var upsertedGroups = 0;
    var deferredGroups = 0;
    for (final group in groups) {
      if (!existingUserIds.contains(group.creatorId)) {
        deferredGroups++;
        debugPrint(
          '[SyncService] deferring group=${group.id} because creator=${group.creatorId} is missing locally',
        );
        continue;
      }
      try {
        await _groupDao.upsertGroup(group);
        upsertedGroups++;
      } catch (error, stackTrace) {
        deferredGroups++;
        debugPrint('[SyncService] failed inserting group=${group.id}: $error');
        debugPrint('$stackTrace');
      }
    }

    final mergedMembers = <String, GroupMemberModel>{
      for (final member in groupMembers) member.id: member,
      for (final member in personalMemberships) member.id: member,
    };

    var upsertedMembers = 0;
    var deferredMembers = 0;
    for (final member in mergedMembers.values) {
      final groupExists = await _localGroupExists(member.groupId);
      final userExists = existingUserIds.contains(member.userId);
      if (!groupExists || !userExists) {
        deferredMembers++;
        debugPrint(
          '[SyncService] deferring group_member=${member.id} missingGroup=$groupExists missingUser=$userExists',
        );
        continue;
      }
      try {
        // Protect a locally-active membership from being downgraded to 'pending'
        // by a stale remote snapshot (e.g. when processPendingSync and
        // syncRemoteToLocal race and the accept-invite write hasn't reached
        // Firestore yet).
        if (member.status != 'active') {
          final local = await _groupMemberDao.getMemberById(member.id);
          if (local != null && local.status == 'active') {
            debugPrint(
              '[SyncService] Protecting active membership ${member.id} '
              'from remote status=${member.status} downgrade',
            );
            upsertedMembers++;
            continue;
          }
        }
        await _groupMemberDao.upsertMember(member);
        upsertedMembers++;
      } catch (error, stackTrace) {
        deferredMembers++;
        debugPrint(
            '[SyncService] failed inserting group_member=${member.id}: $error');
        debugPrint('$stackTrace');
      }
    }

    for (final groupId in allGroupIds) {
      if (!await _localGroupExists(groupId)) {
        continue;
      }
      final count = await _groupMemberDao.countActiveMembers(groupId);
      await _groupDao.updateMemberCount(groupId, count);
    }

    debugPrint(
      '[SyncService] Hydrated groups upserted=$upsertedGroups deferred=$deferredGroups '
      'memberships upserted=$upsertedMembers deferred=$deferredMembers',
    );
  }

  Future<void> refreshGroupWorkspace({
    required String groupId,
    String? currentUid,
  }) async {
    final safeGroupId = groupId.trim();
    final safeUid =
        (currentUid ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (safeGroupId.isEmpty || safeUid.isEmpty) {
      debugPrint(
        '[SyncService] refreshGroupWorkspace skipped group=$safeGroupId user=$safeUid',
      );
      return;
    }

    try {
      final groups = await _firestore.getGroupsByIds([safeGroupId]);
      final members = await _firestore.getGroupMembersByGroupIds([safeGroupId]);
      final personalMemberships = await _firestore.getGroupMembersForUser(
        safeUid,
      );
      final posts = await _firestore.getPostsByGroupId(
        safeGroupId,
        limit: 80,
        includePendingForAdmin: false,
      );

      final referencedUserIds = <String>{
        ...groups.map((group) => group.creatorId),
        ...members.map((member) => member.userId),
        ...personalMemberships.map((member) => member.userId),
        ...posts.map((post) => post.authorId),
      }..removeWhere((id) => id.trim().isEmpty);

      final placeholderUsers = <String, UserModel>{
        for (final group in groups)
          if (group.creatorId.isNotEmpty)
            group.creatorId: _buildPlaceholderUser(
              userId: group.creatorId,
              displayName: group.creatorName,
            ),
        for (final member in members)
          if (member.userId.isNotEmpty)
            member.userId: _buildPlaceholderUser(
              userId: member.userId,
              displayName: member.userName,
              photoUrl: member.userPhotoUrl,
            ),
        for (final member in personalMemberships)
          if (member.userId.isNotEmpty)
            member.userId: _buildPlaceholderUser(
              userId: member.userId,
              displayName: member.userName,
              photoUrl: member.userPhotoUrl,
            ),
        for (final post in posts)
          if (post.authorId.isNotEmpty)
            post.authorId: _buildPlaceholderUser(
              userId: post.authorId,
              displayName: post.authorName,
              photoUrl: post.authorPhotoUrl,
            ),
      };
      final existingUserIds = await _cacheUsersAndGetExistingIds(
        referencedUserIds,
        placeholderUsers: placeholderUsers,
        logContext: 'refresh_group_workspace',
      );

      for (final group in groups) {
        if (existingUserIds.contains(group.creatorId)) {
          await _groupDao.upsertGroup(group);
        }
      }

      final mergedMembers = <String, GroupMemberModel>{
        for (final member in members) member.id: member,
        for (final member in personalMemberships.where(
          (member) => member.groupId == safeGroupId,
        ))
          member.id: member,
      };
      for (final member in mergedMembers.values) {
        if (existingUserIds.contains(member.userId)) {
          if (member.status != 'active') {
            final local = await _groupMemberDao.getMemberById(member.id);
            if (local != null && local.status == 'active') {
              continue;
            }
          }
          await _groupMemberDao.upsertMember(member);
        }
      }

      for (final post in posts) {
        if (existingUserIds.contains(post.authorId)) {
          await _postDao.insertPost(post);
        }
      }

      debugPrint(
        '[SyncService] refreshed group workspace group=$safeGroupId '
        'groups=${groups.length} members=${mergedMembers.length} posts=${posts.length}',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SyncService] refreshGroupWorkspace failed group=$safeGroupId: $error',
      );
      debugPrint('$stackTrace');
    }
  }

  // ── Process a single job ──────────────────────────────────────────────────

  Future<bool> _processJob(SyncJob job) async {
    try {
      _lastJobError = 'sync_failed';
      switch (job.entityType) {
        case 'users':
          return await _syncUser(job);
        case 'posts':
          return await _syncPost(job);
        case 'groups':
          return await _syncGroup(job);
        case 'group_members':
          return await _syncGroupMember(job);
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
        case 'collaboration_requests':
          return await _syncCollabRequest(job);
        case 'opportunity_joins':
          return await _syncOpportunityJoin(job);
        case 'post_ratings':
          return await _syncPostRating(job);
        case 'app_feedback':
          return await _syncAppFeedback(job);
        case 'moderation_queue':
          return await _syncModerationReport(job);
        case 'faculties':
          return await _syncFaculty(job);
        case 'courses':
          return await _syncCourse(job);
        case 'recommendation_logs':
          return await _syncRecommendationLog(job);
        default:
          // Unknown entity type — remove from queue to prevent blocking
          return true;
      }
    } catch (e, st) {
      // Log and return false to trigger backoff
      _lastJobError = e.toString();
      debugPrint(
          '[SyncService] ❌ Job id=${job.id} type=${job.entityType} failed: $e\n$st');
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

  Future<PostModel?> _tryGetRemotePostForSync(String postId) async {
    try {
      return await _firestore.getPostById(postId);
    } on FirebaseException catch (e) {
      // Authors can create pending posts that are not globally readable.
      // If rules deny this pre-read, continue sync with unknown previous state.
      if (e.code == 'permission-denied') {
        debugPrint(
          '[SyncService] Skipping remote pre-read for post=$postId due to permission-denied.',
        );
        return null;
      }
      rethrow;
    }
  }

  Future<bool> _syncPost(SyncJob job) async {
    switch (job.operation) {
      case 'create':
      case 'update':
        final previousRemote = await _tryGetRemotePostForSync(job.entityId);
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
        await _fanoutModerationNotifications(
          post: syncedPost,
          operation: job.operation,
          previousRemoteStatus: previousRemote?.moderationStatus,
        );
        await _fanoutOpportunityMatchNotifications(
          post: syncedPost,
          operation: job.operation,
          previousRemoteStatus: previousRemote?.moderationStatus,
        );
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

  Future<bool> _syncGroup(SyncJob job) async {
    switch (job.operation) {
      case 'create':
      case 'update':
        final localGroup = await _groupDao.getGroupById(job.entityId);
        final group = localGroup ??
            (job.payloadJson.isEmpty
                ? null
                : GroupModel.fromJson(
                    {'id': job.entityId, ...job.payloadJson}));
        if (group == null) return true;
        await _firestore.setGroup(group);
        return true;
      case 'delete':
      case 'dissolve':
        await _firestore.dissolveGroup(job.entityId);
        return true;
      default:
        return true;
    }
  }

  Future<bool> _syncGroupMember(SyncJob job) async {
    switch (job.operation) {
      case 'create':
      case 'update':
        final localMember = await _groupMemberDao.getMemberById(job.entityId);
        final member = localMember ??
            (job.payloadJson.isEmpty
                ? null
                : GroupMemberModel.fromJson({
                    'id': job.entityId,
                    ...job.payloadJson,
                  }));
        if (member == null) return true;
        await _firestore.setGroupMember(member);

        // Notify the invited user when a new pending invite is written to Firestore
        // so their device receives a push alert and the invite card appears immediately.
        if (job.operation == 'create' &&
            member.status == 'pending' &&
            member.invitedBy != null &&
            member.invitedBy!.isNotEmpty &&
            member.userId != member.invitedBy) {
          // group_name is not stored in the group_members SQLite column; look it up.
          final groupName = member.groupName ??
              (await _groupDao.getGroupById(member.groupId))?.name ??
              'a group';
          final inviterName = member.invitedByName ?? 'Someone';
          await _bestEffortUserNotification(
            source: 'group_invite',
            notificationId: 'group_invite_${member.id}',
            receiverId: member.userId,
            senderId: member.invitedBy!,
            senderName: inviterName,
            type: 'group_invite',
            body: '$inviterName invited you to join "$groupName"',
            entityId: member.groupId,
          );
        }
        return true;
      case 'delete':
        await _firestore.deleteGroupMember(job.entityId);
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
    debugPrint(
        '[SyncMessage] Processing job id=${job.id} operation=${job.operation} entityId=${job.entityId}');

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
    if (payload.isEmpty) {
      debugPrint(
          '[SyncMessage] ⚠️ Empty payload for job id=${job.id} — skipping');
      return true;
    }

    debugPrint(
        '[SyncMessage] Payload: conversationId=${payload['conversation_id']} '
        'senderId=${payload['sender_id']} content="${payload['content']}"');

    final conversationId = (payload['conversation_id'] as String?)?.trim();
    final senderId = (payload['sender_id'] as String?)?.trim();
    if (conversationId == null ||
        conversationId.isEmpty ||
        senderId == null ||
        senderId.isEmpty) {
      debugPrint(
        '[SyncMessage] Skipping malformed message payload for job ${job.id}: $payload',
      );
      return true;
    }
    final receiverId =
        _resolveMessageReceiverId(conversationId, senderId, payload);
    if (receiverId == null || receiverId == senderId) {
      debugPrint(
        '[SyncMessage] Skipping self-target message job ${job.id}: '
        'conversationId=$conversationId senderId=$senderId',
      );
      return true;
    }

    final msg = MessageModel(
      id: job.entityId,
      conversationId: conversationId,
      senderId: senderId,
      content: payload['content'] as String,
      messageType: payload['message_type'] as String? ?? 'text',
      fileUrl: payload['file_url'] as String?,
      fileName: payload['file_name'] as String?,
      fileSize: payload['file_size'] as String?,
      createdAt: DateTime.tryParse(payload['created_at'] as String? ?? '') ??
          DateTime.now(),
    );

    debugPrint(
        '[SyncMessage] Writing to Firestore conversations/${msg.conversationId}/messages/${msg.id}');
    await _firestore.sendMessage(msg);
    await _fanoutMessageNotification(
      message: msg,
      receiverId: receiverId,
      senderName: payload['sender_name'] as String?,
    );
    debugPrint(
        '[SyncMessage] ✅ Message ${msg.id} written to Firestore successfully');
    return true;
  }

  String? _resolveMessageReceiverId(
    String conversationId,
    String senderId,
    Map<String, dynamic> payload,
  ) {
    final explicit = (payload['receiver_id'] as String?)?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    final parts = conversationId
        .split('_')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    for (final part in parts) {
      if (part != senderId) {
        return part;
      }
    }
    return null;
  }

  String _messageNotificationPreview(MessageModel message) {
    final type = message.messageType.trim().toLowerCase();
    if (type == 'audio') return 'Voice message';
    if (type == 'image') return 'Image';
    if (type == 'file') return 'Document';
    final text = message.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return 'New message';
    return text.length > 90 ? '${text.substring(0, 90)}...' : text;
  }

  Future<void> _fanoutMessageNotification({
    required MessageModel message,
    required String receiverId,
    String? senderName,
  }) async {
    final senderLabel = _uplinkUserLabel(
      name: senderName,
      id: message.senderId,
    );
    await _bestEffortUserNotification(
      source: 'message',
      notificationId: 'message_${message.id}',
      receiverId: receiverId,
      senderId: message.senderId,
      senderName: senderName,
      type: 'message',
      body: '$senderLabel: ${_messageNotificationPreview(message)}',
      detail: 'Tap to open the chat.',
      entityId: message.senderId,
      extra: {
        'peer_id': message.senderId,
        'conversation_id': message.conversationId,
        'message_id': message.id,
        'message_type': message.messageType,
      },
    );
  }

  Future<bool> _syncPostRating(SyncJob job) async {
    switch (job.operation) {
      case 'create':
      case 'update':
        final payload = job.payloadJson;
        final payloadRaterId = payload['user_id'] as String?;
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid == null || currentUid.isEmpty) {
          debugPrint(
            '[SyncRating] No active auth session for job ${job.id}; will retry.',
          );
          return false;
        }
        final raterId = currentUid;
        if (payloadRaterId != null && payloadRaterId != currentUid) {
          debugPrint(
            '[SyncRating] user_id mismatch on job ${job.id}: '
            'payload=$payloadRaterId auth=$currentUid; normalizing to auth uid.',
          );
        }
        final raterName = payload['rater_name'] as String?;
        final normalizedPayload = <String, dynamic>{
          ...payload,
          'user_id': raterId,
        };
        _uplinkTrace('RATING_WRITE_START', details: {
          'jobId': job.id,
          'operation': job.operation,
          'ratingId': job.entityId,
          'postId': payload['post_id'],
          'userName': _uplinkUserLabel(name: raterName, id: raterId),
          'userId': raterId,
          'stars': payload['stars'],
        });
        debugPrint(
          '[SyncRating] Writing rating id=${job.entityId} '
          'post=${normalizedPayload['post_id']} user=${normalizedPayload['user_id']} '
          'stars=${normalizedPayload['stars']}',
        );
        await _firestore.setPostRating(
          ratingId: job.entityId,
          payload: normalizedPayload,
        );
        await _verifyUplinkDoc(
          action: 'RATING',
          docRef: FirebaseFirestore.instance
              .collection('post_ratings')
              .doc(job.entityId),
          expectedExists: true,
          details: {
            'jobId': job.id,
            'ratingId': job.entityId,
            'postId': payload['post_id'],
            'userName': _uplinkUserLabel(name: raterName, id: raterId),
            'userId': raterId,
          },
        );
        final authorId = payload['author_id'] as String?;
        if (authorId != null &&
            authorId.isNotEmpty &&
            raterId.isNotEmpty &&
            authorId != raterId) {
          final postId = payload['post_id'] as String?;
          final postTitle = payload['post_title'] as String? ?? 'your post';
          final raterName = payload['rater_name'] as String? ?? 'Someone';
          final stars = payload['stars'];
          await _bestEffortUserNotification(
            source: 'rating',
            notificationId: 'rating_${job.entityId}',
            receiverId: authorId,
            senderId: raterId,
            senderName: raterName,
            type: 'rating',
            body: '$raterName rated "$postTitle" ${stars ?? ''}'.trim(),
            detail: stars != null ? 'Rating: $stars star(s)' : null,
            entityId: postId,
          );
        }
        return true;
      case 'delete':
        _uplinkTrace('RATING_DELETE_START', details: {
          'jobId': job.id,
          'operation': job.operation,
          'ratingId': job.entityId,
        });
        await _firestore.deletePostRating(job.entityId);
        await _verifyUplinkDoc(
          action: 'RATING',
          docRef: FirebaseFirestore.instance
              .collection('post_ratings')
              .doc(job.entityId),
          expectedExists: false,
          details: {
            'jobId': job.id,
            'ratingId': job.entityId,
          },
        );
        return true;
      default:
        return true;
    }
  }

  Future<bool> _syncAppFeedback(SyncJob job) async {
    switch (job.operation) {
      case 'create':
      case 'update':
        await _firestore.setAppFeedback(
          feedbackId: job.entityId,
          payload: job.payloadJson,
        );
        return true;
      case 'delete':
        await _firestore.deleteAppFeedback(job.entityId);
        return true;
      default:
        return true;
    }
  }

  // ── Follow sync ───────────────────────────────────────────────────────────

  Future<bool> _syncFollow(SyncJob job) async {
    final payload = job.payloadJson;
    final payloadFollowerId = payload['follower_id'] as String?;
    final followingId =
        (payload['following_id'] ?? payload['followed_id']) as String?;

    if (payloadFollowerId == null || followingId == null) {
      debugPrint(
          '[SyncFollow] Skipping malformed job id=${job.id} payload=$payload');
      return true;
    }

    // Guard: Firestore rule requires follower_id == uid(). If this job was
    // queued under a different account (e.g. during testing), skip it so it
    // doesn't block the queue or generate misleading PERMISSION_DENIED logs.
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint(
        '[SyncFollow] No active auth session for job ${job.id}; will retry.',
      );
      return false;
    }
    final followerId = currentUid;
    if (payloadFollowerId != currentUid) {
      debugPrint(
        '[SyncFollow] follower_id mismatch on job ${job.id}: '
        'payload=$payloadFollowerId auth=$currentUid; normalizing to auth uid.',
      );
    }

    if (job.operation == 'create') {
      debugPrint(
          '[SyncFollow] Writing follow follower=$followerId followee=$followingId entity=${job.entityType}');
      await _firestore.follow(followerId: followerId, followingId: followingId);
      final followerName = payload['follower_name'] as String? ?? 'Someone';
      if (followingId != followerId) {
        final followedAtToken = (payload['followed_at'] as String?)
                ?.replaceAll(RegExp(r'[^0-9A-Za-z]'), '') ??
            DateTime.now().millisecondsSinceEpoch.toString();
        await _bestEffortUserNotification(
          source: 'follow',
          notificationId:
              'follow_${followerId}_${followingId}_$followedAtToken',
          receiverId: followingId,
          senderId: followerId,
          senderName: followerName,
          type: 'follow',
          body: '$followerName started following you',
          entityId: followingId,
        );
      }
    } else if (job.operation == 'delete') {
      debugPrint(
          '[SyncFollow] Removing follow follower=$followerId followee=$followingId');
      await _firestore.unfollow(
          followerId: followerId, followingId: followingId);
    }
    return true;
  }

  // ── Notification sync ─────────────────────────────────────────────────────

  Future<bool> _syncNotification(SyncJob job) async {
    final payload = job.payloadJson;
    final notificationId =
        payload['notification_id'] as String? ?? job.entityId;
    if (notificationId.isEmpty) {
      return true;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint(
        '[SyncNotification] Skipping notification=$notificationId: no active auth user.',
      );
      return true;
    }

    // Guard against stale queue items from another account. These can never
    // satisfy the notification update rule and should not keep retrying.
    final db = await DatabaseHelper.instance.database;
    final localNotification = await db.query(
      'notifications',
      columns: ['user_id'],
      where: 'id = ?',
      whereArgs: [notificationId],
      limit: 1,
    );
    if (localNotification.isNotEmpty) {
      final ownerId = localNotification.first['user_id'] as String?;
      if (ownerId != null && ownerId.isNotEmpty && ownerId != currentUid) {
        debugPrint(
          '[SyncNotification] Skipping notification=$notificationId: owner=$ownerId currentUid=$currentUid.',
        );
        return true;
      }
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
          debugPrint(
              '[SyncNotification] Unable to decode extra_json for notification=$notificationId raw=$raw');
        }
      }
    }
    if (updates.isEmpty) {
      return true;
    }

    debugPrint(
        '[SyncNotification] Updating notification=$notificationId keys=${updates.keys.toList()}');

    final docRef = FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId);
    try {
      // Use update() to match security rules that only allow owner updates on
      // existing notification docs (is_read/extra), not create semantics.
      await docRef.update(updates);
    } on FirebaseException catch (error) {
      if (error.code == 'not-found') {
        debugPrint(
          '[SyncNotification] Dropping notification sync for missing remote doc id=$notificationId.',
        );
        return true;
      }
      if (error.code == 'permission-denied') {
        debugPrint(
          '[SyncNotification] Dropping unsyncable notification job id=${job.id} notification=$notificationId due to permission-denied.',
        );
        return true;
      }
      rethrow;
    }
    return true;
  }

  // ── Like sync ─────────────────────────────────────────────────────────────

  Future<bool> _syncLike(SyncJob job) async {
    final payload = job.payloadJson;
    final payloadUserId = payload['user_id'] as String?;
    final actorName = (payload['actor_name'] ??
        payload['user_name'] ??
        payload['author_name']) as String?;
    final postId = payload['post_id'] as String?;
    final isLiking = payload['is_liking'] as bool? ?? true;

    if (payloadUserId == null || postId == null) {
      debugPrint(
          '[SyncLike] Skipping malformed job id=${job.id} payload=$payload');
      return true;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint(
        '[SyncLike] No active auth session for job ${job.id}; will retry.',
      );
      return false;
    }
    final userId = currentUid;
    if (payloadUserId != currentUid) {
      debugPrint(
        '[SyncLike] user_id mismatch on job ${job.id}: '
        'payload=$payloadUserId auth=$currentUid; normalizing to auth uid.',
      );
    }

    debugPrint(
        '[SyncLike] Writing remote like post=$postId user=$userId isLiking=$isLiking');
    _uplinkTrace('LIKE_WRITE_START', details: {
      'jobId': job.id,
      'operation': job.operation,
      'postId': postId,
      'userName': _uplinkUserLabel(name: actorName, id: userId),
      'userId': userId,
      'isLiking': isLiking,
    });
    await _firestore.toggleLike(
      postId: postId,
      userId: userId,
      isLiking: isLiking,
    );
    await _verifyUplinkDoc(
      action: 'LIKE',
      docRef: FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .collection('likes')
          .doc(userId),
      expectedExists: isLiking,
      details: {
        'jobId': job.id,
        'postId': postId,
        'userName': _uplinkUserLabel(name: actorName, id: userId),
        'userId': userId,
        'isLiking': isLiking,
      },
    );

    final authorId = payload['author_id'] as String?;
    if (isLiking && authorId != null && authorId != userId) {
      final actorName = payload['actor_name'] as String? ?? 'Someone';
      final postTitle = payload['post_title'] as String? ?? 'your project';
      final likedAtToken = (payload['liked_at'] as String?)
              ?.replaceAll(RegExp(r'[^0-9A-Za-z]'), '') ??
          DateTime.now().millisecondsSinceEpoch.toString();
      await _bestEffortUserNotification(
        source: 'like',
        notificationId: 'like_${userId}_${postId}_$likedAtToken',
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
    final actorName = (payload['actor_name'] ??
        payload['user_name'] ??
        payload['author_name']) as String?;
    final postId = payload['post_id'] as String?;
    final isDisliking = payload['is_disliking'] as bool? ?? true;

    if (userId == null || postId == null) {
      debugPrint(
          '[SyncDislike] Skipping malformed job id=${job.id} payload=$payload');
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

    _uplinkTrace('DISLIKE_WRITE_START', details: {
      'jobId': job.id,
      'operation': job.operation,
      'postId': postId,
      'userName': _uplinkUserLabel(name: actorName, id: userId),
      'userId': userId,
      'isDisliking': isDisliking,
    });

    if (isDisliking) {
      await dislikeRef.set({
        'user_id': userId,
        'created_at': FieldValue.serverTimestamp(),
      });
    } else {
      await dislikeRef.delete();
    }

    await _verifyUplinkDoc(
      action: 'DISLIKE',
      docRef: dislikeRef,
      expectedExists: isDisliking,
      details: {
        'jobId': job.id,
        'postId': postId,
        'userName': _uplinkUserLabel(name: actorName, id: userId),
        'userId': userId,
        'isDisliking': isDisliking,
      },
    );

    return true;
  }

  Future<bool> _syncComment(SyncJob job) async {
    final payload = job.payloadJson;
    final payloadAuthorId = payload['author_id'] as String?;
    final authorName =
        (payload['commenter_name'] ?? payload['author_name']) as String?;
    final postId = payload['post_id'] as String?;
    final content = payload['content'] as String? ?? '';
    final parentCommentId = payload['parent_comment_id'] as String?;

    if (payloadAuthorId == null || postId == null || content.trim().isEmpty) {
      return true;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint(
        '[SyncComment] No active auth session for job ${job.id}; will retry.',
      );
      return false;
    }
    final authorId = currentUid;
    if (payloadAuthorId != currentUid) {
      debugPrint(
        '[SyncComment] author_id mismatch on job ${job.id}: '
        'payload=$payloadAuthorId auth=$currentUid; normalizing to auth uid.',
      );
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

    _uplinkTrace('COMMENT_WRITE_START', details: {
      'jobId': job.id,
      'operation': job.operation,
      'commentId': job.entityId,
      'postId': postId,
      'userName': _uplinkUserLabel(name: authorName, id: authorId),
      'authorId': authorId,
      'isReply': parentCommentId != null && parentCommentId.isNotEmpty,
    });

    await FirebaseFirestore.instance
        .collection('comments')
        .doc(job.entityId)
        .set({
      'id': job.entityId,
      'post_id': postId,
      'author_id': authorId,
      'content': content,
      'parent_comment_id': parentCommentId,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _verifyUplinkDoc(
      action: 'COMMENT',
      docRef:
          FirebaseFirestore.instance.collection('comments').doc(job.entityId),
      expectedExists: true,
      details: {
        'jobId': job.id,
        'commentId': job.entityId,
        'postId': postId,
        'userName': _uplinkUserLabel(name: authorName, id: authorId),
        'authorId': authorId,
      },
    );

    final receiverId = payload['receiver_id'] as String?;
    if (receiverId != null && receiverId != authorId) {
      final commenterName =
          (payload['commenter_name'] ?? payload['author_name']) as String? ??
              'Someone';
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
    final payloadViewerId = payload['viewer_id'] as String?;
    final viewerName = payload['viewer_name'] as String?;
    final postId = payload['post_id'] as String?;

    if (payloadViewerId == null || postId == null) {
      debugPrint(
          '[SyncView] Skipping malformed view job id=${job.id} payload=$payload');
      return true;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint(
        '[SyncView] No active auth session for job ${job.id}; will retry.',
      );
      return false;
    }
    final viewerId = currentUid;
    if (payloadViewerId != currentUid) {
      debugPrint(
        '[SyncView] viewer_id mismatch on job ${job.id}: '
        'payload=$payloadViewerId auth=$currentUid; normalizing to auth uid.',
      );
    }

    final normalizedViewId =
        payloadViewerId == currentUid ? job.entityId : '${viewerId}_$postId';
    final authorId = payload['author_id'] as String?;

    final docRef = FirebaseFirestore.instance
        .collection('post_views')
        .doc(normalizedViewId);
    _uplinkTrace('VIEW_WRITE_START', details: {
      'jobId': job.id,
      'operation': job.operation,
      'viewId': normalizedViewId,
      'postId': postId,
      'userName': _uplinkUserLabel(name: viewerName, id: viewerId),
      'viewerId': viewerId,
    });
    var createdRemoteView = false;
    try {
      await docRef.update({
        'viewer_name': payload['viewer_name'] as String?,
        'author_id': authorId,
        'post_title': payload['post_title'] as String?,
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint(
        '[SyncView] Remote view updated viewId=$normalizedViewId post=$postId viewer=$viewerId',
      );
    } on FirebaseException catch (error) {
      final shouldAttemptCreateFallback =
          error.code == 'not-found' || error.code == 'permission-denied';
      if (!shouldAttemptCreateFallback) {
        rethrow;
      }

      try {
        createdRemoteView = true;
        await docRef.set({
          'id': normalizedViewId,
          'viewer_id': viewerId,
          'viewer_name': payload['viewer_name'] as String?,
          'author_id': authorId,
          'post_id': postId,
          'post_title': payload['post_title'] as String?,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint(
          '[SyncView] Remote view created viewId=$normalizedViewId post=$postId viewer=$viewerId',
        );
      } on FirebaseException catch (_) {
        rethrow;
      }
    }

    await _verifyUplinkDoc(
      action: 'VIEW',
      docRef: docRef,
      expectedExists: true,
      details: {
        'jobId': job.id,
        'viewId': normalizedViewId,
        'postId': postId,
        'userName': _uplinkUserLabel(name: viewerName, id: viewerId),
        'viewerId': viewerId,
      },
    );

    if (createdRemoteView) {
      await _bestEffortIncrementPostViewCount(
        postId: postId,
        viewerId: viewerId,
        authorId: authorId,
        jobId: job.id,
      );
    }

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

  Future<void> _bestEffortIncrementPostViewCount({
    required String postId,
    required String viewerId,
    required String jobId,
    String? authorId,
  }) async {
    final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);
    try {
      await postRef.update({
        'view_count': FieldValue.increment(1),
        'updated_at': FieldValue.serverTimestamp(),
      });
      _uplinkTrace('VIEW_COUNT_INCREMENTED', details: {
        'jobId': jobId,
        'postId': postId,
        'viewerId': viewerId,
        'authorId': authorId ?? '',
      });
    } on FirebaseException catch (error) {
      if (error.code == 'not-found') {
        _uplinkTrace('VIEW_COUNT_INCREMENT_SKIPPED_POST_NOT_FOUND', details: {
          'jobId': jobId,
          'postId': postId,
          'viewerId': viewerId,
          'authorId': authorId ?? '',
        });
        return;
      }
      debugPrint(
        '[SyncView] Could not increment post view_count post=$postId '
        'viewer=$viewerId code=${error.code}: ${error.message}',
      );
      _uplinkTrace('VIEW_COUNT_INCREMENT_FAILED', details: {
        'jobId': jobId,
        'postId': postId,
        'viewerId': viewerId,
        'authorId': authorId ?? '',
        'code': error.code,
        'message': error.message ?? '',
      });
    } catch (error) {
      debugPrint(
        '[SyncView] Could not increment post view_count post=$postId '
        'viewer=$viewerId error=$error',
      );
      _uplinkTrace('VIEW_COUNT_INCREMENT_FAILED', details: {
        'jobId': jobId,
        'postId': postId,
        'viewerId': viewerId,
        'authorId': authorId ?? '',
        'error': error.toString(),
      });
    }
  }

  Future<bool> _syncOpportunityJoin(SyncJob job) async {
    final payload = job.payloadJson;
    final userId = payload['user_id'] as String?;
    final postId = payload['post_id'] as String?;

    if (userId == null || postId == null) {
      debugPrint(
          '[SyncJoin] Skipping malformed job id=${job.id} payload=$payload');
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

    final docRef =
        FirebaseFirestore.instance.collection('post_joins').doc(job.entityId);

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

    if (reporterId == null ||
        postId == null ||
        reason == null ||
        reason.trim().isEmpty) {
      debugPrint(
          '[SyncModeration] Skipping malformed job id=${job.id} payload=$payload');
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

    await FirebaseFirestore.instance
        .collection('moderation_queue')
        .doc(job.entityId)
        .set({
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
    debugPrint(
        '[SyncCollab] Processing job id=${job.id} entityId=${job.entityId} retryCount=${job.retryCount}');
    final payload = job.payloadJson;

    if (job.operation == 'update') {
      final status = payload['status'] as String?;
      final responderId = payload['responder_id'] as String?;
      if (status == null || responderId == null) {
        debugPrint(
            '[SyncCollab] ⚠️ Malformed update payload for ${job.entityId}: $payload');
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
      debugPrint(
          '[SyncCollab] Updating Firestore collab_requests/${job.entityId} with status=$status');
      await FirebaseFirestore.instance
          .collection('collab_requests')
          .doc(job.entityId)
          .set(update, SetOptions(merge: true));
      return true;
    }

    final payloadSenderId =
        (payload['sender_id'] ?? payload['from_user_id']) as String?;
    final receiverId =
        (payload['receiver_id'] ?? payload['to_user_id']) as String?;
    final postId = payload['post_id'] as String?;
    final message = payload['message'] as String? ?? '';
    final status = payload['status'] as String? ?? 'pending';
    if (payloadSenderId != null &&
        receiverId != null &&
        payloadSenderId == receiverId) {
      debugPrint(
        '[SyncCollab] Skipping self-target collab job ${job.id}: sender=$payloadSenderId receiver=$receiverId',
      );
      return true;
    }

    debugPrint(
        '[SyncCollab] Payload — sender=$payloadSenderId receiver=$receiverId postId=$postId status=$status');

    if (payloadSenderId == null || receiverId == null) {
      debugPrint('[SyncCollab] ⚠️ Missing sender or receiver — skipping job');
      return true;
    }

    final authUser = FirebaseAuth.instance.currentUser;
    final currentUid = authUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint(
        '[SyncCollab] ⚠️ No active Firebase auth for job ${job.id}; will retry later.',
      );
      return false;
    }

    // Use active Firebase uid for remote writes so security rules
    // (sender_id == uid()) are always satisfied.
    final senderId = currentUid;
    if (payloadSenderId != currentUid) {
      debugPrint(
        '[SyncCollab] sender_id mismatch on job ${job.id}: '
        'payload=$payloadSenderId auth=$currentUid; normalizing to auth uid.',
      );
    }
    if (senderId == receiverId) {
      debugPrint(
        '[SyncCollab] Skipping self-target collab job ${job.id}: sender=$senderId receiver=$receiverId',
      );
      return true;
    }

    debugPrint(
      '[SyncCollab] Auth session uid=$currentUid email=${authUser?.email} '
      'for sender=$senderId',
    );

    debugPrint(
        '[SyncCollab] Writing to Firestore collab_requests/${job.entityId}');
    await FirebaseFirestore.instance
        .collection('collab_requests')
        .doc(job.entityId)
        .set({
      'id': job.entityId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'post_id': postId,
      'message': message,
      'status': status,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
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
    final senderName = payload['sender_name'] as String? ?? 'Someone';
    final postTitle = payload['post_title'] as String? ?? 'a project';
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
      extra: {
        if (postId != null && postId.isNotEmpty) 'post_id': postId,
      },
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
    Map<String, Object?> extra = const {},
  }) async {
    final normalizedReceiver = receiverId.trim();
    final normalizedSender = senderId.trim();
    if (normalizedReceiver.isEmpty || normalizedSender.isEmpty) {
      debugPrint(
        '[SyncNotification] Skipping notification $notificationId due to missing sender/receiver.',
      );
      return;
    }
    if (normalizedReceiver == normalizedSender) {
      debugPrint(
        '[SyncNotification] Skipping self-notification '
        'source=$source notification=$notificationId user=$normalizedSender',
      );
      return;
    }

    final senderLabel = _uplinkUserLabel(name: senderName, id: senderId);
    final receiverLabel = receiverId.trim().isNotEmpty ? receiverId : 'unknown';
    _notificationDebugBlock(
      activity: source,
      user: senderLabel,
      receiver: receiverLabel,
      notificationId: notificationId,
      status: 'sending',
    );

    debugPrint(
      '[SyncNotification] Fan-out requested source=$source type=$type '
      'receiver=$receiverId sender=$senderId notification=$notificationId entity=$entityId',
    );
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
        extra: extra,
      );
      _notificationDebugBlock(
        activity: source,
        user: senderLabel,
        receiver: receiverLabel,
        notificationId: notificationId,
        status: 'sent',
      );
    } on FirebaseException catch (error) {
      _notificationDebugBlock(
        activity: source,
        user: senderLabel,
        receiver: receiverLabel,
        notificationId: notificationId,
        status: 'not sent',
        error:
            'FirebaseException(code=${error.code}, message=${error.message ?? ''})',
      );
      debugPrint(
        '[SyncNotification] Skipping fan-out for source=$source notification=$notificationId '
        'receiver=$receiverId because Firestore rejected it: ${error.code}',
      );
      // Keep permission issues non-retry so the queue can continue, but
      // retry transient Firebase failures (unavailable, deadline-exceeded,
      // aborted, etc.) by bubbling the exception to processPendingSync().
      if (error.code != 'permission-denied') {
        rethrow;
      }
    } catch (error, stackTrace) {
      _notificationDebugBlock(
        activity: source,
        user: senderLabel,
        receiver: receiverLabel,
        notificationId: notificationId,
        status: 'not sent',
        error: error.toString(),
      );
      debugPrint(
        '[SyncNotification] Skipping fan-out for source=$source notification=$notificationId '
        'receiver=$receiverId due to unexpected error: $error',
      );
      debugPrint('[SyncNotification] Fan-out stacktrace: $stackTrace');
      // Non-Firebase exceptions are treated as transient so the parent sync
      // job retries instead of silently dropping the notification write.
      rethrow;
    }
  }

  Future<bool> _currentUserCanReviewPendingPosts() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return false;
    }

    final currentUid = authUser.uid;
    if (currentUid.isEmpty) {
      return false;
    }

    // 1) Fast path: token claims (if present).
    try {
      final claims = await authUser.getIdTokenResult();
      final roleClaim = claims.claims?['role']?.toString().trim().toLowerCase();
      if (roleClaim == 'admin' || roleClaim == 'super_admin') {
        return true;
      }
      final isAdminClaim = claims.claims?['isAdmin'];
      if (isAdminClaim == true) {
        return true;
      }
    } catch (_) {
      // Fall through to profile checks.
    }

    // 2) Firestore profile role.
    try {
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .get(const GetOptions(source: Source.serverAndCache));
      final role =
          (profileDoc.data()?['role'] as String?)?.trim().toLowerCase();
      if (role == 'admin' || role == 'super_admin') {
        return true;
      }
    } catch (_) {
      // Fall through to local profile role.
    }

    // 3) Local user cache fallback.
    try {
      final localUser = await _userDao.getUserById(currentUid);
      final localRole = localUser?.role.name.trim().toLowerCase();
      if (localRole == 'admin' || localRole == 'super_admin') {
        return true;
      }
    } catch (_) {
      // Ignore and default to false.
    }

    return false;
  }

  Future<List<String>> _getAdminUserIds() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['admin', 'super_admin']).get(
              const GetOptions(source: Source.serverAndCache));
      return snapshot.docs.map((doc) => doc.id).toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _fanoutModerationNotifications({
    required PostModel post,
    required String operation,
    ModerationStatus? previousRemoteStatus,
  }) async {
    if (post.id.isEmpty) return;

    final nowPending = post.moderationStatus == ModerationStatus.pending;
    final nowReviewed = post.moderationStatus == ModerationStatus.approved ||
        post.moderationStatus == ModerationStatus.rejected;

    final becamePending = nowPending &&
        (operation == 'create' ||
            previousRemoteStatus != ModerationStatus.pending);
    final moderationChanged = nowReviewed &&
        previousRemoteStatus != null &&
        previousRemoteStatus != post.moderationStatus;

    if (becamePending) {
      final adminIds = await _getAdminUserIds();
      for (final adminId in adminIds) {
        if (adminId.isEmpty) continue;
        await _bestEffortUserNotification(
          source: 'moderation_pending',
          notificationId: 'post_pending_${post.id}_$adminId',
          receiverId: adminId,
          senderId: post.authorId.isNotEmpty ? post.authorId : 'system',
          senderName: post.authorName ?? 'A student',
          type: 'moderation',
          body: 'New post pending review: "${post.title}"',
          detail: 'Open moderation queue to review and approve or reject.',
          entityId: post.id,
        );
      }
    }

    if (moderationChanged && post.authorId.isNotEmpty) {
      final approved = post.moderationStatus == ModerationStatus.approved;
      final actorId = FirebaseAuth.instance.currentUser?.uid ?? 'system';
      final actorName =
          FirebaseAuth.instance.currentUser?.displayName ?? 'Admin';
      await _bestEffortUserNotification(
        source: 'moderation_result',
        notificationId: 'post_review_${post.id}_${post.moderationStatus.name}',
        receiverId: post.authorId,
        senderId: actorId,
        senderName: actorName,
        type: 'moderation',
        body: approved
            ? 'Your post "${post.title}" has been approved and is now live.'
            : 'Your post "${post.title}" was not approved.',
        detail: approved
            ? 'Your content is now visible to viewers.'
            : 'You can edit the post and resubmit for review.',
        entityId: post.id,
      );
    }
  }

  Future<List<UserModel>> _loadOpportunityCandidateStudents() async {
    final byId = <String, UserModel>{};

    try {
      final remote = await _firestore.getAllUsersFromRemote(limit: 500);
      for (final user in remote) {
        if (user.isStudent && user.isActive) {
          byId[user.id] = user;
        }
      }
    } catch (error) {
      debugPrint('[SyncOpportunity] remote candidate load failed: $error');
    }

    try {
      final local = await _userDao.getAllUsers(
        role: UserRole.student.name,
        includeSuspended: false,
        pageSize: 500,
      );
      for (final user in local.where((user) => user.isActive)) {
        final existing = byId[user.id];
        if (existing == null || existing.profile == null) {
          byId[user.id] = user;
        }
      }
    } catch (error) {
      debugPrint('[SyncOpportunity] local candidate load failed: $error');
    }

    return byId.values.toList(growable: false);
  }

  bool _shouldNotifyOpportunityCandidate(RecommendedUser item) {
    final reasons = item.reasons.toSet();
    final hasSkill = reasons.contains('skill_match');
    final hasFaculty = reasons.contains('faculty_match');
    final hasProgram = reasons.contains('program_match');
    final matchScore = item.scoreBreakdown['match_score'] ?? 0.0;
    final opportunityFit = item.scoreBreakdown['opportunity_fit'] ?? 0.0;

    if (hasSkill && item.score >= 0.42) return true;
    if (hasProgram && item.score >= 0.48) return true;
    if (hasFaculty && matchScore >= 0.10 && item.score >= 0.36) return true;
    if (opportunityFit >= 0.35) return true;
    return item.score >= 0.58 && (hasSkill || hasFaculty || hasProgram);
  }

  String _opportunityMatchDetail(RecommendedUser item) {
    final skills = item.matchedSkills
        .map((skill) => skill.trim())
        .where((skill) => skill.isNotEmpty)
        .take(4)
        .toList(growable: false);
    if (skills.isNotEmpty) {
      return 'Matched skills: ${skills.join(', ')}. '
          'Confidence ${(item.score * 100).round()}%.';
    }
    if (item.reasons.contains('program_match')) {
      return 'Your program aligns with this opportunity. '
          'Confidence ${(item.score * 100).round()}%.';
    }
    if (item.reasons.contains('faculty_match')) {
      return 'Your faculty aligns with this opportunity. '
          'Confidence ${(item.score * 100).round()}%.';
    }
    return 'This opportunity looks relevant to your profile. '
        'Confidence ${(item.score * 100).round()}%.';
  }

  Future<void> _fanoutOpportunityMatchNotifications({
    required PostModel post,
    required String operation,
    ModerationStatus? previousRemoteStatus,
  }) async {
    if (post.type.trim().toLowerCase() != 'opportunity') return;
    if (post.id.isEmpty || post.isArchived) return;
    if (post.moderationStatus != ModerationStatus.approved) return;
    if (post.opportunityDeadline != null &&
        post.opportunityDeadline!.isBefore(DateTime.now())) {
      return;
    }

    final becameAvailable = operation == 'create' ||
        (previousRemoteStatus != null &&
            previousRemoteStatus != ModerationStatus.approved);
    if (!becameAvailable) return;

    final candidates = (await _loadOpportunityCandidateStudents())
        .where((user) => user.id != post.authorId)
        .toList(growable: false);
    if (candidates.isEmpty) return;

    final ranked = RecommenderService()
        .rankStudentsForOpportunity(
          opportunity: post,
          candidates: candidates,
        )
        .where(_shouldNotifyOpportunityCandidate)
        .take(20)
        .toList(growable: false);
    if (ranked.isEmpty) return;

    final senderId = post.authorId.trim().isNotEmpty
        ? post.authorId.trim()
        : (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (senderId.isEmpty) return;

    for (final item in ranked) {
      final user = item.user;
      await _bestEffortUserNotification(
        source: 'opportunity_match',
        notificationId: 'opportunity_match_${post.id}_${user.id}',
        receiverId: user.id,
        senderId: senderId,
        senderName: post.authorName ?? 'MUST StarTrack',
        type: 'opportunity',
        body: 'Opportunity match: "${post.title}" fits your profile.',
        detail: _opportunityMatchDetail(item),
        entityId: post.id,
        extra: {
          'post_id': post.id,
          'match_score': item.score,
          'confidence_percent': (item.score * 100).round(),
          'matched_skills': item.matchedSkills,
          'reasons': item.reasons,
        },
      );
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
      await _cacheUsersAndGetExistingIds(
        userIds,
        logContext: 'follow_dependencies',
      );
    }

    final existingUserIds = await _getExistingLocalUserIds(userIds);

    var upserted = 0;
    var deferred = 0;
    for (final doc in docs) {
      final data = doc.data();
      final followerId = data['follower_id'] as String?;
      final followingId = data['following_id'] as String?;
      if (followerId == null || followingId == null) {
        continue;
      }
      if (!existingUserIds.contains(followerId) ||
          !existingUserIds.contains(followingId)) {
        deferred++;
        debugPrint(
          '[SyncService] deferring follow=${doc.id} because follower=$followerId or followee=$followingId is missing locally',
        );
        continue;
      }
      final createdAt = data['created_at'];
      try {
        await db.insert(
          DatabaseSchema.tableFollows,
          {
            'id': doc.id,
            'follower_id': followerId,
            'followee_id': followingId,
            'created_at': createdAt is Timestamp
                ? createdAt.toDate().toIso8601String()
                : DateTime.now().toIso8601String(),
            'sync_status': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        upserted++;
      } catch (error, stackTrace) {
        deferred++;
        debugPrint('[SyncService] failed inserting follow=${doc.id}: $error');
        debugPrint('$stackTrace');
      }
    }
    debugPrint(
        '[SyncService] Hydrated follow rows for user=$currentUid upserted=$upserted deferred=$deferred');
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
      final localMessageRows = await db.query(
        DatabaseSchema.tableMessages,
        columns: ['id', 'is_read'],
        where: 'conversation_id = ?',
        whereArgs: [doc.id],
      );
      final localReadByMessageId = <String, bool>{};
      for (final row in localMessageRows) {
        final messageId = row['id'] as String? ?? '';
        if (messageId.isEmpty) continue;
        localReadByMessageId[messageId] = (row['is_read'] as int? ?? 0) == 1;
      }

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

      // Merge any duplicate local conversations for the same peer that were
      // created before the first sync (e.g. from a push-notification tap).
      // Their messages need to be remapped to the canonical Firestore ID so
      // that localReadByMessageId correctly preserves read state on subsequent
      // syncs.
      final duplicates = await db.query(
        DatabaseSchema.tableConversations,
        columns: ['id'],
        where: 'user_id = ? AND peer_id = ? AND id != ?',
        whereArgs: [currentUid, counterpartId, doc.id],
      );
      for (final dup in duplicates) {
        final oldId = dup['id'] as String;
        // Remap messages stored under the old local ID.
        await db.rawUpdate('''
          UPDATE ${DatabaseSchema.tableMessages}
          SET conversation_id = ?, thread_id = ?
          WHERE conversation_id = ?
        ''', [doc.id, doc.id, oldId]);
        // Remove the orphaned conversation row.
        await db.delete(
          DatabaseSchema.tableConversations,
          where: 'id = ?',
          whereArgs: [oldId],
        );
        await db.delete(
          DatabaseSchema.tableMessageThreads,
          where: 'id = ?',
          whereArgs: [oldId],
        );
      }

      // Rebuild localReadByMessageId now that any remapped messages are
      // under doc.id (re-query to pick up the migrated rows).
      if (duplicates.isNotEmpty) {
        final refreshed = await db.query(
          DatabaseSchema.tableMessages,
          columns: ['id', 'is_read'],
          where: 'conversation_id = ?',
          whereArgs: [doc.id],
        );
        localReadByMessageId.clear();
        for (final row in refreshed) {
          final messageId = row['id'] as String? ?? '';
          if (messageId.isEmpty) continue;
          localReadByMessageId[messageId] = (row['is_read'] as int? ?? 0) == 1;
        }
      }

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
      var hasReadSyncDrift = false;
      for (final msgDoc in msgSnap.docs) {
        final msg = msgDoc.data();
        final createdAt = msg['created_at'];
        final remoteIsRead = msg['is_read'] as bool? ?? false;
        final localIsRead = localReadByMessageId[msgDoc.id] ?? false;
        final effectiveIsRead = remoteIsRead || localIsRead;
        final senderId = msg['sender_id'] as String? ?? '';
        if (senderId != currentUid && !effectiveIsRead) {
          unreadCount++;
        }
        if (senderId != currentUid && localIsRead && !remoteIsRead) {
          hasReadSyncDrift = true;
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
            'status': effectiveIsRead ? 'read' : 'sent',
            'created_at': createdAt is Timestamp
                ? createdAt.millisecondsSinceEpoch
                : DateTime.now().millisecondsSinceEpoch,
            'sent_at': createdAt is Timestamp
                ? createdAt.toDate().toIso8601String()
                : DateTime.now().toIso8601String(),
            'is_read': effectiveIsRead ? 1 : 0,
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

      if (hasReadSyncDrift) {
        unawaited(markConversationReadRemote(
          conversationId: doc.id,
          userId: currentUid,
        ));
      }
    }

    debugPrint(
        '[SyncService] Hydrated $upsertedConversations conversation(s) and $upsertedMessages message(s) for user=$currentUid');
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
          debugPrint(
              '[SyncService] Inserted missing local user dependency user=$userId for like hydration');
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

      final post =
          PostModel.fromJson({'id': remotePost.id, ...remotePost.data()!});
      await ensureUserPresent(post.authorId);
      await _postDao.insertPost(post);
      debugPrint(
          '[SyncService] Inserted missing local post dependency post=$postId for like hydration');
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
      postIds.addAll(localRows
          .map((row) => row['id'] as String? ?? '')
          .where((id) => id.isNotEmpty));
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
          debugPrint(
              '[SyncService] Skipping like hydration for post=$postId because the post is unavailable remotely.');
          continue;
        }
        final createdAt = likeDoc.data()?['created_at'];
        await db.insert(
          DatabaseSchema.tableLikes,
          {
            'id': likeDoc.id,
            'post_id': postId,
            'user_id': currentUid,
            'created_at': createdAt is Timestamp
                ? createdAt.millisecondsSinceEpoch
                : DateTime.now().millisecondsSinceEpoch,
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

  Future<void> _refreshRemoteInteractionCounts({
    Iterable<String> candidatePostIds = const [],
  }) async {
    final db = await DatabaseHelper.instance.database;
    final postIds = <String>{...candidatePostIds.where((id) => id.isNotEmpty)};

    if (postIds.isEmpty) {
      final localRows = await db.query(
        DatabaseSchema.tablePosts,
        columns: ['id'],
        orderBy: 'created_at DESC',
        limit: 100,
      );
      postIds.addAll(localRows
          .map((row) => row['id'] as String? ?? '')
          .where((id) => id.isNotEmpty));
    }

    var refreshed = 0;
    var failed = 0;
    _syncTrace('INTERACTION_REFRESH_START', details: {
      'candidatePosts': postIds.length,
    });
    for (final postId in postIds) {
      try {
        _syncTrace('INTERACTION_STEP_FETCH_BEGIN', details: {'postId': postId});
        final localBefore = await _readLocalInteractionCounts(postId);
        final postRef =
            FirebaseFirestore.instance.collection('posts').doc(postId);
        final postDoc =
            await postRef.get(const GetOptions(source: Source.serverAndCache));
        final postData = postDoc.data() ?? const <String, dynamic>{};

        int parseCount(dynamic raw, int fallback) {
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw) ?? fallback;
          return fallback;
        }

        final localLikesRow = await db.rawQuery(
          'SELECT COUNT(*) AS cnt FROM ${DatabaseSchema.tableLikes} WHERE post_id = ?',
          [postId],
        );
        final localDislikesRow = await db.rawQuery(
          'SELECT COUNT(*) AS cnt FROM ${DatabaseSchema.tableDislikes} WHERE post_id = ?',
          [postId],
        );
        final localCommentsRow = await db.rawQuery(
          'SELECT COUNT(*) AS cnt FROM ${DatabaseSchema.tableComments} WHERE post_id = ? AND COALESCE(is_deleted, 0) = 0',
          [postId],
        );

        final localLikeCount = localLikesRow.first['cnt'] as int? ?? 0;
        final localDislikeCount = localDislikesRow.first['cnt'] as int? ?? 0;
        final localCommentCount = localCommentsRow.first['cnt'] as int? ?? 0;

        int remoteLikeCount;
        try {
          final likesCountSnap =
              await postRef.collection('likes').count().get();
          remoteLikeCount = likesCountSnap.count ??
              parseCount(postData['like_count'], localLikeCount);
        } catch (_) {
          remoteLikeCount = parseCount(postData['like_count'], localLikeCount);
        }

        int remoteDislikeCount;
        try {
          final dislikesCountSnap =
              await postRef.collection('dislikes').count().get();
          remoteDislikeCount = dislikesCountSnap.count ??
              parseCount(postData['dislike_count'], localDislikeCount);
        } catch (_) {
          remoteDislikeCount =
              parseCount(postData['dislike_count'], localDislikeCount);
        }

        int remoteCommentCount;
        try {
          final commentsCountSnap = await FirebaseFirestore.instance
              .collection('comments')
              .where('post_id', isEqualTo: postId)
              .count()
              .get();
          remoteCommentCount = commentsCountSnap.count ??
              parseCount(postData['comment_count'], localCommentCount);
        } catch (_) {
          remoteCommentCount =
              parseCount(postData['comment_count'], localCommentCount);
        }

        final remoteViewCount = parseCount(
          postData['view_count'],
          localBefore['view_count']!,
        );

        _syncTrace('INTERACTION_STEP_REMOTE_COUNTS', details: {
          'postId': postId,
          'remote_like_count': remoteLikeCount,
          'remote_dislike_count': remoteDislikeCount,
          'remote_comment_count': remoteCommentCount,
          'remote_view_count': remoteViewCount,
          'local_like_count': localLikeCount,
          'local_dislike_count': localDislikeCount,
          'local_comment_count': localCommentCount,
          'local_before_like_count': localBefore['like_count'],
          'local_before_dislike_count': localBefore['dislike_count'],
          'local_before_comment_count': localBefore['comment_count'],
          'local_before_view_count': localBefore['view_count'],
        });

        await db.update(
          DatabaseSchema.tablePosts,
          {
            'like_count': remoteLikeCount,
            'dislike_count': remoteDislikeCount,
            'comment_count': remoteCommentCount,
            'view_count': remoteViewCount,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [postId],
        );
        final localAfter = await _readLocalInteractionCounts(postId);
        debugPrint(
          '[SyncService][CountDiag] post=$postId '
          'remote(l=$remoteLikeCount,d=$remoteDislikeCount,c=$remoteCommentCount,v=$remoteViewCount) '
          'local_before(l=${localBefore['like_count']},d=${localBefore['dislike_count']},c=${localBefore['comment_count']},v=${localBefore['view_count']}) '
          'local_after(l=${localAfter['like_count']},d=${localAfter['dislike_count']},c=${localAfter['comment_count']},v=${localAfter['view_count']})',
        );
        _syncTrace('INTERACTION_STEP_LOCAL_UPDATED', details: {
          'postId': postId,
          'local_after_like_count': localAfter['like_count'],
          'local_after_dislike_count': localAfter['dislike_count'],
          'local_after_comment_count': localAfter['comment_count'],
          'local_after_view_count': localAfter['view_count'],
        });
        refreshed++;
      } catch (error) {
        failed++;
        debugPrint(
          '[SyncService] Failed refreshing interaction counts for post=$postId: $error',
        );
        _syncTrace('INTERACTION_STEP_FAILED', details: {
          'postId': postId,
          'error': error.toString(),
        });
      }
    }

    debugPrint(
      '[SyncService] Refreshed interaction counts checked=${postIds.length} '
      'updated=$refreshed failed=$failed',
    );
    _syncTrace('INTERACTION_REFRESH_DONE', details: {
      'checked': postIds.length,
      'updated': refreshed,
      'failed': failed,
    });
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

      final post =
          PostModel.fromJson({'id': remotePost.id, ...remotePost.data()!});
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
      postIds.addAll(localRows
          .map((row) => row['id'] as String? ?? '')
          .where((id) => id.isNotEmpty));
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
            'created_at': createdAt is Timestamp
                ? createdAt.millisecondsSinceEpoch
                : DateTime.now().millisecondsSinceEpoch,
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

  Future<void> _syncRemoteCommentsForPosts({
    Iterable<String> candidatePostIds = const [],
    int perPostLimit = 80,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final postIds = <String>{...candidatePostIds.where((id) => id.isNotEmpty)};

    if (postIds.isEmpty) {
      final localRows = await db.query(
        DatabaseSchema.tablePosts,
        columns: ['id'],
        orderBy: 'created_at DESC',
        limit: 50,
      );
      postIds.addAll(localRows
          .map((row) => row['id'] as String? ?? '')
          .where((id) => id.isNotEmpty));
    }

    var syncedPosts = 0;
    var syncedComments = 0;
    for (final postId in postIds) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('comments')
            .where('post_id', isEqualTo: postId)
            .limit(perPostLimit)
            .get(const GetOptions(source: Source.serverAndCache));

        final docs = [...snap.docs]..sort((a, b) {
            final aTs = a.data()['created_at'];
            final bTs = b.data()['created_at'];
            final aMs = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
            final bMs = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
            return bMs.compareTo(aMs);
          });

        final remoteIds = <String>{};
        for (final doc in docs) {
          remoteIds.add(doc.id);
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
          syncedComments++;
        }

        if (remoteIds.isNotEmpty) {
          final placeholders = List.filled(remoteIds.length, '?').join(',');
          await db.rawDelete(
            '''
            DELETE FROM ${DatabaseSchema.tableComments}
            WHERE post_id = ?
              AND COALESCE(sync_status, 1) = 1
              AND id NOT IN ($placeholders)
            ''',
            [postId, ...remoteIds],
          );
        }

        syncedPosts++;
      } catch (error) {
        debugPrint(
          '[SyncService] Failed syncing comments for post=$postId: $error',
        );
      }
    }

    debugPrint(
      '[SyncService] Hydrated comments for posts=${postIds.length} '
      'syncedPosts=$syncedPosts syncedComments=$syncedComments',
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
        where:
            'user_id = ? AND action = ? AND entity_type = ? AND entity_id = ?',
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
        'created_at': createdAt is Timestamp
            ? createdAt.toDate().toIso8601String()
            : DateTime.now().toIso8601String(),
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

      // Best effort for any IDs omitted by batched fetch (missing docs, limits,
      // or eventual consistency): try fetching individually.
      for (final userId in userIds) {
        final local = await _userDao.getUserById(userId);
        if (local != null) continue;
        final remote = await _firestore.getUser(userId);
        if (remote != null) {
          await _userDao.insertUser(remote);
        }
      }
    }

    var upserted = 0;
    var deferred = 0;
    for (final doc in docsById.values) {
      final data = doc.data();
      final senderId = data['sender_id'] as String?;
      final receiverId = data['receiver_id'] as String?;
      if (senderId == null || receiverId == null) {
        continue;
      }
      if (senderId == receiverId) {
        debugPrint(
          '[SyncService] Skipping self collab_request ${doc.id}: sender=$senderId receiver=$receiverId',
        );
        continue;
      }

      final sender = await _userDao.getUserById(senderId);
      final receiver = await _userDao.getUserById(receiverId);
      if (sender == null || receiver == null) {
        deferred++;
        debugPrint(
          '[SyncService] Deferring collab_request ${doc.id}: '
          'missing local sender/receiver (sender=$senderId receiver=$receiverId)',
        );
        continue;
      }

      final createdAt = data['created_at'];
      final updatedAt = data['updated_at'];
      final respondedAt = data['responded_at'];
      try {
        // Preserve receiver_viewed_at that was set locally (e.g. when the
        // user opened the inbox). ConflictAlgorithm.replace would otherwise
        // wipe it on every sync, making the badge re-appear after every
        // app restart.
        final existingRow = await db.query(
          DatabaseSchema.tableCollabRequests,
          columns: ['receiver_viewed_at'],
          where: 'id = ?',
          whereArgs: [doc.id],
          limit: 1,
        );
        final preservedViewedAt = existingRow.isNotEmpty
            ? existingRow.first['receiver_viewed_at'] as String?
            : null;

        await db.insert(
          DatabaseSchema.tableCollabRequests,
          {
            'id': doc.id,
            'sender_id': senderId,
            'receiver_id': receiverId,
            'post_id': data['post_id'] as String?,
            'message': data['message'] as String?,
            'status': data['status'] as String? ?? 'pending',
            'responded_at': respondedAt is Timestamp
                ? respondedAt.toDate().toIso8601String()
                : respondedAt as String?,
            'created_at': createdAt is Timestamp
                ? createdAt.toDate().toIso8601String()
                : DateTime.now().toIso8601String(),
            'updated_at': updatedAt is Timestamp
                ? updatedAt.toDate().toIso8601String()
                : DateTime.now().toIso8601String(),
            'receiver_viewed_at': preservedViewedAt,
            'sync_status': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        upserted++;
      } on DatabaseException catch (e) {
        deferred++;
        debugPrint(
          '[SyncService] Deferring collab_request ${doc.id} due to SQLite constraint: $e',
        );
      }
    }
    debugPrint(
      '[SyncService] Hydrated collab_requests for user=$currentUid '
      'upserted=$upserted deferred=$deferred',
    );
  }

  Future<void> _syncRemoteOpportunityJoins(String currentUid) async {
    final db = await DatabaseHelper.instance.database;
    final snapshot = await FirebaseFirestore.instance
        .collection('post_joins')
        .where('user_id', isEqualTo: currentUid)
        .get(const GetOptions(source: Source.serverAndCache));

    final remoteByPostId =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
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

      final post =
          PostModel.fromJson({'id': remotePost.id, ...remotePost.data()!});
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
          'created_at': createdAt is Timestamp
              ? createdAt.toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
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

    debugPrint(
        '[SyncService] Hydrated $upserted post join row(s) for user=$currentUid and removed $removed stale row(s)');
  }

  Future<void> syncCommentsForPost(String postId) async {
    _syncTrace('COMMENTS_SYNC_START', details: {'postId': postId});
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint(
          '[SyncService] Skipping comment sync: no active FirebaseAuth session');
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

      final docs = [...snap.docs]..sort((a, b) {
          final aTs = a.data()['created_at'];
          final bTs = b.data()['created_at'];
          final aMs = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
          final bMs = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
          return bMs.compareTo(aMs);
        });

      final remoteIds = <String>{};
      debugPrint(
        '[SyncService][CommentDiag] post=$postId remote_comments=${docs.length} fromCache=${snap.metadata.isFromCache}',
      );
      _syncTrace('COMMENTS_REMOTE_FETCHED', details: {
        'postId': postId,
        'remote_comments': docs.length,
        'fromCache': snap.metadata.isFromCache,
      });

      for (final doc in docs) {
        remoteIds.add(doc.id);
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

      final db = await DatabaseHelper.instance.database;
      if (remoteIds.isNotEmpty) {
        final placeholders = List.filled(remoteIds.length, '?').join(',');
        await db.rawDelete(
          '''
          DELETE FROM ${DatabaseSchema.tableComments}
          WHERE post_id = ?
            AND COALESCE(sync_status, 1) = 1
            AND id NOT IN ($placeholders)
          ''',
          [postId, ...remoteIds],
        );
      }

      final localCountRow = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM ${DatabaseSchema.tableComments} WHERE post_id = ? AND COALESCE(is_deleted, 0) = 0',
        [postId],
      );
      final localCommentsCount = localCountRow.first['cnt'] as int? ?? 0;
      debugPrint(
        '[SyncService][CommentDiag] post=$postId local_comments_after_sync=$localCommentsCount',
      );
      _syncTrace('COMMENTS_LOCAL_UPDATED', details: {
        'postId': postId,
        'local_comments_after_sync': localCommentsCount,
      });

      await _refreshRemoteInteractionCounts(candidatePostIds: [postId]);
      _syncTrace('COMMENTS_SYNC_DONE', details: {'postId': postId});
    } catch (error) {
      debugPrint('[SyncService] Comment remote-to-local sync failed: $error');
      _syncTrace('COMMENTS_SYNC_FAILED', details: {
        'postId': postId,
        'error': error.toString(),
      });
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
    Map<String, Object?> extra = const {},
  }) async {
    if (receiverId.trim().isEmpty ||
        senderId.trim().isEmpty ||
        receiverId.trim() == senderId.trim()) {
      debugPrint(
        '[SyncNotification] Upsert skipped for self/invalid notification '
        'notification=$notificationId receiver=$receiverId sender=$senderId',
      );
      return;
    }

    final docRef = FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId);
    final senderPhotoUrl =
        (await _userDao.getUserById(senderId.trim()))?.photoUrl;
    debugPrint(
      '[SyncNotification] Upsert start notification=$notificationId '
      'receiver=$receiverId sender=$senderId type=$type',
    );

    // IMPORTANT: sender may not have read permission on receiver notifications,
    // so never pre-read the document here. Use a direct merge write instead.
    // Security rules validate sender ownership on create/update paths.
    final upsertData = <String, Object?>{
      'id': notificationId,
      'user_id': receiverId,
      'type': type,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl,
      'body': body,
      'detail': detail,
      'entity_id': entityId,
      if (extra.isNotEmpty) 'extra': extra,
      'is_read': false,
      'created_at': FieldValue.serverTimestamp(),
    };
    await docRef.set(upsertData, SetOptions(merge: true));
    debugPrint(
      '[SyncNotification] Upserted notification=$notificationId '
      'for receiver=$receiverId type=$type payloadKeys=${upsertData.keys.toList()}',
    );
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
          channelDescription:
              'Alerts for follows, comments, views, likes, and collaborations.',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode({'type': type, 'entity_id': row['entity_id']}),
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
      case 'rating':
        return 'New rating';
      case 'message':
        return 'New message';
      case 'opportunity':
        return 'Opportunity match';
      case 'collaboration':
        return 'Collaboration request';
      case 'moderation':
        return 'MUST StarTrack — Moderation';
      default:
        return 'MUST StarTrack';
    }
  }

  Future<bool> _hasValidMustSession({required String context}) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      debugPrint(
          '[SyncService] Skipping $context: no active FirebaseAuth session');
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
      if (role.isEmpty) {
        debugPrint(
          '[SyncService] Delaying $context: users/${authUser.uid} has no role.',
        );
        return false;
      }

      final allowed = _emailMatchesRole(role: role, email: email);
      if (!allowed) {
        debugPrint(
          '[SyncService] Delaying $context: email=$email does not match role=$role.',
        );
      }
      return allowed;
    } catch (error) {
      debugPrint(
          '[SyncService] Unable to validate MUST session for $context: $error');
      return false;
    }
  }

  bool _emailMatchesRole({required String role, required String email}) {
    final normalized = email.toLowerCase();
    if (role == 'student') {
      return normalized.endsWith('@std.must.ac.ug');
    }
    if (role == 'staff' || role == 'lecturer') {
      return normalized.endsWith('@staff.must.ac.ug');
    }
    if (role == 'admin' || role == 'super_admin') {
      return normalized.endsWith('@must.ac.ug');
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

  Future<void> _logSyncSnapshot({required String label}) async {
    try {
      final db = await DatabaseHelper.instance.database;
      Future<int> countRows(String table) async {
        final rows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM $table');
        final value = rows.isNotEmpty ? rows.first['cnt'] : 0;
        return value is int ? value : int.tryParse('$value') ?? 0;
      }

      final users = await countRows('users');
      final posts = await countRows('posts');
      final comments = await countRows('comments');
      final notifications = await countRows('notifications');
      final pending = await _queueDao.getPendingCount();
      final deadLetters = await _queueDao.getDeadLetterCount();

      debugPrint(
        '[SyncService][$label] local users=$users posts=$posts '
        'comments=$comments notifications=$notifications '
        'queuePending=$pending queueDeadLetters=$deadLetters',
      );
    } catch (error) {
      debugPrint('[SyncService][$label] snapshot failed: $error');
    }
  }

  // ── Faculty sync ──────────────────────────────────────────────────────────

  Future<bool> _syncFaculty(SyncJob job) async {
    switch (job.operation) {
      case 'create':
      case 'update':
        final faculty = await _facultyDao.getFacultyById(job.entityId);
        if (faculty == null) return true; // deleted locally
        await _firestore.setFaculty(faculty);
        return true;
      case 'delete':
        await _firestore.deleteFaculty(job.entityId);
        return true;
      default:
        return true;
    }
  }

  // ── Course sync ───────────────────────────────────────────────────────────

  Future<bool> _syncCourse(SyncJob job) async {
    switch (job.operation) {
      case 'create':
      case 'update':
        final course = await _courseDao.getCourseById(job.entityId);
        if (course == null) return true; // deleted locally
        await _firestore.setCourse(course);
        return true;
      case 'delete':
        await _firestore.deleteCourse(job.entityId);
        return true;
      default:
        return true;
    }
  }

  Future<bool> _syncRecommendationLog(SyncJob job) async {
    if (job.operation == 'delete') {
      // Log deletion sync is not required in current analytics model.
      return true;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      debugPrint(
        '[SyncRecLog] No active auth session for job ${job.id}; will retry.',
      );
      return false;
    }

    final payload = job.payloadJson;
    final payloadUserId = (payload['user_id'] as String?)?.trim();
    if (payloadUserId != null &&
        payloadUserId.isNotEmpty &&
        payloadUserId != currentUid) {
      debugPrint(
        '[SyncService] ⚠️ Skipping recommendation log job ${job.id}: '
        'payload user=$payloadUserId but current uid=$currentUid '
        '— removing from queue.',
      );
      return true;
    }

    final id = (payload['id']?.toString().trim().isNotEmpty ?? false)
        ? payload['id'].toString().trim()
        : job.entityId;
    if (id.isEmpty) return true;

    final normalizedPayload = <String, dynamic>{
      ...payload,
      'user_id':
          (payloadUserId != null && payloadUserId.isNotEmpty)
              ? payloadUserId
              : currentUid,
    };

    await FirebaseFirestore.instance
        .collection('recommendation_logs')
        .doc(id)
        .set({
      ...normalizedPayload,
      'server_ts': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return true;
  }
}
