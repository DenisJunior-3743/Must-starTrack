// lib/features/messaging/screens/messages_list_screen.dart
//
// MUST StarTrack — Messages List Screen (Phase 4)
//
// Matches messages_list.html:
//   • Search conversations
//   • Unread badge on conversations
//   • Last message preview + timestamp
//   • Online presence dot
//   • Swipe-to-delete conversation
//
// HCI:
//   • Visibility: unread count badge, online dot
//   • Feedback: swipe reveals delete action
//   • Recognition: avatar initial when no photo

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/message_dao.dart';
import '../bloc/message_cubit.dart';

class MessagesListScreen extends StatefulWidget {
  const MessagesListScreen({super.key});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MessageCubit>().loadConversations();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Messages',
          style: GoogleFonts.lexend(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () {},
            tooltip: 'New message',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                if (v.trim().isEmpty) {
                  context.read<MessageCubit>().loadConversations();
                } else {
                  context.read<MessageCubit>().searchConversations(v.trim());
                }
              },
              decoration: InputDecoration(
                hintText: 'Search conversations…',
                hintStyle: GoogleFonts.lexend(fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          // Conversation list
          Expanded(
            child: BlocBuilder<MessageCubit, MessageState>(
              builder: (context, state) {
                if (state is ConversationsLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is MessageError) {
                  return Center(
                    child: Text(state.message,
                      style: GoogleFonts.lexend(color: AppColors.danger)));
                }
                final convos = state is ConversationsLoaded
                    ? state.conversations : <ConversationSummary>[];

                if (convos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded,
                            size: 56, color: AppColors.primary),
                        const SizedBox(height: 12),
                        Text('No conversations yet.',
                          style: GoogleFonts.lexend(
                            color: AppColors.textSecondaryLight)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: convos.length,
                  itemBuilder: (_, i) => _ConversationTile(
                    convo: convos[i],
                    onTap: () => context.push(
                      '${RouteNames.chatDetail}/${convos[i].id}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationSummary convo;
  final VoidCallback onTap;

  const _ConversationTile({required this.convo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isUnread = convo.unreadCount > 0;

    return Dismissible(
      key: Key(convo.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppColors.danger,
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 28),
      ),
      onDismissed: (_) {}, // Phase 5: delete conversation
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.primaryTint10,
          backgroundImage: convo.peerPhotoUrl != null
              ? NetworkImage(convo.peerPhotoUrl!) : null,
          child: convo.peerPhotoUrl == null
              ? Text(convo.peerName[0].toUpperCase(),
                  style: GoogleFonts.lexend(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.primary))
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(convo.peerName,
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600),
              ),
            ),
            if (convo.isPeerLecturer)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.roleLecturer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull)),
                child: Text('Lecturer',
                  style: GoogleFonts.lexend(
                    fontSize: 9, fontWeight: FontWeight.w700,
                    color: AppColors.roleLecturer)),
              ),
          ],
        ),
        subtitle: Text(convo.lastMessage,
          style: GoogleFonts.lexend(
            fontSize: 12,
            color: isUnread ? AppColors.textPrimaryLight : AppColors.textSecondaryLight,
            fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(timeago.format(convo.lastMessageAt, allowFromNow: true),
              style: GoogleFonts.lexend(
                fontSize: 10, color: AppColors.textSecondaryLight)),
            const SizedBox(height: 4),
            if (convo.unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull)),
                child: Text(convo.unreadCount.toString(),
                  style: GoogleFonts.lexend(
                    fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
