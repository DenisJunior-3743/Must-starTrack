import 'package:equatable/equatable.dart';

enum ChatbotSource { faq, ai, fallback }

class ChatbotAction extends Equatable {
  final String label;
  final String route;

  const ChatbotAction({
    required this.label,
    required this.route,
  });

  @override
  List<Object?> get props => [label, route];
}

class ChatbotFaqEntry extends Equatable {
  final String id;
  final String? group;
  final String question;
  final String answer;
  final List<String> keywords;
  final List<ChatbotAction> actions;
  final List<String> followUps;

  const ChatbotFaqEntry({
    required this.id,
    this.group,
    required this.question,
    required this.answer,
    this.keywords = const [],
    this.actions = const [],
    this.followUps = const [],
  });

  @override
  List<Object?> get props => [id, group, question, answer, keywords, actions, followUps];
}

class ChatbotKnowledgeDoc extends Equatable {
  final String id;
  final String title;
  final String summary;
  final String content;
  final List<String> keywords;
  final List<String> followUps;

  const ChatbotKnowledgeDoc({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    this.keywords = const [],
    this.followUps = const [],
  });

  @override
  List<Object?> get props => [id, title, summary, content, keywords, followUps];
}

class ChatbotResponse extends Equatable {
  final String answer;
  final ChatbotSource source;
  final double confidence;
  final List<ChatbotAction> actions;
  final List<String> followUps;

  const ChatbotResponse({
    required this.answer,
    required this.source,
    required this.confidence,
    this.actions = const [],
    this.followUps = const [],
  });

  @override
  List<Object?> get props => [answer, source, confidence, actions, followUps];
}

class ChatbotMessage extends Equatable {
  final String id;
  final String? interactionId;
  final String text;
  final bool isUser;
  final DateTime createdAt;
  final ChatbotSource? source;
  final double? confidence;
  final List<ChatbotAction> actions;
  final List<String> followUps;
  final bool? isHelpful;

  const ChatbotMessage({
    required this.id,
    this.interactionId,
    required this.text,
    required this.isUser,
    required this.createdAt,
    this.source,
    this.confidence,
    this.actions = const [],
    this.followUps = const [],
    this.isHelpful,
  });

  ChatbotMessage copyWith({
    String? id,
    String? interactionId,
    String? text,
    bool? isUser,
    DateTime? createdAt,
    ChatbotSource? source,
    double? confidence,
    List<ChatbotAction>? actions,
    List<String>? followUps,
    bool? isHelpful,
    bool clearHelpful = false,
  }) {
    return ChatbotMessage(
      id: id ?? this.id,
      interactionId: interactionId ?? this.interactionId,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      actions: actions ?? this.actions,
      followUps: followUps ?? this.followUps,
      isHelpful: clearHelpful ? null : (isHelpful ?? this.isHelpful),
    );
  }

  @override
  List<Object?> get props => [
        id,
        interactionId,
        text,
        isUser,
        createdAt,
        source,
        confidence,
        actions,
        followUps,
        isHelpful,
      ];
}
