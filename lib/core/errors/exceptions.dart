// lib/core/errors/exceptions.dart
//
// MUST StarTrack — Exception Types (Data layer exceptions)
//
// Exceptions are thrown in the data layer (repositories, services).
// They are caught at the repository boundary and mapped to Failures.
//
// The separation keeps the domain layer clean —
// domain code never sees Firebase or SQLite exceptions directly.

/// Base exception.
class AppException implements Exception {
  final String message;
  final String? code;

  const AppException({required this.message, this.code});

  @override
  String toString() => 'AppException($code): $message';
}

// ── Network ───────────────────────────────────────────────────────────────────
class NetworkException extends AppException {
  const NetworkException({
    super.message = 'Network request failed.',
    super.code = 'NETWORK_ERROR',
  });
}

class TimeoutException extends AppException {
  const TimeoutException({
    super.message = 'Request timed out.',
    super.code = 'TIMEOUT',
  });
}

// ── Firebase Auth ─────────────────────────────────────────────────────────────
class AuthException extends AppException {
  const AuthException({required super.message, super.code = 'AUTH_ERROR'});
}

class EmailAlreadyInUseException extends AppException {
  const EmailAlreadyInUseException()
      : super(
          message: 'An account with this email already exists.',
          code: 'EMAIL_IN_USE',
        );
}

class WeakPasswordException extends AppException {
  const WeakPasswordException()
      : super(
          message: 'Password is too weak.',
          code: 'WEAK_PASSWORD',
        );
}

class UserNotFoundException extends AppException {
  const UserNotFoundException()
      : super(
          message: 'No account found with this email.',
          code: 'USER_NOT_FOUND',
        );
}

class WrongPasswordException extends AppException {
  const WrongPasswordException()
      : super(
          message: 'Incorrect password. Please try again.',
          code: 'WRONG_PASSWORD',
        );
}

class GoogleSignInCancelException extends AppException {
  const GoogleSignInCancelException()
      : super(
          message: 'Google sign-in was cancelled.',
          code: 'GOOGLE_CANCELLED',
        );
}

class NonMustEmailException extends AppException {
  const NonMustEmailException()
      : super(
          message: 'Only MUST institutional email addresses are allowed.',
          code: 'NON_MUST_EMAIL',
        );
}

// ── Firestore ─────────────────────────────────────────────────────────────────
class FirestoreException extends AppException {
  const FirestoreException({required super.message, super.code = 'FIRESTORE'});
}

class DocumentNotFoundException extends AppException {
  const DocumentNotFoundException({required super.message})
      : super(code: 'NOT_FOUND');
}

class PermissionDeniedException extends AppException {
  const PermissionDeniedException()
      : super(
          message: 'You do not have permission for this action.',
          code: 'PERMISSION_DENIED',
        );
}

// ── Local DB ──────────────────────────────────────────────────────────────────
class LocalDbException extends AppException {
  const LocalDbException({required super.message, super.code = 'LOCAL_DB'});
}

// ── Media ─────────────────────────────────────────────────────────────────────
class ImageTooLargeException extends AppException {
  const ImageTooLargeException()
      : super(
          message: 'Image file is too large. Maximum allowed is 1.5MB.',
          code: 'IMAGE_TOO_LARGE',
        );
}

class VideoTooLongException extends AppException {
  const VideoTooLongException()
      : super(
          message: 'Video exceeds the 2-minute maximum duration.',
          code: 'VIDEO_TOO_LONG',
        );
}

// ── Validation ────────────────────────────────────────────────────────────────
class ValidationException extends AppException {
  const ValidationException({required super.message, super.code = 'VALIDATION'});
}

// ── Sync ──────────────────────────────────────────────────────────────────────
class SyncException extends AppException {
  const SyncException({required super.message, super.code = 'SYNC'});
}
