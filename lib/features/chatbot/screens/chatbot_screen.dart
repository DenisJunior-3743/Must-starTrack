import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/remote/openai_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../bloc/chatbot_cubit.dart';
import '../data/chatbot_repository.dart';
import '../models/chatbot_models.dart';

class ChatbotScreen extends StatelessWidget {
  final ChatbotRepository repository;

  const ChatbotScreen({
    super.key,
    required this.repository,
  });

  factory ChatbotScreen.standalone({Key? key}) {
    return ChatbotScreen(
      key: key,
      repository: ChatbotRepository.defaultForApp(
        openAiService: sl<OpenAiService>(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatbotCubit(
        repository: repository,
        firestore: sl<FirestoreService>(),
        activityLogDao: sl<ActivityLogDao>(),
      ),
      child: const _ChatbotView(),
    );
  }
}

class _ChatbotView extends StatefulWidget {
  const _ChatbotView();

  @override
  State<_ChatbotView> createState() => _ChatbotViewState();
}

class _ChatbotViewState extends State<_ChatbotView> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  void _scrollToLatest({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent + 120;
      if (animate) {
        _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _submit(BuildContext context, String value) {
    final text = value.trim();
    if (text.isEmpty) return;

    _inputCtrl.clear();

    final auth = sl<AuthCubit>();
    final userId = auth.currentUser?.id;
    final role = auth.currentUser?.role.name;
    final isGuest = auth.currentUser == null;

    context.read<ChatbotCubit>().ask(
          text,
          isGuest: isGuest,
          role: role,
          userId: userId,
        );

    _scrollToLatest();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'App Assistant',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: () => context.read<ChatbotCubit>().clearConversation(),
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: BlocListener<ChatbotCubit, ChatbotState>(
              listenWhen: (previous, current) {
                final prevLen = switch (previous) {
                  ChatbotIdle s => s.messages.length,
                  ChatbotTyping s => s.messages.length,
                  _ => 0,
                };
                final nextLen = switch (current) {
                  ChatbotIdle s => s.messages.length,
                  ChatbotTyping s => s.messages.length,
                  _ => 0,
                };
                return nextLen != prevLen || current is ChatbotTyping;
              },
              listener: (_, __) => _scrollToLatest(),
              child: BlocBuilder<ChatbotCubit, ChatbotState>(
                builder: (context, state) {
                  final messages = switch (state) {
                    ChatbotIdle s => s.messages,
                    ChatbotTyping s => s.messages,
                    _ => const <ChatbotMessage>[],
                  };

                  return ListView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                    children: [
                      ...messages.map(
                        (msg) => _MessageBubble(
                          message: msg,
                          onFollowUp: (prompt) => _submit(context, prompt),
                        ),
                      ),
                      if (state is ChatbotTyping) const _TypingBubble(),
                    ],
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: const Border(
                  top: BorderSide(color: AppColors.borderLight),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) => _submit(context, v),
                      decoration: InputDecoration(
                        hintText:
                            'Ask about navigation, features, or settings...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusMd),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _submit(context, _inputCtrl.text),
                    child: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatbotMessage message;
  final ValueChanged<String>? onFollowUp;

  const _MessageBubble({
    required this.message,
    this.onFollowUp,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    final bubbleColor = isUser
        ? AppColors.primary
        : (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : const Color(0xFFF1F5F9));

    final textColor = isUser ? Colors.white : AppColors.textPrimary(context);
    final actorUserId = sl<AuthCubit>().currentUser?.id;
    final canSendFeedback =
        !isUser && message.interactionId != null && actorUserId != null;
    final canShowFollowUps =
        !isUser && message.followUps.isNotEmpty && onFollowUp != null;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.35,
                  color: textColor,
                ),
              ),
              if (canShowFollowUps) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: message.followUps
                      .take(3)
                      .map(
                        (followUp) => ActionChip(
                          label: Text(
                            followUp,
                            style: GoogleFonts.plusJakartaSans(fontSize: 11),
                          ),
                          onPressed: () => onFollowUp?.call(followUp),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              if (canSendFeedback) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: Text(
                        'Helpful',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11),
                      ),
                      selected: message.isHelpful == true,
                      onSelected: (_) =>
                          context.read<ChatbotCubit>().markHelpful(
                                interactionId: message.interactionId!,
                                isHelpful: true,
                                actorUserId: actorUserId,
                              ),
                    ),
                    FilterChip(
                      label: Text(
                        'Not Helpful',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11),
                      ),
                      selected: message.isHelpful == false,
                      onSelected: (_) =>
                          context.read<ChatbotCubit>().markHelpful(
                                interactionId: message.interactionId!,
                                isHelpful: false,
                                actorUserId: actorUserId,
                              ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E293B)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Thinking...'),
          ],
        ),
      ),
    );
  }
}
