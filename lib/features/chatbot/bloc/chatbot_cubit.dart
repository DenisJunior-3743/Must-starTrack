import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/remote/firestore_service.dart';
import '../data/chatbot_knowledge_base.dart';
import '../data/chatbot_repository.dart';
import '../models/chatbot_models.dart';

abstract class ChatbotState extends Equatable {
  const ChatbotState();

  @override
  List<Object?> get props => [];
}

class ChatbotIdle extends ChatbotState {
  final List<ChatbotMessage> messages;
  final List<String> starterPrompts;

  const ChatbotIdle({
    required this.messages,
    this.starterPrompts = const [],
  });

  @override
  List<Object?> get props => [messages, starterPrompts];

  ChatbotIdle copyWith({
    List<ChatbotMessage>? messages,
    List<String>? starterPrompts,
  }) {
    return ChatbotIdle(
      messages: messages ?? this.messages,
      starterPrompts: starterPrompts ?? this.starterPrompts,
    );
  }
}

class ChatbotTyping extends ChatbotState {
  final List<ChatbotMessage> messages;

  const ChatbotTyping({required this.messages});

  @override
  List<Object?> get props => [messages];
}

class ChatbotCubit extends Cubit<ChatbotState> {
  ChatbotCubit({
    required ChatbotRepository repository,
    required FirestoreService firestore,
    required ActivityLogDao activityLogDao,
  })  : _firestore = firestore,
        _activityLogDao = activityLogDao,
        _repository = repository,
        super(
          ChatbotIdle(
            messages: [
              ChatbotMessage(
                id: 'welcome',
                text: 'Hi, I am your MUST StarTrack assistant. Ask me about navigation, features, permissions, or troubleshooting.',
                isUser: false,
                createdAt: DateTime.now(),
                followUps: ChatbotKnowledgeBase.starterPrompts,
              ),
            ],
            starterPrompts: ChatbotKnowledgeBase.starterPrompts,
          ),
        );

  final ChatbotRepository _repository;
  final FirestoreService _firestore;
  final ActivityLogDao _activityLogDao;

  Future<void> ask(
    String query, {
    required bool isGuest,
    String? role,
    String? userId,
  }) async {
    final text = query.trim();
    if (text.isEmpty) return;

    final currentMessages = _messages;
    final nextMessages = [
      ...currentMessages,
      ChatbotMessage(
        id: 'u_${DateTime.now().microsecondsSinceEpoch}',
        text: text,
        isUser: true,
        createdAt: DateTime.now(),
      ),
    ];

    emit(ChatbotTyping(messages: nextMessages));

    final response = await _repository.answer(
      text,
      isGuest: isGuest,
      role: role,
    );

    final interactionId =
        'chat_${DateTime.now().microsecondsSinceEpoch}_${text.hashCode.abs()}';

    await _logInteraction(
      interactionId: interactionId,
      question: text,
      response: response,
      isGuest: isGuest,
      role: role,
      userId: userId,
    );

    final replied = [
      ...nextMessages,
      ChatbotMessage(
        id: 'b_${DateTime.now().microsecondsSinceEpoch}',
        interactionId: interactionId,
        text: response.answer,
        isUser: false,
        createdAt: DateTime.now(),
        source: response.source,
        confidence: response.confidence,
        actions: response.actions,
        followUps: response.followUps,
      ),
    ];

    emit(
      ChatbotIdle(
        messages: replied,
        starterPrompts: ChatbotKnowledgeBase.starterPrompts,
      ),
    );
  }

  Future<void> markHelpful({
    required String interactionId,
    required bool isHelpful,
    String? actorUserId,
  }) async {
    final updated = _messages.map((m) {
      if (m.interactionId != interactionId) return m;
      return m.copyWith(isHelpful: isHelpful);
    }).toList(growable: false);

    emit(
      ChatbotIdle(
        messages: updated,
        starterPrompts: ChatbotKnowledgeBase.starterPrompts,
      ),
    );

    final safeActorId = actorUserId?.trim();
    if (safeActorId == null || safeActorId.isEmpty) {
      return;
    }

    try {
      await _firestore.setChatbotInteractionFeedback(
        interactionId: interactionId,
        isHelpful: isHelpful,
        feedbackBy: safeActorId,
      );
      await _activityLogDao.logAction(
        userId: safeActorId,
        action: isHelpful ? 'chatbot_feedback_helpful' : 'chatbot_feedback_not_helpful',
        entityType: 'chatbot_interaction',
        entityId: interactionId,
        metadata: {'is_helpful': isHelpful},
      );
    } catch (_) {
      // Metrics failures should never break chat UX.
    }
  }

  void clearConversation() {
    emit(
      ChatbotIdle(
        messages: [
          ChatbotMessage(
            id: 'welcome_reset',
            text: 'Conversation cleared. Ask me anything about the app.',
            isUser: false,
            createdAt: DateTime.now(),
            followUps: ChatbotKnowledgeBase.starterPrompts,
          ),
        ],
        starterPrompts: ChatbotKnowledgeBase.starterPrompts,
      ),
    );
  }

  List<ChatbotMessage> get _messages {
    final s = state;
    if (s is ChatbotTyping) return s.messages;
    if (s is ChatbotIdle) return s.messages;
    return const <ChatbotMessage>[];
  }

  Future<void> _logInteraction({
    required String interactionId,
    required String question,
    required ChatbotResponse response,
    required bool isGuest,
    String? role,
    String? userId,
  }) async {
    final safeUserId = userId?.trim();
    if (isGuest || safeUserId == null || safeUserId.isEmpty) {
      return;
    }

    try {
      await _firestore.setChatbotInteraction(
        interactionId: interactionId,
        payload: {
          'id': interactionId,
          'question': question,
          'answer': response.answer,
          'source': response.source.name,
          'confidence': response.confidence,
          'is_guest': isGuest,
          'user_id': safeUserId,
          'role': role ?? 'unknown',
          'actions_count': response.actions.length,
          'followups_count': response.followUps.length,
          'created_at': DateTime.now().toIso8601String(),
          'is_helpful': null,
        },
      );
    } catch (_) {
      // Ignore remote logging failures.
    }
  }
}
