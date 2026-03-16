// ============================================================
// lib/core/errors/failures.dart
// MUST StarTrack — Failure Types (Clean Architecture)
// ============================================================
// Failures are domain-level error representations.
// They are returned by repositories (via Either<Failure, T>)
// and mapped to user-friendly messages in the BLoC layer.
//
// Panel defence: This pattern (from Robert Martin's Clean
// Architecture) means the UI never sees raw exceptions —
// it always receives a typed, handleable failure.
// ============================================================

import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

/// Network/connectivity failure
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection']);
}

/// Firebase Auth failure
class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed']);
}

/// Firestore / remote DB failure
class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server error. Please try again.']);
}

/// SQLite / local DB failure
class LocalFailure extends Failure {
  const LocalFailure([super.message = 'Local storage error']);
}

/// Input validation failure (domain-level, not just form)
class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'Invalid input']);
}

/// Permission denied (RBAC — wrong role)
class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'You do not have permission to perform this action']);
}

/// Resource not found
class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'Resource not found']);
}

/// Media upload failure (image/video)
class UploadFailure extends Failure {
  const UploadFailure([super.message = 'Upload failed. Please check your connection.']);
}

/// Sync queue failure (offline action could not be replayed)
class SyncFailure extends Failure {
  const SyncFailure([super.message = 'Could not sync queued actions']);
}

/// Session expired
class SessionFailure extends Failure {
  const SessionFailure([super.message = 'Session expired. Please sign in again.']);
}

// ── Phase 5: Specific Firebase Auth failure subclasses ────────────────────────
// These are referenced by FirebaseAuthRepository._mapFirebaseAuthError()
// and displayed as user-friendly messages by AuthCubit.

/// User not found in Firebase / Firestore
class UserNotFoundFailure extends Failure {
  const UserNotFoundFailure([super.message = 'No account found with this email. Please register first.']);
}

/// Wrong password or invalid credential
class InvalidCredentialsFailure extends Failure {
  const InvalidCredentialsFailure([super.message = 'Incorrect email or password. Please try again.']);
}

/// Email already registered
class EmailAlreadyInUseFailure extends Failure {
  const EmailAlreadyInUseFailure([super.message = 'An account already exists with this email address.']);
}

/// Password too weak
class WeakPasswordFailure extends Failure {
  const WeakPasswordFailure([super.message = 'Password is too weak. Use at least 8 characters with letters and numbers.']);
}

/// Malformed email
class InvalidEmailFailure extends Failure {
  const InvalidEmailFailure([super.message = 'Please enter a valid email address.']);
}

/// Account disabled by admin
class AccountDisabledFailure extends Failure {
  const AccountDisabledFailure([super.message = 'Your account has been suspended. Please contact the administrator.']);
}

/// Too many failed login attempts
class RateLimitFailure extends Failure {
  const RateLimitFailure([super.message = 'Too many attempts. Please wait a few minutes and try again.']);
}

/// Session expired — needs re-login
class SessionExpiredFailure extends Failure {
  const SessionExpiredFailure([super.message = 'Your session has expired. Please sign in again.']);
}

/// Email not verified yet
class EmailNotVerifiedFailure extends Failure {
  const EmailNotVerifiedFailure([super.message = 'Please verify your email before logging in. Check your inbox.']);
}

/// Google OAuth cancelled by user
class AuthCancelledFailure extends Failure {
  const AuthCancelledFailure([super.message = 'Sign-in was cancelled.']);
}

/// Non-MUST email used for Google Sign-In
class DomainRestrictedFailure extends Failure {
  const DomainRestrictedFailure([super.message = 'Only @must.ac.ug and @mbarara.ac.ug accounts are permitted.']);
}

/// Catch-all for unexpected errors
class UnexpectedFailure extends Failure {
  const UnexpectedFailure([super.message = 'An unexpected error occurred. Please try again.']);
}
