// lib/core/constants/app_colors.dart
//
// MUST StarTrack — Design Token: Colors
//
// All color values extracted directly from the HTML prototype files.
// Primary: #1152d4  (Tailwind: primary)
// Background Light: #f6f6f8 (Tailwind: background-light)
// Background Dark:  #101622 (Tailwind: background-dark)
//
// HCI Principle: Consistency — the same color always means the same
// thing throughout the app, reducing the user's cognitive load.

import 'package:flutter/material.dart';

/// Central color registry for MUST StarTrack.
/// Import this file wherever colors are needed — never hardcode hex values.
abstract final class AppColors {
  // ── Brand / Primary ──────────────────────────────────────────────────────
  /// MUST StarTrack primary blue — used for all CTAs, active states, links.
  static const Color primary = Color(0xFF1152D4);

  /// 10% opacity tint of primary — used for chip backgrounds, hover states.
  static const Color primaryTint10 = Color(0x1A1152D4);

  /// 20% opacity tint — progress bars, input focus rings.
  static const Color primaryTint20 = Color(0x331152D4);

  /// Darker primary for pressed states.
  static const Color primaryDark = Color(0xFF0D3FA8);

  // ── Backgrounds ──────────────────────────────────────────────────────────
  /// Light mode scaffold/page background.
  static const Color backgroundLight = Color(0xFFF6F6F8);

  /// Dark mode scaffold/page background.
  static const Color backgroundDark = Color(0xFF101622);

  /// Light mode card / surface (white cards on grey page).
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// Dark mode card / surface (slate-900 equivalent).
  static const Color surfaceDark = Color(0xFF1E2738);

  /// Slightly elevated surface in dark mode (slate-800).
  static const Color surfaceDark2 = Color(0xFF253047);

  // ── Text ─────────────────────────────────────────────────────────────────
  /// Primary text — light mode (slate-900).
  static const Color textPrimaryLight = Color(0xFF0F172A);

  /// Primary text — dark mode (slate-100).
  static const Color textPrimaryDark = Color(0xFFF1F5F9);

  /// Secondary / muted text — light mode (slate-500).
  static const Color textSecondaryLight = Color(0xFF64748B);

  /// Secondary / muted text — dark mode (slate-400).
  static const Color textSecondaryDark = Color(0xFF94A3B8);

  /// Tertiary / hint text (slate-400 light / slate-600 dark).
  static const Color textHintLight = Color(0xFF94A3B8);
  static const Color textHintDark = Color(0xFF475569);

  // ── Borders ──────────────────────────────────────────────────────────────
  /// Default border — light mode (slate-200).
  static const Color borderLight = Color(0xFFE2E8F0);

  /// Default border — dark mode (slate-800).
  static const Color borderDark = Color(0xFF1E293B);

  // ── Semantic Status Colors ────────────────────────────────────────────────
  /// Success green (emerald-500 / emerald-600).
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color successDark = Color(0xFF064E3B);
  static const Color successText = Color(0xFF065F46);

  /// Warning amber.
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color warningDark = Color(0xFF78350F);
  static const Color warningText = Color(0xFF92400E);

  /// Danger red.
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerLight = Color(0xFFFEE2E2);
  static const Color dangerDark = Color(0xFF7F1D1D);
  static const Color dangerText = Color(0xFF991B1B);

  /// Info / primary-adjacent blue tint.
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFEFF6FF);
  static const Color infoDark = Color(0xFF1E3A5F);
  static const Color infoText = Color(0xFF1D4ED8);

  // ── Role Badge Colors ─────────────────────────────────────────────────────
  /// Student role badge.
  static const Color roleStudent = Color(0xFF1152D4);
  static const Color roleStudentBg = Color(0xFFEFF6FF);

  /// Lecturer/staff role badge.
  static const Color roleLecturer = Color(0xFF7C3AED);
  static const Color roleLecturerBg = Color(0xFFF5F3FF);

  /// Admin role badge.
  static const Color roleAdmin = Color(0xFFD97706);
  static const Color roleAdminBg = Color(0xFFFFFBEB);

  /// Super admin role badge.
  static const Color roleSuperAdmin = Color(0xFFDC2626);
  static const Color roleSuperAdminBg = Color(0xFFFEF2F2);

  // ── Risk / Suspicion Score Colors ─────────────────────────────────────────
  /// Low suspicion (green).
  static const Color riskLow = Color(0xFF10B981);
  static const Color riskLowBg = Color(0xFFD1FAE5);

  /// Medium suspicion (amber).
  static const Color riskMedium = Color(0xFFF59E0B);
  static const Color riskMediumBg = Color(0xFFFEF3C7);

  /// High suspicion (red).
  static const Color riskHigh = Color(0xFFEF4444);
  static const Color riskHighBg = Color(0xFFFEE2E2);

  // ── Streak / Gamification ─────────────────────────────────────────────────
  static const Color streakActive = Color(0xFFF59E0B);
  static const Color streakInactive = Color(0xFFE2E8F0);

  // ── Online Presence Indicator ─────────────────────────────────────────────
  static const Color onlineGreen = Color(0xFF22C55E);
  static const Color offlineGrey = Color(0xFF94A3B8);

  // ── Message Bubbles ───────────────────────────────────────────────────────
  /// Sent message bubble (primary brand).
  static const Color bubbleSent = Color(0xFF1152D4);
  static const Color bubbleSentText = Color(0xFFFFFFFF);

  /// Received message bubble — light mode.
  static const Color bubbleReceivedLight = Color(0xFFFFFFFF);
  static const Color bubbleReceivedDark = Color(0xFF1E2738);
  static const Color bubbleReceivedText = Color(0xFF0F172A);

  // ── Overlay / Scrim ───────────────────────────────────────────────────────
  static const Color scrimLight = Color(0x33000000);
  static const Color scrimDark = Color(0x99000000);

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the appropriate color for the current theme brightness.
  static Color adaptive(
    BuildContext context, {
    required Color light,
    required Color dark,
  }) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  /// Returns primary text color for current theme.
  static Color textPrimary(BuildContext context) => adaptive(
        context,
        light: textPrimaryLight,
        dark: textPrimaryDark,
      );

  /// Returns secondary text color for current theme.
  static Color textSecondary(BuildContext context) => adaptive(
        context,
        light: textSecondaryLight,
        dark: textSecondaryDark,
      );

  /// Returns surface color for current theme.
  static Color surface(BuildContext context) => adaptive(
        context,
        light: surfaceLight,
        dark: surfaceDark,
      );

  /// Returns page background color for current theme.
  static Color background(BuildContext context) => adaptive(
        context,
        light: backgroundLight,
        dark: backgroundDark,
      );

  /// Returns border color for current theme.
  static Color border(BuildContext context) => adaptive(
        context,
        light: borderLight,
        dark: borderDark,
      );
}
