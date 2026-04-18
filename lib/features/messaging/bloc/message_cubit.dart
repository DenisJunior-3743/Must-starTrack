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

import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/dao/message_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/cloudinary_service.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/remote/recommender_service.dart';
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
  final CloudinaryService _cloudinary;
  final FirestoreService _firestore;
  final RecommenderService _recommenderService;
  StreamSubscription<List<MessageModel>>? _threadSub;
  StreamSubscription<int>? _inboxRealtimeSub;
  StreamSubscription<AuthState>? _authSub;
  Timer? _inboxRefreshDebounce;
  String? _realtimeInboxUserId;
  DateTime? _lastConversationsLoadedAt;

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
    required CloudinaryService cloudinary,
    required FirestoreService firestore,
    required RecommenderService recommenderService,
  })  : _messageDao = messageDao,
        _syncDao = syncDao,
        _authCubit = authCubit,
        _userDao = userDao,
        _syncService = syncService,
        _cloudinary = cloudinary,
        _firestore = firestore,
        _recommenderService = recommenderService,
        super(const MessageInitial()) {
    _authSub = _authCubit.stream.listen((authState) {
      if (authState is AuthAuthenticated) {
        unawaited(loadConversations());
      } else if (authState is AuthUnauthenticated) {
        _stopRealtimeInboxWatcher();
        _emitIfOpen(const ConversationsLoaded(conversations: [], requests: []));
      }
    });
  }

  void _emitIfOpen(MessageState next) {
    if (!isClosed) {
      emit(next);
    }
  }

  Future<void> ensureConversationsLoaded({
    Duration staleAfter = const Duration(minutes: 2),
  }) async {
    final current = state;

    if (current is MessageInitial || current is MessageError) {
      await loadConversations();
      return;
    }

    if (current is! ConversationsLoaded) return;

    final loadedAt = _lastConversationsLoadedAt;
    if (loadedAt == null) {
      _lastConversationsLoadedAt = DateTime.now();
      unawaited(_refreshConversationsInBackground());
      return;
    }

    final age = DateTime.now().difference(loadedAt);
    if (age >= staleAfter) {
      unawaited(_refreshConversationsInBackground());
    }
  }

  // ── Load conversations ────────────────────────────────────────────────────

  Future<void> loadConversations() async {
    await _threadSub?.cancel();
    _threadSub = null;

    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      _emitIfOpen(const ConversationsLoaded(conversations: [], requests: []));
      return;
    }
    _emitIfOpen(const ConversationsLoading());
    try {
      await _syncService.syncRemoteToLocal();
      final convos = await _messageDao.getConversations(
        userId: uid,
        pageSize: _pageSize,
      );
      final requests = await _messageDao.getCollaborationRequests(
        userId: uid,
        incomingOnly: true,
        limit: _pageSize,
      );
      final rankedRequests = await _attachRequestRanking(
        viewerId: uid,
        requests: requests,
      );
      _startRealtimeInboxWatcher(uid);
      _emitIfOpen(ConversationsLoaded(
        conversations: convos,
        requests: rankedRequests,
        hasMore: convos.length == _pageSize,
      ));
      _lastConversationsLoadedAt = DateTime.now();
    } catch (e) {
      _emitIfOpen(MessageError('Failed to load conversations: $e'));
    }
  }

  Future<void> _refreshConversationsInBackground() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;

    try {
      await _syncService.syncRemoteToLocal();
      final convos = await _messageDao.getConversations(
        userId: uid,
        pageSize: _pageSize,
      );
      final requests = await _messageDao.getCollaborationRequests(
        userId: uid,
        incomingOnly: true,
        limit: _pageSize,
      );
      final rankedRequests = await _attachRequestRanking(
        viewerId: uid,
        requests: requests,
      );

      final latest = state;
      if (latest is ConversationsLoaded) {
        _emitIfOpen(ConversationsLoaded(
          conversations: convos,
          requests: rankedRequests,
          hasMore: convos.length == _pageSize,
        ));
        _lastConversationsLoadedAt = DateTime.now();
      }
    } catch (_) {
      // Keep existing inbox view when silent refresh fails.
    }
  }

  void _startRealtimeInboxWatcher(String userId) {
    if (_realtimeInboxUserId == userId && _inboxRealtimeSub != null) {
      return;
    }

    _stopRealtimeInboxWatcher();
    _realtimeInboxUserId = userId;
    _inboxRealtimeSub = _firestore.watchInboxSyncTicks(userId).listen((_) {
      _inboxRefreshDebounce?.cancel();
      _inboxRefreshDebounce = Timer(const Duration(milliseconds: 450), () {
        unawaited(_refreshInboxFromRealtimeTick());
      });
    });
  }

  Future<void> _refreshInboxFromRealtimeTick() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }

    await _syncService.syncRealtimeInboxSlices();
    await _refreshConversationsInBackground();
  }

  void _stopRealtimeInboxWatcher() {
    _inboxRefreshDebounce?.cancel();
    _inboxRefreshDebounce = null;
    _realtimeInboxUserId = null;
    unawaited(_inboxRealtimeSub?.cancel());
    _inboxRealtimeSub = null;
  }

  Future<List<CollaborationInboxItem>> _attachRequestRanking({
    required String viewerId,
    required List<CollaborationInboxItem> requests,
  }) async {
    if (requests.isEmpty) return requests;

    final viewer = await _userDao.getUserById(viewerId);
    if (viewer == null || !viewer.isLecturer || viewer.profile == null) {
      return requests;
    }

    final incomingRequests = requests
        .where((request) => request.isIncoming && request.counterpartId.isNotEmpty)
        .toList();
    if (incomingRequests.isEmpty) return requests;

    final counterpartIds = incomingRequests.map((request) => request.counterpartId).toSet();
    final candidates = <UserModel>[];
    for (final counterpartId in counterpartIds) {
      final user = await _userDao.getUserById(counterpartId);
      if (user != null) {
        candidates.add(user);
      }
    }
    if (candidates.isEmpty) return requests;

    final ranked = _recommenderService.rankCollaborators(
      currentUser: viewer,
      candidates: candidates,
    );
    final rankedById = {
      for (final item in ranked) item.user.id: item,
    };

    return requests.map((request) {
      final fit = rankedById[request.counterpartId];
      if (fit == null || !request.isIncoming) return request;
      return request.copyWith(
        aiFitScore: fit.score,
        aiReasons: fit.reasons,
        aiMatchedSkills: fit.matchedSkills,
      );
    }).toList();
  }

  // ── Load a message thread ─────────────────────────────────────────────────

  Future<void> loadThread({
    required String peerId,
    required String peerName,
    String? peerPhotoUrl,
    bool isPeerLecturer = false,
  }) async {
    _emitIfOpen(const ThreadLoading());

    try {
      final uid = _currentUserId;
      if (uid == null || uid.isEmpty) {
        _emitIfOpen(const MessageError('Not logged in'));
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

      _emitIfOpen(ThreadLoaded(
        conversationId: convoId,
        peerId: peerId,
        peerName: resolvedPeerName,
        peerPhotoUrl: resolvedPeerPhotoUrl,
        isPeerLecturer: resolvedIsPeerLecturer,
        messages: messages,
        hasMore: messages.length == _pageSize,
      ));

      await _threadSub?.cancel();
      _threadSub = _firestore.watchMessages(convoId).listen(
        (remoteMessages) {
          _onRemoteMessages(conversationId: convoId, remoteMessages: remoteMessages);
        },
      );
    } catch (e) {
      _emitIfOpen(MessageError('Failed to load messages: $e'));
    }
  }

  // ── Load more messages (pagination) ──────────────────────────────────────

  Future<void> loadMoreMessages() async {
    final current = state;
    if (current is! ThreadLoaded || current.isLoadingMore || !current.hasMore) return;

    _emitIfOpen(current.copyWith(isLoadingMore: true));

    try {
      final oldest = current.messages.isNotEmpty
          ? current.messages.first.createdAt : null;

      final older = await _messageDao.getMessages(
        conversationId: current.conversationId,
        pageSize: _pageSize,
        before: oldest,
      );

      _emitIfOpen(current.copyWith(
        messages: [...older, ...current.messages],
        hasMore: older.length == _pageSize,
        isLoadingMore: false,
      ));
    } catch (_) {
      _emitIfOpen(current.copyWith(isLoadingMore: false));
    }
  }

  // ── Send a text message ───────────────────────────────────────────────────

  /// Optimistic send:
  ///   1. Build message object with generated ID
  ///   2. Append to UI immediately
  ///   3. Persist to SQLite
  ///   4. Enqueue Firestore sync
  Future<void> sendMessage(String text, {
    String? replyToId,
    String? replyToPreview,
  }) async {
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
      replyToId: replyToId,
      replyToPreview: replyToPreview,
    );

    // 1. Optimistic append
    _emitIfOpen(current.copyWith(messages: [...current.messages, msg]));

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
          'file_url': msg.fileUrl,
          'file_name': msg.fileName,
          'file_size': msg.fileSize,
          'created_at': msg.createdAt.toIso8601String(),
          'reply_to_id': msg.replyToId,
          'reply_to_preview': msg.replyToPreview,
        },
      );
      await _syncService.processPendingSync();
    } catch (e) {
      // Rollback optimistic message on failure
      final rolled = (state as ThreadLoaded).messages
          .where((m) => m.id != msg.id).toList();
      _emitIfOpen((state as ThreadLoaded).copyWith(messages: rolled));
    }
  }

  Future<void> sendAudioMessage({
    required File audioFile,
    Duration? duration,
    String? replyToId,
    String? replyToPreview,
  }) async {
    final current = state;
    if (current is! ThreadLoaded) return;
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;
    if (!await audioFile.exists()) {
      _emitIfOpen(const MessageError('Recorded audio file is missing.'));
      return;
    }

    final fileName = audioFile.path.split(Platform.pathSeparator).last;
    final localPath = audioFile.path;
    final fileSize = (await audioFile.length()).toString();
    final msg = MessageModel(
      id: _uuid.v4(),
      conversationId: current.conversationId,
      senderId: uid,
      content: duration == null
          ? 'Voice message'
          : 'Voice message (${_formatDuration(duration)})',
      messageType: 'audio',
      fileUrl: localPath,
      fileName: fileName,
      fileSize: fileSize,
      createdAt: DateTime.now(),
      isRead: false,
      replyToId: replyToId,
      replyToPreview: replyToPreview,
    );

    _emitIfOpen(current.copyWith(messages: [...current.messages, msg]));

    try {
      await _messageDao.insertMessage(msg);

      String syncedFileUrl = localPath;
      try {
        final uploadedUrl = await _cloudinary.uploadFile(
          audioFile,
          folder: 'chat_audio',
        );

        syncedFileUrl = uploadedUrl;
        await _messageDao.updateMessageMedia(
          messageId: msg.id,
          fileUrl: uploadedUrl,
          fileName: fileName,
          fileSize: fileSize,
        );

        final latest = state;
        if (latest is ThreadLoaded) {
          final updatedMessages = latest.messages
              .map((item) => item.id == msg.id
                  ? MessageModel(
                      id: item.id,
                      conversationId: item.conversationId,
                      senderId: item.senderId,
                      content: item.content,
                      messageType: item.messageType,
                      fileUrl: uploadedUrl,
                      fileName: fileName,
                      fileSize: fileSize,
                      createdAt: item.createdAt,
                      isRead: item.isRead,
                      isDeleted: item.isDeleted,
                      replyToId: item.replyToId,
                      replyToPreview: item.replyToPreview,
                    )
                  : item)
              .toList();
          _emitIfOpen(latest.copyWith(messages: updatedMessages));
        }
      } catch (_) {
        // Keep local-path audio visible when upload fails; sync can retry later.
      }

      await _syncDao.enqueue(
        entity: 'message',
        entityId: msg.id,
        operation: 'create',
        payload: {
          'conversation_id': msg.conversationId,
          'sender_id': msg.senderId,
          'content': msg.content,
          'message_type': msg.messageType,
          'file_url': syncedFileUrl,
          'file_name': fileName,
          'file_size': fileSize,
          'created_at': msg.createdAt.toIso8601String(),
          'reply_to_id': msg.replyToId,
          'reply_to_preview': msg.replyToPreview,
        },
      );
      try {
        await _syncService.processPendingSync();
      } catch (_) {
        // Message stays visible locally even if remote sync is delayed.
      }
    } catch (_) {
      // Keep optimistic message in the thread if background sync fails.
    }
  }

  // ── Delete a message ──────────────────────────────────────────────────────

  Future<void> deleteMessage(String messageId) async {
    final current = state;
    if (current is! ThreadLoaded) return;

    // Optimistic remove
    final updated = current.messages.where((m) => m.id != messageId).toList();
    _emitIfOpen(current.copyWith(messages: updated));

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
        _emitIfOpen(const ConversationsLoaded(conversations: [], requests: []));
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
      _emitIfOpen(ConversationsLoaded(conversations: results, requests: matchingRequests));
    } catch (e) {
      _emitIfOpen(MessageError('Search failed: $e'));
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

  void _onRemoteMessages({
    required String conversationId,
    required List<MessageModel> remoteMessages,
  }) {
    final current = state;
    if (current is! ThreadLoaded || current.conversationId != conversationId) {
      return;
    }

    final merged = _mergeMessages(
      localMessages: current.messages,
      remoteMessages: remoteMessages,
    );

    final uid = _currentUserId;
    if (uid != null && uid.isNotEmpty) {
      final hasUnreadIncoming = merged.any((m) => m.senderId != uid && !m.isRead);
      if (hasUnreadIncoming) {
        final readMerged = merged.map((m) {
          if (m.senderId == uid || m.isRead) return m;
          return MessageModel(
            id: m.id,
            conversationId: m.conversationId,
            senderId: m.senderId,
            content: m.content,
            messageType: m.messageType,
            fileUrl: m.fileUrl,
            fileName: m.fileName,
            fileSize: m.fileSize,
            createdAt: m.createdAt,
            isRead: true,
            isDeleted: m.isDeleted,
            replyToId: m.replyToId,
            replyToPreview: m.replyToPreview,
          );
        }).toList();

        _emitIfOpen(current.copyWith(messages: readMerged));
        unawaited(_markConversationReadEverywhere(
          conversationId: conversationId,
          userId: uid,
        ));
        return;
      }
    }

    _emitIfOpen(current.copyWith(messages: merged));
  }

  Future<void> _markConversationReadEverywhere({
    required String conversationId,
    required String userId,
  }) async {
    try {
      await _messageDao.markConversationRead(
        conversationId: conversationId,
        userId: userId,
      );
      await _syncService.markConversationReadRemote(
        conversationId: conversationId,
        userId: userId,
      );
    } catch (_) {
      // Best effort: local/UI remains usable even if read sync fails.
    }
  }

  List<MessageModel> _mergeMessages({
    required List<MessageModel> localMessages,
    required List<MessageModel> remoteMessages,
  }) {
    final byId = <String, MessageModel>{
      for (final item in localMessages) item.id: item,
    };

    for (final remote in remoteMessages) {
      final local = byId[remote.id];
      if (local == null) {
        byId[remote.id] = remote;
        continue;
      }

      byId[remote.id] = MessageModel(
        id: remote.id,
        conversationId: remote.conversationId,
        senderId: remote.senderId,
        content: remote.content,
        messageType: remote.messageType,
        fileUrl: remote.fileUrl ?? local.fileUrl,
        fileName: remote.fileName ?? local.fileName,
        fileSize: remote.fileSize ?? local.fileSize,
        createdAt: remote.createdAt,
        isRead: remote.isRead,
        isDeleted: local.isDeleted,
        replyToId: remote.replyToId ?? local.replyToId,
        replyToPreview: remote.replyToPreview ?? local.replyToPreview,
      );
    }

    final merged = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Future<void> close() async {
    _inboxRefreshDebounce?.cancel();
    _inboxRefreshDebounce = null;
    await _authSub?.cancel();
    _authSub = null;
    await _inboxRealtimeSub?.cancel();
    _inboxRealtimeSub = null;
    await _threadSub?.cancel();
    return super.close();
  }
}
