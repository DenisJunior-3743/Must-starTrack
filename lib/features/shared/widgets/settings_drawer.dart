// lib/features/shared/widgets/settings_drawer.dart
//
// MUST StarTrack — Settings Side Drawer
//
// Opened by the hamburger (☰) button that lives in each screen's app bar.
// Contains: theme mode selector, notification prefs link, about, logout.
//
// To open from any screen:
//   Scaffold.of(context).openEndDrawer();
// (The hosting screen must declare `endDrawer: const SettingsDrawer()`.)

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../auth/bloc/auth_cubit.dart';

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      width: 300,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ── Branded header ────────────────────────────────────────────────
          _DrawerHeader(isDark: isDark),

          // ── Scrollable body ───────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Appearance section
                const _SectionLabel('Appearance'),
                const _ThemeModeSelector(),
                const SizedBox(height: 8),
                const Divider(indent: 16, endIndent: 16),
                const SizedBox(height: 8),

                // Account section
                const _SectionLabel('Account'),
                _DrawerTile(
                  icon: Icons.person_outline_rounded,
                  label: 'My Profile',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(RouteNames.myProfile);
                  },
                ),
                _DrawerTile(
                  icon: Icons.notifications_outlined,
                  label: 'Notification Settings',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(RouteNames.notificationSettings);
                  },
                ),
                const SizedBox(height: 8),
                const Divider(indent: 16, endIndent: 16),
                const SizedBox(height: 8),

                // App section
                const _SectionLabel('About'),
                _DrawerTile(
                  icon: Icons.info_outline_rounded,
                  label: 'About MUST StarTrack',
                  onTap: () {
                    Navigator.of(context).pop();
                    _showAbout(context);
                  },
                ),
                _DrawerTile(
                  icon: Icons.star_border_rounded,
                  label: 'Rate This App',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 8),
                const Divider(indent: 16, endIndent: 16),
                const SizedBox(height: 8),

                // Logout
                _DrawerTile(
                  icon: Icons.logout_rounded,
                  label: 'Log Out',
                  color: AppColors.danger,
                  onTap: () => _handleLogout(context),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // ── Footer version ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              'MUST StarTrack v1.0',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'MUST StarTrack',
      applicationVersion: '1.0.0',
      applicationLegalese:
          '© 2024 Mbarara University of Science and Technology.\nAll rights reserved.',
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    Navigator.of(context).pop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await sl<AuthCubit>().logout();
      if (context.mounted) context.go(RouteNames.login);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerHeader extends StatelessWidget {
  final bool isDark;
  const _DrawerHeader({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF0D1B3E), const Color(0xFF1152D4)]
              : [const Color(0xFF1152D4), const Color(0xFF0D3FA8)],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),

              Text(
                'MUST StarTrack',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Mbarara University of Science\nand Technology',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme mode selector — 3 pill buttons: Light / System / Dark
// ─────────────────────────────────────────────────────────────────────────────

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeMode>(
      builder: (context, mode) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.adaptive(
                context,
                light: AppColors.backgroundLight,
                dark: AppColors.surfaceDark2,
              ),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _ModeButton(
                  icon: Icons.light_mode_rounded,
                  label: 'Light',
                  active: mode == ThemeMode.light,
                  onTap: () => context.read<ThemeCubit>().setMode(ThemeMode.light),
                ),
                _ModeButton(
                  icon: Icons.settings_suggest_outlined,
                  label: 'System',
                  active: mode == ThemeMode.system,
                  onTap: () => context.read<ThemeCubit>().setMode(ThemeMode.system),
                ),
                _ModeButton(
                  icon: Icons.dark_mode_rounded,
                  label: 'Dark',
                  active: mode == ThemeMode.dark,
                  onTap: () => context.read<ThemeCubit>().setMode(ThemeMode.dark),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: active
                    ? Colors.white
                    : AppColors.textSecondary(context),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: AppColors.textSecondary(context),
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tileColor = color ?? AppColors.textPrimary(context);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: Icon(icon, size: 20, color: tileColor),
      title: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: tileColor,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: AppColors.textSecondary(context),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      ),
    );
  }
}
