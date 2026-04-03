// lib/data/repositories/firebase_auth_repository.dart
//
// MUST StarTrack — Firebase Auth Repository Implementation (Phase 5)
//
// Replaces StubAuthRepository.
// Implements the AuthRepository contract using:
//   • Firebase Authentication (email/password + Google Sign-In)
//   • Institutional domain restriction for registration
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
import 'package:flutter/foundation.dart';
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

  // Admin and Google path domains (kept as-is for current admin flow)

  // Student/Lecturer registration domains
  static const _registrationDomains = [
    'must.ac.ug',
    'std.must.ac.ug',
    'staff.must.ac.ug',
  ];

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


  bool _isAllowedRegistrationEmail(String email) {
    final domain = email.split('@').last.toLowerCase();
    return _registrationDomains.contains(domain);
  }

  UserRole _inferRoleFromEmail(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized.endsWith('@std.must.ac.ug')) {
      return UserRole.student;
    }
    if (normalized.endsWith('@staff.must.ac.ug')) {
      return UserRole.lecturer;
    }
    if (normalized.endsWith('@must.ac.ug')) {
      return UserRole.admin;
    }
    return UserRole.guest;
  }

  // ── Get current user ──────────────────────────────────────────────────────

  @override
  Future<Either<Failure, UserModel>> getCurrentUser() async {
    try {
      final fbUser = _firebaseAuth.currentUser;
      if (fbUser == null) return const Left(SessionExpiredFailure());

      // Try local cache first (offline-first)
      final cached = await _userDao.getUserById(fbUser.uid);
      if (cached != null) {
        final reconciled = await _reconcileUserRole(cached, fbUser.email);
        return Right(reconciled);
      }

      // Fallback: fetch from Firestore
      final doc =
          await _firestore.collection('users').doc(fbUser.uid).get();
      if (!doc.exists || doc.data() == null) {
        final bootstrapped = await _bootstrapMissingUserFromAuth(fbUser);
        return Right(bootstrapped);
      }

      final user = UserModel.fromJson({'id': doc.id, ...doc.data()!});
      final reconciled = await _reconcileUserRole(user, fbUser.email);
      return Right(reconciled);
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
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPassword = password.trim();

    if (normalizedEmail.isEmpty || normalizedPassword.isEmpty) {
      return const Left(ValidationFailure('Email and password are required.'));
    }

    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: normalizedPassword,
      );

      final fbUser = credential.user;
      if (fbUser == null) return const Left(UnexpectedFailure('No user returned'));

      // Email verification gate skipped — SMTP not configured yet.
      // Restore once institutional email relay is live.
      // if (!fbUser.emailVerified && !kDebugMode) {
      //   return const Left(EmailNotVerifiedFailure());
      // }

      return _resolveAndCacheUser(fbUser);
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'invalid-credential' || e.code == 'wrong-password') {
        final localUser = await _userDao.getUserByEmail(normalizedEmail);
        if (localUser != null) {
          return const Left(AuthFailure(
            'Firebase rejected this password. If it was changed offline, '
            'it has not been applied to Firebase Auth yet.',
          ));
        }
      }
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
        if (!_isAllowedRegistrationEmail(googleUser.email)) {
        await _googleSignIn.signOut();
        return const Left(DomainRestrictedFailure(
          'Only @must.ac.ug, @std.must.ac.ug, and @staff.must.ac.ug accounts are allowed.'));
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
    String? email;
    String? password;
    try {
      final emailRaw = data['email'];
      final passwordRaw = data['password'];
      if (emailRaw is! String || emailRaw.trim().isEmpty) {
        return const Left(ValidationFailure('Student email is required.'));
      }
      if (passwordRaw is! String || passwordRaw.isEmpty) {
        return const Left(ValidationFailure('Password is required.'));
      }

      email = emailRaw.trim();
      password = passwordRaw;

      if (!_isAllowedRegistrationEmail(email)) {
        return const Left(DomainRestrictedFailure(
        'Only @must.ac.ug, @std.must.ac.ug, or @staff.must.ac.ug email addresses are allowed.'));
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
      final inferredRole = _inferRoleFromEmail(email);
      final user = UserModel(
        id: fbUser.uid,
        firebaseUid: fbUser.uid,
        email: email,
        displayName: data['displayName'] as String? ?? '',
        role: inferredRole == UserRole.guest ? UserRole.student : inferredRole,
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
          programName: data['programName'] as String?,
          courseName: data['courseName'] as String?,
          yearOfStudy: data['yearOfStudy'] as int?,
          admissionYear: data['admissionYear']?.toString(),
          skills: (data['skills'] as List?)?.cast<String>() ?? [],
          profileVisibility: 'public',
          createdAt: now,
          updatedAt: now,
        ),
      );

      try {
        await _persistUserRecordDurably(user, operation: 'create');
      } catch (e) {
        await _rollbackProvisionedUser(fbUser: fbUser, user: user);
        return Left(UnexpectedFailure(e.toString()));
      }

      // Email verification is intentionally skipped — SMTP not configured yet.
      // Re-enable once the institutional SMTP relay is set up.
      // await fbUser.sendEmailVerification();

      return Right(user);
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use' && email != null && password != null) {
        final recovered = await _recoverExistingAccountAndBootstrapProfile(
          email: email,
          password: password,
          data: data,
        );
        if (recovered != null) return Right(recovered);
      }
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
        try {
          await _persistUserRecordDurably(updated, operation: 'update');
        } catch (e) {
          return Left(UnexpectedFailure(e.toString()));
        }

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

  @override
  Future<Either<Failure, void>> resetPasswordManually({
    required String username,
    required String newPassword,
  }) async {
    final normalized = username.trim();
    if (normalized.isEmpty) {
      return const Left(ValidationFailure('Username is required.'));
    }
    if (newPassword.length < 8) {
      return const Left(
        WeakPasswordFailure('Password must be at least 8 characters.'),
      );
    }

    try {
      final targetUser = await _userDao.getUserByUsername(normalized);
      if (targetUser == null) {
        return const Left(
          UserNotFoundFailure('No account was found for that username.'),
        );
      }

      final current = _firebaseAuth.currentUser;
      if (current == null || current.uid != targetUser.id) {
        return const Left(
          PermissionFailure(
            'Manual reset can only change password for the currently signed-in account. '
            'Continue with Google using this same account, then apply reset again.',
          ),
        );
      }

      await current.updatePassword(newPassword);

      final now = DateTime.now();
      final updatedUser = targetUser.copyWith(updatedAt: now);

      // Local-first persistence so sync jobs can replay offline.
      await _userDao.updateUser(updatedUser);

      try {
        await _firestore.collection('users').doc(updatedUser.id).set(
          {
            ...updatedUser.toJson(),
            'passwordResetAt': now.toIso8601String(),
            'passwordResetMode': 'manual',
            'passwordResetUserName': normalized,
          },
          SetOptions(merge: true),
        );
      } catch (_) {
        await _syncDao.enqueue(
          entity: 'users',
          entityId: updatedUser.id,
          operation: 'update',
          payload: updatedUser.toJson(),
        );
      }

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
      if (cached != null) {
        final reconciled = await _reconcileUserRole(cached, fbUser.email);
        return Right(reconciled);
      }

      // Fetch from Firestore
      final doc = await _firestore
          .collection('users')
          .doc(fbUser.uid)
          .get();

      if (!doc.exists || doc.data() == null) {
        final bootstrapped = await _bootstrapMissingUserFromAuth(fbUser);
        return Right(bootstrapped);
      }

      final user =
          UserModel.fromJson({'id': doc.id, ...doc.data()!});
      final reconciled = await _reconcileUserRole(user, fbUser.email);
      return Right(reconciled);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  Future<UserModel> _bootstrapMissingUserFromAuth(
    fb.User fbUser, {
    UserRole? preferredRole,
  }) async {
    final email = (fbUser.email ?? '').trim();
    if (email.isEmpty) {
      throw const UnexpectedFailure(
        'Authenticated account is missing an email address.',
      );
    }

    final now = DateTime.now();
    final inferredRole = _inferRoleFromEmail(email);
    final resolvedRole = inferredRole == UserRole.guest
        ? (preferredRole ?? UserRole.student)
        : inferredRole;

    final user = UserModel(
      id: fbUser.uid,
      firebaseUid: fbUser.uid,
      email: email,
      displayName: fbUser.displayName ?? '',
      role: resolvedRole,
      photoUrl: fbUser.photoURL,
      isEmailVerified: fbUser.emailVerified,
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

    await _persistUserRecordDurably(user, operation: 'create');

    return user;
  }

  Future<void> _persistUserRecordDurably(
    UserModel user, {
    required String operation,
  }) async {
    await _userDao.insertUser(user);

    try {
      await _firestore
          .collection('users')
          .doc(user.id)
          .set(user.toJson(), SetOptions(merge: true));
      return;
    } catch (firestoreError) {
      debugPrint('⚠️ Firestore users write failed, queuing sync: $firestoreError');
    }

    try {
      await _syncDao.enqueue(
        entity: 'users',
        entityId: user.id,
        operation: operation,
        payload: user.toJson(),
      );
    } catch (queueError) {
      throw UnexpectedFailure(
        'User record could not be durably persisted: $queueError',
      );
    }
  }

  Future<void> _rollbackProvisionedUser({
    required fb.User fbUser,
    required UserModel user,
  }) async {
    try {
      await _userDao.deleteUser(user.id);
    } catch (error) {
      debugPrint('⚠️ Failed to rollback local user ${user.id}: $error');
    }

    try {
      await fbUser.delete();
    } catch (error) {
      debugPrint('⚠️ Failed to delete partially provisioned auth user ${user.id}: $error');
      try {
        await _firebaseAuth.signOut();
      } catch (_) {}
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
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
        role: _inferRoleFromEmail(fbUser.email ?? googleUser.email),
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

      try {
        await _persistUserRecordDurably(user, operation: 'create');
      } catch (e) {
        await _rollbackProvisionedUser(fbUser: fbUser, user: user);
        return Left(UnexpectedFailure(e.toString()));
      }

      return Right(user);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  Future<UserModel?> _recoverExistingAccountAndBootstrapProfile({
    required String email,
    required String password,
    required Map<String, dynamic> data,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final fbUser = credential.user;
      if (fbUser == null) return null;

      // If user doc already exists, resolve and return cached model.
      final existing = await _resolveAndCacheUser(fbUser);
      final existingUser = existing.fold((_) => null, (u) => u);
      if (existingUser != null) {
        // Email verification skipped — SMTP not configured yet.
        // if (!fbUser.emailVerified) await fbUser.sendEmailVerification();
        return existingUser;
      }

      final now = DateTime.now();
      final inferredRole = _inferRoleFromEmail(email);
      final requestedRole = data['role'] == 'lecturer'
          ? UserRole.lecturer
          : UserRole.student;
      final resolvedRole = inferredRole == UserRole.guest
          ? requestedRole
          : inferredRole;

      final user = UserModel(
        id: fbUser.uid,
        firebaseUid: fbUser.uid,
        email: email,
        displayName: data['displayName'] as String? ?? fbUser.displayName ?? '',
        role: resolvedRole,
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
          programName: data['programName'] as String?,
          courseName: data['courseName'] as String?,
          yearOfStudy: data['yearOfStudy'] as int?,
          admissionYear: data['admissionYear']?.toString(),
          skills: (data['skills'] as List?)?.cast<String>() ?? const [],
          profileVisibility: 'public',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _persistUserRecordDurably(user, operation: 'create');

      // Email verification skipped — SMTP not configured yet.
      // if (!fbUser.emailVerified) await fbUser.sendEmailVerification();

      return user;
    } catch (_) {
      return null;
    }
  }

  Future<UserModel> _reconcileUserRole(UserModel user, String? authEmail) async {
    final email = (authEmail ?? user.email).trim();
    final inferredRole = _inferRoleFromEmail(email);

    if (inferredRole == UserRole.guest || inferredRole == user.role) {
      await _userDao.insertUser(user);
      return user;
    }

    final updated = user.copyWith(
      email: email,
      role: inferredRole,
      updatedAt: DateTime.now(),
    );

    await _userDao.insertUser(updated);

    try {
      await _firestore
          .collection('users')
          .doc(updated.id)
          .set(updated.toJson(), SetOptions(merge: true));
    } catch (_) {
      await _syncDao.enqueue(
        entity: 'users',
        entityId: updated.id,
        operation: 'update',
        payload: updated.toJson(),
      );
    }

    return updated;
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
