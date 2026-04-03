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
import '../local/dao/faculty_dao.dart';
import '../local/dao/course_dao.dart';
import '../local/dao/group_dao.dart';
import '../local/dao/group_member_dao.dart';
import '../local/services/notification_preferences_service.dart';
import '../local/database_helper.dart';
import '../local/schema/database_schema.dart';
import 'cloudinary_service.dart';
import 'firestore_service.dart';
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
  final Connectivity _connectivity;
  final CloudinaryService _cloudinary;
  final FlutterLocalNotificationsPlugin _localNotif;
  final NotificationPreferencesService _preferences;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;
  bool _isHydrating = false;
  Future<void>? _hydrationFuture;

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

  void stopListening() => _connectivitySub?.cancel();

  // ── Process sync queue ────────────────────────────────────────────────────

  /// Main sync loop — drains ready jobs from the queue.
  Future<SyncResult> processPendingSync() async {
    if (_isSyncing) {
      return const SyncResult(processed: 0, failed: 0, remaining: 0);
    }

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
        debugPrint(
            '[SyncService] Unable to refresh auth token before sync: $error');
      }

      final jobs = await _queueDao.getReadyJobs(limit: 50);
      debugPrint(
          '[SyncService] Starting sync loop with ${jobs.length} ready job(s).');

      for (final job in jobs) {
        debugPrint(
          '[SyncService] Processing job id=${job.id} entity=${job.entityType} '
          'operation=${job.operation} entityId=${job.entityId} retry=${job.retryCount}',
        );
        final success = await _processJob(job);
        if (success) {
          await _queueDao.deleteJob(job.id);
          debugPrint(
              '[SyncService] Job id=${job.id} entity=${job.entityType} completed and removed from queue.');
          processed++;
        } else {
          await _queueDao.incrementAttempt(job.id);
          debugPrint(
              '[SyncService] Job id=${job.id} entity=${job.entityType} failed and will retry.');
          failed++;
        }
      }

      final remaining = await _queueDao.getPendingCount();
      final deadLetters = await _queueDao.getDeadLetterCount();
      debugPrint(
        '[SyncService] Queue summary processed=$processed failed=$failed '
        'remaining=$remaining deadLetters=$deadLetters',
      );
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
    );
    return _hydrationFuture!;
  }

  Future<void> _runHydration({
    int postLimit = 50,
    bool forceIncludePendingForAdmin = false,
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
        debugPrint('[SyncService] skipping groups hydration (no authenticated user)');
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
            await db.insert('notifications', row,
                conflictAlgorithm: ConflictAlgorithm.replace);
            if (!alreadyDelivered && !notifSnap.metadata.isFromCache) {
              if (!effectiveIsRead) {
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
    debugPrint('[SyncService][UserSync] ── _syncAllUsers starting ──────────────');

    // ── Remote count ──────────────────────────────────────────────────────
    final users = await _firestore.getAllUsersFromRemote(limit: 500);
    debugPrint(
        '[SyncService][UserSync] remote Firestore user count = ${users.length}');
    for (final user in users) {
      debugPrint(
          '[SyncService][UserSync]   remote uid=${user.id} '
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
        debugPrint(
            '[SyncService][UserSync] ⚠ failed upserting uid=${user.id} '
            'email=${user.email} role=${user.role.name}: $error');
      }
    }

    // ── Local count after upsert ──────────────────────────────────────────
    final localAfter = await _userDao.getUserCount();
    debugPrint(
        '[SyncService][UserSync] local SQLite count AFTER upsert  = $localAfter');
    debugPrint(
        '[SyncService][UserSync] summary  remote=${users.length} '
        'upserted=$upserted failed=$failed '
        'localBefore=$localBefore localAfter=$localAfter '
        'delta=${localAfter - localBefore}');
    if (localAfter < users.length) {
      debugPrint(
          '[SyncService][UserSync] ⚠ CONSISTENCY GAP: '
          'remote=${users.length} but local=$localAfter '
          '— ${users.length - localAfter} user(s) missing locally. '
          'Check failed upserts above for FK/constraint errors.');
    } else {
      debugPrint('[SyncService][UserSync] ✓ local count matches remote.');
    }
    debugPrint('[SyncService][UserSync] ── _syncAllUsers done ───────────────────');
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
      displayName: (displayName ?? '').trim().isEmpty ? null : displayName?.trim(),
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
      debugPrint(
          '[SyncService] inserted placeholder user=${user.id} '
          'email=${user.email} role=${user.role.name} context=$logContext');
    } catch (error, stackTrace) {
      debugPrint(
          '[SyncService] failed inserting placeholder user=${user.id} '
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
          debugPrint('[SyncService] failed inserting dependency user=${user.id}: $error');
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
        final placeholder = placeholderUsers?[userId] ??
            _buildPlaceholderUser(userId: userId);
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
        await _groupMemberDao.upsertMember(member);
        upsertedMembers++;
      } catch (error, stackTrace) {
        deferredMembers++;
        debugPrint('[SyncService] failed inserting group_member=${member.id}: $error');
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

  // ── Process a single job ──────────────────────────────────────────────────

  Future<bool> _processJob(SyncJob job) async {
    try {
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

  Future<bool> _syncPost(SyncJob job) async {
    switch (job.operation) {
      case 'create':
      case 'update':
        final previousRemote = await _firestore.getPostById(job.entityId);
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
                : GroupModel.fromJson({'id': job.entityId, ...job.payloadJson}));
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

    final msg = MessageModel(
      id: job.entityId,
      conversationId: payload['conversation_id'] as String,
      senderId: payload['sender_id'] as String,
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
    debugPrint(
        '[SyncMessage] ✅ Message ${msg.id} written to Firestore successfully');
    return true;
  }

  Future<bool> _syncPostRating(SyncJob job) async {
    switch (job.operation) {
      case 'create':
      case 'update':
        await _firestore.setPostRating(
          ratingId: job.entityId,
          payload: job.payloadJson,
        );
        return true;
      case 'delete':
        await _firestore.deletePostRating(job.entityId);
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
    final followerId = payload['follower_id'] as String?;
    final followingId = payload['following_id'] as String?;

    if (followerId == null || followingId == null) {
      debugPrint(
          '[SyncFollow] Skipping malformed job id=${job.id} payload=$payload');
      return true;
    }

    // Guard: Firestore rule requires follower_id == uid(). If this job was
    // queued under a different account (e.g. during testing), skip it so it
    // doesn't block the queue or generate misleading PERMISSION_DENIED logs.
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != followerId) {
      debugPrint('[SyncService] ⚠️ Skipping follow job ${job.id}: '
          'follower=$followerId but current uid=$currentUid — removing from queue.');
      return true; // drop the job; it can never succeed for this session
    }

    if (job.operation == 'create') {
      debugPrint(
          '[SyncFollow] Writing follow follower=$followerId followee=$followingId');
      await _firestore.follow(followerId: followerId, followingId: followingId);
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

    final docRef =
        FirebaseFirestore.instance.collection('notifications').doc(notificationId);
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
    final userId = payload['user_id'] as String?;
    final postId = payload['post_id'] as String?;
    final isLiking = payload['is_liking'] as bool? ?? true;

    if (userId == null || postId == null) {
      debugPrint(
          '[SyncLike] Skipping malformed job id=${job.id} payload=$payload');
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

    debugPrint(
        '[SyncLike] Writing remote like post=$postId user=$userId isLiking=$isLiking');
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
      debugPrint(
          '[SyncView] Skipping malformed view job id=${job.id} payload=$payload');
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

    final docRef =
        FirebaseFirestore.instance.collection('post_views').doc(job.entityId);
    try {
      await docRef.update({
        'viewer_name': payload['viewer_name'] as String?,
        'author_id': payload['author_id'] as String?,
        'post_title': payload['post_title'] as String?,
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint(
        '[SyncView] Remote view updated viewId=${job.entityId} post=$postId viewer=$viewerId',
      );
    } on FirebaseException catch (error) {
      if (error.code != 'not-found') {
        rethrow;
      }

      await docRef.set({
        'id': job.entityId,
        'viewer_id': viewerId,
        'viewer_name': payload['viewer_name'] as String?,
        'author_id': payload['author_id'] as String?,
        'post_id': postId,
        'post_title': payload['post_title'] as String?,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint(
        '[SyncView] Remote view created viewId=${job.entityId} post=$postId viewer=$viewerId',
      );
    }

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

    final senderId = payload['sender_id'] as String?;
    final receiverId = payload['receiver_id'] as String?;
    final postId = payload['post_id'] as String?;
    final message = payload['message'] as String? ?? '';
    final status = payload['status'] as String? ?? 'pending';

    debugPrint(
        '[SyncCollab] Payload — sender=$senderId receiver=$receiverId postId=$postId status=$status');

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
      final role = (profileDoc.data()?['role'] as String?)?.trim().toLowerCase();
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
          .where('role', whereIn: ['admin', 'super_admin'])
          .get(const GetOptions(source: Source.serverAndCache));
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
        (operation == 'create' || previousRemoteStatus != ModerationStatus.pending);
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
      final actorName = FirebaseAuth.instance.currentUser?.displayName ?? 'Admin';
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
    final docRef = FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId);
    final updateData = <String, Object?>{
      'sender_name': senderName,
      'body': body,
      'detail': detail,
      'entity_id': entityId,
    };

    try {
      await docRef.update(updateData);
      debugPrint(
          '[SyncNotification] Updated existing notification=$notificationId for receiver=$receiverId');
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
    debugPrint(
        '[SyncNotification] Created notification=$notificationId for receiver=$receiverId type=$type');
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

    final payload = job.payloadJson;
    final id = (payload['id']?.toString().trim().isNotEmpty ?? false)
        ? payload['id'].toString().trim()
        : job.entityId;
    if (id.isEmpty) return true;

    await FirebaseFirestore.instance
        .collection('recommendation_logs')
        .doc(id)
        .set({
      ...payload,
      'server_ts': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return true;
  }
}
