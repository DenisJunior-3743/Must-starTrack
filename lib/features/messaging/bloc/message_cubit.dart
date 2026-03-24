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
import '../../../data/local/dao/user_dao.dart';
import '../../../data/remote/sync_service.dart';
import '../../auth/bloc/auth_cubit.dart';

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
  final List<CollaborationInboxItem> requests;
  final bool hasMore;

  const ConversationsLoaded({
    required this.conversations,
    this.requests = const [],
    this.hasMore = false,
  });

  @override
  List<Object?> get props => [conversations, requests, hasMore];
}

class ThreadLoading extends MessageState {
  const ThreadLoading();
}

class ThreadLoaded extends MessageState {
  final String conversationId;
  final String peerId;
  final String peerName;
  final String? peerPhotoUrl;
  final bool isPeerLecturer;
  final List<MessageModel> messages;
  final bool hasMore;
  final bool isLoadingMore;

  const ThreadLoaded({
    required this.conversationId,
    required this.peerId,
    required this.peerName,
    this.peerPhotoUrl,
    this.isPeerLecturer = false,
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
    peerId: peerId,
    peerName: peerName,
    peerPhotoUrl: peerPhotoUrl,
    isPeerLecturer: isPeerLecturer,
    messages: messages ?? this.messages,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
  );

  @override
  List<Object?> get props => [
        conversationId,
        peerId,
        peerName,
        peerPhotoUrl,
        isPeerLecturer,
        messages,
        hasMore,
        isLoadingMore,
      ];
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
  final AuthCubit _authCubit;
  final UserDao _userDao;
  final SyncService _syncService;

  String? get currentUserId => _authCubit.currentUser?.id;
  String? get _currentUserId => _authCubit.currentUser?.id;

  static const _pageSize = 40;
  static const _uuid = Uuid();

  MessageCubit({
    required MessageDao messageDao,
    required SyncQueueDao syncDao,
    required AuthCubit authCubit,
    required UserDao userDao,
    required SyncService syncService,
  })  : _messageDao = messageDao,
        _syncDao = syncDao,
        _authCubit = authCubit,
        _userDao = userDao,
        _syncService = syncService,
        super(const MessageInitial());

  // ── Load conversations ────────────────────────────────────────────────────

  Future<void> loadConversations() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      emit(const ConversationsLoaded(conversations: [], requests: []));
      return;
    }
    emit(const ConversationsLoading());
    try {
      await _syncService.syncRemoteToLocal();
      final convos = await _messageDao.getConversations(
        userId: uid,
        pageSize: _pageSize,
      );
      final requests = await _messageDao.getCollaborationRequests(
        userId: uid,
        limit: _pageSize,
      );
      emit(ConversationsLoaded(
        conversations: convos,
        requests: requests,
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
      final uid = _currentUserId;
      if (uid == null || uid.isEmpty) {
        emit(const MessageError('Not logged in'));
        return;
      }

      var resolvedPeerName = peerName.trim();
      var resolvedPeerPhotoUrl = peerPhotoUrl;
      var resolvedIsPeerLecturer = isPeerLecturer;

      if (resolvedPeerName.isEmpty || resolvedPeerPhotoUrl == null) {
        final peer = await _userDao.getUserById(peerId);
        if (peer != null) {
          resolvedPeerName = resolvedPeerName.isEmpty
              ? (peer.displayName?.trim().isNotEmpty == true
                  ? peer.displayName!.trim()
                  : peer.email)
              : resolvedPeerName;
          resolvedPeerPhotoUrl ??= peer.photoUrl;
          resolvedIsPeerLecturer = resolvedIsPeerLecturer || peer.isLecturer;
        }
      }

      if (resolvedPeerName.isEmpty) {
        resolvedPeerName = 'Conversation';
      }

      // Ensure conversation exists (creates if first time)
      final convoId = await _messageDao.ensureConversation(
        userId: uid,
        peerId: peerId,
        peerName: resolvedPeerName,
        peerPhotoUrl: resolvedPeerPhotoUrl,
        isPeerLecturer: resolvedIsPeerLecturer,
      );

      final messages = await _messageDao.getMessages(
        conversationId: convoId,
        pageSize: _pageSize,
      );

      // Mark as read
      await _messageDao.markConversationRead(
        conversationId: convoId,
        userId: uid,
      );
      await _syncService.markConversationReadRemote(
        conversationId: convoId,
        userId: uid,
      );

      emit(ThreadLoaded(
        conversationId: convoId,
        peerId: peerId,
        peerName: resolvedPeerName,
        peerPhotoUrl: resolvedPeerPhotoUrl,
        isPeerLecturer: resolvedIsPeerLecturer,
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
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;

    final msg = MessageModel(
      id: _uuid.v4(),
      conversationId: current.conversationId,
      senderId: uid,
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
      await _syncService.processPendingSync();
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
    await _syncService.processPendingSync();
  }

  // ── Search conversations ──────────────────────────────────────────────────

  Future<void> searchConversations(String query) async {
    if (query.trim().isEmpty) {
      await loadConversations();
      return;
    }
    try {
      final uid = _currentUserId;
      if (uid == null || uid.isEmpty) {
        emit(const ConversationsLoaded(conversations: [], requests: []));
        return;
      }
      final results = await _messageDao.searchConversations(
        userId: uid,
        query: query,
      );
      final requests = await _messageDao.getCollaborationRequests(
        userId: uid,
        limit: _pageSize,
      );
      final lowered = query.toLowerCase();
      final matchingRequests = requests.where((request) {
        return request.counterpartName.toLowerCase().contains(lowered) ||
            request.postTitle.toLowerCase().contains(lowered) ||
            request.message.toLowerCase().contains(lowered);
      }).toList();
      emit(ConversationsLoaded(conversations: results, requests: matchingRequests));
    } catch (e) {
      emit(MessageError('Search failed: $e'));
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    await _messageDao.deleteConversation(conversationId);
    await _syncDao.enqueue(
      entity: 'conversation',
      entityId: conversationId,
      operation: 'delete',
      payload: const {},
    );
    await _syncService.processPendingSync();
    await loadConversations();
  }
}
