// lib/features/shared/widgets/lecturer_bottom_nav.dart
//
// MUST StarTrack — Lecturer Navigation Bar
//
// Role-specific bottom nav rendered by MainShell when the authenticated
// user is a lecturer or staff member.
//
// Tabs:
//   Feed      — shared home feed (browse student projects)
//   My Opps   — lecturer dashboard (own opportunity posts)
//   [+]       — create an opportunity post (centre FAB)
//   Search    — advanced student search
//   Inbox     — messaging (shared with student shell)
//
// HCI Principle: Natural Mapping — each icon maps directly to the
//   lecturer's mental model of their workflow.
// HCI Principle: Consistency — same visual language as StarTrackBottomNav.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';

enum LecturerNavTab {
  feed,
  dashboard,
  search,
  inbox,
  none,
}

class LecturerBottomNav extends StatelessWidget {
  const LecturerBottomNav({
    super.key,
    required this.activeTab,
    required this.onFeedTap,
    required this.onDashboardTap,
    required this.onAddTap,
    required this.onSearchTap,
    required this.onInboxTap,
    this.unreadMessageCount = 0,
  });

  final LecturerNavTab activeTab;
  final VoidCallback onFeedTap;
  final VoidCallback onDashboardTap;
  final VoidCallback onAddTap;
  final VoidCallback onSearchTap;
  final VoidCallback onInboxTap;
  final int unreadMessageCount;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 74,
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _LecturerNavItem(
                icon: Icons.home_rounded,
                label: 'Feed',
                active: activeTab == LecturerNavTab.feed,
                onTap: onFeedTap,
              ),
            ),
            Expanded(
              child: _LecturerNavItem(
                icon: Icons.work_outline_rounded,
                label: 'My Opps',
                active: activeTab == LecturerNavTab.dashboard,
                onTap: onDashboardTap,
              ),
            ),
            Expanded(
              child: Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: onAddTap,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: AppColors.institutionalYellow,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: AppColors.institutionalTextDark,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _LecturerNavItem(
                icon: Icons.manage_search_rounded,
                label: 'Search',
                active: activeTab == LecturerNavTab.search,
                onTap: onSearchTap,
              ),
            ),
            Expanded(
              child: _LecturerNavItem(
                icon: Icons.inbox_rounded,
                label: 'Inbox',
                active: activeTab == LecturerNavTab.inbox,
                onTap: onInboxTap,
                badgeCount: unreadMessageCount,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LecturerNavItem extends StatelessWidget {
  const _LecturerNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    const activeColor = AppColors.institutionalGreen;
    final idleColor = AppColors.textSecondary(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Badge(
            isLabelVisible: badgeCount > 0,
            label: Text(badgeCount > 99 ? '99+' : '$badgeCount'),
            child:
                Icon(icon, size: 22, color: active ? activeColor : idleColor),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? activeColor : idleColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
