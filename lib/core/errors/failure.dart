// lib/core/errors/failure.dart
//
// MUST StarTrack — Failure Types (Domain layer errors)
//
// Using the Either<Failure, Data> pattern from dartz:
//   - Repositories return Either<Failure, T>
//   - BLoC maps failures to error states
//   - UI maps error states to user-friendly messages
//
// This makes error handling explicit and type-safe —
// you can't accidentally forget to handle an error.

import 'package:equatable/equatable.dart';

/// Base class for all domain-level failures.
/// Every repository method returns Either<Failure, T>.
abstract class Failure extends Equatable {
  final String message;
  final String? code;

  const Failure({required this.message, this.code});

  @override
  List<Object?> get props => [message, code];
}

// ── Network / Connectivity ────────────────────────────────────────────────────

/// Thrown when the device is offline or a network request fails.
class NetworkFailure extends Failure {
  const NetworkFailure({
    super.message = 'No internet connection. Please check your network.',
    super.code = 'NETWORK_ERROR',
  });
}

/// Thrown when a network request times out.
class TimeoutFailure extends Failure {
  const TimeoutFailure({
    super.message = 'Request timed out. Please try again.',
    super.code = 'TIMEOUT',
  });
}

// ── Auth ──────────────────────────────────────────────────────────────────────

/// Thrown when credentials are wrong.
class AuthFailure extends Failure {
  const AuthFailure({required super.message, super.code = 'AUTH_ERROR'});
}

/// Thrown when a user tries to access a resource they're not allowed to.
class PermissionFailure extends Failure {
  const PermissionFailure({
    super.message = 'You do not have permission to perform this action.',
    super.code = 'PERMISSION_DENIED',
  });
}

/// Thrown when the auth session has expired.
class SessionExpiredFailure extends Failure {
  const SessionExpiredFailure({
    super.message = 'Your session has expired. Please log in again.',
    super.code = 'SESSION_EXPIRED',
  });
}

// ── Firestore / Data ──────────────────────────────────────────────────────────

/// Thrown when a Firestore document is not found.
class NotFoundFailure extends Failure {
  const NotFoundFailure({
    super.message = 'The requested content was not found.',
    super.code = 'NOT_FOUND',
  });
}

/// Thrown on any Firestore write/read failure.
class ServerFailure extends Failure {
  const ServerFailure({
    super.message = 'Server error. Please try again later.',
    super.code = 'SERVER_ERROR',
  });
}

// ── Local Storage / SQLite ────────────────────────────────────────────────────

/// Thrown when a SQLite operation fails.
class LocalStorageFailure extends Failure {
  const LocalStorageFailure({
    super.message = 'Local storage error.',
    super.code = 'LOCAL_DB_ERROR',
  });
}

// ── Validation ────────────────────────────────────────────────────────────────

/// Thrown when business-rule validation fails.
class ValidationFailure extends Failure {
  const ValidationFailure({required super.message, super.code = 'VALIDATION'});
}

// ── Media ─────────────────────────────────────────────────────────────────────

/// Thrown when an uploaded file exceeds the allowed size/duration.
class MediaFailure extends Failure {
  const MediaFailure({required super.message, super.code = 'MEDIA_ERROR'});
}

// ── Sync ──────────────────────────────────────────────────────────────────────

/// Thrown when the background sync queue fails to push to Firestore.
class SyncFailure extends Failure {
  const SyncFailure({
    super.message = 'Sync failed. Changes will retry when online.',
    super.code = 'SYNC_ERROR',
  });
}

// ── Unknown ───────────────────────────────────────────────────────────────────

/// Catch-all for unexpected failures.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure({
    super.message = 'Something went wrong. Please try again.',
    super.code = 'UNEXPECTED',
  });
}
