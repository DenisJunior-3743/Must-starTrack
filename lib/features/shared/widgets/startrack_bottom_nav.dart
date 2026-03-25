import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';

enum StarTrackNavTab {
  home,
  peers,
  inbox,
  projects,
  none,
}

class StarTrackBottomNav extends StatelessWidget {
  const StarTrackBottomNav({
    super.key,
    required this.activeTab,
    required this.onHomeTap,
    required this.onPeersTap,
    required this.onAddTap,
    required this.onInboxTap,
    required this.onProjectsTap,
  });

  final StarTrackNavTab activeTab;
  final VoidCallback onHomeTap;
  final VoidCallback onPeersTap;
  final VoidCallback onAddTap;
  final VoidCallback onInboxTap;
  final VoidCallback onProjectsTap;

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
              child: _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                active: activeTab == StarTrackNavTab.home,
                onTap: onHomeTap,
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.group_rounded,
                label: 'Peers',
                active: activeTab == StarTrackNavTab.peers,
                onTap: onPeersTap,
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
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.inbox_rounded,
                label: 'Inbox',
                active: activeTab == StarTrackNavTab.inbox,
                onTap: onInboxTap,
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.folder_open_rounded,
                label: 'My Projects',
                active: activeTab == StarTrackNavTab.projects,
                onTap: onProjectsTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = AppColors.primary;
    final idleColor = AppColors.textSecondary(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 22,
            color: active ? activeColor : idleColor,
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

