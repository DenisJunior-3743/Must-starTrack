import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/local/dao/message_dao.dart';
import '../bloc/message_cubit.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessageCubit>().markThreadRead();
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    context.read<MessageCubit>().sendMessage(text);
    _msgCtrl.clear();
    Future.delayed(const Duration(milliseconds: 30), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  bool _onScroll(ScrollNotification notification, ThreadLoaded state) {
    if (notification.metrics.pixels <= 80 && !state.isLoadingMore) {
      context.read<MessageCubit>().loadMoreMessages();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          onPressed: () => context.pop(),
        ),
        title: BlocBuilder<MessageCubit, MessageState>(
          builder: (context, state) {
            final peerName = state is ThreadLoaded ? state.peerName : 'Chat';
            return Text(
              peerName,
              style:
                  GoogleFonts.lexend(fontWeight: FontWeight.w700, fontSize: 15),
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: BlocBuilder<MessageCubit, MessageState>(
              builder: (context, state) {
                if (state is ThreadLoading || state is MessageInitial) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is MessageError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(state.message, textAlign: TextAlign.center),
                    ),
                  );
                }

                if (state is! ThreadLoaded) {
                  return const SizedBox.shrink();
                }

                if (state.messages.isEmpty) {
                  return const Center(child: Text('No messages yet.'));
                }

                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) =>
                      _onScroll(notification, state),
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount:
                        state.messages.length + (state.isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == 0 && state.isLoadingMore) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }

                      final msg = state
                          .messages[state.isLoadingMore ? index - 1 : index];
                      final isMine = msg.senderId == state.currentUserId;
                      return _MessageBubble(
                        message: msg,
                        isMine: isMine,
                        onDelete: isMine
                            ? () => context
                                .read<MessageCubit>()
                                .deleteMessage(msg.id)
                            : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
          _InputBar(controller: _msgCtrl, onSend: _send),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final VoidCallback? onDelete;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          top: 6,
          bottom: 6,
          left: isMine ? 40 : 0,
          right: isMine ? 0 : 40,
        ),
        child: InkWell(
          onLongPress: onDelete,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMine ? AppColors.primary : Theme.of(context).cardColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isMine ? 14 : 2),
                bottomRight: Radius.circular(isMine ? 2 : 14),
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  message.content,
                  style: GoogleFonts.lexend(
                    fontSize: 14,
                    color: isMine ? Colors.white : null,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('hh:mm a').format(message.createdAt),
                      style: GoogleFonts.lexend(
                        fontSize: 10,
                        color: isMine
                            ? Colors.white70
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 5),
                      Icon(
                        _statusIcon(message),
                        size: 14,
                        color: message.syncStatus == 2
                            ? Colors.orange
                            : (message.isRead
                                ? Colors.lightBlueAccent
                                : Colors.white70),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(MessageModel message) {
    switch (message.syncStatus) {
      case 1:
        return message.isRead ? Icons.done_all_rounded : Icons.done_rounded;
      case 2:
        return Icons.error_outline_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _InputBar({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: const Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                maxLength: 1000,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Type a message...',
                  hintStyle: GoogleFonts.lexend(fontSize: 14),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusFull),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onSend,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(12),
              ),
              child: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
