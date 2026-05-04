// lib/features/messaging/screens/messages_list_screen.dart
//
// MUST StarTrack â€” Messages List Screen (Phase 4)
//
// Matches messages_list.html:
//    Search conversations
//    Unread badge on conversations
//    Last message preview + timestamp
//    Online presence dot
//    Swipe-to-delete conversation
//
// HCI:
//    Visibility: unread count badge, online dot
//      Feedback: swipe reveals delete action
//      Recognition: avatar initial when no photo

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/message_dao.dart';
import '../../../data/remote/firestore_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../shared/widgets/guest_auth_required_view.dart';
import '../bloc/message_cubit.dart';

enum _InboxFilter { requests, chats }

class MessagesListScreen extends StatefulWidget {
  const MessagesListScreen({super.key});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  final _searchCtrl = TextEditingController();
  _InboxFilter _filter = _InboxFilter.chats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MessageCubit>().ensureConversationsLoaded(
            staleAfter: const Duration(minutes: 2),
          );
      context.read<MessageCubit>().markIncomingRequestsViewed();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGuest = sl<AuthCubit>().currentUser == null;

    if (isGuest) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Inbox',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
        ),
        body: const GuestAuthRequiredView(
          icon: Icons.mark_chat_unread_rounded,
          title: 'Sign in to access Inbox',
          subtitle:
              'Please authenticate to send messages, view conversations, and manage collaboration requests.',
          fromRoute: RouteNames.inbox,
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF0B1222).withValues(alpha: 0.92)
            : const Color(0xFFF8FBFF).withValues(alpha: 0.92),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Inbox',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.2,
            color: isDark
                ? AppColors.textPrimaryDark
                : AppColors.textPrimaryLight,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => context.push(RouteNames.peers),
            tooltip: 'New message',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF0B1222), Color(0xFF111D36)]
                : const [Color(0xFFF8FBFF), Color(0xFFECF3FF)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -84,
              right: -70,
              child: _GlowBlob(size: 220, color: Color(0x332563EB)),
            ),
            const Positioned(
              bottom: -90,
              left: -85,
              child: _GlowBlob(size: 260, color: Color(0x221152D4)),
            ),
            Column(
              children: [
                SizedBox(
                  height:
                      MediaQuery.of(context).padding.top + kToolbarHeight + 6,
                ),
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) {
                      if (v.trim().isEmpty) {
                        context.read<MessageCubit>().loadConversations();
                      } else {
                        context
                            .read<MessageCubit>()
                            .searchConversations(v.trim());
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Search conversations',
                      hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: BlocBuilder<MessageCubit, MessageState>(
                    buildWhen: (prev, next) =>
                        prev is ConversationsLoaded != next is ConversationsLoaded ||
                        (prev is ConversationsLoaded &&
                            next is ConversationsLoaded &&
                            (prev.conversations != next.conversations ||
                                prev.requests != next.requests)),
                    builder: (context, state) {
                      int chatCount = 0;
                      int requestCount = 0;
                      if (state is ConversationsLoaded) {
                        chatCount = state.conversations
                            .where((c) => c.unreadCount > 0)
                            .length;
                        requestCount = state.requests
                            .where((r) =>
                                r.isIncoming && r.receiverViewedAt == null)
                            .length;
                      }
                      return _InboxSegmentedControl(
                        value: _filter,
                        onChanged: (value) =>
                            setState(() => _filter = value),
                        chatCount: chatCount,
                        requestCount: requestCount,
                      );
                    },
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
                                style: GoogleFonts.plusJakartaSans(
                                    color: AppColors.danger)));
                      }
                      final convos = state is ConversationsLoaded
                          ? state.conversations
                          : <ConversationSummary>[];
                      final requests = state is ConversationsLoaded
                          ? state.requests
                          : <CollaborationInboxItem>[];

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
                              title: 'Requests',
                              subtitle: 'Collaboration and project follow-ups',
                            ),
                            ...visibleRequests.map(
                              (request) => _RequestTile(
                                request: request,
                                onOpenPost: (request.postId?.isEmpty ?? true)
                                    ? null
                                    : () async {
                                        await context
                                            .read<MessageCubit>()
                                            .markCollaborationRequestViewed(
                                              request.id,
                                            );
                                        if (!context.mounted) return;
                                        await context
                                            .push('/project/${request.postId}');
                                      },
                                onMessage: request.counterpartId.isEmpty
                                    ? null
                                    : () async {
                                        await context
                                            .read<MessageCubit>()
                                            .markCollaborationRequestViewed(
                                              request.id,
                                            );
                                        if (!context.mounted) return;
                                        final currentUserId =
                                            sl<AuthCubit>().currentUser?.id;
                                        if (currentUserId != null &&
                                            currentUserId.isNotEmpty) {
                                          unawaited(sl<ActivityLogDao>()
                                              .logAction(
                                            userId: currentUserId,
                                            action: 'start_chat',
                                            entityType: 'conversation',
                                            entityId: request.counterpartId,
                                          ));
                                        }
                                        await context.push(
                                          '/chat/${request.counterpartId}',
                                          extra: {
                                            'peerName': request.counterpartName,
                                            'peerPhotoUrl':
                                                request.counterpartPhotoUrl,
                                            'isPeerLecturer': false,
                                          },
                                        );
                                        if (!context.mounted) return;
                                        context
                                            .read<MessageCubit>()
                                            .refreshConversations(
                                              syncRemoteFirst: false,
                                            );
                                      },
                              ),
                            ),
                          ],
                          if (visibleConvos.isNotEmpty) ...[
                            const _InboxSectionHeader(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: 'Chats',
                              subtitle: 'Direct conversations',
                            ),
                            ...visibleConvos.map(
                              (convo) => _ConversationTile(
                                convo: convo,
                                onDelete: () => context
                                    .read<MessageCubit>()
                                    .deleteConversation(convo.id),
                                onTap: () async {
                                  await context
                                      .read<MessageCubit>()
                                      .markConversationVisited(convo.id);
                                  if (!context.mounted) return;
                                  final currentUserId =
                                      sl<AuthCubit>().currentUser?.id;
                                  if (currentUserId != null &&
                                      currentUserId.isNotEmpty) {
                                    unawaited(sl<ActivityLogDao>().logAction(
                                      userId: currentUserId,
                                      action: 'start_chat',
                                      entityType: 'conversation',
                                      entityId: convo.peerId,
                                    ));
                                  }
                                  await context.push(
                                    '/chat/${convo.peerId}',
                                    extra: {
                                      'peerName': convo.peerName,
                                      'peerPhotoUrl': convo.peerPhotoUrl,
                                      'isPeerLecturer': convo.isPeerLecturer,
                                    },
                                  );
                                  if (!context.mounted) return;
                                  context
                                      .read<MessageCubit>()
                                      .refreshConversations(
                                        syncRemoteFirst: false,
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
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  String _labelForFilter(_InboxFilter filter) {
    switch (filter) {
      case _InboxFilter.requests:
        return 'Requests';
      case _InboxFilter.chats:
        return 'Chats';
    }
  }
}

class _InboxSegmentedControl extends StatelessWidget {
  final _InboxFilter value;
  final ValueChanged<_InboxFilter> onChanged;
  final int chatCount;
  final int requestCount;

  const _InboxSegmentedControl({
    required this.value,
    required this.onChanged,
    this.chatCount = 0,
    this.requestCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _InboxSegmentButton(
              label: 'Chats',
              selected: value == _InboxFilter.chats,
              count: chatCount,
              onTap: () => onChanged(_InboxFilter.chats),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _InboxSegmentButton(
              label: 'Requests',
              selected: value == _InboxFilter.requests,
              count: requestCount,
              onTap: () => onChanged(_InboxFilter.requests),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxSegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int count;

  const _InboxSegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count = 0,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor =
        selected ? Colors.white : AppColors.textSecondary(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF10B981) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: labelColor,
              ),
            ),
            if (count > 0) ...
              [
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.28)
                        : const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : Colors.white,
                    ),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
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
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5, color: AppColors.textSecondaryLight),
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
    final firestore = sl<FirestoreService>();

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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.primaryTint10,
                backgroundImage: convo.peerPhotoUrl != null
                    ? NetworkImage(convo.peerPhotoUrl!)
                    : null,
                child: convo.peerPhotoUrl == null
                    ? Text(convo.peerName[0].toUpperCase(),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary))
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: StreamBuilder<UserDevicePresenceSummary>(
                  stream: firestore.watchUserDevicePresence(convo.peerId),
                  builder: (context, snapshot) {
                    final isOnline = snapshot.data?.isOnline ?? false;
                    return Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? AppColors.success
                            : AppColors.textSecondaryLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  convo.peerName,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600),
                ),
              ),
              if (convo.isPeerLecturer)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppColors.roleLecturer.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusFull)),
                  child: Text('Lecturer',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.roleLecturer)),
                ),
            ],
          ),
          subtitle: Text(convo.lastMessage,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: isUnread
                      ? AppColors.textPrimaryLight
                      : AppColors.textSecondaryLight,
                  fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusFull)),
                  child: Text(convo.unreadCount.toString(),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
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
    final aiFitScore = request.aiFitScore;

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
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15, fontWeight: FontWeight.w800),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            'PROJECT',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondaryLight,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            request.postTitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
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
          if (request.isIncoming && aiFitScore != null) ...[
            const SizedBox(height: 12),
            _RequestFitPanel(request: request),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ActionIconButton(
                icon: Icons.open_in_new_rounded,
                tooltip: 'Open post',
                onTap: onOpenPost,
              ),
              const SizedBox(width: 8),
              _ActionIconButton(
                icon: Icons.chat_bubble_outline_rounded,
                tooltip: 'Message',
                onTap: onMessage,
                filled: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              timeago.format(request.createdAt, allowFromNow: true),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: AppColors.textSecondaryLight),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool filled;

  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF10B981);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? green : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: filled ? BorderSide.none : const BorderSide(color: green),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: 18,
              color: filled ? Colors.white : green,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            radius: 0.9,
          ),
        ),
      ),
    );
  }
}

class _RequestFitPanel extends StatelessWidget {
  final CollaborationInboxItem request;

  const _RequestFitPanel({required this.request});

  @override
  Widget build(BuildContext context) {
    final score = request.aiFitScore ?? 0;
    final stars = (score * 5).clamp(1, 5).round();
    final reasons = request.aiReasons.map(_reasonLabel).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryTint10,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph_rounded,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'AI fit for this collaborator',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              Text(
                '${(score * 100).round()}%',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (index) {
              final filled = index < stars;
              return Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 16,
                  color: filled ? AppColors.warning : AppColors.borderLight,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: score.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              color: AppColors.primary,
            ),
          ),
          if (request.aiMatchedSkills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: request.aiMatchedSkills.take(4).map((skill) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusFull),
                  ),
                  child: Text(
                    skill,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: reasons.take(3).map((reason) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusFull),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Text(
                    reason,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  static String _reasonLabel(String reason) {
    switch (reason) {
      case 'skill_match':
        return 'Skill match';
      case 'complementary_skills':
        return 'Complementary skills';
      case 'faculty_match':
        return 'Same faculty';
      case 'program_match':
        return 'Same program';
      case 'search_intent':
        return 'Matches your interest';
      default:
        return reason.replaceAll('_', ' ');
    }
  }
}
