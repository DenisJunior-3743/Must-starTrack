import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/remote/gemini_service.dart';
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
        geminiService: sl<GeminiService>(),
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 220,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
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
            child: BlocBuilder<ChatbotCubit, ChatbotState>(
              builder: (context, state) {
                final messages = switch (state) {
                  ChatbotIdle s => s.messages,
                  ChatbotTyping s => s.messages,
                  _ => const <ChatbotMessage>[],
                };

                final starterPrompts =
                    state is ChatbotIdle ? state.starterPrompts : const <String>[];

                return ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                  children: [
                    ...messages.map((msg) => _MessageBubble(message: msg)),
                    if (state is ChatbotTyping) const _TypingBubble(),
                    if (messages.length <= 1 && starterPrompts.isNotEmpty)
                      _PromptChips(
                        prompts: starterPrompts,
                        onTap: (value) => _submit(context, value),
                      ),
                  ],
                );
              },
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
                        hintText: 'Ask about navigation, features, or settings...',
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

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    final bubbleColor = isUser
        ? AppColors.primary
        : (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : const Color(0xFFF1F5F9));

    final textColor = isUser ? Colors.white : AppColors.textPrimary(context);

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
              if (!isUser && message.source != null) ...[
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isUser
                            ? Colors.white24
                            : AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        message.source == ChatbotSource.faq
                            ? 'FAQ'
                            : (message.source == ChatbotSource.ai
                                ? 'AI fallback'
                                : 'Fallback'),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isUser
                              ? Colors.white
                              : AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                    if (message.confidence != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Conf ${(message.confidence! * 100).round()}%',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (!isUser && message.interactionId != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Helpful'),
                      selected: message.isHelpful == true,
                      onSelected: (_) => context.read<ChatbotCubit>().markHelpful(
                            interactionId: message.interactionId!,
                            isHelpful: true,
                            actorUserId: sl<AuthCubit>().currentUser?.id,
                          ),
                    ),
                    ChoiceChip(
                      label: const Text('Not Helpful'),
                      selected: message.isHelpful == false,
                      onSelected: (_) => context.read<ChatbotCubit>().markHelpful(
                            interactionId: message.interactionId!,
                            isHelpful: false,
                            actorUserId: sl<AuthCubit>().currentUser?.id,
                          ),
                    ),
                  ],
                ),
              ],
              if (!isUser && message.actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: message.actions
                      .map(
                        (action) => OutlinedButton(
                          onPressed: () => context.push(action.route),
                          child: Text(action.label),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              if (!isUser && message.followUps.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: message.followUps
                      .take(4)
                      .map(
                        (suggestion) => ActionChip(
                          label: Text(
                            suggestion,
                            style: GoogleFonts.plusJakartaSans(fontSize: 11),
                          ),
                          onPressed: () => context.read<ChatbotCubit>().ask(
                                suggestion,
                                isGuest: sl<AuthCubit>().currentUser == null,
                                role: sl<AuthCubit>().currentUser?.role.name,
                              userId: sl<AuthCubit>().currentUser?.id,
                              ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptChips extends StatelessWidget {
  final List<String> prompts;
  final ValueChanged<String> onTap;

  const _PromptChips({required this.prompts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: prompts
            .map(
              (p) => ActionChip(
                label: Text(
                  p,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                ),
                onPressed: () => onTap(p),
              ),
            )
            .toList(growable: false),
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
