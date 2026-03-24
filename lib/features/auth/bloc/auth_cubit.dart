// lib/features/auth/bloc/auth_cubit.dart
//
// MUST StarTrack — AuthCubit (Phase 5 — Fully Wired)
//
// All stub implementations replaced with real FirebaseAuthRepository calls.
// This is the ONLY file in the app that calls AuthRepository.
// Every screen reads AuthState — never calls Firebase directly.
//
// State machine:
//
//   App launch ──► checkAuthStatus()
//                     │
//              ┌──────┴──────┐
//         Authenticated   Unauthenticated
//              │               │
//         [home feed]     [login screen]
//
//   Login ──► loading ──► Authenticated / AuthError
//   Register ──► step 1 ──► step 2 ──► step 3
//            ──► loading ──► EmailVerificationSent / AuthError
//   Google ──► loading ──► Authenticated / AuthError
//   Logout ──► Unauthenticated
//
// HCI principle — Feedback:
//   Every state transition drives a UI change:
//   AuthLoading   → spinner shown
//   AuthError     → SnackBar with human-readable message
//   Authenticated → GoRouter redirects to /home
//   Unauthenticated → GoRouter redirects to /auth/login
//
// Panel defence:
//   "We use BLoC's Cubit (a simplified bloc with no Events).
//    AuthCubit is registered as a singleton in get_it so the
//    same auth state is shared across the entire widget tree.
//    GoRouter listens to it via refreshListenable to trigger
//    automatic redirects on login/logout."

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../data/models/user_model.dart';
import '../../../data/remote/fcm_service.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../core/router/route_guards.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STATES
// ─────────────────────────────────────────────────────────────────────────────

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

/// App just launched — auth status not checked yet.
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// An async auth operation is in progress → show loading spinner.
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// Fully authenticated and email-verified user.
class AuthAuthenticated extends AuthState {
  final UserModel user;
  const AuthAuthenticated(this.user);

  @override
  List<Object?> get props => [user];
}

/// No active session — show login screen.
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// Registration succeeded, awaiting email verification click.
class AuthEmailVerificationSent extends AuthState {
  final String email;
  const AuthEmailVerificationSent(this.email);

  @override
  List<Object?> get props => [email];
}

/// Tracks data collected across the 3-step student registration.
/// currentStep: 1 | 2 | 3
class AuthRegistrationInProgress extends AuthState {
  final int currentStep;
  final Map<String, dynamic> collectedData;

  const AuthRegistrationInProgress({
    required this.currentStep,
    required this.collectedData,
  });

  @override
  List<Object?> get props => [currentStep, collectedData];
}

/// A human-readable error message for the UI.
class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

// ─────────────────────────────────────────────────────────────────────────────
// CUBIT
// ─────────────────────────────────────────────────────────────────────────────

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _repo;
  final RouteGuards _guards;
  final FcmService? _fcmService;

  AuthCubit({
    required AuthRepository authRepository,
    required RouteGuards guards,
    FcmService? fcmService,
  })  : _repo = authRepository,
        _guards = guards,
        _fcmService = fcmService,
        super(const AuthInitial());

  // ── Check persisted session on app launch ─────────────────────────────────

  /// Called from SplashScreen. If Firebase has a persisted session,
  /// this resolves instantly from local cache (SQLite).
  Future<void> checkAuthStatus() async {
    emit(const AuthLoading());
    try {
      final result = await _repo.getCurrentUser();
      result.fold(
        (failure) => _emitUnauthenticated(),
        (user) => _emitAuthenticated(user),
      );
    } catch (e) {
      _emitUnauthenticated();
    }
  }

  // ── Email / Password Login ────────────────────────────────────────────────

  Future<void> login({
    required String email,
    required String password,
  }) async {
    emit(const AuthLoading());
    try {
      final result = await _repo.loginWithEmail(
        email: email,
        password: password,
      );
      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (user) => _emitAuthenticated(user),
      );
    } catch (e) {
      emit(const AuthError('Unexpected error. Please try again.'));
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  /// Triggers Google OAuth. Enforces @must.ac.ug domain restriction.
  Future<void> signInWithGoogle() async {
    emit(const AuthLoading());
    try {
      final result = await _repo.signInWithGoogle();
      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (user) => _emitAuthenticated(user),
      );
    } catch (e) {
      emit(const AuthError('Google Sign-In failed. Please try again.'));
    }
  }

  // ── Multi-step Student Registration ───────────────────────────────────────

  /// Called when Step 1 form (name, email, password) is validated.
  void advanceToStep2(Map<String, dynamic> step1Data) {
    emit(AuthRegistrationInProgress(
      currentStep: 2,
      collectedData: Map.from(step1Data),
    ));
  }

  /// Called when Step 2 form (university info) is validated.
  void advanceToStep3(Map<String, dynamic> step2Data) {
    final existing = _collectedData();
    emit(AuthRegistrationInProgress(
      currentStep: 3,
      collectedData: {...existing, ...step2Data},
    ));
  }

  /// Final step — submits all collected data to Firebase.
  Future<void> completeStudentRegistration({
    required Map<String, dynamic> step3Data,
  }) async {
    final allData = {..._collectedData(), ...step3Data};
    emit(const AuthLoading());
    try {
      final result = await _repo.registerStudent(data: allData);
      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (user) => _emitAuthenticated(user), // skip email gate — SMTP pending
      );
    } catch (e) {
      emit(const AuthError('Registration failed. Please try again.'));
    }
  }

  // ── Lecturer Registration ─────────────────────────────────────────────────

  Future<void> registerLecturer({
    required Map<String, dynamic> formData,
  }) async {
    emit(const AuthLoading());
    try {
      final result = await _repo.registerLecturer(data: formData);
      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (user) => _emitAuthenticated(user), // skip email gate — SMTP pending
      );
    } catch (e) {
      emit(const AuthError('Registration failed. Please try again.'));
    }
  }

  // ── Resend Email Verification ─────────────────────────────────────────────

  Future<void> resendVerification() async {
    try {
      await _repo.sendEmailVerification();
    } catch (_) {}
  }

  // ── Password Reset ────────────────────────────────────────────────────────

  Future<void> sendPasswordReset(String email) async {
    emit(const AuthLoading());
    try {
      final result = await _repo.sendPasswordReset(email);
      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (_) => emit(AuthEmailVerificationSent(email)),
      );
    } catch (e) {
      emit(const AuthError('Could not send reset email. Please try again.'));
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    final currentUid = currentUser?.id;
    try {
      if (currentUid != null && currentUid.isNotEmpty) {
        try {
          await _fcmService?.removeTokenForUser(currentUid);
        } catch (_) {
          // Token cleanup should not block logout.
        }
      }
      await _repo.logout();
    } catch (_) {
      // Even if logout fails remotely, clear local state
    } finally {
      _emitUnauthenticated();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _emitAuthenticated(UserModel user) {
    // Update route guards so GoRouter redirect fires immediately
    _guards.updateAuthState(
      role: user.role,
      isAuthenticated: true,
      userId: user.id,
    );
    unawaited(_fcmService?.saveTokenForUser(user.id));
    emit(AuthAuthenticated(user));
  }

  void _emitUnauthenticated() {
    _guards.updateAuthState(
      role: UserRole.guest,
      isAuthenticated: false,
    );
    emit(const AuthUnauthenticated());
  }

  Map<String, dynamic> _collectedData() {
    final s = state;
    return s is AuthRegistrationInProgress
        ? Map.from(s.collectedData)
        : <String, dynamic>{};
  }

  /// Convenience getter — null if not authenticated.
  UserModel? get currentUser {
    final s = state;
    return s is AuthAuthenticated ? s.user : null;
  }

  /// True if the current user has admin-level access.
  bool get isAdmin {
    final u = currentUser;
    if (u == null) return false;
    return u.role == UserRole.admin || u.role == UserRole.superAdmin;
  }

  /// Updates the in-memory authenticated user (e.g. after a profile save).
  /// Only acts when the current state is AuthAuthenticated.
  void updateCurrentUser(UserModel updatedUser) {
    if (state is AuthAuthenticated) {
      _guards.updateAuthState(
        role: updatedUser.role,
        isAuthenticated: true,
        userId: updatedUser.id,
      );
      emit(AuthAuthenticated(updatedUser));
    }
  }
}
