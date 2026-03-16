// lib/features/auth/bloc/auth_cubit.dart
//
// MUST StarTrack — AuthCubit (State Manager for Authentication)
//
// BLoC pattern: Cubit variant (simpler — emits states directly).
// The Cubit is the ONLY place in the app that calls AuthRepository.
// Screens listen to AuthState changes and rebuild accordingly.
//
// State transitions:
//   AuthInitial
//     → checkAuthStatus()
//   AuthLoading
//     → login / register / googleSignIn
//   AuthAuthenticated(user)
//     → successful auth
//   AuthUnauthenticated
//     → no session / logout
//   AuthError(message)
//     → any failure
//   AuthEmailVerificationSent
//     → after registration, waiting for email click
//   AuthRegistrationStep(step, data)
//     → tracks multi-step registration state
//
// HCI Principle: Feedback — every async auth operation moves
//   through Loading → Success/Error states, driving UI feedback.

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../data/models/user_model.dart';
import '../../../core/router/route_guards.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STATES
// ─────────────────────────────────────────────────────────────────────────────

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

/// App just launched — hasn't checked session yet.
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// An async auth operation is in progress.
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// User is fully authenticated and verified.
class AuthAuthenticated extends AuthState {
  final UserModel user;
  const AuthAuthenticated(this.user);
  @override
  List<Object?> get props => [user];
}

/// No active session.
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// Registration succeeded but email not yet verified.
class AuthEmailVerificationSent extends AuthState {
  final String email;
  const AuthEmailVerificationSent(this.email);
  @override
  List<Object?> get props => [email];
}

/// Holds data being collected across the 3-step registration.
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

/// An auth error occurred.
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
  // AuthRepository will be injected here in Phase 2 backend hookup.
  // final AuthRepository _authRepository;

  final RouteGuards _guards;

  AuthCubit({
    // required AuthRepository authRepository,
    required RouteGuards guards,
  })  :
        // _authRepository = authRepository,
        _guards = guards,
        super(const AuthInitial());

  // ── Check persisted session on app launch ─────────────────────────────────

  /// Called from app.dart — checks SharedPreferences / Firebase Auth state.
  Future<void> checkAuthStatus() async {
    emit(const AuthLoading());
    try {
      // Phase 2: replace with actual auth repository call
      // final result = await _authRepository.getCurrentUser();
      // result.fold(
      //   (failure) => _emitUnauthenticated(),
      //   (user) => _emitAuthenticated(user),
      // );

      // Phase 1 stub — always unauthenticated
      await Future.delayed(const Duration(milliseconds: 500));
      _emitUnauthenticated();
    } catch (e) {
      _emitUnauthenticated();
    }
  }

  // ── Email / Password Login ────────────────────────────────────────────────

  /// Authenticates with email + password.
  Future<void> login({
    required String email,
    required String password,
  }) async {
    emit(const AuthLoading());
    try {
      // Phase 2:
      // final result = await _authRepository.loginWithEmail(email, password);
      // result.fold(
      //   (failure) => emit(AuthError(failure.message)),
      //   (user) => _emitAuthenticated(user),
      // );

      // Phase 1 stub
      await Future.delayed(const Duration(seconds: 1));
      emit(const AuthError('Backend not connected yet. Phase 2 pending.'));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  /// Triggers Google OAuth flow. Enforces MUST domain restriction.
  Future<void> signInWithGoogle() async {
    emit(const AuthLoading());
    try {
      // Phase 2:
      // final result = await _authRepository.signInWithGoogle();
      // result.fold(
      //   (failure) => emit(AuthError(failure.message)),
      //   (user) => _emitAuthenticated(user),
      // );

      await Future.delayed(const Duration(seconds: 1));
      emit(const AuthError('Google Sign-In: Phase 2 pending.'));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  // ── Multi-step Student Registration ───────────────────────────────────────

  /// Called when Step 1 (bio) is completed.
  void advanceToStep2(Map<String, dynamic> step1Data) {
    emit(AuthRegistrationInProgress(
      currentStep: 2,
      collectedData: step1Data,
    ));
  }

  /// Called when Step 2 (university info) is completed.
  void advanceToStep3(Map<String, dynamic> step2Data) {
    final currentData = state is AuthRegistrationInProgress
        ? (state as AuthRegistrationInProgress).collectedData
        : <String, dynamic>{};
    emit(AuthRegistrationInProgress(
      currentStep: 3,
      collectedData: {...currentData, ...step2Data},
    ));
  }

  /// Final step — creates the account with all collected data.
  Future<void> completeStudentRegistration({
    required Map<String, dynamic> step3Data,
  }) async {
    final currentData = state is AuthRegistrationInProgress
        ? (state as AuthRegistrationInProgress).collectedData
        : <String, dynamic>{};
    final allData = {...currentData, ...step3Data};

    emit(const AuthLoading());
    try {
      // Phase 2:
      // final result = await _authRepository.registerStudent(allData);
      // result.fold(
      //   (failure) => emit(AuthError(failure.message)),
      //   (user) {
      //     emit(AuthEmailVerificationSent(user.email));
      //   },
      // );

      await Future.delayed(const Duration(seconds: 1));
      emit(AuthEmailVerificationSent(allData['email'] as String? ?? ''));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  /// Registers a lecturer/staff account (single-step form).
  Future<void> registerLecturer({
    required Map<String, dynamic> formData,
  }) async {
    emit(const AuthLoading());
    try {
      await Future.delayed(const Duration(seconds: 1));
      emit(AuthEmailVerificationSent(formData['email'] as String? ?? ''));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  // ── Password Reset ────────────────────────────────────────────────────────

  Future<void> sendPasswordReset(String email) async {
    emit(const AuthLoading());
    try {
      // Phase 2:
      // final result = await _authRepository.sendPasswordReset(email);
      // result.fold(
      //   (failure) => emit(AuthError(failure.message)),
      //   (_) => emit(AuthEmailVerificationSent(email)),
      // );

      await Future.delayed(const Duration(seconds: 1));
      emit(AuthEmailVerificationSent(email));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    // Phase 2: await _authRepository.logout();
    _emitUnauthenticated();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _emitUnauthenticated() {
    _guards.updateAuthState(
      role: UserRole.guest,
      isAuthenticated: false,
    );
    emit(const AuthUnauthenticated());
  }

  /// Returns the user if authenticated, null otherwise.
  UserModel? get currentUser {
    final s = state;
    return s is AuthAuthenticated ? s.user : null;
  }
}
