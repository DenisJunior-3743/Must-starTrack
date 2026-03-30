// lib/app/app.dart
//
// MUST StarTrack — Root Application Widget (Phase 5 — Fully Wired)
//
// Provides:
//   • MultiBlocProvider — global cubits injected at the root so any
//     screen can read auth state, connectivity, and notifications
//     without needing to be nested in a BlocProvider.
//   • MaterialApp.router with GoRouter
//   • Light + Dark ThemeData (Lexend font, Material 3)
//   • Locale: en_UG (Uganda English)
//   • FcmService.init() called in initState so notification taps
//     can navigate using the live router reference.
//
// Why global BlocProviders here?
//   AuthCubit — GoRouter's refreshListenable reads it. Must be above
//   the MaterialApp so it's available before any route resolves.
//
//   NotificationCubit — the nav shell shows a badge count. It must
//   persist across tab switches, so it lives at the root.
//
//   ConnectivityCubit — the offline banner in MainShell reads it.
//   It must survive navigation to stay accurate.
//
// Panel defence:
//   "We use MultiBlocProvider at the root instead of BlocProvider
//    per-screen for cubits that model truly global state (auth,
//    connectivity, notifications). Screen-scoped cubits like
//    ProfileCubit and FeedCubit are provided closer to their
//    screens by the router so they are created fresh on every
//    navigation and disposed automatically when popped."

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/di/injection_container.dart';
import '../core/router/app_router.dart';
import '../core/router/route_guards.dart';
import '../core/services/session_timeout_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_cubit.dart';
import '../core/constants/app_strings.dart';

import '../features/auth/bloc/auth_cubit.dart';
import '../features/notifications/bloc/notification_cubit.dart';
import '../features/messaging/bloc/message_cubit.dart';
import '../data/remote/fcm_service.dart';

class StarTrackApp extends StatefulWidget {
  const StarTrackApp({super.key});

  @override
  State<StarTrackApp> createState() => _StarTrackAppState();
}

class _StarTrackAppState extends State<StarTrackApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final guards = sl<RouteGuards>();
    _router = AppRouter.router(guards: guards);

    // FCM init needs the router to handle notification taps.
    // We use addPostFrameCallback so context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        sl<FcmService>().init(context, _router);
      }
    });

    // Wire session timeout to auth state.
    // startTracking() on login, stopTracking() on logout.
    final authCubit = sl<AuthCubit>();
    final sessionService = sl<SessionTimeoutService>();
    _syncSession(authCubit.state, sessionService, authCubit);
    _authSub = authCubit.stream.listen(
      (state) => _syncSession(state, sessionService, authCubit),
    );
  }

  void _syncSession(
    AuthState state,
    SessionTimeoutService service,
    AuthCubit authCubit,
  ) {
    if (state is AuthAuthenticated) {
      service.startTracking(onExpired: authCubit.logout);
    } else if (state is AuthUnauthenticated) {
      service.stopTracking();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final authCubit = sl<AuthCubit>();
    if (authCubit.state is! AuthAuthenticated) return;
    final sessionService = sl<SessionTimeoutService>();
    if (sessionService.isStale()) {
      authCubit.logout();
    } else {
      sessionService.resetActivity();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    sl<SessionTimeoutService>().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // ── Global: theme mode (light / dark / system) ────────────────────
        BlocProvider<ThemeCubit>.value(
          value: sl<ThemeCubit>(),
        ),

        // ── Global: auth state ─────────────────────────────────────────────
        // Uses existing singleton from sl<> — does NOT create a new instance.
        BlocProvider<AuthCubit>.value(
          value: sl<AuthCubit>(),
        ),

        // ── Global: notification badge count ───────────────────────────────
        BlocProvider<NotificationCubit>(
          create: (_) => sl<NotificationCubit>()..loadNotifications(),
        ),

        // ── Global: message conversations (inbox badge + list) ─────────────
        BlocProvider<MessageCubit>(
          create: (_) => sl<MessageCubit>()..loadConversations(),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (_, themeMode) => MaterialApp.router(
          // ── Identity ──────────────────────────────────────────────────────
          title: AppStrings.appFullName,
          debugShowCheckedModeBanner: false,

          // ── Theme ─────────────────────────────────────────────────────────
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,

        // ── Router ─────────────────────────────────────────────────────────
          routerConfig: _router,

          // ── Locale ─────────────────────────────────────────────────────────
          locale: const Locale('en', 'UG'),
          supportedLocales: const [
            Locale('en', 'UG'),
            Locale('en', 'US'),
          ],

          // ── Builder: ensures MediaQuery is accessible for overlays ──────────
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final constrained = mediaQuery.copyWith(
              textScaler: TextScaler.linear(
                mediaQuery.textScaler.scale(1.0).clamp(0.8, 1.3),
              ),
            );
            return MediaQuery(
              data: constrained,
              // Reset the inactivity timer on every user touch.
              child: Listener(
                onPointerDown: (_) =>
                    sl<SessionTimeoutService>().resetActivity(),
                behavior: HitTestBehavior.translucent,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );
  }
}
