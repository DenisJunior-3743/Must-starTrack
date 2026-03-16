// lib/features/messaging/bloc/message_cubit.dart
//
// MUST StarTrack — Message Cubit (Phase 4)
//
// Manages two related but distinct state machines:
//   A) ConversationList — the messages inbox screen
//   B) MessageThread    — a single chat thread
//
// Both are driven by this one cubit to minimise DI boilerplate.
// In Phase 5 a Firestore stream will replace the polling approach.
//
// States:
//   MessageInitial          — idle
//   ConversationsLoading    — loading inbox
//   ConversationsLoaded     — inbox ready, paginated
//   ThreadLoading           — loading chat messages
//   ThreadLoaded            — thread ready, paginated
//   MessageSending          — optimistic send in progress
//   MessageError            — error with context
//
// Offline-first guarantee:
//   sendMessage() writes to SQLite immediately → SyncQueueDao enqueues
//   the Firestore write. If offline the message is visible instantly
//   but marked with a pending sync indicator (extra_json: {"synced": false}).

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/dao/message_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class MessageState extends Equatable {
  const MessageState();
  @override
  List<Object?> get props => [];
}

class MessageInitial extends MessageState {
  const MessageInitial();
}

class ConversationsLoading extends MessageState {
  const ConversationsLoading();
}

class ConversationsLoaded extends MessageState {
  final List<ConversationSummary> conversations;
  final bool hasMore;

  const ConversationsLoaded({
    required this.conversations,
    this.hasMore = false,
  });

  @override
  List<Object?> get props => [conversations, hasMore];
}

class ThreadLoading extends MessageState {
  const ThreadLoading();
}

class ThreadLoaded extends MessageState {
  final String conversationId;
  final String peerName;
  final List<MessageModel> messages;
  final bool hasMore;
  final bool isLoadingMore;

  const ThreadLoaded({
    required this.conversationId,
    required this.peerName,
    required this.messages,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  ThreadLoaded copyWith({
    List<MessageModel>? messages,
    bool? hasMore,
    bool? isLoadingMore,
  }) => ThreadLoaded(
    conversationId: conversationId,
    peerName: peerName,
    messages: messages ?? this.messages,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
  );

  @override
  List<Object?> get props => [conversationId, messages, hasMore, isLoadingMore];
}

class MessageError extends MessageState {
  final String message;
  const MessageError(this.message);

  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class MessageCubit extends Cubit<MessageState> {
  final MessageDao _messageDao;
  final SyncQueueDao _syncDao;

  // inject from AuthCubit in Phase 5
  static const _currentUserId = 'current_user';
  static const _pageSize = 40;
  static const _uuid = Uuid();

  MessageCubit({
    required MessageDao messageDao,
    required SyncQueueDao syncDao,
  })  : _messageDao = messageDao,
        _syncDao = syncDao,
        super(const MessageInitial());

  // ── Load conversations ────────────────────────────────────────────────────

  Future<void> loadConversations() async {
    emit(const ConversationsLoading());
    try {
      final convos = await _messageDao.getConversations(
        userId: _currentUserId,
        pageSize: _pageSize,
      );
      emit(ConversationsLoaded(
        conversations: convos,
        hasMore: convos.length == _pageSize,
      ));
    } catch (e) {
      emit(MessageError('Failed to load conversations: $e'));
    }
  }

  // ── Load a message thread ─────────────────────────────────────────────────

  Future<void> loadThread({
    required String peerId,
    required String peerName,
    String? peerPhotoUrl,
    bool isPeerLecturer = false,
  }) async {
    emit(const ThreadLoading());

    try {
      // Ensure conversation exists (creates if first time)
      final convoId = await _messageDao.ensureConversation(
        userId: _currentUserId,
        peerId: peerId,
        peerName: peerName,
        peerPhotoUrl: peerPhotoUrl,
        isPeerLecturer: isPeerLecturer,
      );

      final messages = await _messageDao.getMessages(
        conversationId: convoId,
        pageSize: _pageSize,
      );

      // Mark as read
      await _messageDao.markConversationRead(
        conversationId: convoId,
        userId: _currentUserId,
      );

      emit(ThreadLoaded(
        conversationId: convoId,
        peerName: peerName,
        messages: messages,
        hasMore: messages.length == _pageSize,
      ));
    } catch (e) {
      emit(MessageError('Failed to load messages: $e'));
    }
  }

  // ── Load more messages (pagination) ──────────────────────────────────────

  Future<void> loadMoreMessages() async {
    final current = state;
    if (current is! ThreadLoaded || current.isLoadingMore || !current.hasMore) return;

    emit(current.copyWith(isLoadingMore: true));

    try {
      final oldest = current.messages.isNotEmpty
          ? current.messages.first.createdAt : null;

      final older = await _messageDao.getMessages(
        conversationId: current.conversationId,
        pageSize: _pageSize,
        before: oldest,
      );

      emit(current.copyWith(
        messages: [...older, ...current.messages],
        hasMore: older.length == _pageSize,
        isLoadingMore: false,
      ));
    } catch (_) {
      emit(current.copyWith(isLoadingMore: false));
    }
  }

  // ── Send a text message ───────────────────────────────────────────────────

  /// Optimistic send:
  ///   1. Build message object with generated ID
  ///   2. Append to UI immediately
  ///   3. Persist to SQLite
  ///   4. Enqueue Firestore sync
  Future<void> sendMessage(String text) async {
    final current = state;
    if (current is! ThreadLoaded) return;

    final msg = MessageModel(
      id: _uuid.v4(),
      conversationId: current.conversationId,
      senderId: _currentUserId,
      content: text.trim(),
      messageType: 'text',
      createdAt: DateTime.now(),
      isRead: false,
    );

    // 1. Optimistic append
    emit(current.copyWith(messages: [...current.messages, msg]));

    try {
      // 2. Persist locally
      await _messageDao.insertMessage(msg);

      // 3. Enqueue remote sync
      await _syncDao.enqueue(
        entity: 'message',
        entityId: msg.id,
        operation: 'create',
        payload: {
          'conversation_id': msg.conversationId,
          'sender_id': msg.senderId,
          'content': msg.content,
          'message_type': msg.messageType,
          'created_at': msg.createdAt.toIso8601String(),
        },
      );
    } catch (e) {
      // Rollback optimistic message on failure
      final rolled = (state as ThreadLoaded).messages
          .where((m) => m.id != msg.id).toList();
      emit((state as ThreadLoaded).copyWith(messages: rolled));
    }
  }

  // ── Delete a message ──────────────────────────────────────────────────────

  Future<void> deleteMessage(String messageId) async {
    final current = state;
    if (current is! ThreadLoaded) return;

    // Optimistic remove
    final updated = current.messages.where((m) => m.id != messageId).toList();
    emit(current.copyWith(messages: updated));

    await _messageDao.deleteMessage(messageId);
    await _syncDao.enqueue(
      entity: 'message',
      entityId: messageId,
      operation: 'delete',
      payload: {},
    );
  }

  // ── Search conversations ──────────────────────────────────────────────────

  Future<void> searchConversations(String query) async {
    if (query.trim().isEmpty) {
      await loadConversations();
      return;
    }
    try {
      final results = await _messageDao.searchConversations(
        userId: _currentUserId,
        query: query,
      );
      emit(ConversationsLoaded(conversations: results));
    } catch (e) {
      emit(MessageError('Search failed: $e'));
    }
  }
}
