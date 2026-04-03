// lib/features/admin/screens/admin_notifications_screen.dart
//
// MUST StarTrack — Admin Notifications Screen
//
// Shows notifications addressed to the currently signed-in admin:
//   • New pending posts waiting for moderation review
//   • System events and other admin-scoped messages
//
// The notification pipeline:
//   1. User posts a project → SyncService._fanoutModerationNotifications()
//      writes a Firestore notification doc (type='moderation') for every admin.
//   2. SyncService._startWatchingNotifications() (Firestore real-time listener)
//      detects the new doc and fires a local push alert immediately.
//   3. Admin opens this screen → NotificationCubit loads from local SQLite
//      (already synced) and renders the list.
//   4. Tapping a moderation notification navigates to PostModerationReviewScreen.
//   5. After admin approves/rejects, SyncService sends a 'moderation' result
//      notification to the post author (handled in _fanoutModerationNotifications).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/notification_dao.dart';
import '../../notifications/bloc/notification_cubit.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class AdminNotificationsScreen extends StatelessWidget {
  const AdminNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NotificationCubit>(
      create: (_) => sl<NotificationCubit>()..loadNotifications(),
      child: const _AdminNotifBody(),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _AdminNotifBody extends StatefulWidget {
  const _AdminNotifBody();

  @override
  State<_AdminNotifBody> createState() => _AdminNotifBodyState();
}

class _AdminNotifBodyState extends State<_AdminNotifBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  static const _tabs = <_Tab>[
    _Tab(label: 'All', filter: null),
    _Tab(label: 'Moderation', filter: 'moderation'),
    _Tab(label: 'System', filter: 'system'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationCubit, NotificationState>(
      builder: (context, state) {
        final notifs = state is NotificationsLoaded
            ? state.notifications
            : <NotificationModel>[];
        final unread = state is NotificationsLoaded ? state.unreadCount : 0;
        final loading = state is NotificationsLoading;

        List<NotificationModel> filtered(String? type) {
          if (type == null) return notifs;
          return notifs.where((n) => n.type == type).toList();
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.notifications_active_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Admin Notifications',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700),
                  ),
                ),
                if (unread > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints:
                        const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (unread > 0)
                TextButton(
                  onPressed: () =>
                      context.read<NotificationCubit>().markAllRead(),
                  child: Text(
                    'Mark all read',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
            bottom: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondaryLight,
              onTap: (index) {
                context
                    .read<NotificationCubit>()
                    .loadNotifications(type: _tabs[index].filter);
              },
              tabs: _tabs
                  .map((t) => Tab(text: t.label))
                  .toList(),
            ),
          ),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabCtrl,
                  children: _tabs
                      .map((t) => _AdminNotifList(
                            notifs: filtered(t.filter),
                          ))
                      .toList(),
                ),
        );
      },
    );
  }
}

// ── Tab descriptor ────────────────────────────────────────────────────────────

class _Tab {
  final String label;
  final String? filter;
  const _Tab({required this.label, required this.filter});
}

// ── Notification list ─────────────────────────────────────────────────────────

class _AdminNotifList extends StatelessWidget {
  final List<NotificationModel> notifs;

  const _AdminNotifList({required this.notifs});

  @override
  Widget build(BuildContext context) {
    if (notifs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_none_rounded,
                size: 56, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              'All caught up!',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'No notifications yet.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.textSecondaryLight),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          context.read<NotificationCubit>().loadNotifications(),
      child: ListView.separated(
        itemCount: notifs.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 64),
        itemBuilder: (_, i) => _AdminNotifTile(notif: notifs[i]),
      ),
    );
  }
}

// ── Notification tile ─────────────────────────────────────────────────────────

class _AdminNotifTile extends StatelessWidget {
  final NotificationModel notif;

  const _AdminNotifTile({required this.notif});

  IconData _iconFor(String type) {
    switch (type) {
      case 'moderation':
        return Icons.pending_actions_rounded;
      case 'collaboration':
        return Icons.handshake_outlined;
      case 'system':
        return Icons.info_outline_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'moderation':
        return AppColors.warning;
      case 'collaboration':
        return AppColors.primary;
      case 'system':
        return AppColors.textSecondaryLight;
      default:
        return AppColors.primary;
    }
  }

  void _handleTap(BuildContext context) {
    if (!notif.isRead) {
      context.read<NotificationCubit>().markRead(notif.id);
    }

    final eid = notif.entityId;
    if (eid == null || eid.isEmpty) return;

    switch (notif.type) {
      case 'moderation':
        // Navigate to post review screen so admin can act immediately.
        context.push(
          RouteNames.adminPostReview.replaceFirst(':postId', eid),
        );
      case 'collaboration':
      case 'opportunity':
        context.push('/project/$eid');
      default:
        // Nothing to navigate to — mark read was enough.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _colorFor(notif.type);
    final isUnread = !notif.isRead;

    return InkWell(
      onTap: () => _handleTap(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: isUnread
            ? AppColors.primary.withValues(alpha: 0.05)
            : Colors.transparent,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leading icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_iconFor(notif.type),
                  size: 22, color: iconColor),
            ),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender + timestamp row
                  Row(
                    children: [
                      if (notif.senderName != null) ...[
                        Flexible(
                          child: Text(
                            notif.senderName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        timeago.format(notif.createdAt),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),

                  // Body
                  Text(
                    notif.body,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: isUnread
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),

                  // Detail subtext
                  if (notif.detail != null &&
                      notif.detail!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      notif.detail!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  ],

                  // "Review" CTA for moderation notifications
                  if (notif.type == 'moderation' &&
                      notif.entityId != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Tap to review →',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Unread dot
            if (isUnread)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
