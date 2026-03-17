import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:must_startrack/data/local/dao/message_dao.dart';
import 'package:must_startrack/data/repositories/message_repository.dart';
import 'package:must_startrack/features/messaging/bloc/message_cubit.dart';

class _MockMessageRepository extends Mock implements MessageRepository {}

void main() {
  late _MockMessageRepository repo;

  final conversation = ConversationSummary(
    id: 'c1',
    peerId: 'p1',
    peerName: 'Jane',
    peerPhotoUrl: null,
    lastMessage: 'Hello',
    lastMessageAt: DateTime.fromMillisecondsSinceEpoch(1000),
    unreadCount: 1,
  );

  setUp(() {
    repo = _MockMessageRepository();
  });

  blocTest<MessageCubit, MessageState>(
    'emits error when unauthenticated tries loading conversations',
    build: () => MessageCubit(repository: repo, currentUserId: () => null),
    act: (cubit) => cubit.loadConversations(),
    expect: () => [const MessageError('Please sign in to access inbox.')],
  );

  blocTest<MessageCubit, MessageState>(
    'loads and emits conversations for authenticated user',
    build: () {
      when(() => repo.watchConversations('u1'))
          .thenAnswer((_) => Stream.value([conversation]));
      when(() => repo.loadConversations(
              userId: 'u1', pageSize: any(named: 'pageSize')))
          .thenAnswer((_) async => [conversation]);
      return MessageCubit(repository: repo, currentUserId: () => 'u1');
    },
    act: (cubit) => cubit.loadConversations(),
    expect: () => [
      const ConversationsLoading(),
      ConversationsLoaded(conversations: [conversation], hasMore: false),
    ],
  );

  blocTest<MessageCubit, MessageState>(
    'sendMessage delegates to repository when thread is loaded',
    build: () {
      when(() => repo.sendMessage(
            userId: 'u1',
            conversationId: 'c1',
            text: 'Hi there',
          )).thenAnswer((_) async {});
      return MessageCubit(repository: repo, currentUserId: () => 'u1');
    },
    seed: () => const ThreadLoaded(
      conversationId: 'c1',
      currentUserId: 'u1',
      peerName: 'Jane',
      messages: [],
    ),
    act: (cubit) => cubit.sendMessage('Hi there'),
    verify: (_) {
      verify(() => repo.sendMessage(
            userId: 'u1',
            conversationId: 'c1',
            text: 'Hi there',
          )).called(1);
    },
  );
}
