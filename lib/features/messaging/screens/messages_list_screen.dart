// lib/features/messaging/screens/messages_list_screen.dart
//
// MUST StarTrack â€” Messages List Screen (Phase 4)
//
// Matches messages_list.html:
//   â€¢ Search conversations
//   â€¢ Unread badge on conversations
//   â€¢ Last message preview + timestamp
//   â€¢ Online presence dot
//   â€¢ Swipe-to-delete conversation
//
// HCI:
//   â€¢ Visibility: unread count badge, online dot
//   â€¢ Feedback: swipe reveals delete action
//   â€¢ Recognition: avatar initial when no photo

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/message_dao.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../bloc/message_cubit.dart';

enum _InboxFilter { all, requests, chats }

class MessagesListScreen extends StatefulWidget {
  const MessagesListScreen({super.key});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  final _searchCtrl = TextEditingController();
  _InboxFilter _filter = _InboxFilter.all;

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
        title: Text('Inbox',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
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
                hintText: 'Search conversationsâ€¦',
                hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _InboxFilter.values.map((filter) {
                return ChoiceChip(
                  label: Text(_labelForFilter(filter)),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                );
              }).toList(),
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
                      style: GoogleFonts.plusJakartaSans(color: AppColors.danger)));
                }
                final convos = state is ConversationsLoaded
                    ? state.conversations : <ConversationSummary>[];
                final requests = state is ConversationsLoaded
                    ? state.requests : <CollaborationInboxItem>[];

                final visibleRequests = _filter == _InboxFilter.chats
                    ? const <CollaborationInboxItem>[]
                    : requests;
                final visibleConvos = _filter == _InboxFilter.requests
                    ? const <ConversationSummary>[]
                    : convos;

                if (visibleRequests.isEmpty && visibleConvos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inbox_outlined,
                            size: 56, color: AppColors.primary),
                        const SizedBox(height: 12),
                        Text('Inbox is empty.',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textSecondaryLight)),
                      ],
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    if (visibleRequests.isNotEmpty) ...[
                      const _InboxSectionHeader(
                        icon: Icons.handshake_outlined,
                        title: 'Collaboration Requests',
                        subtitle: 'Requests, responses, and project follow-ups.',
                      ),
                      ...visibleRequests.map(
                        (request) => _RequestTile(
                          request: request,
                          onOpenPost: (request.postId?.isEmpty ?? true)
                              ? null
                              : () => context.push('/project/${request.postId}'),
                          onMessage: request.counterpartId.isEmpty
                              ? null
                              : () {
                                  final currentUserId = sl<AuthCubit>().currentUser?.id;
                                  if (currentUserId != null && currentUserId.isNotEmpty) {
                                    unawaited(sl<ActivityLogDao>().logAction(
                                      userId: currentUserId,
                                      action: 'start_chat',
                                      entityType: 'conversation',
                                      entityId: request.counterpartId,
                                    ));
                                  }
                                  context.push(
                                    '/chat/${request.counterpartId}',
                                    extra: {
                                      'peerName': request.counterpartName,
                                      'peerPhotoUrl': request.counterpartPhotoUrl,
                                      'isPeerLecturer': false,
                                    },
                                  );
                                },
                        ),
                      ),
                    ],
                    if (visibleConvos.isNotEmpty) ...[
                      const _InboxSectionHeader(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'Chats',
                        subtitle: 'Direct conversations and follow-up messages.',
                      ),
                      ...visibleConvos.map(
                        (convo) => _ConversationTile(
                          convo: convo,
                          onDelete: () => context.read<MessageCubit>().deleteConversation(convo.id),
                          onTap: () {
                            final currentUserId = sl<AuthCubit>().currentUser?.id;
                            if (currentUserId != null && currentUserId.isNotEmpty) {
                              unawaited(sl<ActivityLogDao>().logAction(
                                userId: currentUserId,
                                action: 'start_chat',
                                entityType: 'conversation',
                                entityId: convo.peerId,
                              ));
                            }
                            context.push(
                              '/chat/${convo.peerId}',
                              extra: {
                                'peerName': convo.peerName,
                                'peerPhotoUrl': convo.peerPhotoUrl,
                                'isPeerLecturer': convo.isPeerLecturer,
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _labelForFilter(_InboxFilter filter) {
    switch (filter) {
      case _InboxFilter.all:
        return 'All';
      case _InboxFilter.requests:
        return 'Requests';
      case _InboxFilter.chats:
        return 'Chats';
    }
  }
}

class _InboxSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InboxSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textSecondaryLight),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationSummary convo;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.convo,
    required this.onTap,
    required this.onDelete,
  });

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
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.primaryTint10,
          backgroundImage: convo.peerPhotoUrl != null
              ? NetworkImage(convo.peerPhotoUrl!) : null,
          child: convo.peerPhotoUrl == null
              ? Text(convo.peerName[0].toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.primary))
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(convo.peerName,
                style: GoogleFonts.plusJakartaSans(
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
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9, fontWeight: FontWeight.w700,
                    color: AppColors.roleLecturer)),
              ),
          ],
        ),
        subtitle: Text(convo.lastMessage,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: isUnread ? AppColors.textPrimaryLight : AppColors.textSecondaryLight,
            fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(timeago.format(convo.lastMessageAt, allowFromNow: true),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10, color: AppColors.textSecondaryLight)),
            const SizedBox(height: 4),
            if (convo.unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull)),
                child: Text(convo.unreadCount.toString(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
          ],
        ),
        onTap: onTap,
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final CollaborationInboxItem request;
  final VoidCallback? onOpenPost;
  final VoidCallback? onMessage;

  const _RequestTile({
    required this.request,
    this.onOpenPost,
    this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (request.status) {
      'accepted' => AppColors.success,
      'rejected' || 'cancelled' => AppColors.danger,
      _ => AppColors.warning,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primaryTint10,
                backgroundImage: request.counterpartPhotoUrl != null
                    ? NetworkImage(request.counterpartPhotoUrl!)
                    : null,
                child: request.counterpartPhotoUrl == null
                    ? Text(
                        request.counterpartName.isNotEmpty
                            ? request.counterpartName[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.counterpartName,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      request.isIncoming
                          ? 'Sent you a collaboration request'
                          : 'You requested collaboration',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                ),
                child: Text(
                  request.status.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            request.postTitle,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (request.message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              request.message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppColors.textSecondaryLight,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenPost,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open Post'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onMessage,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Message'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              timeago.format(request.createdAt, allowFromNow: true),
              style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textSecondaryLight),
            ),
          ),
        ],
      ),
    );
  }
}

