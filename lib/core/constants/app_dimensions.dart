// lib/core/constants/app_dimensions.dart
//
// MUST StarTrack — Design Token: Dimensions & Spacing
//
// All values derived from the HTML prototype analysis:
// - rounded-xl = 12px → radiusXl
// - rounded-full = 9999px → radiusFull
// - p-4 = 16px → paddingMd
// - gap-3 = 12px → spacingSm
//
// HCI Principle: Consistency & Natural Mapping — consistent spacing
// creates visual rhythm that users internalize without noticing.
// HCI Principle: Universal Design — minimum 48dp touch targets
// per WCAG 2.1 success criterion 2.5.5.

abstract final class AppDimensions {
  // ── Touch Targets (HCI: Universal Design) ────────────────────────────────
  /// Minimum tap target size — WCAG 2.5.5 requires 44×44px minimum.
  /// We use 48dp to be safe across all Android densities.
  static const double touchTargetMin = 48.0;

  /// Icon button size (matches p-2 + icon size in prototypes).
  static const double iconButtonSize = 40.0;

  // ── Border Radius ─────────────────────────────────────────────────────────
  /// Extra small — tags, badges (rounded).
  static const double radiusXs = 4.0;

  /// Small — input fields, small chips (rounded-lg in prototypes → 8px).
  static const double radiusSm = 8.0;

  /// Medium — most cards, containers (rounded-xl = 12px).
  static const double radiusMd = 12.0;

  /// Large — bottom sheets, modal cards (rounded-2xl = 16px).
  static const double radiusLg = 16.0;

  /// Extra large — feature cards, onboarding panels (rounded-3xl = 24px).
  static const double radiusXl = 24.0;

  /// Full — pills, avatars, FABs (rounded-full = 9999).
  static const double radiusFull = 9999.0;

  // ── Spacing / Padding ─────────────────────────────────────────────────────
  /// 4px — tight gaps between inline elements.
  static const double spacingXxs = 4.0;

  /// 8px — gap within a component (icon + label).
  static const double spacingXs = 8.0;

  /// 12px — gap-3 in prototypes, card internal padding.
  static const double spacingSm = 12.0;

  /// 16px — p-4 in prototypes — standard screen horizontal padding.
  static const double spacingMd = 16.0;

  /// 20px — p-5, larger section gaps.
  static const double spacingLg = 20.0;

  /// 24px — p-6, section-to-section breathing room.
  static const double spacingXl = 24.0;

  /// 32px — p-8, hero area padding.
  static const double spacingXxl = 32.0;

  /// 48px — section breaks, bottom nav offset.
  static const double spacingHuge = 48.0;

  // ── Screen Padding ────────────────────────────────────────────────────────
  /// Horizontal padding applied to all screen content.
  static const double screenHPadding = 16.0;

  /// Vertical padding between screen sections.
  static const double screenVPadding = 16.0;

  // ── AppBar ────────────────────────────────────────────────────────────────
  static const double appBarHeight = 60.0;

  // ── Bottom Navigation Bar ─────────────────────────────────────────────────
  static const double bottomNavHeight = 68.0;

  /// Extra scroll padding so list content isn't hidden behind the nav bar.
  static const double bottomNavScrollPadding = 84.0;

  // ── Avatar Sizes ──────────────────────────────────────────────────────────
  /// Tiny — notification list avatars.
  static const double avatarXs = 28.0;

  /// Small — feed post author, chat list.
  static const double avatarSm = 36.0;

  /// Medium — chat detail header, peer cards.
  static const double avatarMd = 48.0;

  /// Large — profile screen header.
  static const double avatarLg = 80.0;

  /// Extra large — onboarding photo upload.
  static const double avatarXl = 128.0;

  // ── Cards ─────────────────────────────────────────────────────────────────
  /// Feed post card media aspect ratio (16:9).
  static const double mediaAspectRatio = 16 / 9;

  /// Standard card elevation.
  static const double cardElevation = 0.0; // flat, border instead

  /// Card border width.
  static const double cardBorderWidth = 0.8;

  // ── Input Fields ──────────────────────────────────────────────────────────
  /// Standard input field height (h-14 = 56px in prototypes).
  static const double inputHeight = 56.0;

  /// Multiline input min height.
  static const double inputMultilineMin = 100.0;

  // ── Icons ─────────────────────────────────────────────────────────────────
  /// Standard icon size in app bars and buttons.
  static const double iconMd = 24.0;

  /// Smaller icon for inline use.
  static const double iconSm = 20.0;

  /// Large icons in stat cards (admin dashboard).
  static const double iconLg = 32.0;

  // ── Progress / Badges ─────────────────────────────────────────────────────
  /// Onboarding progress bar height.
  static const double progressBarHeight = 10.0;

  /// Online presence indicator dot size.
  static const double presenceDot = 12.0;

  /// Notification badge size.
  static const double badgeSize = 18.0;

  // ── Shimmer / Skeleton ────────────────────────────────────────────────────
  /// Height of a skeleton text line.
  static const double skeletonLineHeight = 14.0;

  /// Height of a skeleton card.
  static const double skeletonCardHeight = 120.0;

  // ── Feed ──────────────────────────────────────────────────────────────────
  /// Number of posts fetched per page (infinite scroll).
  static const int feedPageSize = 10;

  /// Number of messages fetched per page in chat.
  static const int chatPageSize = 20;
}
