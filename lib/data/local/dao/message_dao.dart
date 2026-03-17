import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';

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
  final int syncStatus;

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
    this.syncStatus = 0,
  });

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
        syncStatus: m['sync_status'] as int? ?? 0,
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
        'sync_status': syncStatus,
      };

  MessageModel copyWith({
    bool? isRead,
    bool? isDeleted,
    int? syncStatus,
  }) {
    return MessageModel(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      messageType: messageType,
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      isDeleted: isDeleted ?? this.isDeleted,
      syncStatus: syncStatus ?? this.syncStatus,
    );
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

  factory ConversationSummary.fromMap(Map<String, dynamic> m) =>
      ConversationSummary(
        id: m['id'] as String,
        peerId: m['peer_id'] as String,
        peerName: m['peer_name'] as String,
        peerPhotoUrl: m['peer_photo_url'] as String?,
        lastMessage: m['last_message'] as String? ?? '',
        lastMessageAt:
            DateTime.fromMillisecondsSinceEpoch(m['last_message_at'] as int),
        unreadCount: m['unread_count'] as int? ?? 0,
        isPeerLecturer: (m['is_peer_lecturer'] as int? ?? 0) == 1,
      );
}

class MessageDao {
  final _db = DatabaseHelper.instance;

  final Map<String, StreamController<List<ConversationSummary>>>
      _conversationWatchers = {};
  final Map<String, StreamController<List<MessageModel>>> _threadWatchers = {};

  String _deterministicConversationId(String userId, String peerId) {
    final pair = [userId, peerId]..sort();
    return '${pair.first}_${pair.last}';
  }

  Future<void> insertMessage(MessageModel message) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.rawUpdate(
        '''
        UPDATE conversations
        SET last_message = ?,
            last_message_at = ?,
            updated_at = ?,
            unread_count = CASE
              WHEN user_id = ? THEN unread_count
              ELSE unread_count + 1
            END
        WHERE id = ?
      ''',
        [
          message.content.length > 80
              ? '${message.content.substring(0, 80)}...'
              : message.content,
          message.createdAt.millisecondsSinceEpoch,
          DateTime.now().toIso8601String(),
          message.senderId,
          message.conversationId,
        ],
      );
    });

    await _notifyConversationById(message.conversationId);
    await _notifyThread(message.conversationId);
  }

  Future<void> upsertIncomingMessage({
    required MessageModel message,
    required String currentUserId,
  }) async {
    final db = await _db.database;

    await db.transaction((txn) async {
      await txn.insert(
        'messages',
        message.copyWith(syncStatus: 1).toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      final unreadDelta = message.senderId == currentUserId ? 0 : 1;
      await txn.rawUpdate(
        '''
        UPDATE conversations
        SET last_message = ?,
            last_message_at = ?,
            updated_at = ?,
            unread_count = unread_count + ?
        WHERE id = ? AND user_id = ?
      ''',
        [
          message.content.length > 80
              ? '${message.content.substring(0, 80)}...'
              : message.content,
          message.createdAt.millisecondsSinceEpoch,
          DateTime.now().toIso8601String(),
          unreadDelta,
          message.conversationId,
          currentUserId,
        ],
      );
    });

    await _notifyConversationById(message.conversationId);
    await _notifyThread(message.conversationId);
  }

  Future<void> markMessageSyncStatus(String messageId, int syncStatus) async {
    final db = await _db.database;
    await db.update(
      'messages',
      {'sync_status': syncStatus},
      where: 'id = ?',
      whereArgs: [messageId],
    );

    final row = await db.query(
      'messages',
      columns: ['conversation_id'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (row.isNotEmpty) {
      final conversationId = row.first['conversation_id'] as String;
      await _notifyThread(conversationId);
    }
  }

  Future<List<ConversationSummary>> getConversations({
    required String userId,
    int pageSize = 30,
    DateTime? before,
  }) async {
    final db = await _db.database;
    final whereArgs = <dynamic>[userId];
    var cursorClause = '';
    if (before != null) {
      cursorClause = 'AND last_message_at < ?';
      whereArgs.add(before.millisecondsSinceEpoch);
    }

    final rows = await db.rawQuery(
      '''
      SELECT * FROM conversations
      WHERE user_id = ? $cursorClause
      ORDER BY last_message_at DESC
      LIMIT ?
    ''',
      [...whereArgs, pageSize],
    );

    return rows.map(ConversationSummary.fromMap).toList();
  }

  Stream<List<ConversationSummary>> watchConversations(String userId) {
    final controller = _conversationWatchers.putIfAbsent(
        userId, () => StreamController.broadcast());
    unawaited(_notifyConversations(userId));
    return controller.stream;
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

    final rows = await db.rawQuery(
      '''
      SELECT * FROM messages
      WHERE conversation_id = ?
        AND is_deleted = ?
        $cursorClause
      ORDER BY created_at DESC
      LIMIT ?
    ''',
      [...whereArgs, pageSize],
    );

    return rows.reversed.map(MessageModel.fromMap).toList();
  }

  Stream<List<MessageModel>> watchMessages(String conversationId) {
    final controller = _threadWatchers.putIfAbsent(
      conversationId,
      () => StreamController.broadcast(),
    );
    unawaited(_notifyThread(conversationId));
    return controller.stream;
  }

  Future<void> markConversationRead({
    required String conversationId,
    required String userId,
  }) async {
    final db = await _db.database;

    await db.transaction((txn) async {
      await txn.update(
        'conversations',
        {
          'unread_count': 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND user_id = ?',
        whereArgs: [conversationId, userId],
      );

      await txn.rawUpdate(
        '''
        UPDATE messages
        SET is_read = 1
        WHERE conversation_id = ?
          AND sender_id != ?
          AND is_read = 0
      ''',
        [conversationId, userId],
      );
    });

    await _notifyConversations(userId);
    await _notifyThread(conversationId);
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await _db.database;
    final rows = await db.query(
      'messages',
      columns: ['conversation_id'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final conversationId = rows.first['conversation_id'] as String;
    await db.update(
      'messages',
      {'is_deleted': 1, 'sync_status': 0},
      where: 'id = ?',
      whereArgs: [messageId],
    );

    await _recalculateConversationPreview(conversationId);
    await _notifyConversationById(conversationId);
    await _notifyThread(conversationId);
  }

  Future<void> deleteConversation({
    required String conversationId,
    required String userId,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );
      await txn.delete(
        'conversations',
        where: 'id = ? AND user_id = ?',
        whereArgs: [conversationId, userId],
      );
    });

    await _notifyConversations(userId);
    await _notifyThread(conversationId);
  }

  Future<List<String>> getMessageIds(String conversationId) async {
    final db = await _db.database;
    final rows = await db.query(
      'messages',
      columns: ['id'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
    return rows.map((row) => row['id'] as String).toList();
  }

  Future<int> getTotalUnreadCount(String userId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(unread_count), 0) AS total
      FROM conversations
      WHERE user_id = ?
    ''',
      [userId],
    );
    return result.first['total'] as int? ?? 0;
  }

  Future<List<ConversationSummary>> searchConversations({
    required String userId,
    required String query,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT * FROM conversations
      WHERE user_id = ?
        AND peer_name LIKE ?
      ORDER BY last_message_at DESC
      LIMIT 30
    ''',
      [userId, '%$query%'],
    );
    return rows.map(ConversationSummary.fromMap).toList();
  }

  Future<ConversationSummary?> getConversationById({
    required String conversationId,
    required String userId,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'conversations',
      where: 'id = ? AND user_id = ?',
      whereArgs: [conversationId, userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ConversationSummary.fromMap(rows.first);
  }

  Future<String> ensureConversation({
    required String userId,
    required String peerId,
    required String peerName,
    String? peerPhotoUrl,
    bool isPeerLecturer = false,
  }) async {
    final db = await _db.database;

    final existing = await db.query(
      'conversations',
      where: 'user_id = ? AND peer_id = ?',
      whereArgs: [userId, peerId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final conversationId = existing.first['id'] as String;
      await db.update(
        'conversations',
        {
          'peer_name': peerName,
          'peer_photo_url': peerPhotoUrl,
          'is_peer_lecturer': isPeerLecturer ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [conversationId],
      );
      await _notifyConversations(userId);
      return conversationId;
    }

    final id = _deterministicConversationId(userId, peerId);
    final now = DateTime.now();
    await db.insert(
        'conversations',
        {
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
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    await _notifyConversations(userId);
    return id;
  }

  Future<void> _recalculateConversationPreview(String conversationId) async {
    final db = await _db.database;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ? AND is_deleted = 0',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      await db.update(
        'conversations',
        {
          'last_message': '',
          'last_message_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [conversationId],
      );
      return;
    }

    final latest = MessageModel.fromMap(rows.first);
    await db.update(
      'conversations',
      {
        'last_message': latest.content.length > 80
            ? '${latest.content.substring(0, 80)}...'
            : latest.content,
        'last_message_at': latest.createdAt.millisecondsSinceEpoch,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> _notifyConversations(String userId) async {
    final controller = _conversationWatchers[userId];
    if (controller == null || controller.isClosed) return;
    final convos = await getConversations(userId: userId, pageSize: 200);
    controller.add(convos);
  }

  Future<void> _notifyConversationById(String conversationId) async {
    final db = await _db.database;
    final rows = await db.query(
      'conversations',
      columns: ['user_id'],
      where: 'id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final userId = rows.first['user_id'] as String;
      await _notifyConversations(userId);
    }
  }

  Future<void> _notifyThread(String conversationId) async {
    final controller = _threadWatchers[conversationId];
    if (controller == null || controller.isClosed) return;
    final messages =
        await getMessages(conversationId: conversationId, pageSize: 200);
    controller.add(messages);
  }

  Future<void> dispose() async {
    for (final watcher in _conversationWatchers.values) {
      await watcher.close();
    }
    _conversationWatchers.clear();
    for (final watcher in _threadWatchers.values) {
      await watcher.close();
    }
    _threadWatchers.clear();
  }
}
