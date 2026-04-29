import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:must_startrack/core/di/injection_container.dart';
import 'package:must_startrack/data/local/dao/activity_log_dao.dart';
import 'package:must_startrack/data/remote/firestore_service.dart';
import 'package:must_startrack/data/remote/openai_service.dart';
import 'package:must_startrack/features/auth/bloc/auth_cubit.dart';
import 'package:must_startrack/features/chatbot/data/chatbot_repository.dart';
import 'package:must_startrack/features/chatbot/models/chatbot_models.dart';
import 'package:must_startrack/features/chatbot/screens/chatbot_screen.dart';

void main() {
  late MockAuthCubit authCubit;
  late MockFirestoreService firestore;
  late MockActivityLogDao activityLogDao;

  setUp(() async {
    await sl.reset();

    authCubit = MockAuthCubit();
    firestore = MockFirestoreService();
    activityLogDao = MockActivityLogDao();

    when(() => authCubit.currentUser).thenReturn(null);
    when(
      () => firestore.setChatbotInteraction(
        interactionId: any(named: 'interactionId'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => firestore.getRecentChatbotInteractions(
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => const <Map<String, dynamic>>[]);

    sl.registerSingleton<AuthCubit>(authCubit);
    sl.registerSingleton<FirestoreService>(firestore);
    sl.registerSingleton<ActivityLogDao>(activityLogDao);
  });

  tearDown(() async {
    await sl.reset();
  });

  testWidgets('renders OpenAI response and follow-up chips', (tester) async {
    final repository = ChatbotRepository(
      faqs: const [
        ChatbotFaqEntry(
          id: 'faq_1',
          question: 'How do I edit profile?',
          answer: 'Use profile settings.',
          keywords: ['profile'],
        ),
      ],
      projectDocs: const [],
      knownRoutes: const {'/home'},
      openAiService: _FakeOpenAiService(
        configured: true,
        response: '''
{
  "answer": "OpenAI produced this answer.",
  "confidence": 0.88,
  "followUps": ["Need more details?"],
  "actions": []
}
''',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotScreen(repository: repository),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'Explain recommendation score blending for ambiguous matches.',
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI produced this answer.'), findsOneWidget);
    expect(find.text('Need more details?'), findsOneWidget);

    await tester.tap(find.text('Need more details?'));
    await tester.pumpAndSettle();

    expect(find.text('Need more details?'), findsWidgets);
    verifyNever(
      () => firestore.setChatbotInteraction(
        interactionId: any(named: 'interactionId'),
        payload: any(named: 'payload'),
      ),
    );
  });
}

class MockAuthCubit extends Mock implements AuthCubit {}

class MockFirestoreService extends Mock implements FirestoreService {}

class MockActivityLogDao extends Mock implements ActivityLogDao {}

class _FakeOpenAiService extends OpenAiService {
  _FakeOpenAiService({
    required this.configured,
    required this.response,
  }) : super(apiKey: 'test-key');

  final bool configured;
  final String? response;

  @override
  bool get isConfigured => configured;

  @override
  Future<String?> generateJson(String prompt) async => response;
}
