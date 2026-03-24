// lib/core/router/app_router.dart
//
// MUST StarTrack — GoRouter Configuration (Phase 5 — Fully Wired)
//
// All _PlaceholderScreen instances replaced with real screen widgets.
//
// Key GoRouter features used:
//   • refreshListenable: AuthCubit — router re-evaluates redirect on
//     every auth state change (login/logout triggers navigation automatically)
//   • redirect callback: role-based access control before any screen renders
//   • ShellRoute: MainShell wraps the 5 bottom-nav tabs
//   • Path parameters: /profile/:userId, /inbox/chat/:threadId, etc.
//
// Navigation flow:
//   App launch → /splash → checkAuthStatus()
//     ├── authenticated  → /home
//     └── unauthenticated→ /auth/login
//
//   Login success → GoRouter.redirect fires → /home
//   Logout        → GoRouter.redirect fires → /auth/login
//
// HCI — Constraints:
//   The redirect guard is a system constraint — users cannot reach
//   admin screens by typing a URL. They are silently redirected to
//   their highest-permitted screen.
//
// Panel defence:
//   "We use GoRouter's refreshListenable on the AuthCubit stream.
//    Every time AuthCubit emits a new state, GoRouter re-runs the
//    redirect function. This means login/logout navigation is
//    automatic and no screen has to call context.go() manually."

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../di/injection_container.dart';
import 'route_names.dart';
import 'route_guards.dart';

// ── Auth screens ──────────────────────────────────────────────────────────────
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_step1_screen.dart';
import '../../features/auth/screens/register_step2_screen.dart';
import '../../features/auth/screens/register_step3_screen.dart';
import '../../features/auth/screens/lecturer_register_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/password_reset_sent_screen.dart';

// ── Feed screens ──────────────────────────────────────────────────────────────
import '../../features/feed/screens/home_feed_screen.dart';
import '../../features/feed/screens/project_detail_screen.dart';
import '../../features/feed/screens/create_post_screen.dart';
import '../../features/feed/screens/my_projects_screen.dart';

// ── Discover screens ──────────────────────────────────────────────────────────
import '../../features/discover/screens/discover_screen.dart';
import '../../features/discover/screens/guest_discover_screen.dart';

// ── Peers screen ──────────────────────────────────────────────────────────────
import '../../features/peers/screens/peers_screen.dart';

// ── Profile screens ───────────────────────────────────────────────────────────
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';

// ── Messaging screens ─────────────────────────────────────────────────────────
import '../../features/messaging/screens/messages_list_screen.dart';
import '../../features/messaging/screens/chat_detail_screen.dart';

// ── Notifications screen ──────────────────────────────────────────────────────
import '../../features/notifications/screens/notification_center_screen.dart';
import '../../features/notifications/screens/notification_settings_screen.dart';
import '../../features/shared/screens/screen_hub_screen.dart';

// ── Admin screens ─────────────────────────────────────────────────────────────
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/super_admin/screens/super_admin_dashboard_screen.dart';
// ── Lecturer screens ──────────────────────────────────────────────────────
import '../../features/lecturer/screens/lecturer_dashboard_screen.dart';
import '../../features/lecturer/screens/opportunity_applicants_screen.dart';
import '../../features/lecturer/screens/lecturer_ranking_screen.dart';
import '../../features/lecturer/screens/advanced_search_screen.dart';
import '../../features/lecturer/bloc/lecturer_cubit.dart';
// ── Shell ─────────────────────────────────────────────────────────────────────
import '../../features/shared/widgets/main_shell.dart';

// ── BLoCs ─────────────────────────────────────────────────────────────────────
import '../../features/auth/bloc/auth_cubit.dart';
import '../../features/feed/bloc/feed_cubit.dart';
import '../../features/profile/bloc/profile_cubit.dart';
import '../../features/messaging/bloc/message_cubit.dart';
import '../../features/admin/bloc/admin_cubit.dart';
import '../../data/models/post_model.dart';

// ─────────────────────────────────────────────────────────────────────────────

class AppRouter {
  AppRouter._();

  /// Builds the GoRouter. Call once in app.dart.
  static GoRouter router({required RouteGuards guards}) {
    // refreshListenable wraps the AuthCubit stream so GoRouter
    // re-evaluates redirect on every auth state change.
    final authCubit = sl<AuthCubit>();
    final listenable = _AuthListenable(authCubit);

    return GoRouter(
      initialLocation: Routes.splash,
      debugLogDiagnostics: false,
      refreshListenable: listenable,

      // ── Global redirect (RBAC) ───────────────────────────────────────────
      redirect: (BuildContext context, GoRouterState state) {
        final location = state.matchedLocation;
        final role = guards.currentRole;
        final isAuth = guards.isAuthenticated;

        // Public routes — always accessible to everyone
        final publicRoutes = [
          Routes.splash,
          Routes.login,
          Routes.registerStep1,
          Routes.registerStep2,
          Routes.registerStep3,
          Routes.lecturerRegister,
          Routes.forgotPassword,
          Routes.passwordReset,
          Routes.guestDiscover,
        ];

        final isPublic = publicRoutes.any(
          (r) => location.startsWith(r.split(':').first),
        );

        if (isPublic) return null;

        // Home feed is the offline-first landing screen for all users.
        // Guests can still view cached/public content without authentication.
        if (location.startsWith(Routes.home)) return null;

        // Not authenticated → send to login
        if (!isAuth) {
          return '${Routes.login}?from=${Uri.encodeComponent(location)}';
        }

        // Admin-only routes
        final adminOnly = [
          Routes.adminDashboard,
          Routes.adminModeration,
          Routes.adminUsers,
          Routes.adminAnalytics,
          Routes.adminReports,
          Routes.activityLogs,
        ];
        final isAdminRoute = adminOnly.any(
          (r) => location.startsWith(r.split(':').first),
        );
        if (isAdminRoute && !role.isAdmin) return Routes.home;

        // Lecturer-only routes (applicants route is open to any
        // authenticated user so post authors can view their own applicants)
        final lecturerOnly = [
          Routes.lecturerDashboard,
          Routes.lecturerRanking,
          Routes.lecturerSearch,
        ];
        final isLecturerRoute = lecturerOnly.any(
          (r) => location.startsWith(r.split(':').first),
        );
        if (isLecturerRoute &&
            role != UserRole.lecturer &&
            !role.isAdmin) {
          return Routes.home;
        }

        // Super-admin-only routes
        final superAdminOnly = [
          Routes.superAdminDashboard,
          Routes.superAdminSettings,
          Routes.superAdminUsers,
          Routes.superAdminAnalytics,
        ];
        final isSuperRoute = superAdminOnly.any(
          (r) => location.startsWith(r.split(':').first),
        );
        if (isSuperRoute && role != UserRole.superAdmin) {
          return role.isAdmin ? Routes.adminDashboard : Routes.home;
        }

        return null; // allow
      },

      // ── Route tree ───────────────────────────────────────────────────────
      routes: [

        // ── Splash ─────────────────────────────────────────────────────────
        GoRoute(
          path: Routes.splash,
          builder: (_, __) => const SplashScreen(),
        ),

        // ── Auth ───────────────────────────────────────────────────────────
        GoRoute(
          path: Routes.login,
          builder: (_, __) => BlocProvider.value(
            value: sl<AuthCubit>(),
            child: const LoginScreen(),
          ),
        ),
        GoRoute(
          path: Routes.registerStep1,
          builder: (_, __) => BlocProvider.value(
            value: sl<AuthCubit>(),
            child: const RegisterStep1Screen(),
          ),
        ),
        GoRoute(
          name: RouteNames.registerStep2Name,
          path: Routes.registerStep2,
          builder: (_, state) => BlocProvider.value(
            value: sl<AuthCubit>(),
            child: RegisterStep2Screen(
              step1Data: state.extra is Map<String, dynamic>
                  ? state.extra! as Map<String, dynamic>
                  : const {},
            ),
          ),
        ),
        GoRoute(
          name: RouteNames.registerStep3Name,
          path: Routes.registerStep3,
          builder: (_, state) => BlocProvider.value(
            value: sl<AuthCubit>(),
            child: RegisterStep3Screen(
              combinedData: state.extra is Map<String, dynamic>
                  ? state.extra! as Map<String, dynamic>
                  : const {},
            ),
          ),
        ),
        GoRoute(
          path: Routes.lecturerRegister,
          builder: (_, __) => BlocProvider.value(
            value: sl<AuthCubit>(),
            child: const LecturerRegisterScreen(),
          ),
        ),
        GoRoute(
          path: Routes.forgotPassword,
          builder: (_, __) => BlocProvider.value(
            value: sl<AuthCubit>(),
            child: const ForgotPasswordScreen(),
          ),
        ),
        GoRoute(
          path: Routes.passwordReset,
          builder: (_, state) => PasswordResetSentScreen(
            email: state.uri.queryParameters['email'] ?? '',
          ),
        ),

        // ── Guest discover ─────────────────────────────────────────────────
        GoRoute(
          path: Routes.guestDiscover,
          builder: (_, __) => const GuestDiscoverScreen(),
        ),

        // ── Main shell (bottom nav) ─────────────────────────────────────────
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            // Home feed
            GoRoute(
              path: Routes.home,
              builder: (_, __) => BlocProvider(
                create: (_) => sl<FeedCubit>()..loadFeed(),
                child: const HomeFeedScreen(),
              ),
            ),
            // Discover
            GoRoute(
              path: Routes.discover,
              builder: (_, __) => const DiscoverScreen(),
            ),
            // Peers
            GoRoute(
              path: Routes.peers,
              builder: (_, __) => const PeersScreen(),
            ),
            // Inbox (messages list)
            GoRoute(
              path: Routes.inbox,
              builder: (_, __) => BlocProvider(
                create: (_) => sl<MessageCubit>()..loadConversations(),
                child: const MessagesListScreen(),
              ),
            ),
            // Notifications (mapped to /projects slot as 5th tab)
            GoRoute(
              path: Routes.projects,
              builder: (_, __) => const MyProjectsScreen(),
            ),

            // ── Lecturer screens (inside shell so nav persists) ───────────
            GoRoute(
              path: Routes.lecturerDashboard,
              name: RouteNames.lecturerDashboardName,
              builder: (_, __) => BlocProvider(
                create: (_) => sl<LecturerCubit>(),
                child: const LecturerDashboardScreen(),
              ),
            ),
            GoRoute(
              path: Routes.lecturerApplicants,
              name: RouteNames.lecturerApplicantsName,
              builder: (_, state) {
                final opportunity = state.extra as PostModel;
                return BlocProvider(
                  create: (_) => sl<LecturerCubit>(),
                  child: OpportunityApplicantsScreen(opportunity: opportunity),
                );
              },
            ),
            GoRoute(
              path: Routes.lecturerRanking,
              name: RouteNames.lecturerRankingName,
              builder: (_, __) => BlocProvider(
                create: (_) => sl<LecturerCubit>(),
                child: const LecturerRankingScreen(),
              ),
            ),
            GoRoute(
              path: Routes.lecturerSearch,
              name: RouteNames.lecturerSearchName,
              builder: (_, __) => BlocProvider(
                create: (_) => sl<LecturerCubit>(),
                child: const AdvancedSearchScreen(),
              ),
            ),
          ],
        ),

        // ── Post detail / create ────────────────────────────────────────────
        GoRoute(
          path: Routes.postDetail,
          builder: (_, state) => ProjectDetailScreen(
            postId: state.pathParameters['postId'] ?? '',
          ),
        ),
        GoRoute(
          path: Routes.createPost,
          builder: (_, state) => BlocProvider(
            create: (_) => sl<FeedCubit>(),
            child: CreatePostScreen(
              existingPost: state.extra is PostModel ? state.extra as PostModel : null,
            ),
          ),
        ),

        // ── Profile ────────────────────────────────────────────────────────
        GoRoute(
          path: Routes.myProfile,
          builder: (_, __) => BlocProvider(
            create: (_) => sl<ProfileCubit>()..loadProfile(null),
            child: const ProfileScreen(),
          ),
        ),
        GoRoute(
          path: Routes.profile,
          builder: (_, state) {
            final userId = state.pathParameters['userId'] ?? '';
            return BlocProvider(
              create: (_) => sl<ProfileCubit>()..loadProfile(userId),
              child: ProfileScreen(userId: userId),
            );
          },
        ),
        GoRoute(
          path: Routes.editProfile,
          builder: (_, __) => BlocProvider(
            create: (_) => sl<ProfileCubit>()..loadProfile(null),
            child: const EditProfileScreen(),
          ),
        ),

        // ── Chat ───────────────────────────────────────────────────────────
        GoRoute(
          path: Routes.chatDetail,
          builder: (_, state) {
            final threadId = state.pathParameters['threadId'] ?? '';
            // Extra data passed via GoRouter extra parameter
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return BlocProvider(
              create: (_) => sl<MessageCubit>()..loadThread(
                peerId: threadId,
                peerName: extra['peerName'] as String? ?? '',
                peerPhotoUrl: extra['peerPhotoUrl'] as String?,
                isPeerLecturer: extra['isPeerLecturer'] as bool? ?? false,
              ),
              child: const ChatDetailScreen(),
            );
          },
        ),

        // ── Notifications ──────────────────────────────────────────────────
        GoRoute(
          path: Routes.notifications,
          builder: (_, __) => const NotificationCenterScreen(),
        ),
        GoRoute(
          path: Routes.notificationSettings,
          builder: (_, __) => const NotificationSettingsScreen(),
        ),

        // ── Screen hub (newly added module screens) ──────────────────────
        GoRoute(
          path: Routes.screenHub,
          builder: (_, __) => const ScreenHubScreen(),
        ),

        // ── Admin ──────────────────────────────────────────────────────────
        GoRoute(
          path: Routes.adminDashboard,
          builder: (_, __) => BlocProvider(
            create: (_) => sl<AdminCubit>()..loadDashboard(),
            child: const AdminDashboardScreen(),
          ),
        ),

        // ── Super Admin ────────────────────────────────────────────────────
        GoRoute(
          path: Routes.superAdminDashboard,
          builder: (_, __) => const SuperAdminDashboardScreen(),
        ),
      ],

      // ── 404 page ─────────────────────────────────────────────────────────
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Page Not Found')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Could not find: ${state.uri.path}',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── refreshListenable adapter ─────────────────────────────────────────────────
//
// GoRouter requires a Listenable to know when to re-run redirect.
// We wrap AuthCubit's stream in a ChangeNotifier adapter.

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(AuthCubit cubit) {
    cubit.stream.listen((_) => notifyListeners());
  }
}
