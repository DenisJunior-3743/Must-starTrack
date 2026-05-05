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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/router/route_names.dart';
import '../../../core/router/route_guards.dart';
import '../../messaging/bloc/message_cubit.dart';
import 'lecturer_bottom_nav.dart';
import 'startrack_bottom_nav.dart';

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final ConnectivityService _connectivityService = sl<ConnectivityService>();
  StreamSubscription<bool>? _connectivitySub;
  Timer? _onlineBannerTimer;
  bool _isOnline = true;
  bool _showOnlineBanner = false;
  final int _lastUnreadCount = 0;

  void _setStateAfterPointerFrame(VoidCallback update) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(update);
    });
  }

  @override
  void initState() {
    super.initState();
    _isOnline = _connectivityService.isOnline;

    _connectivityService.checkConnectivity().then((online) {
      if (!mounted) return;
      _setStateAfterPointerFrame(() => _isOnline = online);
    });

    _connectivitySub =
        _connectivityService.onConnectivityChanged.listen((online) {
      if (!mounted) return;
      final wasOnline = _isOnline;
      _setStateAfterPointerFrame(() {
        _isOnline = online;
        if (!online) {
          _showOnlineBanner = false;
        }
      });

      if (online && !wasOnline) {
        _setStateAfterPointerFrame(() => _showOnlineBanner = true);
        _onlineBannerTimer?.cancel();
        _onlineBannerTimer = Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          _setStateAfterPointerFrame(() => _showOnlineBanner = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _onlineBannerTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

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
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
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
    if (location.startsWith(RouteNames.globalRanks)) {
      return StarTrackNavTab.leaderboard;
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
    if (location.startsWith(RouteNames.lecturerLeaderboard)) {
      return LecturerNavTab.leaderboard;
    }
    if (location.startsWith(RouteNames.inbox)) return LecturerNavTab.inbox;
    if (location.startsWith(RouteNames.home) ||
        location.startsWith(RouteNames.discover)) {
      return LecturerNavTab.feed;
    }
    return LecturerNavTab.none;
  }

  Widget _withNetworkIndicator(BuildContext context, Widget scaffold) {
    final showBanner = !_isOnline || _showOnlineBanner;
    final isOffline = !_isOnline;
    final bannerColor = isOffline ? Colors.black : AppColors.success;
    final message = isOffline ? 'No internet connection' : 'Back online';
    final icon = isOffline ? Icons.wifi_off_rounded : Icons.wifi_rounded;

    return Stack(
      children: [
        Positioned.fill(child: scaffold),
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(context).padding.top + 8,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                reverseDuration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final fade = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                  );
                  final slide = Tween<Offset>(
                    begin: const Offset(0, -0.35),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ));

                  return FadeTransition(
                    opacity: fade,
                    child: SlideTransition(
                      position: slide,
                      child: child,
                    ),
                  );
                },
                child: showBanner
                    ? Padding(
                        key: ValueKey<String>(isOffline ? 'offline' : 'online'),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: bannerColor,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x38000000),
                                  blurRadius: 14,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, size: 16, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      message,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        height: 1.1,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey<String>('hidden')),
              ),
            ),
          ),
        ),
      ],
    );
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
      return _lastUnreadCount;
    }();

    // Lecturers get their own nav bar with role-specific destinations.
    if (role == UserRole.lecturer) {
      final scaffold = Scaffold(
        body: widget.child,
        bottomNavigationBar: LecturerBottomNav(
          activeTab: _lecturerCurrentTab(location),
          onFeedTap: () => context.go(RouteNames.home),
          onDashboardTap: () => context.go(RouteNames.lecturerDashboard),
          onAddTap: () => _handleAddTap(context),
          onLeaderboardTap: () => context.go(RouteNames.lecturerLeaderboard),
          onInboxTap: () => context.go(RouteNames.inbox),
          unreadMessageCount: unreadCount,
        ),
      );
      return _withNetworkIndicator(context, scaffold);
    }

    // Students, admins, super-admins — standard student nav.
    final currentTab = _currentTab(location);
    final scaffold = Scaffold(
      body: widget.child,
      bottomNavigationBar: StarTrackBottomNav(
        activeTab: currentTab,
        onHomeTap: () => context.go(RouteNames.home),
        onPeersTap: () => context.go(RouteNames.peers),
        onAddTap: () => _handleAddTap(context),
        onInboxTap: () => context.go(RouteNames.inbox),
        onLeaderboardTap: () => context.go(RouteNames.globalRanks),
        unreadMessageCount: unreadCount,
      ),
    );
    return _withNetworkIndicator(context, scaffold);
  }
}
