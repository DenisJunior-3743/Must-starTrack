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

import '../network/connectivity_service.dart';
import '../router/route_guards.dart';

import '../../data/local/database_helper.dart';
import '../../data/local/dao/user_dao.dart';
import '../../data/local/dao/post_dao.dart';
import '../../data/local/dao/message_dao.dart';
import '../../data/local/dao/notification_dao.dart';
import '../../data/local/dao/sync_queue_dao.dart';

import '../../data/remote/firestore_service.dart';
import '../../data/remote/fcm_service.dart';
import '../../data/remote/gemini_service.dart';
import '../../data/remote/recommender_service.dart';
import '../../data/remote/sync_service.dart';
import '../../data/remote/cloudinary_service.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/firebase_auth_repository.dart';

import '../../features/auth/bloc/auth_cubit.dart';
import '../../features/feed/bloc/feed_cubit.dart';
import '../../features/profile/bloc/profile_cubit.dart';
import '../../features/messaging/bloc/message_cubit.dart';
import '../../features/notifications/bloc/notification_cubit.dart';
import '../../features/admin/bloc/admin_cubit.dart';

/// Global service locator instance — the single access point.
final sl = GetIt.instance;

class InjectionContainer {
  InjectionContainer._();

  static Future<void> init() async {
    // ── 1. External: Flutter / system dependencies ──────────────────────────

    final sharedPrefs = await SharedPreferences.getInstance();
    sl.registerSingleton<SharedPreferences>(sharedPrefs);

    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    sl.registerSingleton<FlutterSecureStorage>(secureStorage);

    sl.registerSingleton<Connectivity>(Connectivity());

    // Local notifications plugin (used by FcmService foreground handler)
    sl.registerSingleton<FlutterLocalNotificationsPlugin>(
      FlutterLocalNotificationsPlugin(),
    );

    // ── 2. Firebase instances ───────────────────────────────────────────────

    sl.registerSingleton<fb.FirebaseAuth>(fb.FirebaseAuth.instance);
    sl.registerSingleton<FirebaseFirestore>(FirebaseFirestore.instance);

    // Google Sign-In restricted to MUST domain
    sl.registerSingleton<GoogleSignIn>(
      GoogleSignIn(
        scopes: ['email', 'profile'],
        // hostedDomain restricts the Google account chooser to @must.ac.ug.
        // This is UI-level only; server-side rules enforce it independently.
        hostedDomain: 'must.ac.ug',
      ),
    );

    // ── 3. Infrastructure: local database ───────────────────────────────────

    sl.registerSingleton<DatabaseHelper>(DatabaseHelper.instance);

    // Open database eagerly so first screen never waits for DB init
    await sl<DatabaseHelper>().database;

    // ── 4. DAOs (all singletons — one instance, shared across cubits) ───────

    sl.registerSingleton<UserDao>(UserDao());
    sl.registerSingleton<PostDao>(PostDao());
    sl.registerSingleton<MessageDao>(MessageDao());
    sl.registerSingleton<NotificationDao>(NotificationDao());
    sl.registerSingleton<SyncQueueDao>(SyncQueueDao());

    // ── 5. Remote services ──────────────────────────────────────────────────

    sl.registerSingleton<FirestoreService>(
      FirestoreService(firestore: sl<FirebaseFirestore>()),
    );

    // Gemini key can be injected at runtime (secure storage/env). Empty key disables remote rerank.
    sl.registerSingleton<GeminiService>(
      GeminiService(apiKey: ''),
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
      ),
    );

    sl.registerSingleton<SyncService>(
      SyncService(
        queueDao: sl<SyncQueueDao>(),
        firestore: sl<FirestoreService>(),
        userDao: sl<UserDao>(),
        postDao: sl<PostDao>(),
        connectivity: sl<Connectivity>(),
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

    // ── 9. AuthCubit — singleton so auth state is global ───────────────────
    //
    // All other cubits are registered as factories (new instance per screen).
    // AuthCubit must be a singleton because the router reads it for guards
    // and the app bar reads it for the user avatar.

    sl.registerSingleton<AuthCubit>(
      AuthCubit(
        authRepository: sl<AuthRepository>(),
        guards: sl<RouteGuards>(),
      ),
    );

    // ── 10. Feature cubits (factories — new instance per route) ─────────────

    sl.registerFactory<FeedCubit>(
      () => FeedCubit(
        postDao: sl<PostDao>(),
        syncQueue: sl<SyncQueueDao>(),
        syncService: sl<SyncService>(),
      ),
    );

    sl.registerFactory<ProfileCubit>(
      () => ProfileCubit(
        userDao: sl<UserDao>(),
        postDao: sl<PostDao>(),
      ),
    );

    sl.registerFactory<MessageCubit>(
      () => MessageCubit(
        messageDao: sl<MessageDao>(),
        syncDao: sl<SyncQueueDao>(),
      ),
    );

    sl.registerFactory<NotificationCubit>(
      () => NotificationCubit(dao: sl<NotificationDao>()),
    );

    sl.registerFactory<AdminCubit>(
      () => AdminCubit(
        postDao: sl<PostDao>(),
        userDao: sl<UserDao>(),
      ),
    );
  }
}
