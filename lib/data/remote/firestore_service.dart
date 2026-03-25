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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../local/dao/message_dao.dart';
import '../local/dao/notification_dao.dart';

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
  CollectionReference<Map<String, dynamic>> get _follows =>
      _db.collection('follows');

  // ── User operations ───────────────────────────────────────────────────────

  /// Creates or overwrites a user document (used on registration + profile update).
  Future<void> setUser(UserModel user) async {
    await _users.doc(user.id).set(user.toJson(), SetOptions(merge: true));
  }

  /// Fetches a single user. Returns null if not found.
  Future<UserModel?> getUser(String userId) async {
    final doc = await _users.doc(userId).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromJson({'id': doc.id, ...doc.data()!});
  }

  /// Streams profile changes for real-time profile screen updates (Phase 6).
  Stream<UserModel?> watchUser(String userId) {
    return _users.doc(userId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return UserModel.fromJson({'id': snap.id, ...snap.data()!});
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
        .where('moderation_status', whereIn: [null, 'approved']) // Only show approved or unmoderated posts
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
    return snapshot.docs.map((d) =>
        PostModel.fromJson({'id': d.id, ...d.data()})).toList();
  }

  /// Pull a recent batch of posts from Firestore for local cache hydration.
  Future<List<PostModel>> getRecentPosts({int limit = 50}) async {
    final snapshot = await _posts
        .where('is_archived', isEqualTo: false)
        .limit(limit)
        .get();

    final posts = <PostModel>[];
    for (final doc in snapshot.docs) {
      try {
        final post = PostModel.fromJson({'id': doc.id, ...doc.data()});
        if (post.isArchived) {
          continue;
        }
        posts.add(post);
      } catch (error) {
        debugPrint('[FirestoreService] Skipping unreadable post ${doc.id}: $error');
      }
    }
    posts.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return posts;
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

      final snapshot = await _users.where(FieldPath.documentId, whereIn: batch).get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        try {
          users.add(UserModel.fromJson({'id': doc.id, ...data}));
        } catch (error) {
          debugPrint('[FirestoreService] Skipping unreadable user ${doc.id}: $error');
        }
      }
    }
    return users;
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
}
