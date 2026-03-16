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
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';

// ── Notification model ────────────────────────────────────────────────────────

enum _NType { collaboration, message, opportunity, achievement, endorsement, system }

class _Notif {
  final String id;
  final _NType type;
  final String? senderName;
  final String? senderPhoto;
  final String body;
  final String? detail;
  final DateTime createdAt;
  bool isRead;
  bool? accepted; // for collab requests: null=pending, true=accepted, false=declined

  _Notif({
    required this.id,
    required this.type,
    this.senderName,
    // ignore: unused_element_parameter
    this.senderPhoto,
    required this.body,
    this.detail,
    required this.createdAt,
    this.isRead = false,
    // ignore: unused_element_parameter
    this.accepted,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  final _notifications = [
    _Notif(
      id: 'n1', type: _NType.collaboration, senderName: 'Marcus Chen',
      body: 'sent you a collaboration request for Neural Diagnostic Tools',
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
    _Notif(
      id: 'n2', type: _NType.message, senderName: 'Dr. Sarah Smith',
      body: 'sent you a message: "I reviewed your abstract and have some feedback..."',
      createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
    ),
    _Notif(
      id: 'n3', type: _NType.opportunity,
      body: 'New Internship: Quantum Algorithms posted in your faculty.',
      detail: 'Faculty of Advanced Computing',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      isRead: true,
    ),
    _Notif(
      id: 'n4', type: _NType.achievement,
      body: "You've reached a 7-day streak! Keep it up!",
      detail: 'Complete one more task to hit 8 days.',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      isRead: true,
    ),
    _Notif(
      id: 'n5', type: _NType.endorsement, senderName: 'Alex Rivera',
      body: 'endorsed your Python skill.',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      isRead: true,
    ),
    _Notif(
      id: 'n6', type: _NType.system,
      body: 'Your account security review is complete.',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      isRead: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  List<_Notif> _filtered(_NType? filter) {
    if (filter == null) return _notifications;
    return _notifications.where((n) => n.type == filter).toList();
  }

  void _markAllRead() {
    setState(() {
      for (final n in _notifications) { n.isRead = true; }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => !n.isRead).length;

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
              onPressed: _markAllRead,
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
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _NotifList(notifs: _filtered(null), onUpdate: () => setState(() {})),
          _NotifList(notifs: _filtered(_NType.collaboration), onUpdate: () => setState(() {})),
          _NotifList(notifs: _filtered(_NType.opportunity), onUpdate: () => setState(() {})),
          _NotifList(notifs: _filtered(_NType.system), onUpdate: () => setState(() {})),
        ],
      ),
    );
  }
}

// ── Notification list ─────────────────────────────────────────────────────────

class _NotifList extends StatelessWidget {
  final List<_Notif> notifs;
  final VoidCallback onUpdate;

  const _NotifList({required this.notifs, required this.onUpdate});

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
      itemBuilder: (_, i) => _NotifTile(notif: notifs[i], onUpdate: onUpdate),
    );
  }
}

// ── Notification tile ─────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final _Notif notif;
  final VoidCallback onUpdate;

  const _NotifTile({required this.notif, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        notif.isRead = true;
        onUpdate();
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
                  if (notif.type == _NType.collaboration &&
                      notif.accepted == null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () { notif.accepted = true; onUpdate(); },
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
                          onPressed: () { notif.accepted = false; onUpdate(); },
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
                  if (notif.type == _NType.collaboration &&
                      notif.accepted != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          notif.accepted!
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 14,
                          color: notif.accepted! ? AppColors.success : AppColors.danger),
                        const SizedBox(width: 4),
                        Text(notif.accepted! ? 'Request accepted' : 'Request declined',
                          style: GoogleFonts.lexend(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: notif.accepted! ? AppColors.success : AppColors.danger)),
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
  final _Notif notif;
  const _Leading({required this.notif});

  @override
  Widget build(BuildContext context) {
    if (notif.senderName != null) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primaryTint10,
        backgroundImage: notif.senderPhoto != null
            ? NetworkImage(notif.senderPhoto!) : null,
        child: notif.senderPhoto == null
            ? Text(notif.senderName![0].toUpperCase(),
                style: GoogleFonts.lexend(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppColors.primary))
            : null,
      );
    }

    final (icon, color, bg) = switch (notif.type) {
      _NType.opportunity => (Icons.work_outline_rounded, AppColors.primary, AppColors.primaryTint10),
      _NType.achievement => (Icons.local_fire_department_rounded, const Color(0xFFF97316), const Color(0xFFFFF7ED)),
      _NType.system => (Icons.info_outline_rounded, AppColors.textSecondaryLight, AppColors.surfaceLight),
      _ => (Icons.notifications_rounded, AppColors.primary, AppColors.primaryTint10),
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
  final _Notif notif;
  const _BodyText({required this.notif});

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.lexend(fontSize: 13, height: 1.4);
    final bold = base.copyWith(fontWeight: FontWeight.w700);

    // Simple rich text: senderName bold + rest normal
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
