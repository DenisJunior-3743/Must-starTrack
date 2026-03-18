// lib/features/notifications/screens/notification_center_screen.dart
//
// MUST StarTrack — Notification Center Screen (Phase 4)
//
// Matches notification_center.html exactly:
//   • Sticky header with settings button
//   • Tab bar: All | Requests | Opportunities | System
//   • Per-notification: avatar, body text with rich spans, timestamp
//   • Unread indicator (blue dot + tinted background)
//   • Collaboration request: Accept / Decline inline actions
//   • Opportunity: icon + department label
//   • Achievement: fire icon + streak info
//   • Endorsement: skill name highlighted
//   • System: info icon
//   • Mark all read button
//
// HCI:
//   • Feedback: Accept/Decline buttons resolve inline (no navigation)
//   • Chunking: tabs group notifications by type (reduces cognitive load)
//   • Visibility: unread dot + tinted row for unread items

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/local/dao/notification_dao.dart';
import '../bloc/notification_cubit.dart';


// ── Screen ────────────────────────────────────────────────────────────────────

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // Tab index → notification type filter (null = all)
  static const _tabFilters = <String?>[null, 'collaboration', 'opportunity', 'system'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    // Reload each time the user opens this screen so it stays fresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationCubit>().loadNotifications();
    });
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
        final notifs = state is NotificationsLoaded ? state.notifications : <NotificationModel>[];
        final unread  = state is NotificationsLoaded ? state.unreadCount : 0;
        final loading = state is NotificationsLoading;

        List<NotificationModel> filtered(String? type) {
          if (type == null) return notifs;
          return notifs.where((n) => n.type == type).toList();
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.star_rate_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notifications',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.lexend(fontWeight: FontWeight.w700),
                  ),
                ),
                if (unread > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppDimensions.radiusFull)),
                    child: Text('$unread',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lexend(
                        fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ],
            ),
            actions: [
              if (unread > 0)
                TextButton(
                  onPressed: () => context.read<NotificationCubit>().markAllRead(),
                  child: Text('Mark all read',
                    style: GoogleFonts.lexend(
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {},
                tooltip: 'Notification settings',
              ),
            ],
            bottom: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondaryLight,
              tabs: const [
                Tab(text: 'All'),
                Tab(text: 'Requests'),
                Tab(text: 'Opportunities'),
                Tab(text: 'System'),
              ],
            ),
          ),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabCtrl,
                  children: _tabFilters.map((filter) =>
                    _NotifList(notifs: filtered(filter)),
                  ).toList(),
                ),
        );
      },
    );
  }
}

// ── Notification list ─────────────────────────────────────────────────────────

class _NotifList extends StatelessWidget {
  final List<NotificationModel> notifs;

  const _NotifList({required this.notifs});

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
            Text('All caught up!',
              style: GoogleFonts.lexend(
                fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: notifs.length,
      itemBuilder: (_, i) => _NotifTile(notif: notifs[i]),
    );
  }
}

// ── Notification tile ─────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final NotificationModel notif;

  const _NotifTile({required this.notif});

  bool? get _accepted {
    final v = notif.extra['accepted'];
    if (v == null) return null;
    return v as bool;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        if (!notif.isRead) {
          context.read<NotificationCubit>().markRead(notif.id);
        }
      },
      child: Container(
        color: notif.isRead
            ? Colors.transparent
            : AppColors.primary.withValues(alpha: 0.05),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leading icon / avatar
            _Leading(notif: notif),
            const SizedBox(width: 14),

            // Body
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _BodyText(notif: notif)),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          Text(timeago.format(notif.createdAt),
                            style: GoogleFonts.lexend(
                              fontSize: 10, color: AppColors.textSecondaryLight)),
                          if (!notif.isRead)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary, shape: BoxShape.circle)),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (notif.detail != null) ...[
                    const SizedBox(height: 4),
                    Text(notif.detail!,
                      style: GoogleFonts.lexend(
                        fontSize: 12, color: AppColors.textSecondaryLight)),
                  ],
                  // Accept / Decline for collaboration requests
                  if (notif.type == 'collaboration' && _accepted == null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () => context.read<NotificationCubit>()
                              .respondToCollab(notificationId: notif.id, accepted: true),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            minimumSize: Size.zero,
                            textStyle: GoogleFonts.lexend(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                          child: const Text('Accept'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => context.read<NotificationCubit>()
                              .respondToCollab(notificationId: notif.id, accepted: false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            minimumSize: Size.zero,
                            textStyle: GoogleFonts.lexend(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                          child: const Text('Decline'),
                        ),
                      ],
                    ),
                  ],
                  if (notif.type == 'collaboration' && _accepted != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          _accepted!
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 14,
                          color: _accepted! ? AppColors.success : AppColors.danger),
                        const SizedBox(width: 4),
                        Text(_accepted! ? 'Request accepted' : 'Request declined',
                          style: GoogleFonts.lexend(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: _accepted! ? AppColors.success : AppColors.danger)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Leading extends StatelessWidget {
  final NotificationModel notif;
  const _Leading({required this.notif});

  @override
  Widget build(BuildContext context) {
    if (notif.senderName != null) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primaryTint10,
        backgroundImage: notif.senderPhotoUrl != null
            ? NetworkImage(notif.senderPhotoUrl!) : null,
        child: notif.senderPhotoUrl == null
            ? Text(notif.senderName![0].toUpperCase(),
                style: GoogleFonts.lexend(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppColors.primary))
            : null,
      );
    }

    final (icon, color, bg) = switch (notif.type) {
      'opportunity' => (Icons.work_outline_rounded, AppColors.primary, AppColors.primaryTint10),
      'achievement' => (Icons.local_fire_department_rounded, const Color(0xFFF97316), const Color(0xFFFFF7ED)),
      'system'      => (Icons.info_outline_rounded, AppColors.textSecondaryLight, AppColors.surfaceLight),
      _             => (Icons.notifications_rounded, AppColors.primary, AppColors.primaryTint10),
    };

    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd)),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _BodyText extends StatelessWidget {
  final NotificationModel notif;
  const _BodyText({required this.notif});

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.lexend(fontSize: 13, height: 1.4);
    final bold = base.copyWith(fontWeight: FontWeight.w700);

    if (notif.senderName != null) {
      return RichText(
        text: TextSpan(
          style: base.copyWith(
            color: Theme.of(context).textTheme.bodyMedium?.color),
          children: [
            TextSpan(text: notif.senderName, style: bold),
            TextSpan(text: ' ${notif.body}'),
          ],
        ),
      );
    }

    return Text(notif.body, style: base.copyWith(
      color: Theme.of(context).textTheme.bodyMedium?.color));
  }
}
