// lib/features/admin/screens/admin_dashboard_screen.dart
//
// MUST StarTrack — Admin Moderation Dashboard (Phase 4)
//
// Matches admin_moderation_dashboard.html exactly:
//   • Sticky header: shield icon + notifications bell (with red dot)
//   • Summary cards: Pending Reviews | Flagged Posts | Reported Users
//   • Flagged content list:
//     - Title + reported-by
//     - Risk badge (High Risk amber / Medium / Low)
//     - Violation type with icon
//     - Review + more-options buttons
//   • Multi-select mode: floating action bar (Approve / Reject / Ban)
//   • Bottom tab bar: Overview | Queue | Users | Logs | Settings
//
// HCI:
//   • Feedback: select mode activates instantly on long-press
//   • Visibility: risk badge colour codes severity (amber/grey)
//   • Constraint: bulk actions only appear when items are selected
//   • Affordance: "Review" CTA clearly primary action per card

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';


// ── Flagged item model ────────────────────────────────────────────────────────

enum _Risk { high, medium, low }
enum _Violation { inappropriate, suspicious, spam, other }

class _FlaggedItem {
  final String id;
  final String title;
  final String reportedBy;
  final _Risk risk;
  final _Violation violation;
  bool isSelected = false;

  _FlaggedItem({
    required this.id, required this.title, required this.reportedBy,
    required this.risk, required this.violation,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _pendingReviews = 24;
  int _flaggedPosts = 18;
  final int _reportedUsers = 7;

  int _selectedTab = 0;

  final _items = [
    _FlaggedItem(
      id: 'f1', title: '"Campus Party Tonight! No ID..."',
      reportedBy: '@john_doe_99', risk: _Risk.high,
      violation: _Violation.inappropriate,
    ),
    _FlaggedItem(
      id: 'f2', title: '"Buy cheap exam papers here..."',
      reportedBy: '@academic_safety', risk: _Risk.medium,
      violation: _Violation.suspicious,
    ),
    _FlaggedItem(
      id: 'f3', title: '"StarTrack is slow today"',
      reportedBy: '@auto_mod', risk: _Risk.low,
      violation: _Violation.spam,
    ),
    _FlaggedItem(
      id: 'f4', title: '"Free money giveaway — click here"',
      reportedBy: '@safety_bot', risk: _Risk.high,
      violation: _Violation.suspicious,
    ),
  ];

  List<_FlaggedItem> get _selected =>
      _items.where((i) => i.isSelected).toList();

  void _toggleSelect(String id) {
    setState(() {
      final item = _items.firstWhere((i) => i.id == id);
      item.isSelected = !item.isSelected;
    });
  }

  void _approve() {
    setState(() {
      _items.removeWhere((i) => i.isSelected);
      _pendingReviews = (_pendingReviews - _selected.length).clamp(0, 999);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Selected posts approved.')));
  }

  void _reject() {
    setState(() {
      _flaggedPosts = (_flaggedPosts - _selected.length).clamp(0, 999);
      _items.removeWhere((i) => i.isSelected);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Selected posts rejected and removed.'),
        backgroundColor: AppColors.danger));
  }

  @override
  Widget build(BuildContext context) {
    final hasSelected = _selected.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.shield_outlined, color: AppColors.primary),
        ),
        title: Text('Moderation Dashboard',
          style: GoogleFonts.lexend(fontWeight: FontWeight.w700)),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {},
              ),
              Positioned(
                top: 10, right: 10,
                child: Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.danger, shape: BoxShape.circle)),
              ),
            ],
          ),
        ],
      ),

      body: ListView(
        padding: EdgeInsets.only(bottom: hasSelected ? 196 : 96),
        children: [
          // ── Summary cards ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SUMMARY OVERVIEW',
                  style: GoogleFonts.lexend(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryLight, letterSpacing: 0.08)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _SummaryCard(
                      icon: Icons.pending_actions_rounded,
                      iconColor: AppColors.warning,
                      value: _pendingReviews.toString(),
                      label: 'Pending Reviews',
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _SummaryCard(
                      icon: Icons.flag_rounded,
                      iconColor: AppColors.danger,
                      value: _flaggedPosts.toString(),
                      label: 'Flagged Posts',
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _SummaryCard(
                      icon: Icons.person_off_rounded,
                      iconColor: AppColors.primary,
                      value: _reportedUsers.toString(),
                      label: 'Reported Users',
                    )),
                  ],
                ),
              ],
            ),
          ),

          // ── Flagged content ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('FLAGGED CONTENT',
                  style: GoogleFonts.lexend(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryLight, letterSpacing: 0.08)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint10,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusFull)),
                  child: Text('${_items.length} New',
                    style: GoogleFonts.lexend(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._items.map((item) => _FlaggedCard(
            item: item,
            onSelect: () => _toggleSelect(item.id),
            onReview: () {},
          )),
        ],
      ),

      bottomSheet: hasSelected
          ? SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 68),
              child: _BulkActionBar(
                count: _selected.length,
                onApprove: _approve,
                onReject: _reject,
                onBan: () {},
                onDeselect: () => setState(() {
                  for (final i in _items) {
                    i.isSelected = false;
                  }
                }),
              ),
            )
          : null,

      // ── Admin bottom nav ────────────────────────────────────────────────
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (i) => setState(() => _selectedTab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Overview'),
          NavigationDestination(
            icon: Icon(Icons.playlist_add_check_outlined),
            selectedIcon: Icon(Icons.playlist_add_check_rounded),
            label: 'Queue'),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group_rounded),
            label: 'Users'),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Logs'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings'),
        ],
      ),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _SummaryCard({
    required this.icon, required this.iconColor,
    required this.value, required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.lexend(
            fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.lexend(
            fontSize: 11, color: AppColors.textSecondaryLight)),
        ],
      ),
    );
  }
}

// ── Flagged card ──────────────────────────────────────────────────────────────

class _FlaggedCard extends StatelessWidget {
  final _FlaggedItem item;
  final VoidCallback onSelect;
  final VoidCallback onReview;

  const _FlaggedCard({required this.item, required this.onSelect, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final (riskLabel, riskBg, riskFg) = switch (item.risk) {
      _Risk.high   => ('High Risk', const Color(0xFFFEF3C7), const Color(0xFFB45309)),
      _Risk.medium => ('Medium',    AppColors.surfaceLight,   AppColors.textSecondaryLight),
      _Risk.low    => ('Low',       AppColors.surfaceLight,   AppColors.textSecondaryLight),
    };

    final (violIcon, violLabel) = switch (item.violation) {
      _Violation.inappropriate => (Icons.warning_rounded, 'Inappropriate Content'),
      _Violation.suspicious    => (Icons.error_outline_rounded, 'Suspicious Activity'),
      _Violation.spam          => (Icons.block_rounded, 'Spam / Repeated Post'),
      _Violation.other         => (Icons.help_outline_rounded, 'Other'),
    };

    return GestureDetector(
      onLongPress: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: item.isSelected
              ? AppColors.primaryTint10
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(
            color: item.isSelected ? AppColors.primary : AppColors.borderLight,
            width: item.isSelected ? 1.5 : 0.8),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + risk badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                          style: GoogleFonts.lexend(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text('Reported by: ${item.reportedBy}',
                          style: GoogleFonts.lexend(
                            fontSize: 11, color: AppColors.textSecondaryLight)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: riskBg,
                      borderRadius: BorderRadius.circular(4)),
                    child: Text(riskLabel.toUpperCase(),
                      style: GoogleFonts.lexend(
                        fontSize: 9, fontWeight: FontWeight.w800,
                        color: riskFg, letterSpacing: 0.08)),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Violation type
              Row(
                children: [
                  Icon(violIcon, size: 16, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Text(violLabel,
                    style: GoogleFonts.lexend(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.danger)),
                ],
              ),
              const SizedBox(height: 12),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: AppDimensions.touchTargetMin,
                      child: ElevatedButton(
                        onPressed: onReview,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, AppDimensions.touchTargetMin),
                          maximumSize: const Size(double.infinity, AppDimensions.touchTargetMin),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text('Review',
                          style: GoogleFonts.lexend(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: AppDimensions.touchTargetMin,
                    height: AppDimensions.touchTargetMin,
                    child: OutlinedButton(
                      onPressed: onSelect,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(AppDimensions.touchTargetMin, AppDimensions.touchTargetMin),
                        maximumSize: const Size(AppDimensions.touchTargetMin, AppDimensions.touchTargetMin),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.more_horiz_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bulk action bar ───────────────────────────────────────────────────────────

class _BulkActionBar extends StatelessWidget {
  final int count;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onBan;
  final VoidCallback onDeselect;

  const _BulkActionBar({
    required this.count, required this.onApprove,
    required this.onReject, required this.onBan, required this.onDeselect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          boxShadow: const [BoxShadow(
            color: Colors.black38, blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text('$count item${count > 1 ? 's' : ''} selected',
                  style: GoogleFonts.lexend(
                    color: Colors.white, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: onDeselect,
                  child: Text('Deselect',
                    style: GoogleFonts.lexend(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: Colors.white60)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _BulkBtn(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Approve', color: AppColors.success,
                  onTap: onApprove),
                const SizedBox(width: 8),
                _BulkBtn(
                  icon: Icons.delete_outline_rounded,
                  label: 'Reject', color: AppColors.danger,
                  onTap: onReject),
                const SizedBox(width: 8),
                _BulkBtn(
                  icon: Icons.person_off_rounded,
                  label: 'Ban User', color: Colors.grey,
                  onTap: onBan),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BulkBtn({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            border: Border.all(color: color.withValues(alpha: 0.3))),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(label.toUpperCase(),
                style: GoogleFonts.lexend(
                  fontSize: 9, fontWeight: FontWeight.w800,
                  color: color, letterSpacing: 0.08)),
            ],
          ),
        ),
      ),
    );
  }
}
