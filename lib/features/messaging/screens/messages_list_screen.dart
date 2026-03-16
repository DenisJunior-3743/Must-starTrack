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
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/route_names.dart';

// ── Mock conversation model (Phase 5: replace with MessageDao) ────────────────

class _Conversation {
  final String id;
  final String name;
  final String? photoUrl;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;
  final bool isOnline;
  final bool isLecturer;

  const _Conversation({
    required this.id,
    required this.name,
    // ignore: unused_element_parameter
    this.photoUrl,
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCount = 0,
    this.isOnline = false,
    this.isLecturer = false,
  });
}

class MessagesListScreen extends StatefulWidget {
  const MessagesListScreen({super.key});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Sample data — Phase 5 replaces with MessageDao stream
  final _conversations = [
    _Conversation(
      id: 'c1', name: 'Dr. Jane Smith',
      lastMessage: 'I reviewed your abstract and have some feedback...',
      lastMessageAt: DateTime.now().subtract(const Duration(minutes: 15)),
      unreadCount: 2, isOnline: true, isLecturer: true,
    ),
    _Conversation(
      id: 'c2', name: 'Marcus Chen',
      lastMessage: 'Great project! Can we collaborate on the ML module?',
      lastMessageAt: DateTime.now().subtract(const Duration(hours: 2)),
      unreadCount: 1, isOnline: false,
    ),
    _Conversation(
      id: 'c3', name: 'Elena Vance',
      lastMessage: 'Sent you the dataset. Check your email!',
      lastMessageAt: DateTime.now().subtract(const Duration(hours: 5)),
      unreadCount: 0, isOnline: true,
    ),
    _Conversation(
      id: 'c4', name: 'Prof. Omar Kizza',
      lastMessage: 'Your thesis proposal has been approved.',
      lastMessageAt: DateTime.now().subtract(const Duration(days: 1)),
      unreadCount: 0, isOnline: false, isLecturer: true,
    ),
    _Conversation(
      id: 'c5', name: 'Julian Hart',
      lastMessage: 'See you at the hackathon! 🚀',
      lastMessageAt: DateTime.now().subtract(const Duration(days: 2)),
      unreadCount: 0, isOnline: false,
    ),
  ];

  List<_Conversation> get _filtered => _query.isEmpty
      ? _conversations
      : _conversations.where((c) =>
          c.name.toLowerCase().contains(_query.toLowerCase())).toList();

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
              onChanged: (v) => setState(() => _query = v),
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
            child: _filtered.isEmpty
                ? Center(
                    child: Text('No conversations found.',
                      style: GoogleFonts.lexend(color: AppColors.textSecondaryLight)))
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _ConversationTile(
                      convo: _filtered[i],
                      onTap: () => context.push(
                        '${RouteNames.chatDetail}/${_filtered[i].id}'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final _Conversation convo;
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
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primaryTint10,
              backgroundImage: convo.photoUrl != null
                  ? NetworkImage(convo.photoUrl!) : null,
              child: convo.photoUrl == null
                  ? Text(convo.name[0].toUpperCase(),
                      style: GoogleFonts.lexend(
                        fontSize: 18, fontWeight: FontWeight.w700,
                        color: AppColors.primary))
                  : null,
            ),
            if (convo.isOnline)
              Positioned(
                bottom: 2, right: 2,
                child: Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.success, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2)),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(convo.name,
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600),
              ),
            ),
            if (convo.isLecturer)
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
