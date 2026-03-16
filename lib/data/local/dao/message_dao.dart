// lib/data/local/dao/message_dao.dart
//
// MUST StarTrack — Message DAO (Phase 4)
//
// Handles all SQLite operations for direct messages:
//   • insertMessage         — writes new message, updates conversation last_message_at
//   • getConversations      — paginated list of conversations with last message preview
//   • getMessages           — cursor-based paginated message thread
//   • markConversationRead  — clears unread count for a conversation
//   • deleteMessage         — soft delete (sets is_deleted=1)
//   • deleteConversation    — removes all messages + conversation row
//   • getUnreadCount        — badge count for nav bar
//   • searchConversations   — search by peer display name
//
// Offline-first:
//   Writes go to SQLite first. Phase 5 will enqueue to SyncQueueDao
//   and propagate to Firestore. Firestore push notification arrives via
//   FCM → writes to SQLite → notifies MessagingCubit via stream.
//
// Schema tables used (defined in database_schema.dart):
//   conversations(id, user_id, peer_id, peer_name, peer_photo_url,
//                 last_message, last_message_at, unread_count, is_peer_lecturer)
//   messages(id, conversation_id, sender_id, content, message_type,
//            file_url, file_name, file_size, created_at, is_read, is_deleted)

import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';

// ── Message model ─────────────────────────────────────────────────────────────

class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String messageType; // 'text' | 'file' | 'project_link'
  final String? fileUrl;
  final String? fileName;
  final String? fileSize;
  final DateTime createdAt;
  final bool isRead;
  final bool isDeleted;

  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.messageType,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    required this.createdAt,
    this.isRead = false,
    this.isDeleted = false,
  });

  /// Constructs from SQLite row map.
  factory MessageModel.fromMap(Map<String, dynamic> m) => MessageModel(
    id: m['id'] as String,
    conversationId: m['conversation_id'] as String,
    senderId: m['sender_id'] as String,
    content: m['content'] as String,
    messageType: m['message_type'] as String? ?? 'text',
    fileUrl: m['file_url'] as String?,
    fileName: m['file_name'] as String?,
    fileSize: m['file_size'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    isRead: (m['is_read'] as int? ?? 0) == 1,
    isDeleted: (m['is_deleted'] as int? ?? 0) == 1,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'content': content,
    'message_type': messageType,
    'file_url': fileUrl,
    'file_name': fileName,
    'file_size': fileSize,
    'created_at': createdAt.millisecondsSinceEpoch,
    'is_read': isRead ? 1 : 0,
    'is_deleted': isDeleted ? 1 : 0,
  };
}

// ── Conversation summary model ────────────────────────────────────────────────

class ConversationSummary {
  final String id;
  final String peerId;
  final String peerName;
  final String? peerPhotoUrl;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;
  final bool isPeerLecturer;

  const ConversationSummary({
    required this.id,
    required this.peerId,
    required this.peerName,
    this.peerPhotoUrl,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    this.isPeerLecturer = false,
  });

  factory ConversationSummary.fromMap(Map<String, dynamic> m) =>
      ConversationSummary(
        id: m['id'] as String,
        peerId: m['peer_id'] as String,
        peerName: m['peer_name'] as String,
        peerPhotoUrl: m['peer_photo_url'] as String?,
        lastMessage: m['last_message'] as String? ?? '',
        lastMessageAt: DateTime.fromMillisecondsSinceEpoch(
            m['last_message_at'] as int),
        unreadCount: m['unread_count'] as int? ?? 0,
        isPeerLecturer: (m['is_peer_lecturer'] as int? ?? 0) == 1,
      );
}

// ── DAO ───────────────────────────────────────────────────────────────────────

class MessageDao {
  final _db = DatabaseHelper.instance;

  // ── Insert a new message ─────────────────────────────────────────────────

  /// Inserts [message] and updates the parent conversation's preview.
  /// Runs atomically in a single transaction.
  Future<void> insertMessage(MessageModel message) async {
    final db = await _db.database;

    await db.transaction((txn) async {
      // 1. Insert message row
      await txn.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Update conversation preview + bump unread for peer
      await txn.rawUpdate('''
        UPDATE conversations
        SET last_message       = ?,
            last_message_at    = ?,
            unread_count       = CASE
                                   WHEN user_id != ? THEN unread_count + 1
                                   ELSE 0
                                 END
        WHERE id = ?
      ''', [
        message.content.length > 80
            ? '${message.content.substring(0, 80)}…'
            : message.content,
        message.createdAt.millisecondsSinceEpoch,
        message.senderId,
        message.conversationId,
      ]);
    });
  }

  // ── Get conversations ────────────────────────────────────────────────────

  /// Returns all conversations for [userId] sorted by most recent message.
  Future<List<ConversationSummary>> getConversations({
    required String userId,
    int pageSize = 30,
    DateTime? before,
  }) async {
    final db = await _db.database;

    final whereArgs = <dynamic>[userId];
    String cursorClause = '';
    if (before != null) {
      cursorClause = 'AND last_message_at < ?';
      whereArgs.add(before.millisecondsSinceEpoch);
    }

    final rows = await db.rawQuery('''
      SELECT * FROM conversations
      WHERE user_id = ? $cursorClause
      ORDER BY last_message_at DESC
      LIMIT ?
    ''', [...whereArgs, pageSize]);

    return rows.map(ConversationSummary.fromMap).toList();
  }

  // ── Get messages in thread ───────────────────────────────────────────────

  /// Cursor-based pagination: loads [pageSize] messages before [before].
  /// This yields O(log n) complexity vs OFFSET-based O(n).
  Future<List<MessageModel>> getMessages({
    required String conversationId,
    int pageSize = 40,
    DateTime? before,
  }) async {
    final db = await _db.database;

    final whereArgs = <dynamic>[conversationId, 0]; // is_deleted = 0
    String cursorClause = '';
    if (before != null) {
      cursorClause = 'AND created_at < ?';
      whereArgs.add(before.millisecondsSinceEpoch);
    }

    final rows = await db.rawQuery('''
      SELECT * FROM messages
      WHERE conversation_id = ?
        AND is_deleted = ?
        $cursorClause
      ORDER BY created_at DESC
      LIMIT ?
    ''', [...whereArgs, pageSize]);

    // Reverse so caller gets chronological order
    return rows.reversed.map(MessageModel.fromMap).toList();
  }

  // ── Mark conversation as read ────────────────────────────────────────────

  /// Resets unread_count to 0 and marks all unread messages as read.
  Future<void> markConversationRead({
    required String conversationId,
    required String userId,
  }) async {
    final db = await _db.database;

    await db.transaction((txn) async {
      // Zero out unread on conversation
      await txn.update(
        'conversations',
        {'unread_count': 0},
        where: 'id = ? AND user_id = ?',
        whereArgs: [conversationId, userId],
      );

      // Mark individual messages as read
      await txn.rawUpdate('''
        UPDATE messages
        SET is_read = 1
        WHERE conversation_id = ?
          AND sender_id != ?
          AND is_read = 0
      ''', [conversationId, userId]);
    });
  }

  // ── Soft-delete a message ────────────────────────────────────────────────

  Future<void> deleteMessage(String messageId) async {
    final db = await _db.database;
    await db.update(
      'messages',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  // ── Hard-delete a conversation ───────────────────────────────────────────

  Future<void> deleteConversation(String conversationId) async {
    final db = await _db.database;

    await db.transaction((txn) async {
      await txn.delete(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );
      await txn.delete(
        'conversations',
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
  }

  // ── Total unread count (nav badge) ───────────────────────────────────────

  Future<int> getTotalUnreadCount(String userId) async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(unread_count), 0) AS total
      FROM conversations
      WHERE user_id = ?
    ''', [userId]);
    return result.first['total'] as int? ?? 0;
  }

  // ── Search conversations ─────────────────────────────────────────────────

  Future<List<ConversationSummary>> searchConversations({
    required String userId,
    required String query,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT * FROM conversations
      WHERE user_id = ?
        AND peer_name LIKE ?
      ORDER BY last_message_at DESC
      LIMIT 30
    ''', [userId, '%$query%']);
    return rows.map(ConversationSummary.fromMap).toList();
  }

  // ── Ensure conversation exists ───────────────────────────────────────────

  /// Creates a conversation row if none exists between [userId] and [peerId].
  /// Returns the conversation ID (either existing or newly created).
  Future<String> ensureConversation({
    required String userId,
    required String peerId,
    required String peerName,
    String? peerPhotoUrl,
    bool isPeerLecturer = false,
  }) async {
    final db = await _db.database;

    // Check existing
    final existing = await db.query(
      'conversations',
      where: 'user_id = ? AND peer_id = ?',
      whereArgs: [userId, peerId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return existing.first['id'] as String;
    }

    // Create new
    final id = '${userId}_${peerId}_${DateTime.now().millisecondsSinceEpoch}';
    await db.insert('conversations', {
      'id': id,
      'user_id': userId,
      'peer_id': peerId,
      'peer_name': peerName,
      'peer_photo_url': peerPhotoUrl,
      'last_message': '',
      'last_message_at': DateTime.now().millisecondsSinceEpoch,
      'unread_count': 0,
      'is_peer_lecturer': isPeerLecturer ? 1 : 0,
    });

    return id;
  }
}
