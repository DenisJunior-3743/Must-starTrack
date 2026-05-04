// lib/features/notifications/screens/notification_center_screen.dart
//
// MUST StarTrack - Notification Center Screen
//
// Modern glow-shell design:
//   Gradient background + ambient glow blobs
//   Modern pill tab bar
//   Cards with unread accent left-border + tinted bg
//   Sender display pictures with type badge overlay
//   Read items: flat, muted; Unread: elevated + accent

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/notification_dao.dart';
import '../bloc/notification_cubit.dart';

// -- Glow blob ---------------------------------------------------------------

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
          boxShadow: [BoxShadow(color: color, blurRadius: 80, spreadRadius: 25)],
        ),
      ),
    );
  }
}

// -- Screen ------------------------------------------------------------------

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  static const _tabFilters = <String?>[null, 'requests', 'opportunity', 'system'];
  static const _tabLabels = ['All', 'Requests', 'Opportunities', 'System'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocBuilder<NotificationCubit, NotificationState>(
      builder: (context, state) {
        final notifs = state is NotificationsLoaded
            ? state.notifications
            : <NotificationModel>[];
        final unread = state is NotificationsLoaded ? state.unreadCount : 0;
        final loading = state is NotificationsLoading;

        List<NotificationModel> filtered(String? type) {
          if (type == null) return notifs;
          if (type == 'requests') {
            return notifs
                .where((n) => n.type == 'collaboration' || n.type == 'group_invite')
                .toList();
          }
          return notifs.where((n) => n.type == type).toList();
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: false,
          appBar: _buildAppBar(context, isDark, unread),
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
                  top: -60,
                  right: -60,
                  child: _GlowBlob(size: 200, color: Color(0x1A2563EB)),
                ),
                const Positioned(
                  bottom: -80,
                  left: -70,
                  child: _GlowBlob(size: 240, color: Color(0x151152D4)),
                ),
                loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabCtrl,
                        children: _tabFilters
                            .map((f) => _NotifList(notifs: filtered(f)))
                            .toList(),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isDark, int unread) {
    return AppBar(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: isDark
          ? const Color(0xFF0B1222).withValues(alpha: 0.95)
          : const Color(0xFFF8FBFF).withValues(alpha: 0.95),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.notifications_rounded,
                color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Notifications',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3),
            ),
          ),
          if (unread > 0) ...[
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 22),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull)),
              child: Text(
                '$unread',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (unread > 0)
          TextButton(
            onPressed: () => context.read<NotificationCubit>().markAllRead(),
            child: Text('Mark all read',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
        IconButton(
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => context.push(Routes.notificationSettings),
          tooltip: 'Notification settings',
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: _ModernTabBar(controller: _tabCtrl, labels: _tabLabels),
      ),
    );
  }
}

// -- Modern pill tab bar -----------------------------------------------------

class _ModernTabBar extends StatefulWidget {
  final TabController controller;
  final List<String> labels;
  const _ModernTabBar({required this.controller, required this.labels});

  @override
  State<_ModernTabBar> createState() => _ModernTabBarState();
}

class _ModernTabBarState extends State<_ModernTabBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTabChange);
  }

  void _onTabChange() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onTabChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: widget.labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final active = widget.controller.index == i;
          return GestureDetector(
            onTap: () => widget.controller.animateTo(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary
                    : (isDark
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : AppColors.primary.withValues(alpha: 0.08)),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.labels[i],
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? Colors.white
                      : (isDark ? Colors.white70 : AppColors.primary),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// -- Notification list -------------------------------------------------------

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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_none_rounded,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text('All caught up!',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text("You're up to date",
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppColors.textSecondaryLight)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: notifs.length,
      itemBuilder: (_, i) => _NotifTile(notif: notifs[i]),
    );
  }
}

// -- Notification tile -------------------------------------------------------

class _NotifTile extends StatelessWidget {
  final NotificationModel notif;
  const _NotifTile({required this.notif});

  bool? get _accepted {
    final v = notif.extra['accepted'];
    if (v == null) return null;
    return v as bool;
  }

  void _navigateToEntity(BuildContext context) {
    final eid = notif.entityId;
    if (eid == null || eid.isEmpty) return;
    switch (notif.type) {
      case 'collaboration':
        final postId = notif.extra['post_id'] as String?;
        if (postId != null && postId.isNotEmpty) {
          context.push('/project/$postId');
        } else {
          context.push(RouteNames.notifications);
        }
        return;
      case 'group_invite':
        context.push(RouteNames.groupDetail.replaceFirst(':groupId', eid));
        return;
      case 'like':
      case 'comment':
      case 'view':
      case 'rating':
      case 'opportunity':
      case 'achievement':
      case 'moderation':
        context.push('/project/$eid');
        return;
      case 'follow':
        context.push('/profile/$eid');
        return;
      case 'message':
        final peerId = notif.extra['peer_id'] as String? ?? notif.senderId ?? eid;
        if (peerId.isNotEmpty) context.push('/chat/$peerId');
        return;
      case 'endorsement':
        context.push('/profile/$eid');
        return;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUnread = !notif.isRead;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (isUnread) context.read<NotificationCubit>().markRead(notif.id);
            _navigateToEntity(context);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isUnread
                  ? (isDark
                      ? AppColors.primary.withValues(alpha: 0.13)
                      : AppColors.primary.withValues(alpha: 0.06))
                  : (isDark ? const Color(0xFF152035) : Colors.white),
              border: Border(
                left: isUnread
                    ? const BorderSide(color: AppColors.primary, width: 3)
                    : BorderSide.none,
              ),
              boxShadow: isUnread
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AvatarWithBadge(notif: notif),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _BodyText(notif: notif, isUnread: isUnread)),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                timeago.format(notif.createdAt),
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    color: isUnread
                                        ? AppColors.primary.withValues(alpha: 0.8)
                                        : AppColors.textSecondaryLight),
                              ),
                              if (isUnread) ...[
                                const SizedBox(height: 5),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      if (notif.detail != null) ...[
                        const SizedBox(height: 4),
                        Text(notif.detail!,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AppColors.textSecondaryLight)),
                      ],
                      if ((notif.type == 'collaboration' || notif.type == 'group_invite') &&
                          _accepted == null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: () {
                                final cubit = context.read<NotificationCubit>();
                                notif.type == 'group_invite'
                                    ? cubit.respondToGroupInvite(
                                        notificationId: notif.id, accepted: true)
                                    : cubit.respondToCollab(
                                        notificationId: notif.id, accepted: true);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 8),
                                minimumSize: Size.zero,
                                textStyle: GoogleFonts.plusJakartaSans(
                                    fontSize: 12, fontWeight: FontWeight.w700),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Accept'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () {
                                final cubit = context.read<NotificationCubit>();
                                notif.type == 'group_invite'
                                    ? cubit.respondToGroupInvite(
                                        notificationId: notif.id, accepted: false)
                                    : cubit.respondToCollab(
                                        notificationId: notif.id, accepted: false);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: BorderSide(
                                    color: AppColors.danger.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 8),
                                minimumSize: Size.zero,
                                textStyle: GoogleFonts.plusJakartaSans(
                                    fontSize: 12, fontWeight: FontWeight.w700),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Decline'),
                            ),
                          ],
                        ),
                      ],
                      if ((notif.type == 'collaboration' || notif.type == 'group_invite') &&
                          _accepted != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: (_accepted!
                                    ? AppColors.success
                                    : AppColors.danger)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                  _accepted!
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_rounded,
                                  size: 13,
                                  color: _accepted!
                                      ? AppColors.success
                                      : AppColors.danger),
                              const SizedBox(width: 5),
                              Text(
                                _accepted! ? 'Request accepted' : 'Request declined',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _accepted!
                                        ? AppColors.success
                                        : AppColors.danger),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -- Avatar with type badge overlay ------------------------------------------

class _AvatarWithBadge extends StatelessWidget {
  final NotificationModel notif;
  const _AvatarWithBadge({required this.notif});

  @override
  Widget build(BuildContext context) {
    final (badgeIcon, badgeColor) = _badgeForType(notif.type);

    Widget avatar;
    if (notif.senderName != null) {
      avatar = CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primaryTint10,
        backgroundImage:
            notif.senderPhotoUrl != null ? NetworkImage(notif.senderPhotoUrl!) : null,
        child: notif.senderPhotoUrl == null
            ? Text(
                notif.senderName![0].toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary),
              )
            : null,
      );
    } else {
      final (icon, color, bg) = switch (notif.type) {
        'opportunity' => (
            Icons.work_outline_rounded,
            AppColors.primary,
            AppColors.primaryTint10
          ),
        'achievement' => (
            Icons.local_fire_department_rounded,
            const Color(0xFFF97316),
            const Color(0xFFFFF7ED)
          ),
        'system' => (
            Icons.info_outline_rounded,
            AppColors.textSecondaryLight,
            AppColors.surfaceLight
          ),
        _ => (
            Icons.notifications_rounded,
            AppColors.primary,
            AppColors.primaryTint10
          ),
      };
      avatar = Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22),
      );
    }

    if (badgeIcon == null) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          bottom: -2,
          right: -2,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(badgeIcon, size: 11, color: Colors.white),
          ),
        ),
      ],
    );
  }

  static (IconData?, Color) _badgeForType(String type) {
    return switch (type) {
      'like' => (Icons.favorite_rounded, const Color(0xFFEF4444)),
      'comment' => (Icons.chat_bubble_rounded, AppColors.primary),
      'follow' => (Icons.person_add_rounded, const Color(0xFF10B981)),
      'collaboration' => (Icons.handshake_rounded, const Color(0xFF8B5CF6)),
      'group_invite' => (Icons.group_add_rounded, const Color(0xFF8B5CF6)),
      'endorsement' => (Icons.star_rounded, const Color(0xFFF59E0B)),
      'message' => (Icons.send_rounded, AppColors.primary),
      'rating' => (Icons.star_half_rounded, const Color(0xFFF59E0B)),
      'achievement' => (Icons.local_fire_department_rounded, const Color(0xFFF97316)),
      _ => (null, Colors.transparent),
    };
  }
}

// -- Body text ----------------------------------------------------------------

class _BodyText extends StatelessWidget {
  final NotificationModel notif;
  final bool isUnread;
  const _BodyText({required this.notif, required this.isUnread});

  @override
  Widget build(BuildContext context) {
    final baseColor = isUnread
        ? Theme.of(context).textTheme.bodyMedium?.color
        : AppColors.textSecondaryLight;
    final base = GoogleFonts.plusJakartaSans(
        fontSize: 13, height: 1.4, color: baseColor);
    final bold = base.copyWith(
        fontWeight: FontWeight.w700,
        color: Theme.of(context).textTheme.bodyMedium?.color);

    if (notif.senderName != null) {
      final senderName = notif.senderName!;
      final body = notif.body.startsWith(senderName)
          ? notif.body.substring(senderName.length).trimLeft()
          : notif.body;
      return RichText(
        text: TextSpan(
          style: base,
          children: [
            TextSpan(text: senderName, style: bold),
            TextSpan(text: ' $body'),
          ],
        ),
      );
    }

    return Text(notif.body, style: bold);
  }
}