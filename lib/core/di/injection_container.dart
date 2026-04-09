// lib/core/di/injection_container.dart
//
// MUST StarTrack — Dependency Injection (Phase 5 — Fully Wired)
//
// Service locator using get_it. All dependencies are registered here
// in the correct order:
//
//   1. External       → SharedPreferences, Firebase instances
//   2. Infrastructure → DatabaseHelper, SecureStorage, Connectivity
//   3. DAOs           → all SQLite data access objects
//   4. Remote         → FirestoreService, FcmService, SyncService
//   5. Repositories   → FirebaseAuthRepository (implements AuthRepository)
//   6. Guards         → RouteGuards (auth state for GoRouter)
//   7. Cubits         → AuthCubit (singleton), feature cubits (factories)
//
// Panel defence:
//   "get_it is a service locator — not true constructor injection,
//    but it gives us testability: in tests we call sl.reset() then
//    register mocks. Every class receives its dependencies through
//    its constructor, so no class reaches out to sl<> itself —
//    only this file does. That's the dependency rule from Clean
//    Architecture."
//
// Usage anywhere in the app:
//   final auth = sl<AuthCubit>();
//   final repo = sl<AuthRepository>();

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';

import '../config/gemini_config.dart';
import '../network/connectivity_service.dart';
import '../router/route_guards.dart';

import '../../data/local/database_helper.dart';
import '../../data/local/dao/activity_log_dao.dart';
import '../../data/local/dao/user_dao.dart';
import '../../data/local/dao/post_dao.dart';
import '../../data/local/dao/comment_dao.dart';
import '../../data/local/dao/message_dao.dart';
import '../../data/local/dao/notification_dao.dart';
import '../../data/local/dao/faculty_dao.dart';
import '../../data/local/dao/course_dao.dart';
import '../../data/local/dao/group_dao.dart';
import '../../data/local/dao/group_member_dao.dart';
import '../../data/local/dao/sync_queue_dao.dart';
import '../../data/local/dao/post_join_dao.dart';
import '../../data/local/dao/recommendation_log_dao.dart';
import '../../data/local/services/notification_preferences_service.dart';
import '../../data/local/services/faculty_seeder.dart';

import '../../data/remote/firestore_service.dart';
import '../../data/remote/fcm_service.dart';
import '../../data/remote/gemini_service.dart';
import '../../data/remote/recommender_service.dart';
import '../../data/remote/sync_service.dart';
import '../../data/remote/cloudinary_service.dart';

import '../../core/services/session_timeout_service.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/firebase_auth_repository.dart';

import '../../features/auth/bloc/auth_cubit.dart';
import '../../features/feed/bloc/feed_cubit.dart';
import '../../features/profile/bloc/profile_cubit.dart';
import '../../features/messaging/bloc/message_cubit.dart';
import '../../features/notifications/bloc/notification_cubit.dart';
import '../../features/admin/bloc/admin_cubit.dart';
import '../../features/admin/bloc/faculty_management_cubit.dart';
import '../../features/admin/bloc/course_management_cubit.dart';
import '../../features/lecturer/bloc/lecturer_cubit.dart';
import '../theme/theme_cubit.dart';

/// Global service locator instance — the single access point.
final sl = GetIt.instance;

const _geminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: GeminiConfig.bundledApiKey,
);

class InjectionContainer {
  InjectionContainer._();

  static Future<void> init() async {
    // ── 1. External: Flutter / system dependencies ──────────────────────────

    final sharedPrefs = await SharedPreferences.getInstance();
    sl.registerSingleton<SharedPreferences>(sharedPrefs);
    sl.registerSingleton<NotificationPreferencesService>(
      NotificationPreferencesService(prefs: sharedPrefs),
    );

    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    sl.registerSingleton<FlutterSecureStorage>(secureStorage);

    sl.registerSingleton<Connectivity>(Connectivity());

    sl.registerSingleton<SessionTimeoutService>(
      SessionTimeoutService(prefs: sharedPrefs),
    );

    // Local notifications plugin (used by FcmService foreground handler)
    // Initialise the plugin here — before SyncService.startListening() — so
    // both Android channels exist the moment the notification watcher fires.
    // FcmService.init() will re-initialise with the tap callback once the
    // router is available (addPostFrameCallback in app.dart).
    final localNotifPlugin = FlutterLocalNotificationsPlugin();
    await localNotifPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    final androidNotifPlugin = localNotifPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidNotifPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'startrack_main',
        'StarTrack Notifications',
        description: 'Collaboration requests, messages, and updates',
        importance: Importance.high,
      ),
    );
    await androidNotifPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'must_startrack_events',
        'Activity Alerts',
        description:
            'Alerts for follows, comments, views, likes, and collaborations.',
        importance: Importance.max,
      ),
    );
    sl.registerSingleton<FlutterLocalNotificationsPlugin>(localNotifPlugin);

    // ── 2. Firebase instances ───────────────────────────────────────────────

    sl.registerSingleton<fb.FirebaseAuth>(fb.FirebaseAuth.instance);
    sl.registerSingleton<FirebaseFirestore>(FirebaseFirestore.instance);

    // Let Google show available device accounts; the repository enforces
    // allowed MUST domains after the user selects an account.
    sl.registerSingleton<GoogleSignIn>(
      GoogleSignIn(
        scopes: ['email', 'profile'],
      ),
    );

    // ── 3. Infrastructure: local database ───────────────────────────────────

    sl.registerSingleton<DatabaseHelper>(DatabaseHelper.instance);

    // Open database eagerly so first screen never waits for DB init
    await sl<DatabaseHelper>().database;

    // ── 4. DAOs (all singletons — one instance, shared across cubits) ───────

    sl.registerSingleton<UserDao>(UserDao());
    sl.registerSingleton<ActivityLogDao>(ActivityLogDao());
    sl.registerSingleton<PostDao>(PostDao());
    sl.registerSingleton<CommentDao>(CommentDao());
    sl.registerSingleton<MessageDao>(MessageDao());
    sl.registerSingleton<NotificationDao>(NotificationDao());
    sl.registerSingleton<FacultyDao>(FacultyDao(sl<DatabaseHelper>()));
    sl.registerSingleton<CourseDao>(CourseDao(sl<DatabaseHelper>()));
    sl.registerSingleton<GroupDao>(GroupDao());
    sl.registerSingleton<GroupMemberDao>(GroupMemberDao());
    sl.registerSingleton<SyncQueueDao>(SyncQueueDao());
    sl.registerSingleton<PostJoinDao>(PostJoinDao());

    // Seed canonical MUST faculties + programs on first run (idempotent)
    await FacultySeeder.seed(
      sl<FacultyDao>(),
      sl<CourseDao>(),
    );

    // ── 5. Remote services ──────────────────────────────────────────────────

    sl.registerSingleton<FirestoreService>(
      FirestoreService(firestore: sl<FirebaseFirestore>()),
    );

    sl.registerSingleton<RecommendationLogDao>(
      RecommendationLogDao(
        firestoreService: sl<FirestoreService>(),
        syncQueueDao: sl<SyncQueueDao>(),
      ),
    );

    // Gemini key is injected at runtime via --dart-define. Empty disables remote rerank.
    sl.registerSingleton<GeminiService>(
      GeminiService(apiKey: _geminiApiKey),
    );

    sl.registerSingleton<RecommenderService>(
      RecommenderService(geminiService: sl<GeminiService>()),
    );

    sl.registerSingleton<CloudinaryService>(
      CloudinaryService(dio: Dio()),
    );

    sl.registerSingleton<FcmService>(
      FcmService(
        messaging: null,   // uses FirebaseMessaging.instance internally
        firestore: sl<FirebaseFirestore>(),
        localNotif: sl<FlutterLocalNotificationsPlugin>(),
        preferences: sl<NotificationPreferencesService>(),
      ),
    );

    sl.registerSingleton<SyncService>(
      SyncService(
        queueDao: sl<SyncQueueDao>(),
        firestore: sl<FirestoreService>(),
        userDao: sl<UserDao>(),
        postDao: sl<PostDao>(),
        commentDao: sl<CommentDao>(),
        facultyDao: sl<FacultyDao>(),
        courseDao: sl<CourseDao>(),
        groupDao: sl<GroupDao>(),
        groupMemberDao: sl<GroupMemberDao>(),
        notificationDao: sl<NotificationDao>(),
        cloudinary: sl<CloudinaryService>(),
        connectivity: sl<Connectivity>(),
        localNotif: sl<FlutterLocalNotificationsPlugin>(),
        preferences: sl<NotificationPreferencesService>(),
      ),
    );

    // Start listening to connectivity changes for automatic sync
    sl<SyncService>().startListening();

    // ── 6. Connectivity service ─────────────────────────────────────────────

    sl.registerSingleton<ConnectivityService>(
      ConnectivityService(),
    );

    // ── 7. Repositories ─────────────────────────────────────────────────────

    sl.registerLazySingleton<AuthRepository>(
      () => FirebaseAuthRepository(
        firebaseAuth: sl<fb.FirebaseAuth>(),
        googleSignIn: sl<GoogleSignIn>(),
        firestore: sl<FirebaseFirestore>(),
        userDao: sl<UserDao>(),
        syncDao: sl<SyncQueueDao>(),
        secureStorage: sl<FlutterSecureStorage>(),
      ),
    );

    // ── 8. Route guards (needed by AppRouter + AuthCubit) ───────────────────

    sl.registerSingleton<RouteGuards>(RouteGuards());

    // ── 9a. ThemeCubit — singleton, persists theme mode across sessions ─────
    sl.registerSingleton<ThemeCubit>(ThemeCubit(sl<SharedPreferences>()));

    // ── 9. AuthCubit — singleton so auth state is global ───────────────────
    //
    // All other cubits are registered as factories (new instance per screen).
    // AuthCubit must be a singleton because the router reads it for guards
    // and the app bar reads it for the user avatar.

    sl.registerSingleton<AuthCubit>(
      AuthCubit(
        authRepository: sl<AuthRepository>(),
        guards: sl<RouteGuards>(),
        fcmService: sl<FcmService>(),
        syncService: sl<SyncService>(),
      ),
    );

    // ── 10. Feature cubits (factories — new instance per route) ─────────────

    sl.registerFactory<FeedCubit>(
      () => FeedCubit(
        postDao: sl<PostDao>(),
        userDao: sl<UserDao>(),
        activityLogDao: sl<ActivityLogDao>(),
        recommenderService: sl<RecommenderService>(),
        syncQueue: sl<SyncQueueDao>(),
        syncService: sl<SyncService>(),
        currentUserId: sl<AuthCubit>().currentUser?.id,
        authCubit: sl<AuthCubit>(),
        recLogDao: sl<RecommendationLogDao>(),
      ),
    );

    sl.registerFactory<ProfileCubit>(
      () => ProfileCubit(
        userDao: sl<UserDao>(),
        postDao: sl<PostDao>(),
        authCubit: sl<AuthCubit>(),
        syncQueue: sl<SyncQueueDao>(),
        cloudinary: sl<CloudinaryService>(),
        firestore: sl<FirestoreService>(),
      ),
    );

    sl.registerFactory<MessageCubit>(
      () => MessageCubit(
        messageDao: sl<MessageDao>(),
        syncDao: sl<SyncQueueDao>(),
        authCubit: sl<AuthCubit>(),
        userDao: sl<UserDao>(),
        syncService: sl<SyncService>(),
        cloudinary: sl<CloudinaryService>(),
        firestore: sl<FirestoreService>(),
        recommenderService: sl<RecommenderService>(),
      ),
    );

    sl.registerFactory<NotificationCubit>(
      () => NotificationCubit(
        dao: sl<NotificationDao>(),
        authCubit: sl<AuthCubit>(),
        syncQueueDao: sl<SyncQueueDao>(),
        syncService: sl<SyncService>(),
      ),
    );

    sl.registerFactory<AdminCubit>(
      () => AdminCubit(
        postDao: sl<PostDao>(),
        userDao: sl<UserDao>(),
      ),
    );

    sl.registerFactory<FacultyManagementCubit>(
      () => FacultyManagementCubit(
        facultyDao: sl<FacultyDao>(),
        syncQueueDao: sl<SyncQueueDao>(),
        syncService: sl<SyncService>(),
      ),
    );

    sl.registerFactory<CourseManagementCubit>(
      () => CourseManagementCubit(
        courseDao: sl<CourseDao>(),
        syncQueueDao: sl<SyncQueueDao>(),
        syncService: sl<SyncService>(),
      ),
    );

    sl.registerFactory<LecturerCubit>(
      () => LecturerCubit(
        postDao: sl<PostDao>(),
        postJoinDao: sl<PostJoinDao>(),
        userDao: sl<UserDao>(),
        recommenderService: sl<RecommenderService>(),
        recLogDao: sl<RecommendationLogDao>(),
      ),
    );
  }
}
