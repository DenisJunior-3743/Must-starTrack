import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';
import '../schema/database_schema.dart';

class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String messageType;
  final String? fileUrl;
  final String? fileName;
  final String? fileSize;
  final DateTime createdAt;
  final bool isRead;
  final bool isDeleted;
  final String? replyToId;
  final String? replyToPreview;

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
    this.replyToId,
    this.replyToPreview,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) => MessageModel(
        id: map['id'] as String,
        conversationId: (map['conversation_id'] ?? map['thread_id']) as String,
        senderId: map['sender_id'] as String,
        content: map['content'] as String? ?? '',
        messageType: map['message_type'] as String? ?? 'text',
        fileUrl: map['file_url'] as String? ?? map['media_url'] as String?,
        fileName: map['file_name'] as String?,
        fileSize: map['file_size'] as String?,
        createdAt: _dateFromDb(map['created_at'] ?? map['sent_at']),
        isRead:
            (map['is_read'] as int? ?? (map['read_at'] != null ? 1 : 0)) == 1,
        isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
        replyToId: map['reply_to_id'] as String?,
        replyToPreview: map['reply_to_preview'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'thread_id': conversationId,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': content,
        'message_type': messageType,
        'file_url': fileUrl,
        'file_name': fileName,
        'file_size': fileSize,
        'media_url': fileUrl,
        'created_at': createdAt.millisecondsSinceEpoch,
        'sent_at': createdAt.toIso8601String(),
        'status': isRead ? 'read' : 'sent',
        'is_read': isRead ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
        'reply_to_id': replyToId,
        'reply_to_preview': replyToPreview,
      };

  static DateTime _dateFromDb(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      final numeric = int.tryParse(value);
      if (numeric != null) {
        return DateTime.fromMillisecondsSinceEpoch(numeric);
      }
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return DateTime.now();
  }
}

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

  factory ConversationSummary.fromMap(Map<String, dynamic> map) =>
      ConversationSummary(
        id: map['id'] as String,
        peerId: map['peer_id'] as String,
        peerName: map['peer_name'] as String? ?? 'Unknown',
        peerPhotoUrl: map['peer_photo_url'] as String?,
        lastMessage: map['last_message'] as String? ?? '',
        lastMessageAt: MessageModel._dateFromDb(map['last_message_at']),
        unreadCount: map['unread_count'] as int? ?? 0,
        isPeerLecturer: (map['is_peer_lecturer'] as int? ?? 0) == 1,
      );
}

class CollaborationInboxItem {
  final String id;
  final String counterpartId;
  final String counterpartName;
  final String? counterpartPhotoUrl;
  final String? postId;
  final String postTitle;
  final String message;
  final String status;
  final bool isIncoming;
  final DateTime createdAt;
  final DateTime? receiverViewedAt;
  final double? aiFitScore;
  final List<String> aiReasons;
  final List<String> aiMatchedSkills;

  const CollaborationInboxItem({
    required this.id,
    required this.counterpartId,
    required this.counterpartName,
    this.counterpartPhotoUrl,
    this.postId,
    required this.postTitle,
    required this.message,
    required this.status,
    required this.isIncoming,
    required this.createdAt,
    this.receiverViewedAt,
    this.aiFitScore,
    this.aiReasons = const [],
    this.aiMatchedSkills = const [],
  });

  CollaborationInboxItem copyWith({
    DateTime? receiverViewedAt,
    double? aiFitScore,
    List<String>? aiReasons,
    List<String>? aiMatchedSkills,
  }) {
    return CollaborationInboxItem(
      id: id,
      counterpartId: counterpartId,
      counterpartName: counterpartName,
      counterpartPhotoUrl: counterpartPhotoUrl,
      postId: postId,
      postTitle: postTitle,
      message: message,
      status: status,
      isIncoming: isIncoming,
      createdAt: createdAt,
      receiverViewedAt: receiverViewedAt ?? this.receiverViewedAt,
      aiFitScore: aiFitScore ?? this.aiFitScore,
      aiReasons: aiReasons ?? this.aiReasons,
      aiMatchedSkills: aiMatchedSkills ?? this.aiMatchedSkills,
    );
  }
}

class AcceptedPeerCollaboration {
  final String requestId;
  final String peerId;
  final String peerName;
  final String? peerPhotoUrl;
  final String peerRole;
  final String? postId;
  final String postTitle;
  final String? postCategory;
  final List<String> postMediaUrls;
  final String message;
  final DateTime acceptedAt;

  const AcceptedPeerCollaboration({
    required this.requestId,
    required this.peerId,
    required this.peerName,
    this.peerPhotoUrl,
    required this.peerRole,
    this.postId,
    required this.postTitle,
    this.postCategory,
    this.postMediaUrls = const [],
    required this.message,
    required this.acceptedAt,
  });
}

class MessageDao {
  final _db = DatabaseHelper.instance;

  Future<void> _ensureThreadRecord({
    required Database db,
    required String conversationId,
    required String userId,
    required String peerId,
  }) async {
    final existing = await db.query(
      DatabaseSchema.tableMessageThreads,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return;
    }

    final now = DateTime.now().toIso8601String();
    await db.insert(DatabaseSchema.tableMessageThreads, {
      'id': conversationId,
      'participant_ids': '[$userId,$peerId]',
      'last_message_id': null,
      'last_message_text': '',
      'last_message_at': now,
      'unread_count': 0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 0,
    });
  }

  Future<void> insertMessage(MessageModel message) async {
    final db = await _db.database;
    final previewText = _conversationPreviewText(message);

    await db.transaction((txn) async {
      final existingRows = await txn.query(
        DatabaseSchema.tableMessages,
        columns: ['is_read'],
        where: 'id = ?',
        whereArgs: [message.id],
        limit: 1,
      );
      final wasAlreadyStored = existingRows.isNotEmpty;
      final existingWasRead =
          wasAlreadyStored && (existingRows.first['is_read'] as int? ?? 0) == 1;
      final storedMessage = existingWasRead && !message.isRead
          ? MessageModel(
              id: message.id,
              conversationId: message.conversationId,
              senderId: message.senderId,
              content: message.content,
              messageType: message.messageType,
              fileUrl: message.fileUrl,
              fileName: message.fileName,
              fileSize: message.fileSize,
              createdAt: message.createdAt,
              isRead: true,
              isDeleted: message.isDeleted,
              replyToId: message.replyToId,
              replyToPreview: message.replyToPreview,
            )
          : message;

      await txn.insert(
        DatabaseSchema.tableMessages,
        storedMessage.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.rawUpdate('''
        UPDATE ${DatabaseSchema.tableConversations}
        SET last_message = ?,
            last_message_at = ?,
            updated_at = ?,
            unread_count = CASE
              WHEN user_id != ? AND ? = 0 AND ? = 0 THEN unread_count + 1
              WHEN user_id = ? THEN 0
              ELSE unread_count
            END
        WHERE id = ?
      ''', [
        previewText.length > 80
            ? '${previewText.substring(0, 80)}…'
            : previewText,
        message.createdAt.millisecondsSinceEpoch,
        message.createdAt.toIso8601String(),
        message.senderId,
        wasAlreadyStored ? 1 : 0,
        storedMessage.isRead ? 1 : 0,
        message.senderId,
        message.conversationId,
      ]);
    });
  }

  Future<void> updateMessageMedia({
    required String messageId,
    required String fileUrl,
    String? fileName,
    String? fileSize,
  }) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tableMessages,
      {
        'file_url': fileUrl,
        'media_url': fileUrl,
        'file_name': fileName,
        'file_size': fileSize,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  String _conversationPreviewText(MessageModel message) {
    if (message.messageType == 'audio') {
      return 'Voice message';
    }
    return message.content;
  }

  Future<List<ConversationSummary>> getConversations({
    required String userId,
    int pageSize = 30,
    DateTime? before,
  }) async {
    final db = await _db.database;
    await _recalculateUnreadCountsForUser(db, userId);
    final whereArgs = <dynamic>[userId];
    var cursorClause = '';
    if (before != null) {
      cursorClause = 'AND last_message_at < ?';
      whereArgs.add(before.millisecondsSinceEpoch);
    }

    final rows = await db.rawQuery('''
      SELECT * FROM ${DatabaseSchema.tableConversations}
      WHERE user_id = ? $cursorClause
      ORDER BY COALESCE(last_message_at, 0) DESC
      LIMIT ?
    ''', [...whereArgs, pageSize]);

    return rows.map(ConversationSummary.fromMap).toList();
  }

  Future<List<MessageModel>> getMessages({
    required String conversationId,
    int pageSize = 40,
    DateTime? before,
  }) async {
    final db = await _db.database;
    final whereArgs = <dynamic>[conversationId, 0];
    var cursorClause = '';
    if (before != null) {
      cursorClause = 'AND created_at < ?';
      whereArgs.add(before.millisecondsSinceEpoch);
    }

    final rows = await db.rawQuery('''
      SELECT * FROM ${DatabaseSchema.tableMessages}
      WHERE conversation_id = ?
        AND is_deleted = ?
        $cursorClause
      ORDER BY created_at DESC
      LIMIT ?
    ''', [...whereArgs, pageSize]);

    return rows.reversed.map(MessageModel.fromMap).toList();
  }

  Future<void> markConversationRead({
    required String conversationId,
    required String userId,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        DatabaseSchema.tableConversations,
        {
          'unread_count': 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND user_id = ?',
        whereArgs: [conversationId, userId],
      );

      await txn.rawUpdate('''
        UPDATE ${DatabaseSchema.tableMessages}
        SET is_read = 1,
            read_at = COALESCE(read_at, ?),
            status = 'read'
        WHERE conversation_id = ?
          AND sender_id != ?
          AND is_read = 0
      ''', [DateTime.now().toIso8601String(), conversationId, userId]);
    });
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tableMessages,
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> deleteConversation(String conversationId) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        DatabaseSchema.tableMessages,
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );
      await txn.delete(
        DatabaseSchema.tableConversations,
        where: 'id = ?',
        whereArgs: [conversationId],
      );
      await txn.delete(
        DatabaseSchema.tableMessageThreads,
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
  }

  Future<int> getTotalUnreadCount(String userId) async {
    final db = await _db.database;
    await _recalculateUnreadCountsForUser(db, userId);
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(unread_count), 0) AS total
      FROM ${DatabaseSchema.tableConversations}
      WHERE user_id = ?
    ''', [userId]);
    return result.first['total'] as int? ?? 0;
  }

  Future<void> _recalculateUnreadCountsForUser(
    DatabaseExecutor db,
    String userId,
  ) async {
    await db.rawUpdate('''
      UPDATE ${DatabaseSchema.tableConversations}
      SET unread_count = (
        SELECT COUNT(*)
        FROM ${DatabaseSchema.tableMessages} m
        WHERE m.conversation_id = ${DatabaseSchema.tableConversations}.id
          AND m.sender_id != ?
          AND COALESCE(m.is_read, 0) = 0
          AND COALESCE(m.is_deleted, 0) = 0
      )
      WHERE user_id = ?
    ''', [userId, userId]);
  }

  /// Zeroes the unread badge for every conversation belonging to [userId].
  /// Called when the user opens the inbox list so the bottom-nav badge clears.
  Future<void> markAllConversationsAsViewed(String userId) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.rawUpdate('''
        UPDATE ${DatabaseSchema.tableMessages}
        SET is_read = 1,
            read_at = COALESCE(read_at, ?),
            status = 'read'
        WHERE sender_id != ?
          AND is_read = 0
          AND conversation_id IN (
            SELECT id
            FROM ${DatabaseSchema.tableConversations}
            WHERE user_id = ?
          )
      ''', [now, userId, userId]);

      await txn.update(
        DatabaseSchema.tableConversations,
        {
          'unread_count': 0,
          'updated_at': now,
        },
        where: 'user_id = ? AND unread_count > 0',
        whereArgs: [userId],
      );
    });
  }

  Future<List<ConversationSummary>> searchConversations({
    required String userId,
    required String query,
  }) async {
    final db = await _db.database;
    await _recalculateUnreadCountsForUser(db, userId);
    final rows = await db.rawQuery('''
      SELECT * FROM ${DatabaseSchema.tableConversations}
      WHERE user_id = ?
        AND peer_name LIKE ?
      ORDER BY COALESCE(last_message_at, 0) DESC
      LIMIT 30
    ''', [userId, '%$query%']);
    return rows.map(ConversationSummary.fromMap).toList();
  }

  Future<String> ensureConversation({
    required String userId,
    required String peerId,
    required String peerName,
    String? peerPhotoUrl,
    bool isPeerLecturer = false,
  }) async {
    if (userId.trim().isEmpty ||
        peerId.trim().isEmpty ||
        userId.trim() == peerId.trim()) {
      throw ArgumentError('Cannot create a conversation with yourself.');
    }

    final db = await _db.database;
    final existing = await db.query(
      DatabaseSchema.tableConversations,
      where: 'user_id = ? AND peer_id = ?',
      whereArgs: [userId, peerId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final conversationId = existing.first['id'] as String;
      await _ensureThreadRecord(
        db: db,
        conversationId: conversationId,
        userId: userId,
        peerId: peerId,
      );
      return conversationId;
    }

    final now = DateTime.now();
    final id = '${userId}_${peerId}_${now.millisecondsSinceEpoch}';
    await db.insert(DatabaseSchema.tableConversations, {
      'id': id,
      'user_id': userId,
      'peer_id': peerId,
      'peer_name': peerName,
      'peer_photo_url': peerPhotoUrl,
      'last_message': '',
      'last_message_at': now.millisecondsSinceEpoch,
      'unread_count': 0,
      'is_peer_lecturer': isPeerLecturer ? 1 : 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await _ensureThreadRecord(
      db: db,
      conversationId: id,
      userId: userId,
      peerId: peerId,
    );

    return id;
  }

  Future<List<CollaborationInboxItem>> getCollaborationRequests({
    required String userId,
    bool incomingOnly = true,
    int limit = 40,
  }) async {
    final db = await _db.database;
    final whereClause = incomingOnly
        ? 'r.receiver_id = ?'
        : '(r.sender_id = ? OR r.receiver_id = ?)';
    final whereArgs =
        incomingOnly ? <Object?>[userId] : <Object?>[userId, userId];
    final rows = await db.rawQuery('''
      SELECT
        r.id,
        r.post_id,
        r.message,
        r.status,
        r.receiver_viewed_at,
        r.created_at,
        r.updated_at,
        CASE WHEN r.receiver_id = ? THEN 1 ELSE 0 END AS is_incoming,
        CASE WHEN r.receiver_id = ? THEN r.sender_id ELSE r.receiver_id END AS counterpart_id,
        CASE
          WHEN r.receiver_id = ? THEN COALESCE(us.display_name, us.email, 'Someone')
          ELSE COALESCE(ur.display_name, ur.email, 'Someone')
        END AS counterpart_name,
        CASE WHEN r.receiver_id = ? THEN us.photo_url ELSE ur.photo_url END AS counterpart_photo_url,
        COALESCE(p.title, 'Project request') AS post_title
      FROM ${DatabaseSchema.tableCollabRequests} r
      LEFT JOIN ${DatabaseSchema.tableUsers} us ON us.id = r.sender_id
      LEFT JOIN ${DatabaseSchema.tableUsers} ur ON ur.id = r.receiver_id
      LEFT JOIN ${DatabaseSchema.tablePosts} p ON p.id = r.post_id
      WHERE $whereClause
        AND COALESCE(r.sender_id, '') != COALESCE(r.receiver_id, '')
      ORDER BY COALESCE(r.updated_at, r.created_at) DESC
      LIMIT ?
    ''', [
      userId,
      userId,
      userId,
      userId,
      ...whereArgs,
      limit,
    ]);

    return rows
        .map(
          (row) => CollaborationInboxItem(
            id: row['id'] as String,
            counterpartId: row['counterpart_id'] as String? ?? '',
            counterpartName: row['counterpart_name'] as String? ?? 'Someone',
            counterpartPhotoUrl: row['counterpart_photo_url'] as String?,
            postId: row['post_id'] as String?,
            postTitle: row['post_title'] as String? ?? 'Project request',
            message: row['message'] as String? ?? '',
            status: row['status'] as String? ?? 'pending',
            isIncoming: (row['is_incoming'] as int? ?? 0) == 1,
            receiverViewedAt: row['receiver_viewed_at'] == null
                ? null
                : DateTime.tryParse(row['receiver_viewed_at'] as String),
            createdAt: MessageModel._dateFromDb(
                row['updated_at'] ?? row['created_at']),
          ),
        )
        .toList();
  }

  Future<void> markCollaborationRequestViewed({
    required String requestId,
    required String userId,
  }) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tableCollabRequests,
      {
        'receiver_viewed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND receiver_id = ? AND receiver_viewed_at IS NULL',
      whereArgs: [requestId, userId],
    );
  }

  Future<void> markAllIncomingRequestsViewed(String userId) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tableCollabRequests,
      {
        'receiver_viewed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'receiver_id = ? AND receiver_viewed_at IS NULL',
      whereArgs: [userId],
    );
  }

  Future<int> countUnviewedIncomingRequests(String userId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM ${DatabaseSchema.tableCollabRequests}
      WHERE receiver_id = ?
        AND receiver_viewed_at IS NULL
    ''', [userId]);
    return rows.first['total'] as int? ?? 0;
  }

  Future<List<AcceptedPeerCollaboration>> getAcceptedCollaborators({
    required String userId,
    int limit = 60,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        r.id,
        r.post_id,
        r.message,
        r.updated_at,
        CASE WHEN r.receiver_id = ? THEN r.sender_id ELSE r.receiver_id END AS peer_id,
        CASE
          WHEN r.receiver_id = ? THEN COALESCE(us.display_name, us.email, 'Someone')
          ELSE COALESCE(ur.display_name, ur.email, 'Someone')
        END AS peer_name,
        CASE WHEN r.receiver_id = ? THEN us.photo_url ELSE ur.photo_url END AS peer_photo_url,
        CASE WHEN r.receiver_id = ? THEN COALESCE(us.role, 'student') ELSE COALESCE(ur.role, 'student') END AS peer_role,
        COALESCE(p.title, 'Untitled project') AS post_title,
        p.category AS post_category,
        p.images AS post_images,
        p.videos AS post_videos
      FROM ${DatabaseSchema.tableCollabRequests} r
      LEFT JOIN ${DatabaseSchema.tableUsers} us ON us.id = r.sender_id
      LEFT JOIN ${DatabaseSchema.tableUsers} ur ON ur.id = r.receiver_id
      LEFT JOIN ${DatabaseSchema.tablePosts} p ON p.id = r.post_id
      WHERE (r.sender_id = ? OR r.receiver_id = ?)
        AND COALESCE(r.sender_id, '') != COALESCE(r.receiver_id, '')
        AND r.status = 'accepted'
      ORDER BY COALESCE(r.updated_at, r.created_at) DESC
      LIMIT ?
    ''', [userId, userId, userId, userId, userId, userId, limit]);

    List<String> parseList(dynamic value) {
      if (value is String && value.isNotEmpty) {
        try {
          return List<String>.from(jsonDecode(value) as List);
        } catch (_) {
          return const [];
        }
      }
      if (value is List) {
        return value.map((entry) => entry.toString()).toList();
      }
      return const [];
    }

    return rows
        .map(
          (row) => AcceptedPeerCollaboration(
            requestId: row['id'] as String,
            peerId: row['peer_id'] as String? ?? '',
            peerName: row['peer_name'] as String? ?? 'Someone',
            peerPhotoUrl: row['peer_photo_url'] as String?,
            peerRole: row['peer_role'] as String? ?? 'student',
            postId: row['post_id'] as String?,
            postTitle: row['post_title'] as String? ?? 'Untitled project',
            postCategory: row['post_category'] as String?,
            postMediaUrls: [
              ...parseList(row['post_images']),
              ...parseList(row['post_videos']),
            ],
            message: row['message'] as String? ?? '',
            acceptedAt: MessageModel._dateFromDb(row['updated_at']),
          ),
        )
        .toList();
  }
}
