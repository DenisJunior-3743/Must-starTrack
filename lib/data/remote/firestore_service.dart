// lib/data/remote/firestore_service.dart
//
// MUST StarTrack — Firestore Service (Phase 5)
//
// Central gateway for ALL Firestore operations.
// No other file imports cloud_firestore directly — only this service.
// This isolates the Firebase dependency behind a thin abstraction,
// making it trivial to swap out or mock in tests.
//
// Collections structure:
//   users/{uid}
//     profiles/{uid}          (sub-collection for extended profile)
//   posts/{postId}
//   conversations/{convoId}
//     messages/{messageId}   (sub-collection)
//   notifications/{notifId}
//   skills (public collection for trending skill aggregation)
//   follows/{followerId}_{followingId}
//   sync_audit/{docId}        (admin audit log)
//
// Panel defence:
//   "Firestore is our source of truth for multi-device sync.
//    SQLite is the local read cache. Every mutation writes to
//    SQLite first (optimistic), then to Firestore. If Firestore
//    is unreachable, the SyncQueueDao retries with exponential
//    backoff. This means the app works fully offline — users on
//    3G in Mbarara still get a great experience."

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../models/faculty_model.dart';
import '../models/course_model.dart';
import '../models/group_model.dart';
import '../models/group_member_model.dart';
import '../local/dao/message_dao.dart';
import '../local/dao/notification_dao.dart';

class UserDevicePresenceSummary {
  final int totalDevices;
  final int activeDevices;
  final DateTime? lastSeenAt;

  const UserDevicePresenceSummary({
    required this.totalDevices,
    required this.activeDevices,
    required this.lastSeenAt,
  });

  bool get isOnline => activeDevices > 0;
}

class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // ── Collection references ─────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');
  CollectionReference<Map<String, dynamic>> get _conversations =>
      _db.collection('conversations');
  CollectionReference<Map<String, dynamic>> get _notifications =>
      _db.collection('notifications');
  CollectionReference<Map<String, dynamic>> get _collabRequests =>
      _db.collection('collab_requests');
  CollectionReference<Map<String, dynamic>> get _follows =>
      _db.collection('follows');
  CollectionReference<Map<String, dynamic>> get _faculties =>
      _db.collection('faculties');
  CollectionReference<Map<String, dynamic>> get _courses =>
      _db.collection('courses');
  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groups');
  CollectionReference<Map<String, dynamic>> get _groupMembers =>
      _db.collection('group_members');
  CollectionReference<Map<String, dynamic>> get _recommendationLogs =>
      _db.collection('recommendation_logs');
  CollectionReference<Map<String, dynamic>> get _userRecommendations =>
      _db.collection('user_recommendations');
  CollectionReference<Map<String, dynamic>> get _comments =>
      _db.collection('comments');

  // ── User pre-computed recommendations (from mobile app) ─────────────────────────

  /// Fetches pre-computed recommendations for a specific user from Firestore.
  /// Returns cached recommendation results computed by the mobile algorithm.
  Future<Map<String, dynamic>> getUserRecommendations(
      {required String userId}) {
    return _userRecommendations.doc(userId).get().then((snapshot) {
      return snapshot.data() ?? <String, dynamic>{};
    }).catchError((_) => <String, dynamic>{});
  }

  /// Watches pre-computed recommendations for a user (real-time updates).
  Stream<Map<String, dynamic>> watchUserRecommendations(
      {required String userId}) {
    return _userRecommendations.doc(userId).snapshots().map((snapshot) {
      return snapshot.data() ?? <String, dynamic>{};
    });
  }

  /// Fetches all user recommendation documents (for admin/analytics).
  Future<List<Map<String, dynamic>>> getAllUserRecommendations(
      {int limit = 200}) async {
    final safeLimit = limit <= 0 ? 200 : limit;
    final snapshot = await _userRecommendations.limit(safeLimit).get();

    return snapshot.docs
        .map((doc) => {'userId': doc.id, ...doc.data()})
        .toList(growable: false);
  }

  /// Pushes pre-computed recommendations to Firestore (written by background job).
  Future<void> saveUserRecommendations({
    required String userId,
    required Map<String, dynamic> recs,
  }) async {
    final batch = _db.batch();
    batch.set(
      _userRecommendations.doc(userId),
      {
        ...recs,
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  CollectionReference<Map<String, dynamic>> get _postRatings =>
      _db.collection('post_ratings');
  CollectionReference<Map<String, dynamic>> get _appFeedback =>
      _db.collection('app_feedback');
  CollectionReference<Map<String, dynamic>> get _accountDeletionRequests =>
      _db.collection('account_deletion_requests');
  CollectionReference<Map<String, dynamic>> get _chatbotInteractions =>
      _db.collection('chatbot_interactions');

  // ── Recommendation log operations ─────────────────────────────────────────

  /// Pushes a batch of recommendation log rows to Firestore.
  /// Splits into chunks of 400 to stay under the 500-write Firestore limit.
  /// Fire-and-forget from the DAO layer — failures are acceptable.
  Future<void> pushRecommendationLogs(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    const chunkSize = 400;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.sublist(i, (i + chunkSize).clamp(0, rows.length));
      final batch = _db.batch();
      for (final row in chunk) {
        final docId = row['id'] as String?;
        if (docId == null || docId.isEmpty) continue;
        batch.set(
          _recommendationLogs.doc(docId),
          {
            ...row,
            'server_ts': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  Future<List<Map<String, dynamic>>> getRecentRecommendationLogs({
    int limit = 200,
  }) async {
    final safeLimit = limit <= 0 ? 200 : limit;
    final snapshot = await _recommendationLogs
        .orderBy('logged_at', descending: true)
        .limit(safeLimit)
        .get(const GetOptions(source: Source.serverAndCache));

    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList(growable: false);
  }

  Future<void> setPostRating({
    required String ratingId,
    required Map<String, dynamic> payload,
  }) async {
    await _postRatings.doc(ratingId).set(
      {
        ...payload,
        'server_ts': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deletePostRating(String ratingId) async {
    await _postRatings.doc(ratingId).delete();
  }

  Future<void> setAppFeedback({
    required String feedbackId,
    required Map<String, dynamic> payload,
  }) async {
    await _appFeedback.doc(feedbackId).set(
      {
        ...payload,
        'server_ts': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setGroup(GroupModel group) async {
    await _groups.doc(group.id).set(
      {
        ...group.toJson(),
        'server_ts': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> dissolveGroup(String groupId) async {
    await _groups.doc(groupId).set(
      {
        'is_dissolved': true,
        'updated_at': DateTime.now().toIso8601String(),
        'server_ts': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setGroupMember(GroupMemberModel member) async {
    await _groupMembers.doc(member.id).set(
      {
        ...member.toJson(),
        'server_ts': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteGroupMember(String membershipId) async {
    await _groupMembers.doc(membershipId).delete();
  }

  Future<void> deleteAppFeedback(String feedbackId) async {
    await _appFeedback.doc(feedbackId).delete();
  }

  /// Fetches recent comment snippets grouped by post id.
  ///
  /// The schema for comments can differ between environments, so this method
  /// accepts common field aliases for both post id and text content.
  Future<Map<String, List<String>>> getRecentCommentSnippetsForPosts({
    required List<String> postIds,
    int perPost = 4,
  }) async {
    if (postIds.isEmpty) return const <String, List<String>>{};

    final grouped = <String, List<String>>{};
    final normalizedIds = postIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) return const <String, List<String>>{};

    Iterable<List<String>> chunked(List<String> source, int size) sync* {
      for (var i = 0; i < source.length; i += size) {
        yield source.sublist(i, (i + size).clamp(0, source.length));
      }
    }

    Future<void> runQueryForField(String postField) async {
      for (final chunk in chunked(normalizedIds, 10)) {
        final snapshot = await _comments
            .where(postField, whereIn: chunk)
            .limit(chunk.length * perPost * 4)
            .get(const GetOptions(source: Source.serverAndCache));

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final postId = _extractCommentPostId(data);
          if (postId == null || !normalizedIds.contains(postId)) continue;

          final text = _extractCommentText(data);
          if (text == null || text.isEmpty) continue;

          final list = grouped.putIfAbsent(postId, () => <String>[]);
          if (list.length < perPost) {
            list.add(text);
          }
        }
      }
    }

    try {
      await runQueryForField('post_id');
    } catch (_) {
      try {
        await runQueryForField('postId');
      } catch (_) {
        return grouped;
      }
    }

    return grouped;
  }

  String? _extractCommentPostId(Map<String, dynamic> data) {
    final raw = data['post_id'] ?? data['postId'] ?? data['project_id'];
    final id = raw?.toString().trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  String? _extractCommentText(Map<String, dynamic> data) {
    final raw = data['content'] ??
        data['comment'] ??
        data['comment_text'] ??
        data['body'] ??
        data['message'] ??
        data['text'];
    final text = raw?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  /// Writes an account deletion request to Firestore.
  /// The record is flagged for admin review — no data is purged immediately.
  Future<void> flagAccountForDeletion({
    required String requestId,
    required Map<String, dynamic> payload,
  }) async {
    await _accountDeletionRequests.doc(requestId).set(
      {
        ...payload,
        'server_ts': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<List<Map<String, dynamic>>> getRecentAppFeedback({
    int limit = 60,
  }) async {
    final safeLimit = limit <= 0 ? 60 : limit;
    final snapshot = await _appFeedback
        .orderBy('created_at', descending: true)
        .limit(safeLimit)
        .get(const GetOptions(source: Source.serverAndCache));

    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList(growable: false);
  }

  Future<void> setChatbotInteraction({
    required String interactionId,
    required Map<String, dynamic> payload,
  }) async {
    await _chatbotInteractions.doc(interactionId).set(
      {
        ...payload,
        'server_ts': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setChatbotInteractionFeedback({
    required String interactionId,
    required bool isHelpful,
    String? feedbackNote,
    String? feedbackBy,
  }) async {
    await _chatbotInteractions.doc(interactionId).set(
      {
        'is_helpful': isHelpful,
        'feedback_note': feedbackNote ?? '',
        'feedback_by': feedbackBy ?? '',
        'feedback_at': DateTime.now().toIso8601String(),
        'server_ts': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<List<Map<String, dynamic>>> getRecentChatbotInteractions({
    int limit = 200,
  }) async {
    final safeLimit = limit <= 0 ? 200 : limit;
    final snapshot = await _chatbotInteractions
        .orderBy('created_at', descending: true)
        .limit(safeLimit)
        .get(const GetOptions(source: Source.serverAndCache));

    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList(growable: false);
  }

  // ── User operations ───────────────────────────────────────────────────────

  /// Creates or overwrites a user document (used on registration + profile update).
  Future<void> setUser(UserModel user) async {
    await _users.doc(user.id).set(user.toJson(), SetOptions(merge: true));
  }

  String _firestoreDateToIso(dynamic value, {DateTime? fallback}) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is String && value.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) {
        return parsed.toIso8601String();
      }
    }
    return (fallback ?? DateTime.now()).toIso8601String();
  }

  UserModel _decodeUserDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final now = DateTime.now();
    final createdAt = _firestoreDateToIso(
      data['createdAt'] ?? data['created_at'],
      fallback: now,
    );
    final updatedAt = _firestoreDateToIso(
      data['updatedAt'] ??
          data['updated_at'] ??
          data['createdAt'] ??
          data['created_at'],
      fallback: now,
    );
    final lastSeenAtRaw = data['lastSeenAt'] ?? data['last_seen_at'];

    return UserModel.fromJson({
      'id': doc.id,
      'firebaseUid': data['firebaseUid'] ?? data['firebase_uid'],
      'email': data['email'] ?? '',
      'role': data['role'],
      'displayName': data['displayName'] ?? data['display_name'],
      'photoUrl': data['photoUrl'] ?? data['photo_url'],
      'isEmailVerified':
          data['isEmailVerified'] ?? data['is_email_verified'] ?? false,
      'isSuspended': data['isSuspended'] ?? data['is_suspended'] ?? false,
      'isBanned': data['isBanned'] ?? data['is_banned'] ?? false,
      'lastSeenAt': lastSeenAtRaw == null
          ? null
          : _firestoreDateToIso(lastSeenAtRaw, fallback: now),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'profile': data['profile'],
    });
  }

  /// Fetches a single user. Returns null if not found.
  Future<UserModel?> getUser(String userId) async {
    final doc = await _users.doc(userId).get();
    if (!doc.exists || doc.data() == null) return null;
    return _decodeUserDoc(doc);
  }

  /// Streams profile changes for real-time profile screen updates (Phase 6).
  Stream<UserModel?> watchUser(String userId) {
    return _users.doc(userId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return _decodeUserDoc(snap);
    });
  }

  Future<void> setDevicePresence({
    required String userId,
    required String deviceId,
    required bool isInApp,
    required bool isNetworkOnline,
  }) async {
    if (userId.trim().isEmpty || deviceId.trim().isEmpty) return;

    final now = DateTime.now().toIso8601String();
    await _users.doc(userId).set(
      {
        'lastSeenAt': now,
        'updatedAt': now,
        'presence_devices.$deviceId': {
          'device_id': deviceId,
          'is_in_app': isInApp,
          'is_network_online': isNetworkOnline,
          'last_seen_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        },
      },
      SetOptions(merge: true),
    );
  }

  DateTime? _presenceTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  UserDevicePresenceSummary _decodePresenceSummary(
    Map<String, dynamic>? data,
  ) {
    if (data == null) {
      return const UserDevicePresenceSummary(
        totalDevices: 0,
        activeDevices: 0,
        lastSeenAt: null,
      );
    }

    final devicesRaw = data['presence_devices'];
    final devices = devicesRaw is Map
        ? Map<String, dynamic>.from(devicesRaw)
        : const <String, dynamic>{};

    var active = 0;
    DateTime? latest;
    final now = DateTime.now();

    devices.forEach((_, value) {
      if (value is! Map) return;
      final map = Map<String, dynamic>.from(value);
      final isInApp = map['is_in_app'] == true;
      final isNetworkOnline = map['is_network_online'] == true;
      final seen = _presenceTimestamp(map['last_seen_at']);

      if (seen != null && (latest == null || seen.isAfter(latest!))) {
        latest = seen;
      }

      final fresh = seen != null && now.difference(seen).inSeconds <= 70;
      if (isInApp && isNetworkOnline && fresh) {
        active += 1;
      }
    });

    latest ??= _presenceTimestamp(data['lastSeenAt'] ?? data['last_seen_at']);

    return UserDevicePresenceSummary(
      totalDevices: devices.length,
      activeDevices: active,
      lastSeenAt: latest,
    );
  }

  Stream<UserDevicePresenceSummary> watchUserDevicePresence(String userId) {
    return _users.doc(userId).snapshots().map((snap) {
      return _decodePresenceSummary(snap.data());
    });
  }

  // ── Post operations ───────────────────────────────────────────────────────

  /// Fetches a single post by ID from Firestore. Returns null if not found.
  Future<PostModel?> getPostById(String postId) async {
    final doc = await _posts.doc(postId).get();
    if (!doc.exists || doc.data() == null) return null;
    return PostModel.fromJson({'id': doc.id, ...doc.data()!});
  }

  /// Writes a post document (create or update).
  Future<void> setPost(PostModel post) async {
    await _posts.doc(post.id).set(post.toMap(), SetOptions(merge: true));
  }

  /// Archives a post (sets is_archived = true server-side).
  Future<void> archivePost(String postId) async {
    await _posts.doc(postId).update({
      'is_archived': true,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a post document.
  Future<void> deletePost(String postId) async {
    await _posts.doc(postId).delete();
  }

  /// Toggles a like on a post using Firestore transaction
  /// (prevents race conditions when multiple users like simultaneously).
  Future<void> toggleLike({
    required String postId,
    required String userId,
    required bool isLiking,
  }) async {
    final likeRef = _posts.doc(postId).collection('likes').doc(userId);

    if (isLiking) {
      await likeRef.set({
        'user_id': userId,
        'created_at': FieldValue.serverTimestamp(),
      });
    } else {
      await likeRef.delete();
    }
    // like_count is maintained by a Firestore Cloud Function trigger
    // on posts/{postId}/likes — same pattern as follower/following counts.
  }

  /// Paginated feed query — returns [pageSize] posts before [lastDoc].
  Future<List<PostModel>> getFeedPage({
    int pageSize = 20,
    DocumentSnapshot? lastDoc,
    String? facultyFilter,
    String? categoryFilter,
  }) async {
    Query<Map<String, dynamic>> query = _posts
        .where('is_archived', isEqualTo: false)
        // Firestore whereIn cannot contain null.
        .where('moderation_status', isEqualTo: 'approved')
        .orderBy('created_at', descending: true)
        .limit(pageSize);

    if (facultyFilter != null) {
      // 'faculties' is a Firestore array written by PostModel.toJson().
      // array-contains supports multi-faculty opportunities correctly.
      query = query.where('faculties', arrayContains: facultyFilter);
    }
    if (categoryFilter != null) {
      query = query.where('category', isEqualTo: categoryFilter);
    }
    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((d) => PostModel.fromJson({'id': d.id, ...d.data()}))
        .toList();
  }

  /// Pull a recent batch of posts from Firestore for local cache hydration.
  Future<List<PostModel>> getRecentPosts({
    int limit = 50,
    bool includePendingForAdmin = false,
  }) async {
    debugPrint('[FirestoreService] getRecentPosts(limit=$limit) starting');

    // The security rules require is_archived == false.
    // If we don't include this filter, the entire query is rejected.
    Query<Map<String, dynamic>> query = _posts
        .where('is_archived', isEqualTo: false)
        .orderBy('created_at', descending: true)
        .limit(limit);

    if (!includePendingForAdmin) {
      // Firestore whereIn cannot contain null.
      query = query.where('moderation_status', isEqualTo: 'approved');
    }

    final snapshot =
        await query.get(const GetOptions(source: Source.serverAndCache));

    debugPrint(
      '[FirestoreService] getRecentPosts fetched ${snapshot.docs.length} raw docs '
      'fromCache=${snapshot.metadata.isFromCache}',
    );

    final posts = <PostModel>[];
    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        debugPrint(
          '[FirestoreService] reading post=${doc.id} '
          'keys=${data.keys.toList()} '
          'is_archived=${data['is_archived']} '
          'isArchived=${data['isArchived']} '
          'moderation_status=${data['moderation_status']} '
          'moderationStatus=${data['moderationStatus']}',
        );

        final post = PostModel.fromJson({'id': doc.id, ...data});
        // This second check is redundant if the query filter works, but safe.
        if (post.isArchived) {
          debugPrint('[FirestoreService] skipping archived post=${doc.id}');
          continue;
        }

        posts.add(post);
      } catch (error, stackTrace) {
        debugPrint('[FirestoreService] unreadable post ${doc.id}: $error');
        debugPrint('$stackTrace');
      }
    }

    posts.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    debugPrint('[FirestoreService] returning ${posts.length} hydrated posts');
    return posts;
  }

  Future<List<PostModel>> getPostsByGroupId(
    String groupId, {
    int limit = 80,
    bool includePendingForAdmin = false,
  }) async {
    final safeGroupId = groupId.trim();
    if (safeGroupId.isEmpty) return const [];

    Query<Map<String, dynamic>> query = _posts
        .where('group_id', isEqualTo: safeGroupId)
        .where('is_archived', isEqualTo: false)
        .orderBy('created_at', descending: true)
        .limit(limit);

    if (!includePendingForAdmin) {
      query = query.where('moderation_status', isEqualTo: 'approved');
    }

    try {
      final snapshot =
          await query.get(const GetOptions(source: Source.serverAndCache));
      return snapshot.docs
          .map((doc) => PostModel.fromJson({'id': doc.id, ...doc.data()}))
          .where((post) => !post.isArchived)
          .toList(growable: false);
    } on FirebaseException catch (error) {
      if (error.code == 'failed-precondition') {
        debugPrint(
          '[FirestoreService] getPostsByGroupId missing composite index; '
          'falling back to group-only query for $safeGroupId',
        );
        try {
          if (includePendingForAdmin) {
            final snapshot = await _posts
                .where('group_id', isEqualTo: safeGroupId)
                .where('is_archived', isEqualTo: false)
                .limit(limit)
                .get(const GetOptions(source: Source.serverAndCache));
            final posts = snapshot.docs
                .map((doc) => PostModel.fromJson({'id': doc.id, ...doc.data()}))
                .where((post) => !post.isArchived)
                .toList(growable: false)
              ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
            return posts;
          }

          // Non-admin fallback must keep moderation filtering in-query so
          // Firestore rules can prove all documents satisfy read conditions.
          final approvedSnapshot = await _posts
              .where('group_id', isEqualTo: safeGroupId)
              .where('is_archived', isEqualTo: false)
              .where('moderation_status', isEqualTo: 'approved')
              .limit(limit)
              .get(const GetOptions(source: Source.serverAndCache));

          final unmoderatedSnapshot = await _posts
              .where('group_id', isEqualTo: safeGroupId)
              .where('is_archived', isEqualTo: false)
              .where('moderation_status', isNull: true)
              .limit(limit)
              .get(const GetOptions(source: Source.serverAndCache));

          final merged = <String, PostModel>{
            for (final doc in approvedSnapshot.docs)
              doc.id: PostModel.fromJson({'id': doc.id, ...doc.data()}),
            for (final doc in unmoderatedSnapshot.docs)
              doc.id: PostModel.fromJson({'id': doc.id, ...doc.data()}),
          };

          final posts = merged.values
              .where((post) => !post.isArchived)
              .toList(growable: false)
            ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
          return posts.take(limit).toList(growable: false);
        } on FirebaseException catch (fallbackError) {
          if (fallbackError.code == 'permission-denied') {
            debugPrint(
              '[FirestoreService] getPostsByGroupId fallback denied by security rules',
            );
            return const [];
          }
          rethrow;
        }
      }
      if (error.code == 'permission-denied') {
        debugPrint(
          '[FirestoreService] getPostsByGroupId denied by security rules',
        );
        return const [];
      }
      rethrow;
    }
  }

  /// Streams a recent batch of posts from Firestore for real-time dashboards.
  Stream<List<PostModel>> watchRecentPosts({
    int limit = 80,
    bool includePendingForAdmin = false,
  }) {
    Query<Map<String, dynamic>> query = _posts
        .where('is_archived', isEqualTo: false)
        .orderBy('created_at', descending: true)
        .limit(limit);

    if (!includePendingForAdmin) {
      query = query.where('moderation_status', isEqualTo: 'approved');
    }

    return query.snapshots().map((snapshot) {
      final posts = <PostModel>[];
      for (final doc in snapshot.docs) {
        try {
          final post = PostModel.fromJson({'id': doc.id, ...doc.data()});
          if (post.isArchived) continue;
          posts.add(post);
        } catch (error, stackTrace) {
          debugPrint(
              '[FirestoreService] unreadable streamed post ${doc.id}: $error');
          debugPrint('$stackTrace');
        }
      }
      posts.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return posts;
    });
  }

  /// Fetches users by Firestore document ID in small batches.
  Future<List<UserModel>> getUsersByIds(Iterable<String> userIds) async {
    final uniqueIds = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) {
      return const [];
    }

    final users = <UserModel>[];
    for (var index = 0; index < uniqueIds.length; index += 10) {
      final batch = uniqueIds.sublist(
        index,
        index + 10 > uniqueIds.length ? uniqueIds.length : index + 10,
      );

      final snapshot =
          await _users.where(FieldPath.documentId, whereIn: batch).get();
      for (final doc in snapshot.docs) {
        try {
          users.add(_decodeUserDoc(doc));
        } catch (error) {
          debugPrint(
              '[FirestoreService] Skipping unreadable user ${doc.id}: $error keys=${doc.data().keys.toList()}');
        }
      }
    }
    return users;
  }

  /// Fetches all users from Firestore for admin full-hydration.
  Future<List<UserModel>> getAllUsersFromRemote({int limit = 500}) async {
    try {
      final snapshot =
          await _users.get(const GetOptions(source: Source.serverAndCache));
      final users = <UserModel>[];
      for (final doc in snapshot.docs) {
        try {
          users.add(_decodeUserDoc(doc));
        } catch (error) {
          debugPrint(
              '[FirestoreService] Skipping unreadable user ${doc.id}: $error keys=${doc.data().keys.toList()}');
        }
      }
      users.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      debugPrint(
          '[FirestoreService] getAllUsersFromRemote returned ${users.length} users '
          'fromCache=${snapshot.metadata.isFromCache}');
      if (users.length > limit) {
        return users.take(limit).toList(growable: false);
      }
      return users;
    } on FirebaseException catch (error) {
      if (error.code == 'unavailable') {
        debugPrint(
            '[FirestoreService] getAllUsersFromRemote server unavailable; retrying from cache only');
        try {
          final cacheSnapshot =
              await _users.get(const GetOptions(source: Source.cache));
          final users = <UserModel>[];
          for (final doc in cacheSnapshot.docs) {
            try {
              users.add(_decodeUserDoc(doc));
            } catch (decodeError) {
              debugPrint(
                  '[FirestoreService] Skipping unreadable cached user ${doc.id}: '
                  '$decodeError keys=${doc.data().keys.toList()}');
            }
          }
          users
              .sort((left, right) => right.createdAt.compareTo(left.createdAt));
          debugPrint(
              '[FirestoreService] getAllUsersFromRemote cache fallback returned '
              '${users.length} users');
          if (users.length > limit) {
            return users.take(limit).toList(growable: false);
          }
          return users;
        } on FirebaseException catch (cacheError) {
          debugPrint(
              '[FirestoreService] getAllUsersFromRemote cache fallback failed: '
              '${cacheError.code} ${cacheError.message}');
        }
      }
      debugPrint(
          '[FirestoreService] getAllUsersFromRemote failed: ${error.code} ${error.message}');
      return const [];
    }
  }

  /// Streams all user documents — used by the admin dashboard for real-time
  /// updates so newly registered users appear without a manual refresh.
  Stream<List<UserModel>> watchAllUsers({int limit = 500}) {
    return _users.snapshots().map((snap) {
      final users = <UserModel>[];
      for (final doc in snap.docs) {
        try {
          users.add(_decodeUserDoc(doc));
        } catch (error) {
          debugPrint(
              '[FirestoreService] Skipping unreadable user in stream ${doc.id}: $error keys=${doc.data().keys.toList()}');
        }
      }
      users.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      if (users.length > limit) {
        return users.take(limit).toList(growable: false);
      }
      return users;
    });
  }

  Future<List<GroupModel>> getGroupsByIds(Iterable<String> groupIds) async {
    final uniqueIds = groupIds.where((id) => id.isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) {
      return const [];
    }

    final groups = <GroupModel>[];
    try {
      for (var index = 0; index < uniqueIds.length; index += 10) {
        final batch = uniqueIds.sublist(
          index,
          index + 10 > uniqueIds.length ? uniqueIds.length : index + 10,
        );
        final snapshot =
            await _groups.where(FieldPath.documentId, whereIn: batch).get();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          try {
            groups.add(GroupModel.fromJson({'id': doc.id, ...data}));
          } catch (error) {
            debugPrint(
                '[FirestoreService] Skipping unreadable group ${doc.id}: $error');
          }
        }
      }
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        debugPrint(
            '[FirestoreService] getGroupsByIds denied by security rules');
        return const [];
      }
      rethrow;
    }
    return groups;
  }

  Future<List<GroupModel>> getRecentGroups({int limit = 80}) async {
    try {
      final snapshot = await _groups
          .where('is_dissolved', isEqualTo: false)
          .orderBy('updated_at', descending: true)
          .limit(limit)
          .get(const GetOptions(source: Source.serverAndCache));
      return snapshot.docs
          .map((doc) => GroupModel.fromJson({'id': doc.id, ...doc.data()}))
          .toList();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        debugPrint(
            '[FirestoreService] getRecentGroups denied by security rules');
        return const [];
      }
      if (error.code == 'failed-precondition') {
        debugPrint(
          '[FirestoreService] getRecentGroups missing composite index, falling back to updated_at query and client-side filtering',
        );
        final snapshot = await _groups
            .orderBy('updated_at', descending: true)
            .limit(limit)
            .get(const GetOptions(source: Source.serverAndCache));
        return snapshot.docs
            .where((doc) => (doc.data()['is_dissolved'] as bool?) != true)
            .map((doc) => GroupModel.fromJson({'id': doc.id, ...doc.data()}))
            .toList();
      }
      rethrow;
    }
  }

  Future<List<GroupMemberModel>> getGroupMembersByGroupIds(
    Iterable<String> groupIds,
  ) async {
    final uniqueIds = groupIds.where((id) => id.isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) {
      return const [];
    }

    final members = <GroupMemberModel>[];
    try {
      for (var index = 0; index < uniqueIds.length; index += 10) {
        final batch = uniqueIds.sublist(
          index,
          index + 10 > uniqueIds.length ? uniqueIds.length : index + 10,
        );
        final snapshot = await _groupMembers
            .where('group_id', whereIn: batch)
            .get(const GetOptions(source: Source.serverAndCache));
        for (final doc in snapshot.docs) {
          final data = doc.data();
          try {
            members.add(GroupMemberModel.fromJson({'id': doc.id, ...data}));
          } catch (error) {
            debugPrint(
                '[FirestoreService] Skipping unreadable group member ${doc.id}: $error');
          }
        }
      }
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        debugPrint(
            '[FirestoreService] getGroupMembersByGroupIds denied by security rules');
        return const [];
      }
      rethrow;
    }
    return members;
  }

  Future<List<GroupMemberModel>> getGroupMembersForUser(
    String userId,
  ) async {
    try {
      final snapshot = await _groupMembers
          .where('user_id', isEqualTo: userId)
          .get(const GetOptions(source: Source.serverAndCache));
      return snapshot.docs
          .map(
              (doc) => GroupMemberModel.fromJson({'id': doc.id, ...doc.data()}))
          .toList();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        debugPrint(
            '[FirestoreService] getGroupMembersForUser denied by security rules');
        return const [];
      }
      rethrow;
    }
  }

  // ── Messaging operations ──────────────────────────────────────────────────

  /// Writes a message to Firestore.
  /// Atomic update of conversation's last_message_at via transaction.
  Future<void> sendMessage(MessageModel message) async {
    final convoRef = _conversations.doc(message.conversationId);
    final msgRef = convoRef.collection('messages').doc(message.id);

    // Parse user_id and peer_id from the conversation ID.
    // Format: "{userId}_{peerId}_{timestamp}" — Firebase UIDs are alphanumeric
    // and never contain underscores, so splitting on '_' is safe.
    final parts = message.conversationId.split('_');
    final convoUserId = parts.isNotEmpty ? parts[0] : message.senderId;
    final convoPeerId = parts.length >= 2 ? parts[1] : '';
    if (convoPeerId.isNotEmpty && convoPeerId == message.senderId) {
      debugPrint(
        '[FirestoreService] Skipping self-target message '
        'conversation=${message.conversationId} sender=${message.senderId}',
      );
      return;
    }

    // Use separate writes instead of a transaction.  A transaction with
    // SetOptions(merge:true) requires Firestore to internally READ the
    // conversation document to apply the merge; if the doc doesn't exist
    // yet, the READ rule fails and brings the whole transaction down even
    // though the write rules would be satisfied.
    await msgRef.set({
      'id': message.id,
      'sender_id': message.senderId,
      'content': message.content,
      'message_type': message.messageType,
      'file_url': message.fileUrl,
      'file_name': message.fileName,
      'file_size': message.fileSize,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
    });

    // Include user_id and peer_id so the Firestore create rule
    // ("request.resource.data.user_id == uid()") is satisfied when the
    // conversation document doesn't yet exist.
    await convoRef.set({
      'user_id': convoUserId,
      'peer_id': convoPeerId,
      'last_message': message.content.length > 80
          ? '${message.content.substring(0, 80)}…'
          : message.content,
      'last_message_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Wait for the server to confirm the writes (not just local-cache
    // acceptance). This throws if the server rejects with permission-denied
    // or any other error, surfacing it to the caller instead of silently
    // failing behind offline persistence.
    await _db.waitForPendingWrites();
  }

  /// Streams new messages in real-time for the chat screen.
  Stream<List<MessageModel>> watchMessages(String conversationId) {
    return _conversations
        .doc(conversationId)
        .collection('messages')
        .orderBy('created_at', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              final ts = data['created_at'] as Timestamp?;
              return MessageModel(
                id: d.id,
                conversationId: conversationId,
                senderId: data['sender_id'] as String,
                content: data['content'] as String,
                messageType: data['message_type'] as String? ?? 'text',
                fileUrl: data['file_url'] as String?,
                fileName: data['file_name'] as String?,
                fileSize: data['file_size'] as String?,
                createdAt: ts?.toDate() ?? DateTime.now(),
                isRead: data['is_read'] as bool? ?? false,
              );
            }).toList());
  }

  /// Deletes a conversation document and any message docs under it for the
  /// current user's thread.
  Future<void> deleteConversation(String conversationId) async {
    final convoRef = _conversations.doc(conversationId);
    final messageSnap = await convoRef.collection('messages').get();

    for (final doc in messageSnap.docs) {
      await doc.reference.delete();
    }

    await convoRef.delete();
  }

  /// Marks all incoming messages in a conversation as read for the current user.
  Future<void> markConversationRead({
    required String conversationId,
    required String userId,
  }) async {
    final convoRef = _conversations.doc(conversationId);
    final snapshot = await convoRef.collection('messages').get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final senderId = data['sender_id'] as String?;
      final isRead = data['is_read'] as bool? ?? false;
      if (senderId == null || senderId == userId || isRead) {
        continue;
      }
      await doc.reference.update({'is_read': true});
    }
  }

  // ── Notification operations ───────────────────────────────────────────────

  /// Writes a notification to Firestore.
  Future<void> sendNotification(NotificationModel notif) async {
    await _notifications.doc(notif.id).set({
      'user_id': notif.userId,
      'type': notif.type,
      'sender_id': notif.senderId,
      'sender_name': notif.senderName,
      'body': notif.body,
      'detail': notif.detail,
      'entity_id': notif.entityId,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
      'extra': notif.extra,
    });
  }

  /// Streams unread notification count for nav badge.
  Stream<int> watchUnreadNotifCount(String userId) {
    return _notifications
        .where('user_id', isEqualTo: userId)
        .where('is_read', isEqualTo: false)
        .snapshots()
        .map((s) => s.size);
  }

  /// Emits lightweight ticks whenever inbox-relevant Firestore collections
  /// change for the current user.
  Stream<int> watchInboxSyncTicks(String userId) {
    late final StreamController<int> controller;
    final subscriptions = <StreamSubscription<dynamic>>[];
    var seq = 0;

    void emitTick() {
      if (!controller.isClosed) {
        controller.add(++seq);
      }
    }

    void handleError(Object error, StackTrace stackTrace) {
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<int>.broadcast(
      onListen: () {
        subscriptions.add(
          _conversations.where('user_id', isEqualTo: userId).snapshots().listen(
                (_) => emitTick(),
                onError: handleError,
              ),
        );
        subscriptions.add(
          _conversations.where('peer_id', isEqualTo: userId).snapshots().listen(
                (_) => emitTick(),
                onError: handleError,
              ),
        );
        subscriptions.add(
          _collabRequests
              .where('sender_id', isEqualTo: userId)
              .snapshots()
              .listen(
                (_) => emitTick(),
                onError: handleError,
              ),
        );
        subscriptions.add(
          _collabRequests
              .where('receiver_id', isEqualTo: userId)
              .snapshots()
              .listen(
                (_) => emitTick(),
                onError: handleError,
              ),
        );
      },
      onCancel: () async {
        for (final sub in subscriptions) {
          await sub.cancel();
        }
        subscriptions.clear();
      },
    );

    return controller.stream;
  }

  /// Emits ticks when recent approved posts change so feed can refresh quickly.
  Stream<int> watchRecentPostActivityTicks({int limit = 120}) {
    return _posts
        .where('is_archived', isEqualTo: false)
        .where('moderation_status', isEqualTo: 'approved')
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((_) => DateTime.now().millisecondsSinceEpoch);
  }

  // ── Follow operations ─────────────────────────────────────────────────────

  Future<void> follow({
    required String followerId,
    required String followingId,
  }) async {
    final docId = '${followerId}_$followingId';
    await _follows.doc(docId).set({
      'follower_id': followerId,
      'following_id': followingId,
      'created_at': FieldValue.serverTimestamp(),
    });
    // Note: follower/following counts are maintained by a Firestore
    // Cloud Function trigger on the follows collection, not by the client,
    // because a client cannot update another user's document.
  }

  Future<void> unfollow({
    required String followerId,
    required String followingId,
  }) async {
    final docId = '${followerId}_$followingId';
    await _follows.doc(docId).delete();
    // Count decrement handled by Cloud Function trigger (see above).
  }

  Future<int?> getFollowerCountForUser({required String userId}) async {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return null;
    try {
      final snapshot = await _follows
          .where('following_id', isEqualTo: safeUserId)
          .count()
          .get();
      return snapshot.count;
    } on FirebaseException catch (error) {
      debugPrint(
        '[FirestoreService] follower count lookup failed for $safeUserId: '
        '${error.code} ${error.message}',
      );
      return null;
    }
  }

  Future<Map<String, int>> getFollowerCountIndex({int limit = 5000}) async {
    try {
      Query<Map<String, dynamic>> query = _follows;
      if (limit > 0) {
        query = query.limit(limit);
      }
      final snapshot = await query.get(
        const GetOptions(source: Source.serverAndCache),
      );

      final counts = <String, int>{};
      for (final doc in snapshot.docs) {
        final followingId = (doc.data()['following_id'] as String?)?.trim();
        if (followingId == null || followingId.isEmpty) continue;
        counts[followingId] = (counts[followingId] ?? 0) + 1;
      }
      return counts;
    } on FirebaseException catch (error) {
      debugPrint(
        '[FirestoreService] follower index lookup failed: '
        '${error.code} ${error.message}',
      );
      return const <String, int>{};
    }
  }

  // ── Search ────────────────────────────────────────────────────────────────

  /// Full-text search via Firestore array-contains (skills field).
  /// For production, replace with Algolia or Firebase Extensions Search.
  Future<List<PostModel>> searchPostsBySkill(String skill) async {
    final snapshot = await _posts
        .where('skills', arrayContains: skill)
        .where('is_archived', isEqualTo: false)
        .orderBy('created_at', descending: true)
        .limit(30)
        .get();

    return snapshot.docs
        .map((d) => PostModel.fromJson({'id': d.id, ...d.data()}))
        .toList();
  }

  // ── Admin operations ──────────────────────────────────────────────────────

  /// Writes an audit log entry to Firestore (for admin moderation trail).
  Future<void> logAuditEvent({
    required String adminId,
    required String actionType,
    required String targetId,
    required String targetType,
    String? reason,
  }) async {
    await _db.collection('audit_log').add({
      'admin_id': adminId,
      'action_type': actionType,
      'target_id': targetId,
      'target_type': targetType,
      'reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Fetches platform-wide stats for super admin dashboard.
  Future<Map<String, dynamic>> getPlatformStats() async {
    final results = await Future.wait([
      _users.count().get(),
      _posts.where('is_archived', isEqualTo: false).count().get(),
      _follows.count().get(),
    ]);

    return {
      'total_users': results[0].count ?? 0,
      'total_posts': results[1].count ?? 0,
      'total_follows': results[2].count ?? 0,
    };
  }

  // ── Faculty operations ────────────────────────────────────────────────────

  Future<List<String>> getActiveFacultyNames({int limit = 200}) async {
    final safeLimit = limit <= 0 ? 200 : limit;
    final snapshot = await _faculties
        .where('isActive', isEqualTo: true)
        .limit(safeLimit)
        .get(const GetOptions(source: Source.serverAndCache));

    final names = snapshot.docs
        .map((doc) => (doc.data()['name'] as String?)?.trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    return names;
  }

  Future<void> setFaculty(FacultyModel faculty) async {
    await _faculties
        .doc(faculty.id)
        .set(faculty.toFirestore(), SetOptions(merge: true));
  }

  Future<void> deleteFaculty(String facultyId) async {
    await _faculties.doc(facultyId).update({'isActive': false});
  }

  // ── Course operations ─────────────────────────────────────────────────────

  Future<void> setCourse(CourseModel course) async {
    await _courses
        .doc(course.id)
        .set(course.toFirestore(), SetOptions(merge: true));
  }

  Future<void> deleteCourse(String courseId) async {
    await _courses.doc(courseId).update({'isActive': false});
  }
}
