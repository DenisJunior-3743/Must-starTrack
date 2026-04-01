import 'package:flutter_test/flutter_test.dart';

import 'package:must_startrack/data/remote/gemini_service.dart';
import 'package:must_startrack/features/chatbot/data/chatbot_repository.dart';
import 'package:must_startrack/features/chatbot/models/chatbot_models.dart';

void main() {
  group('ChatbotRepository Gemini integration', () {
    test('uses FAQ answer first for strong local matches', () async {
      final gemini = _FakeGeminiService(
        configured: true,
        response: '{"answer":"AI should not be called"}',
      );

      final repo = ChatbotRepository(
        faqs: const [
          ChatbotFaqEntry(
            id: 'faq_guest_mode',
            question: 'What can I do in guest mode?',
            answer: 'Guests can browse only.',
            keywords: ['guest mode', 'guest'],
          ),
        ],
        projectDocs: const [],
        knownRoutes: const {'/home'},
        geminiService: gemini,
      );

      final result = await repo.answer(
        'What can I do in guest mode?',
        isGuest: true,
      );

      expect(result.source, ChatbotSource.faq);
      expect(result.answer, 'Guests can browse only.');
      expect(gemini.callCount, 0);
    });

    test('returns AI response when Gemini is configured and JSON is valid', () async {
      final gemini = _FakeGeminiService(
        configured: true,
        response: '''
{
  "answer": "This answer came from Gemini.",
  "confidence": 0.91,
  "followUps": ["Do you want setup steps?", "Need route guidance?"],
  "actions": [
    {"label": "Open Home", "route": "/home"},
    {"label": "Unknown", "route": "/missing"}
  ]
}
''',
      );

      final repo = ChatbotRepository(
        faqs: const [
          ChatbotFaqEntry(
            id: 'faq_1',
            question: 'How do I reset my password?',
            answer: 'Use settings.',
            keywords: ['password', 'reset'],
          ),
        ],
        projectDocs: const [],
        knownRoutes: const {'/home', '/discover'},
        geminiService: gemini,
      );

      final result = await repo.answer(
        'Explain advanced recommender ranking internals for cold-start users.',
        isGuest: false,
        role: 'student',
      );

      expect(gemini.callCount, 1);
      expect(result.source, ChatbotSource.ai);
      expect(result.answer, 'This answer came from Gemini.');
      expect(result.confidence, closeTo(0.91, 0.0001));
      expect(result.followUps, contains('Do you want setup steps?'));
      expect(result.actions, hasLength(1));
      expect(result.actions.first.route, '/home');
    });

    test('falls back when Gemini is not configured', () async {
      final gemini = _FakeGeminiService(
        configured: false,
        response: '{"answer":"should not be used"}',
      );

      final repo = ChatbotRepository(
        faqs: const [
          ChatbotFaqEntry(
            id: 'faq_1',
            question: 'What is peer endorsement?',
            answer: 'Peers can endorse your skills.',
            keywords: ['endorsement'],
          ),
        ],
        projectDocs: const [],
        knownRoutes: const {'/home'},
        geminiService: gemini,
      );

      final result = await repo.answer(
        'How does embedding retrieval work for recommendations?',
        isGuest: false,
        role: 'student',
      );

      expect(gemini.callCount, 0);
      expect(result.source, ChatbotSource.fallback);
      expect(result.answer, contains('I am still learning'));
    });

    test('falls back when Gemini returns invalid JSON', () async {
      final gemini = _FakeGeminiService(
        configured: true,
        response: 'this-is-not-json',
      );

      final repo = ChatbotRepository(
        faqs: const [
          ChatbotFaqEntry(
            id: 'faq_1',
            question: 'How do I edit my profile?',
            answer: 'Open profile settings.',
            keywords: ['profile'],
          ),
        ],
        projectDocs: const [],
        knownRoutes: const {'/home'},
        geminiService: gemini,
      );

      final result = await repo.answer(
        'Describe recommender score blending internals and audit fields.',
        isGuest: true,
      );

      expect(gemini.callCount, 1);
      expect(result.source, ChatbotSource.fallback);
      expect(result.answer, contains('I am still learning'));
    });
  });
}

class _FakeGeminiService extends GeminiService {
  _FakeGeminiService({
    required this.configured,
    required this.response,
  }) : super(apiKey: 'test-key');

  final bool configured;
  final String? response;
  int callCount = 0;

  @override
  bool get isConfigured => configured;

  @override
  Future<String?> generateJson(String prompt) async {
    callCount += 1;
    return response;
  }
}