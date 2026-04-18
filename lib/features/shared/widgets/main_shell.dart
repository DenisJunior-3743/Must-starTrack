// lib/features/shared/widgets/main_shell.dart
//
// MUST StarTrack — Main Navigation Shell
//
// Wraps the 5 bottom-nav destinations (Home, Discover, Peers, Inbox, Projects).
// Implements the persistent bottom navigation bar shown in the wireframes.
//
// HCI Principle: Visibility — active tab is always highlighted.
// HCI Principle: Consistency — nav bar is identical across all 5 tabs.
// HCI Principle: Natural Mapping — icon + label matches mental model:
//   Home → feed, Peers → social, Inbox → messages,
//   Discover → explore, (bell icon) → notifications.
//
// Uses Material 3 NavigationBar (not the older BottomNavigationBar)
// for proper M3 indicator animation and theming.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../core/router/route_guards.dart';
import '../../messaging/bloc/message_cubit.dart';
import 'lecturer_bottom_nav.dart';
import 'startrack_bottom_nav.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  void _handleAddTap(BuildContext context) {
    final guards = sl<RouteGuards>();

    // Students, lecturers, admins and super-admins can all create content.
    if (guards.canCreatePost() || guards.canPostOpportunity()) {
      context.push(RouteNames.createPost);
      return;
    }

    // Not authenticated → prompt to sign in.
    if (!guards.isAuthenticated) {
      _showAuthRequiredModal(context);
      return;
    }

    // Authenticated but role doesn't allow posting (edge case).
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Post creation is not available for your account type.'),
      ),
    );
  }

  Future<void> _showAuthRequiredModal(BuildContext context) async {
    final from = Uri.encodeComponent(RouteNames.createPost);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border(modalContext),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Authentication Needed',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'To upload a project and showcase your competencies, please sign in or register first.',
                  style: TextStyle(height: 1.35),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(modalContext).pop();
                      context.push('${RouteNames.registerStep1}?from=$from');
                    },
                    child: const Text('Register As Student'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(modalContext).pop();
                      context.push('${RouteNames.login}?from=$from');
                    },
                    child: const Text('I Already Have An Account'),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(modalContext).pop(),
                    child: const Text('Maybe Later'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  StarTrackNavTab _currentTab(String location) {
    if (location.startsWith(RouteNames.peers)) return StarTrackNavTab.peers;
    if (location.startsWith(RouteNames.inbox)) return StarTrackNavTab.inbox;
    if (location.startsWith(RouteNames.projects)) {
      return StarTrackNavTab.projects;
    }
    if (location.startsWith(RouteNames.home) ||
        location.startsWith(RouteNames.discover)) {
      return StarTrackNavTab.home;
    }
    return StarTrackNavTab.none;
  }

  LecturerNavTab _lecturerCurrentTab(String location) {
    if (location.startsWith(RouteNames.lecturerDashboard) ||
        location.startsWith(RouteNames.lecturerApplicants) ||
        location.startsWith(RouteNames.lecturerRanking)) {
      return LecturerNavTab.dashboard;
    }
    if (location.startsWith(RouteNames.lecturerSearch)) return LecturerNavTab.search;
    if (location.startsWith(RouteNames.inbox)) return LecturerNavTab.inbox;
    if (location.startsWith(RouteNames.home) ||
        location.startsWith(RouteNames.discover)) {
      return LecturerNavTab.feed;
    }
    return LecturerNavTab.none;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final role = sl<RouteGuards>().currentRole;

    final unreadCount = () {
      final msgState = context.watch<MessageCubit>().state;
      if (msgState is ConversationsLoaded) {
        return msgState.conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
      }
      return 0;
    }();

    // Lecturers get their own nav bar with role-specific destinations.
    if (role == UserRole.lecturer) {
      return Scaffold(
        body: child,
        bottomNavigationBar: LecturerBottomNav(
          activeTab: _lecturerCurrentTab(location),
          onFeedTap: () => context.go(RouteNames.home),
          onDashboardTap: () => context.go(RouteNames.lecturerDashboard),
          onAddTap: () => _handleAddTap(context),
          onSearchTap: () => context.go(RouteNames.lecturerSearch),
          onInboxTap: () => context.go(RouteNames.inbox),
          unreadMessageCount: unreadCount,
        ),
      );
    }

    // Students, admins, super-admins — standard student nav.
    final currentTab = _currentTab(location);
    return Scaffold(
      body: child,
      bottomNavigationBar: StarTrackBottomNav(
        activeTab: currentTab,
        onHomeTap: () => context.go(RouteNames.home),
        onPeersTap: () => context.go(RouteNames.peers),
        onAddTap: () => _handleAddTap(context),
        onInboxTap: () => context.go(RouteNames.inbox),
        onProjectsTap: () => context.go(RouteNames.projects),
        unreadMessageCount: unreadCount,
      ),
    );
  }
}
