// lib/core/router/route_guards.dart
//
// MUST StarTrack — Route Guards
//
// Implements role-based access control at the navigation layer.
// Every protected route checks the user's role before rendering.
//
// Guard hierarchy:
//   unauthenticated → guest routes only
//   student         → student + guest routes
//   lecturer/staff  → lecturer + student routes
//   admin           → admin + lecturer + student routes
//   super_admin     → everything
//
// HCI Principle: Constraints — users are never shown a screen
// they cannot use; they're redirected to the appropriate screen
// with an explanation message.
//
// Integration: RouteGuards is provided via get_it and injected
// into AppRouter. It reads the current AuthRepository state.

import 'package:flutter/foundation.dart';
import 'route_names.dart';

/// User role enum used throughout the app for RBAC.
enum UserRole {
  guest,
  student,
  lecturer,
  admin,
  superAdmin;

  /// Parses a role string from the database/Firestore.
  static UserRole fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'student':    return UserRole.student;
      case 'lecturer':   return UserRole.lecturer;
      case 'staff':      return UserRole.lecturer; // staff = lecturer
      case 'admin':      return UserRole.admin;
      case 'super_admin':return UserRole.superAdmin;
      default:           return UserRole.guest;
    }
  }

  String get label {
    switch (this) {
      case UserRole.guest:      return 'Guest';
      case UserRole.student:    return 'Student';
      case UserRole.lecturer:   return 'Lecturer / Staff';
      case UserRole.admin:      return 'Admin';
      case UserRole.superAdmin: return 'Super Admin';
    }
  }

  /// Whether this role can access admin features.
  bool get isAdmin => this == UserRole.admin || this == UserRole.superAdmin;

  /// Whether this role is authenticated (not a guest).
  bool get isAuthenticated => this != UserRole.guest;
}

/// Provides guard methods consumed by AppRouter.redirect.
/// In production, reads session from SharedPreferences / Firebase Auth state.
class RouteGuards {
  // Injected by DI — holds the current authenticated user's role.
  // In Phase 2 this will read from AuthRepository.
  // For Phase 1 (stub) we return guest to allow building screens.
  UserRole _currentRole = UserRole.guest;
  bool _isAuthenticated = false;
  String? _currentUserId;

  // Called by AuthCubit when auth state changes.
  void updateAuthState({
    required UserRole role,
    required bool isAuthenticated,
    String? userId,
  }) {
    _currentRole = role;
    _isAuthenticated = isAuthenticated;
    _currentUserId = userId;
    debugPrint('🔒 Route guard: role=$role, auth=$isAuthenticated');
  }

  UserRole get currentRole => _currentRole;
  bool get isAuthenticated => _isAuthenticated;
  String? get currentUserId => _currentUserId;

  // ── Public routes (no auth required) ────────────────────────────────────

  static const Set<String> _publicRoutes = {
    RouteNames.splash,
    RouteNames.guestDiscover,
    RouteNames.login,
    RouteNames.registerStep1,
    RouteNames.lecturerRegister,
    RouteNames.forgotPassword,
    RouteNames.passwordResetSent,
  };

  // ── Global redirect logic ─────────────────────────────────────────────────

  /// Called by GoRouter for every navigation.
  /// Returns null to allow navigation, or a redirect path to redirect.
  Future<String?> globalRedirect(String location) async {
    final isPublic = _publicRoutes.any((r) => location.startsWith(r));

    // Allow public routes always.
    if (isPublic) return null;

    // If not authenticated and trying to access protected route → login.
    if (!_isAuthenticated) {
      // But allow guest to browse explore.
      if (location.startsWith(RouteNames.guestDiscover)) return null;
      return RouteNames.login;
    }

    // Authenticated — check role for protected admin routes.
    if (location.startsWith(RouteNames.adminDashboard) &&
        !_currentRole.isAdmin) {
      debugPrint('⛔ Access denied: ${_currentRole.label} → /admin');
      return RouteNames.home;
    }

    if (location.startsWith(RouteNames.superAdminDashboard) &&
        _currentRole != UserRole.superAdmin) {
      debugPrint('⛔ Access denied: ${_currentRole.label} → /super-admin');
      return RouteNames.home;
    }

    return null; // Allow navigation.
  }

  // ── Action-level guards ────────────────────────────────────────────────────
  // These are called by widgets before performing an action.

  /// Returns true if the current user can perform social actions
  /// (like, comment, follow, etc.). Guests cannot.
  bool canInteract() => _isAuthenticated;

  /// Returns true if the current user can create posts.
  bool canCreatePost() =>
      _isAuthenticated &&
      (_currentRole == UserRole.student ||
        _currentRole == UserRole.admin ||
        _currentRole == UserRole.superAdmin);

  /// Returns true if the user can send collaboration requests.
  bool canCollaborate() => _isAuthenticated;

  /// Returns true if the user can access admin panel.
  bool canAccessAdmin() => _currentRole.isAdmin;

  /// Returns true if the user can access super admin panel.
  bool canAccessSuperAdmin() => _currentRole == UserRole.superAdmin;

  /// Returns true if the user can post opportunity posts.
  bool canPostOpportunity() =>
      _currentRole == UserRole.lecturer ||
      _currentRole == UserRole.admin ||
      _currentRole == UserRole.superAdmin;

  // ── Guard helpers used by GoRouter redirect ────────────────────────────────

  Future<String?> requireAuth(String location) async {
    if (!_isAuthenticated) return RouteNames.login;
    return null;
  }

  Future<String?> requireAdmin(String location) async {
    if (!_isAuthenticated) return RouteNames.login;
    if (!_currentRole.isAdmin) return RouteNames.home;
    return null;
  }

  Future<String?> requireSuperAdmin(String location) async {
    if (!_isAuthenticated) return RouteNames.login;
    if (_currentRole != UserRole.superAdmin) return RouteNames.home;
    return null;
  }
}
