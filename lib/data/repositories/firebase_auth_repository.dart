// lib/data/repositories/firebase_auth_repository.dart
//
// MUST StarTrack — Firebase Auth Repository Implementation (Phase 5)
//
// Replaces StubAuthRepository.
// Implements the AuthRepository contract using:
//   • Firebase Authentication (email/password + Google Sign-In)
//   • MUST domain restriction (@must.ac.ug / @mbarara.ac.ug)
//   • UserDao (SQLite) — local cache of the authenticated user
//   • SyncQueueDao — queues new user Firestore writes offline
//   • FlutterSecureStorage — encrypted token storage
//
// All methods return Either<Failure, T> — the cubit never sees
// Firebase exceptions directly (Clean Architecture boundary).
//
// Panel defence:
//   "Firebase Auth handles token refresh, session persistence,
//    and email verification. We add MUST-domain restriction in
//    signInWithGoogle() using the hosted_domain constraint.
//    Even if someone tricks the OAuth flow, our Firestore security
//    rules independently verify the email domain server-side."

import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/errors/failures.dart';
import '../../core/router/route_guards.dart' show UserRole;
import '../local/dao/user_dao.dart';
import '../local/dao/sync_queue_dao.dart';
import '../models/user_model.dart';
import '../models/profile_model.dart';
import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final fb.FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final FirebaseFirestore _firestore;
  final UserDao _userDao;
  final SyncQueueDao _syncDao;
  final FlutterSecureStorage _secureStorage;

  // Accepted MUST email domains
  static const _mustDomains = ['must.ac.ug', 'mbarara.ac.ug'];

  FirebaseAuthRepository({
    required fb.FirebaseAuth firebaseAuth,
    required GoogleSignIn googleSignIn,
    required FirebaseFirestore firestore,
    required UserDao userDao,
    required SyncQueueDao syncDao,
    required FlutterSecureStorage secureStorage,
  })  : _firebaseAuth = firebaseAuth,
        _googleSignIn = googleSignIn,
        _firestore = firestore,
        _userDao = userDao,
        _syncDao = syncDao,
        _secureStorage = secureStorage;

  // ── Domain enforcement ────────────────────────────────────────────────────

  bool _isMustEmail(String email) {
    final domain = email.split('@').last.toLowerCase();
    return _mustDomains.contains(domain);
  }

  // ── Get current user ──────────────────────────────────────────────────────

  @override
  Future<Either<Failure, UserModel>> getCurrentUser() async {
    try {
      final fbUser = _firebaseAuth.currentUser;
      if (fbUser == null) return const Left(SessionExpiredFailure());

      // Try local cache first (offline-first)
      final cached = await _userDao.getUserById(fbUser.uid);
      if (cached != null) return Right(cached);

      // Fallback: fetch from Firestore
      final doc =
          await _firestore.collection('users').doc(fbUser.uid).get();
      if (!doc.exists) return const Left(UserNotFoundFailure());

      final user = UserModel.fromJson({'id': doc.id, ...doc.data()!});
      await _userDao.insertUser(user);
      return Right(user);
    } on fb.FirebaseAuthException catch (e) {
      return Left(_mapFirebaseAuthError(e));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  // ── Email / password login ────────────────────────────────────────────────

  @override
  Future<Either<Failure, UserModel>> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final fbUser = credential.user;
      if (fbUser == null) return const Left(UnexpectedFailure('No user returned'));

      // Email verification gate
      if (!fbUser.emailVerified) {
        return const Left(EmailNotVerifiedFailure());
      }

      return _resolveAndCacheUser(fbUser);
    } on fb.FirebaseAuthException catch (e) {
      return Left(_mapFirebaseAuthError(e));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  @override
  Future<Either<Failure, UserModel>> signInWithGoogle() async {
    try {
      // Trigger Google OAuth
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return const Left(AuthCancelledFailure());

      // MUST domain restriction
      if (!_isMustEmail(googleUser.email)) {
        await _googleSignIn.signOut();
        return const Left(DomainRestrictedFailure(
            'Only @must.ac.ug and @mbarara.ac.ug accounts are allowed.'));
      }

      final googleAuth = await googleUser.authentication;
      final credential = fb.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final fbCredential =
          await _firebaseAuth.signInWithCredential(credential);
      final fbUser = fbCredential.user;
      if (fbUser == null) return const Left(UnexpectedFailure('No user returned'));

      // First-time Google login: create user document in Firestore + SQLite
      if (fbCredential.additionalUserInfo?.isNewUser ?? false) {
        return _createNewGoogleUser(fbUser, googleUser);
      }

      return _resolveAndCacheUser(fbUser);
    } on fb.FirebaseAuthException catch (e) {
      return Left(_mapFirebaseAuthError(e));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  // ── Register student ──────────────────────────────────────────────────────

  @override
  Future<Either<Failure, UserModel>> registerStudent({
    required Map<String, dynamic> data,
  }) async {
    try {
      final email = (data['email'] as String).trim();
      final password = data['password'] as String;

      if (!_isMustEmail(email)) {
        return const Left(DomainRestrictedFailure(
            'Only @must.ac.ug email addresses are allowed.'));
      }

      // Create Firebase Auth account
      final credential =
          await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final fbUser = credential.user!;

      // Update display name in Firebase Auth
      await fbUser.updateDisplayName(data['displayName'] as String? ?? '');

      // Build UserModel
      final now = DateTime.now();
      final user = UserModel(
        id: fbUser.uid,
        firebaseUid: fbUser.uid,
        email: email,
        displayName: data['displayName'] as String? ?? '',
        role: UserRole.student,
        photoUrl: fbUser.photoURL,
        createdAt: now,
        updatedAt: now,
        profile: ProfileModel(
          id: fbUser.uid,
          userId: fbUser.uid,
          regNumber: data['regNumber'] as String?,
          gender: data['gender'] as String?,
          phone: data['phone'] as String?,
          faculty: data['faculty'] as String?,
          department: data['department'] as String?,
          programName: data['programme'] as String?,
          yearOfStudy: data['yearOfStudy'] as int?,
          admissionYear: data['admissionYear']?.toString(),
          skills: (data['skills'] as List?)?.cast<String>() ?? [],
          profileVisibility: 'public',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Persist locally (offline-first)
      await _userDao.insertUser(user);

      // Enqueue Firestore write (sync when online)
      await _syncDao.enqueue(
        entity: 'users',
        entityId: user.id,
        operation: 'create',
        payload: user.toJson(),
      );

      // Send email verification
      await fbUser.sendEmailVerification();

      return Right(user);
    } on fb.FirebaseAuthException catch (e) {
      return Left(_mapFirebaseAuthError(e));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  // ── Register lecturer ─────────────────────────────────────────────────────

  @override
  Future<Either<Failure, UserModel>> registerLecturer({
    required Map<String, dynamic> data,
  }) async {
    // Lecturers use the same flow but role = 'lecturer' + extra fields
    final merged = {...data, 'role': 'lecturer'};

    // Delegate to student registration with role override
    final result = await registerStudent(data: merged);
    return result.fold(
      Left.new,
      (user) async {
        // Update role in SQLite
        final updated = user.copyWith(role: UserRole.lecturer);
        await _userDao.updateUser(updated);
        return Right(updated);
      },
    );
  }

  // ── Password reset ────────────────────────────────────────────────────────

  @override
  Future<Either<Failure, void>> sendPasswordReset(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
      return const Right(null);
    } on fb.FirebaseAuthException catch (e) {
      return Left(_mapFirebaseAuthError(e));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  // ── Email verification ────────────────────────────────────────────────────

  @override
  Future<Either<Failure, void>> sendEmailVerification() async {
    try {
      final fbUser = _firebaseAuth.currentUser;
      if (fbUser == null) return const Left(SessionExpiredFailure());
      await fbUser.sendEmailVerification();
      return const Right(null);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  @override
  Future<Either<Failure, void>> logout() async {
    try {
      await Future.wait([
        _firebaseAuth.signOut(),
        _googleSignIn.signOut(),
        _secureStorage.deleteAll(),
      ]);
      return const Right(null);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Fetches user from Firestore and caches in SQLite.
  Future<Either<Failure, UserModel>> _resolveAndCacheUser(
      fb.User fbUser) async {
    try {
      // Try SQLite cache first
      final cached = await _userDao.getUserById(fbUser.uid);
      if (cached != null) return Right(cached);

      // Fetch from Firestore
      final doc = await _firestore
          .collection('users')
          .doc(fbUser.uid)
          .get();

      if (!doc.exists || doc.data() == null) {
        return const Left(UserNotFoundFailure());
      }

      final user =
          UserModel.fromJson({'id': doc.id, ...doc.data()!});
      await _userDao.insertUser(user);
      return Right(user);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  /// Creates Firestore document for a first-time Google sign-in user.
  Future<Either<Failure, UserModel>> _createNewGoogleUser(
    fb.User fbUser,
    GoogleSignInAccount googleUser,
  ) async {
    try {
      final now = DateTime.now();
      final user = UserModel(
        id: fbUser.uid,
        firebaseUid: fbUser.uid,
        email: fbUser.email ?? googleUser.email,
        displayName: fbUser.displayName ?? googleUser.displayName ?? '',
        role: UserRole.student,
        photoUrl: fbUser.photoURL ?? googleUser.photoUrl,
        createdAt: now,
        updatedAt: now,
        profile: ProfileModel(
          id: fbUser.uid,
          userId: fbUser.uid,
          skills: const [],
          profileVisibility: 'public',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _userDao.insertUser(user);
      await _syncDao.enqueue(
        entity: 'users',
        entityId: user.id,
        operation: 'create',
        payload: user.toJson(),
      );

      return Right(user);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  // ── Firebase error mapping ────────────────────────────────────────────────

  Failure _mapFirebaseAuthError(fb.FirebaseAuthException e) {
    return switch (e.code) {
      'user-not-found'           => const UserNotFoundFailure(),
      'wrong-password'           => const InvalidCredentialsFailure(),
      'invalid-credential'       => const InvalidCredentialsFailure(),
      'email-already-in-use'     => const EmailAlreadyInUseFailure(),
      'weak-password'            => const WeakPasswordFailure(),
      'invalid-email'            => const InvalidEmailFailure(),
      'user-disabled'            => const AccountDisabledFailure(),
      'too-many-requests'        => const RateLimitFailure(),
      'network-request-failed'   => const NetworkFailure(),
      'requires-recent-login'    => const SessionExpiredFailure(),
      _                          => UnexpectedFailure(e.message ?? e.code),
    };
  }
}
