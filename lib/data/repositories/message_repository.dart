import 'dart:async';

import 'package:uuid/uuid.dart';

import '../local/dao/message_dao.dart';
import '../local/dao/sync_queue_dao.dart';
import '../remote/firestore_service.dart';

class ThreadSnapshot {
  final String conversationId;
  final String peerName;
  final List<MessageModel> messages;
  final bool hasMore;

  const ThreadSnapshot({
    required this.conversationId,
    required this.peerName,
    required this.messages,
    required this.hasMore,
  });
}

abstract class MessageRepository {
  Stream<List<ConversationSummary>> watchConversations(String userId);

  Future<List<ConversationSummary>> loadConversations({
    required String userId,
    int pageSize,
  });

  Future<List<ConversationSummary>> searchConversations({
    required String userId,
    required String query,
  });

  Future<ThreadSnapshot> openThread({
    required String userId,
    required String threadOrPeerId,
    required String peerName,
    String? peerPhotoUrl,
    bool isPeerLecturer,
    int pageSize,
  });

  Stream<List<MessageModel>> watchMessages({
    required String userId,
    required String conversationId,
  });

  Future<List<MessageModel>> loadMoreMessages({
    required String conversationId,
    required DateTime before,
    int pageSize,
  });

  Future<void> sendMessage({
    required String userId,
    required String conversationId,
    required String text,
  });

  Future<void> deleteMessage({
    required String messageId,
    required String conversationId,
  });

  Future<void> deleteConversation({
    required String userId,
    required String conversationId,
  });

  Future<void> markConversationRead({
    required String userId,
    required String conversationId,
  });
}

class MessageRepositoryImpl implements MessageRepository {
  static const _pageSize = 40;
  static const _uuid = Uuid();

  final MessageDao _dao;
  final SyncQueueDao _syncDao;
  final FirestoreService _firestore;
  final Map<String, StreamSubscription<List<MessageModel>>> _remoteSubs = {};

  MessageRepositoryImpl({
    required MessageDao dao,
    required SyncQueueDao syncDao,
    required FirestoreService firestore,
  })  : _dao = dao,
        _syncDao = syncDao,
        _firestore = firestore;

  @override
  Stream<List<ConversationSummary>> watchConversations(String userId) {
    return _dao.watchConversations(userId);
  }

  @override
  Future<List<ConversationSummary>> loadConversations({
    required String userId,
    int pageSize = _pageSize,
  }) {
    return _dao.getConversations(userId: userId, pageSize: pageSize);
  }

  @override
  Future<List<ConversationSummary>> searchConversations({
    required String userId,
    required String query,
  }) {
    return _dao.searchConversations(userId: userId, query: query);
  }

  @override
  Future<ThreadSnapshot> openThread({
    required String userId,
    required String threadOrPeerId,
    required String peerName,
    String? peerPhotoUrl,
    bool isPeerLecturer = false,
    int pageSize = _pageSize,
  }) async {
    final existing = await _dao.getConversationById(
      conversationId: threadOrPeerId,
      userId: userId,
    );

    final conversationId = existing?.id ??
        await _dao.ensureConversation(
          userId: userId,
          peerId: threadOrPeerId,
          peerName: peerName.isEmpty ? 'Unknown' : peerName,
          peerPhotoUrl: peerPhotoUrl,
          isPeerLecturer: isPeerLecturer,
        );

    await markConversationRead(userId: userId, conversationId: conversationId);
    final messages = await _dao.getMessages(
        conversationId: conversationId, pageSize: pageSize);

    return ThreadSnapshot(
      conversationId: conversationId,
      peerName: existing?.peerName ?? peerName,
      messages: messages,
      hasMore: messages.length == pageSize,
    );
  }

  @override
  Stream<List<MessageModel>> watchMessages({
    required String userId,
    required String conversationId,
  }) {
    _remoteSubs[conversationId]?.cancel();
    _remoteSubs[conversationId] =
        _firestore.watchMessages(conversationId).listen((remoteMessages) async {
      for (final message in remoteMessages) {
        await _dao.upsertIncomingMessage(
          message: message,
          currentUserId: userId,
        );
      }
    });
    return _dao.watchMessages(conversationId);
  }

  @override
  Future<List<MessageModel>> loadMoreMessages({
    required String conversationId,
    required DateTime before,
    int pageSize = _pageSize,
  }) {
    return _dao.getMessages(
      conversationId: conversationId,
      pageSize: pageSize,
      before: before,
    );
  }

  @override
  Future<void> sendMessage({
    required String userId,
    required String conversationId,
    required String text,
  }) async {
    final message = MessageModel(
      id: _uuid.v4(),
      conversationId: conversationId,
      senderId: userId,
      content: text.trim(),
      messageType: 'text',
      createdAt: DateTime.now(),
      isRead: false,
      syncStatus: 0,
    );

    await _dao.insertMessage(message);
    await _syncDao.enqueue(
      entity: 'message',
      entityId: message.id,
      operation: 'create',
      payload: {
        'conversation_id': message.conversationId,
        'sender_id': message.senderId,
        'content': message.content,
        'message_type': message.messageType,
        'created_at': message.createdAt.toIso8601String(),
      },
    );
  }

  @override
  Future<void> deleteMessage({
    required String messageId,
    required String conversationId,
  }) async {
    await _dao.deleteMessage(messageId);
    await _syncDao.enqueue(
      entity: 'message',
      entityId: messageId,
      operation: 'delete',
      payload: {'conversation_id': conversationId},
    );
  }

  @override
  Future<void> deleteConversation({
    required String userId,
    required String conversationId,
  }) async {
    final messageIds = await _dao.getMessageIds(conversationId);
    await _dao.deleteConversation(
        conversationId: conversationId, userId: userId);
    for (final messageId in messageIds) {
      await _syncDao.enqueue(
        entity: 'message',
        entityId: messageId,
        operation: 'delete',
        payload: {'conversation_id': conversationId},
      );
    }
  }

  @override
  Future<void> markConversationRead({
    required String userId,
    required String conversationId,
  }) {
    return _dao.markConversationRead(
      conversationId: conversationId,
      userId: userId,
    );
  }

  Future<void> dispose() async {
    for (final sub in _remoteSubs.values) {
      await sub.cancel();
    }
    _remoteSubs.clear();
  }
}
