// lib/core/constants/app_text_styles.dart
//
// MUST StarTrack — Design Token: Typography
//
// Font: Lexend (loaded via google_fonts package)
// Source: Matched from all HTML prototype files which use:
//   font-family: 'Lexend', sans-serif
//
// HCI Principle: Consistency — uniform type scale across all screens
// reduces cognitive friction and speeds up reading/scanning.
//
// Scale follows Material 3 naming but with Lexend applied throughout.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Central typography registry for MUST StarTrack.
/// All text styles use Lexend at the correct weights from prototypes.
abstract final class AppTextStyles {
  // ── Display ──────────────────────────────────────────────────────────────
  /// Large hero headings — used on welcome/splash screens.
  static TextStyle displayLarge({Color? color}) => GoogleFonts.lexend(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: color,
      );

  static TextStyle displayMedium({Color? color}) => GoogleFonts.lexend(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: color,
      );

  // ── Headlines ────────────────────────────────────────────────────────────
  /// Page/screen titles (e.g., "Project Showcase", "Notification Center").
  static TextStyle headlineLarge({Color? color}) => GoogleFonts.lexend(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: color,
      );

  /// Section headings within a screen.
  static TextStyle headlineMedium({Color? color}) => GoogleFonts.lexend(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
        color: color,
      );

  static TextStyle headlineSmall({Color? color}) => GoogleFonts.lexend(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: color,
      );

  // ── Titles ───────────────────────────────────────────────────────────────
  /// AppBar titles, card titles (text-lg font-bold in prototypes).
  static TextStyle titleLarge({Color? color}) => GoogleFonts.lexend(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.015,
        color: color,
      );

  /// Card sub-titles, list item primary text (text-base font-bold).
  static TextStyle titleMedium({Color? color}) => GoogleFonts.lexend(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.01,
        color: color,
      );

  /// Smaller titles, chip labels (text-sm font-semibold).
  static TextStyle titleSmall({Color? color}) => GoogleFonts.lexend(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: color,
      );

  // ── Body ─────────────────────────────────────────────────────────────────
  /// Default body text — descriptions, bio text (text-sm leading-relaxed).
  static TextStyle bodyLarge({Color? color}) => GoogleFonts.lexend(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: color,
      );

  static TextStyle bodyMedium({Color? color}) => GoogleFonts.lexend(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );

  /// Smaller body — feed timestamps, metadata (text-xs).
  static TextStyle bodySmall({Color? color}) => GoogleFonts.lexend(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: color,
      );

  // ── Labels ───────────────────────────────────────────────────────────────
  /// Buttons, input labels (text-sm font-semibold).
  static TextStyle labelLarge({Color? color}) => GoogleFonts.lexend(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.01,
        color: color,
      );

  /// Badge text, chip text (text-xs font-bold).
  static TextStyle labelMedium({Color? color}) => GoogleFonts.lexend(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.02,
        color: color,
      );

  /// Uppercase section headers (uppercase tracking-wider in prototypes).
  static TextStyle labelSmall({Color? color}) => GoogleFonts.lexend(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.08,
        color: color,
      );

  // ── Input Fields ─────────────────────────────────────────────────────────
  static TextStyle inputText({Color? color}) => GoogleFonts.lexend(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle inputLabel({Color? color}) => GoogleFonts.lexend(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle inputHint({Color? color}) => GoogleFonts.lexend(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textHintLight,
      );

  // ── Navigation ───────────────────────────────────────────────────────────
  /// Bottom nav bar labels.
  static TextStyle navLabel({Color? color}) => GoogleFonts.lexend(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.02,
        color: color,
      );

  // ── Message Bubbles ───────────────────────────────────────────────────────
  static TextStyle messageBubble({Color? color}) => GoogleFonts.lexend(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );

  static TextStyle messageTimestamp({Color? color}) => GoogleFonts.lexend(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: color,
      );

  // ── Stats / Analytics ─────────────────────────────────────────────────────
  /// Large metric numbers in admin dashboards.
  static TextStyle statNumber({Color? color}) => GoogleFonts.lexend(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: color,
      );

  static TextStyle statLabel({Color? color}) => GoogleFonts.lexend(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: color,
      );

  // ── Code / Monospace ──────────────────────────────────────────────────────
  /// Registration number display (e.g., 2020/BSE/001/PS).
  static TextStyle regNumber({Color? color}) => TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: color,
      );
}
