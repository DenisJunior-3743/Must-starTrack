import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/local/dao/message_dao.dart';
import '../../../data/repositories/message_repository.dart';

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
  final String query;

  const ConversationsLoaded({
    required this.conversations,
    this.hasMore = false,
    this.query = '',
  });

  ConversationsLoaded copyWith({
    List<ConversationSummary>? conversations,
    bool? hasMore,
    String? query,
  }) {
    return ConversationsLoaded(
      conversations: conversations ?? this.conversations,
      hasMore: hasMore ?? this.hasMore,
      query: query ?? this.query,
    );
  }

  @override
  List<Object?> get props => [conversations, hasMore, query];
}

class ThreadLoading extends MessageState {
  const ThreadLoading();
}

class ThreadLoaded extends MessageState {
  final String conversationId;
  final String currentUserId;
  final String peerName;
  final List<MessageModel> messages;
  final bool hasMore;
  final bool isLoadingMore;

  const ThreadLoaded({
    required this.conversationId,
    required this.currentUserId,
    required this.peerName,
    required this.messages,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  ThreadLoaded copyWith({
    List<MessageModel>? messages,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return ThreadLoaded(
      conversationId: conversationId,
      currentUserId: currentUserId,
      peerName: peerName,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => [
        conversationId,
        currentUserId,
        peerName,
        messages,
        hasMore,
        isLoadingMore
      ];
}

class MessageError extends MessageState {
  final String message;

  const MessageError(this.message);

  @override
  List<Object?> get props => [message];
}

class MessageCubit extends Cubit<MessageState> {
  static const _pageSize = 40;

  final MessageRepository _repo;
  final String? Function() _currentUserId;

  StreamSubscription<List<ConversationSummary>>? _conversationSub;
  StreamSubscription<List<MessageModel>>? _threadSub;

  MessageCubit({
    required MessageRepository repository,
    required String? Function() currentUserId,
  })  : _repo = repository,
        _currentUserId = currentUserId,
        super(const MessageInitial());

  String? get _userId => _currentUserId();

  Future<void> loadConversations() async {
    final userId = _userId;
    if (userId == null) {
      emit(const MessageError('Please sign in to access inbox.'));
      return;
    }

    emit(const ConversationsLoading());

    await _conversationSub?.cancel();
    _conversationSub = _repo.watchConversations(userId).listen((conversations) {
      final current = state;
      if (current is ConversationsLoaded) {
        emit(current.copyWith(conversations: conversations));
        return;
      }
      emit(ConversationsLoaded(
        conversations: conversations,
        hasMore: conversations.length == _pageSize,
      ));
    });

    try {
      final convos =
          await _repo.loadConversations(userId: userId, pageSize: _pageSize);
      emit(ConversationsLoaded(
        conversations: convos,
        hasMore: convos.length == _pageSize,
      ));
    } catch (e) {
      emit(MessageError('Failed to load conversations: $e'));
    }
  }

  Future<void> searchConversations(String query) async {
    final userId = _userId;
    if (userId == null) {
      emit(const MessageError('Please sign in to search inbox.'));
      return;
    }

    if (query.trim().isEmpty) {
      await loadConversations();
      return;
    }

    try {
      final results =
          await _repo.searchConversations(userId: userId, query: query.trim());
      emit(ConversationsLoaded(
        conversations: results,
        query: query,
        hasMore: false,
      ));
    } catch (e) {
      emit(MessageError('Search failed: $e'));
    }
  }

  Future<void> loadThread({
    required String threadOrPeerId,
    required String peerName,
    String? peerPhotoUrl,
    bool isPeerLecturer = false,
  }) async {
    final userId = _userId;
    if (userId == null) {
      emit(const MessageError('Please sign in to open chats.'));
      return;
    }

    emit(const ThreadLoading());

    try {
      final thread = await _repo.openThread(
        userId: userId,
        threadOrPeerId: threadOrPeerId,
        peerName: peerName,
        peerPhotoUrl: peerPhotoUrl,
        isPeerLecturer: isPeerLecturer,
        pageSize: _pageSize,
      );

      await _threadSub?.cancel();
      _threadSub = _repo
          .watchMessages(userId: userId, conversationId: thread.conversationId)
          .listen((messages) {
        final current = state;
        if (current is ThreadLoaded &&
            current.conversationId == thread.conversationId) {
          emit(current.copyWith(messages: messages));
        }
      });

      emit(ThreadLoaded(
        conversationId: thread.conversationId,
        currentUserId: userId,
        peerName: thread.peerName,
        messages: thread.messages,
        hasMore: thread.hasMore,
      ));
    } catch (e) {
      emit(MessageError('Failed to load messages: $e'));
    }
  }

  Future<void> loadMoreMessages() async {
    final current = state;
    if (current is! ThreadLoaded || current.isLoadingMore || !current.hasMore) {
      return;
    }

    emit(current.copyWith(isLoadingMore: true));
    try {
      final oldest =
          current.messages.isNotEmpty ? current.messages.first.createdAt : null;
      if (oldest == null) {
        emit(current.copyWith(isLoadingMore: false, hasMore: false));
        return;
      }

      final older = await _repo.loadMoreMessages(
        conversationId: current.conversationId,
        before: oldest,
        pageSize: _pageSize,
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

  Future<void> sendMessage(String text) async {
    final current = state;
    final userId = _userId;
    if (current is! ThreadLoaded || userId == null) return;

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    try {
      await _repo.sendMessage(
        userId: userId,
        conversationId: current.conversationId,
        text: trimmed,
      );
    } catch (e) {
      emit(MessageError('Could not send message: $e'));
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final current = state;
    if (current is! ThreadLoaded) return;

    try {
      await _repo.deleteMessage(
        messageId: messageId,
        conversationId: current.conversationId,
      );
    } catch (e) {
      emit(MessageError('Could not delete message: $e'));
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    final userId = _userId;
    if (userId == null) return;

    try {
      await _repo.deleteConversation(
        userId: userId,
        conversationId: conversationId,
      );
      await loadConversations();
    } catch (e) {
      emit(MessageError('Could not delete conversation: $e'));
    }
  }

  Future<void> markThreadRead() async {
    final current = state;
    final userId = _userId;
    if (current is! ThreadLoaded || userId == null) return;

    await _repo.markConversationRead(
      userId: userId,
      conversationId: current.conversationId,
    );
  }

  @override
  Future<void> close() async {
    await _conversationSub?.cancel();
    await _threadSub?.cancel();
    return super.close();
  }
}
