// lib/data/repositories/auth_repository.dart
//
// MUST StarTrack — Auth Repository
//
// Abstract interface + stub implementation for Phase 1.
// Phase 2: replace stub with FirebaseAuthRepositoryImpl.
//
// The repository pattern means:
//   - AuthCubit only knows about AuthRepository (interface)
//   - Firebase implementation can be swapped for a mock in tests
//   - Network and local concerns are completely separated from business logic
//
// Return type: Either<Failure, T> from dartz.
//   Left(failure) → an error occurred
//   Right(data)   → success

import 'package:dartz/dartz.dart';
import '../../core/errors/failures.dart';
import '../models/user_model.dart';

/// Abstract contract — what the AuthCubit can call.
abstract class AuthRepository {
  /// Returns the currently authenticated user from local cache.
  /// Returns Left(SessionExpiredFailure) if no session.
  Future<Either<Failure, UserModel>> getCurrentUser();

  /// Authenticates with email + password.
  Future<Either<Failure, UserModel>> loginWithEmail({
    required String email,
    required String password,
  });

  /// Triggers Google OAuth. Enforces MUST domain restriction.
  Future<Either<Failure, UserModel>> signInWithGoogle();

  /// Creates a new student account across SQLite + Firestore.
  Future<Either<Failure, UserModel>> registerStudent({
    required Map<String, dynamic> data,
  });

  /// Creates a new lecturer/staff account.
  Future<Either<Failure, UserModel>> registerLecturer({
    required Map<String, dynamic> data,
  });

  /// Sends a password reset email via Firebase Auth.
  Future<Either<Failure, void>> sendPasswordReset(String email);

  /// Manually resets a password using a username-like identifier.
  ///
  /// This updates local persistence first, then syncs the user record remotely.
  Future<Either<Failure, void>> resetPasswordManually({
    required String username,
    required String newPassword,
  });

  /// Sends an email verification link.
  Future<Either<Failure, void>> sendEmailVerification();

  /// Signs out and clears local session.
  Future<Either<Failure, void>> logout();
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 1 Stub Implementation
// Replaced with FirebaseAuthRepositoryImpl in Phase 2.
// ─────────────────────────────────────────────────────────────────────────────

class StubAuthRepository implements AuthRepository {
  @override
  Future<Either<Failure, UserModel>> getCurrentUser() async {
    return const Left(SessionExpiredFailure());
  }

  @override
  Future<Either<Failure, UserModel>> loginWithEmail({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return const Left(AuthFailure('Backend not connected. Phase 2 pending.'));
  }

  @override
  Future<Either<Failure, UserModel>> signInWithGoogle() async {
    return const Left(AuthFailure('Google Sign-In: Phase 2 pending.'));
  }

  @override
  Future<Either<Failure, UserModel>> registerStudent({
    required Map<String, dynamic> data,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return const Left(AuthFailure('Registration: Phase 2 pending.'));
  }

  @override
  Future<Either<Failure, UserModel>> registerLecturer({
    required Map<String, dynamic> data,
  }) async {
    return const Left(AuthFailure('Staff registration: Phase 2 pending.'));
  }

  @override
  Future<Either<Failure, void>> sendPasswordReset(String email) async {
    await Future.delayed(const Duration(seconds: 1));
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> resetPasswordManually({
    required String username,
    required String newPassword,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> sendEmailVerification() async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> logout() async {
    return const Right(null);
  }
}
