import 'dart:async';

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
                text:
                    'Hi, I am your MUST StarTrack assistant. Ask me about navigation, features, permissions, or troubleshooting.',
                isUser: false,
                createdAt: DateTime.now(),
                followUps: ChatbotKnowledgeBase.starterPrompts,
              ),
            ],
            starterPrompts: ChatbotKnowledgeBase.starterPrompts,
          ),
        ) {
    unawaited(_refreshLearningMemory(force: true));
  }

  final ChatbotRepository _repository;
  final FirestoreService _firestore;
  final ActivityLogDao _activityLogDao;
  List<ChatbotLearnedExample> _learnedExamples =
      const <ChatbotLearnedExample>[];
  DateTime? _lastLearningRefreshAt;
  bool _learningRefreshInFlight = false;

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

    if (_shouldRefreshLearningMemory()) {
      unawaited(_refreshLearningMemory());
    }

    final behaviorContext = await _loadBehaviorContext(
      isGuest: isGuest,
      userId: userId,
    );

    final response = await _repository.answer(
      text,
      isGuest: isGuest,
      role: role,
      conversation: nextMessages,
      learnedExamples: _learnedExamples,
      behaviorContext: behaviorContext,
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
      behaviorContext: behaviorContext,
    );

    _logUserQuestionForBehavior(
      question: text,
      isGuest: isGuest,
      userId: userId,
      role: role,
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
        action: isHelpful
            ? 'chatbot_feedback_helpful'
            : 'chatbot_feedback_not_helpful',
        entityType: 'chatbot_interaction',
        entityId: interactionId,
        metadata: {'is_helpful': isHelpful},
      );
      if (isHelpful) {
        unawaited(_refreshLearningMemory(force: true));
      }
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
    required ChatbotBehaviorContext behaviorContext,
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
          'behavior_context': behaviorContext.toPromptMap(),
          'created_at': DateTime.now().toIso8601String(),
          'is_helpful': null,
        },
      );
    } catch (_) {
      // Ignore remote logging failures.
    }
  }

  bool _shouldRefreshLearningMemory() {
    final last = _lastLearningRefreshAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= const Duration(minutes: 6);
  }

  Future<ChatbotBehaviorContext> _loadBehaviorContext({
    required bool isGuest,
    String? userId,
  }) async {
    final safeUserId = userId?.trim();
    if (isGuest || safeUserId == null || safeUserId.isEmpty) {
      return const ChatbotBehaviorContext();
    }

    try {
      final results = await Future.wait<Set<String>>([
        _activityLogDao.getRecentSearchTerms(safeUserId, limit: 8),
        _activityLogDao.getRecentCategorySignals(safeUserId, limit: 8),
      ]);
      return ChatbotBehaviorContext(
        recentSearchTerms: results[0].take(8).toList(growable: false),
        recentlyViewedCategories: results[1].take(8).toList(growable: false),
      );
    } catch (_) {
      return const ChatbotBehaviorContext();
    }
  }

  void _logUserQuestionForBehavior({
    required String question,
    required bool isGuest,
    String? userId,
    String? role,
  }) {
    final safeUserId = userId?.trim();
    if (isGuest || safeUserId == null || safeUserId.isEmpty) {
      return;
    }

    unawaited(
      _activityLogDao.logAction(
        userId: safeUserId,
        action: 'chatbot_question',
        entityType: 'chatbot_interaction',
        entityId: question.length > 80 ? question.substring(0, 80) : question,
        metadata: {
          'question': question,
          'role': role ?? 'unknown',
        },
      ),
    );
  }

  Future<void> _refreshLearningMemory({bool force = false}) async {
    if (_learningRefreshInFlight) return;
    if (!force && !_shouldRefreshLearningMemory()) return;

    _learningRefreshInFlight = true;
    try {
      final rows = await _firestore.getRecentChatbotInteractions(limit: 500);
      _learnedExamples = _buildLearnedExamples(rows);
      _lastLearningRefreshAt = DateTime.now();
    } catch (_) {
      // Learning memory should never block assistant responses.
    } finally {
      _learningRefreshInFlight = false;
    }
  }

  List<ChatbotLearnedExample> _buildLearnedExamples(
    List<Map<String, dynamic>> rows,
  ) {
    final byQuestionKey = <String, ChatbotLearnedExample>{};
    final zeroTime = DateTime.fromMillisecondsSinceEpoch(0);

    for (final row in rows) {
      if (row['is_helpful'] != true) continue;

      final question = (row['question'] ?? '').toString().trim();
      final answer = (row['answer'] ?? '').toString().trim();
      if (question.isEmpty || answer.isEmpty) continue;

      final key = _normalizeKey(question);
      if (key.isEmpty) continue;

      final confidence = (row['confidence'] as num?)?.toDouble() ?? 0;
      final source = (row['source'] ?? '').toString().trim();
      final role = (row['role'] ?? '').toString().trim();
      final createdAtRaw = row['created_at']?.toString() ?? '';
      final createdAt = DateTime.tryParse(createdAtRaw);

      final candidate = ChatbotLearnedExample(
        question: question,
        answer: answer,
        confidence: confidence.clamp(0.0, 1.0),
        source: source,
        role: role,
        createdAt: createdAt,
      );

      final existing = byQuestionKey[key];
      if (existing == null) {
        byQuestionKey[key] = candidate;
        continue;
      }

      final betterConfidence = candidate.confidence > existing.confidence;
      final sameConfidence = candidate.confidence.toStringAsFixed(4) ==
          existing.confidence.toStringAsFixed(4);
      final fresher = (candidate.createdAt ?? zeroTime)
          .isAfter(existing.createdAt ?? zeroTime);

      if (betterConfidence || (sameConfidence && fresher)) {
        byQuestionKey[key] = candidate;
      }
    }

    final learned = byQuestionKey.values.toList(growable: false)
      ..sort((a, b) {
        final score = b.confidence.compareTo(a.confidence);
        if (score != 0) return score;
        final aTime = a.createdAt ?? zeroTime;
        final bTime = b.createdAt ?? zeroTime;
        return bTime.compareTo(aTime);
      });

    return learned.take(250).toList(growable: false);
  }

  String _normalizeKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
