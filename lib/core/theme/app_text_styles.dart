// lib/core/theme/app_text_styles.dart
//
// MUST StarTrack — Typography Scale (Plus Jakarta Sans)
//
// Named constants for the app's full type scale.
// Prefer using Theme.of(context).textTheme for most widgets — use these
// constants only when a widget is outside the theme tree or when you need
// a very specific one-off style that doesn't map to the Material text scale.
//
// Scale summary:
//   display*   — hero numbers, splash screens (32–44 px, w800)
//   headline*  — section / page titles       (20–28 px, w700)
//   title*     — card titles, app bars       (15–18 px, w600–w700)
//   body*      — paragraph / descriptive     (13–15 px, w400)
//   label*     — chips, badges, nav labels   (10–13 px, w600–w700)
//   caption    — timestamps, metadata        (11 px,  w400)

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

abstract final class AppTextStyles {
  // ── Display ───────────────────────────────────────────────────────────────
  static TextStyle displayLarge({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 44,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.1,
        color: color ?? AppColors.textPrimaryLight,
      );

  static TextStyle displayMedium({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.15,
        color: color ?? AppColors.textPrimaryLight,
      );

  // ── Headline ──────────────────────────────────────────────────────────────
  static TextStyle headlineLarge({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.2,
        color: color ?? AppColors.textPrimaryLight,
      );

  static TextStyle headlineMedium({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.25,
        color: color ?? AppColors.textPrimaryLight,
      );

  static TextStyle headlineSmall({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.3,
        color: color ?? AppColors.textPrimaryLight,
      );

  // ── Title ─────────────────────────────────────────────────────────────────
  static TextStyle titleLarge({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.35,
        color: color ?? AppColors.textPrimaryLight,
      );

  static TextStyle titleMedium({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.4,
        color: color ?? AppColors.textPrimaryLight,
      );

  static TextStyle titleSmall({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.4,
        color: color ?? AppColors.textPrimaryLight,
      );

  // ── Body ──────────────────────────────────────────────────────────────────
  static TextStyle bodyLarge({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: color ?? AppColors.textPrimaryLight,
      );

  static TextStyle bodyMedium({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: color ?? AppColors.textPrimaryLight,
      );

  static TextStyle bodySmall({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color ?? AppColors.textSecondaryLight,
      );

  // ── Label ─────────────────────────────────────────────────────────────────
  static TextStyle labelLarge({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: color ?? AppColors.textPrimaryLight,
      );

  static TextStyle labelMedium({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.05,
        color: color ?? AppColors.textPrimaryLight,
      );

  static TextStyle labelSmall({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: color ?? AppColors.textSecondaryLight,
      );

  // ── Caption / Meta ────────────────────────────────────────────────────────
  static TextStyle caption({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: color ?? AppColors.textSecondaryLight,
      );

  // ── Overline ──────────────────────────────────────────────────────────────
  /// All-caps section label (e.g. "APPEARANCE", "RECENT").
  static TextStyle overline({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: color ?? AppColors.textSecondaryLight,
      );

  // ── Button ────────────────────────────────────────────────────────────────
  static TextStyle button({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: color ?? Colors.white,
      );

  static TextStyle buttonSmall({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.05,
        color: color ?? Colors.white,
      );
}
