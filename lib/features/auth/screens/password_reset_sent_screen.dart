// lib/features/auth/screens/password_reset_sent_screen.dart
//
// MUST StarTrack â€” Password Reset / Email Verification Sent
// Used after: forgot password, new registration (verification email)
//
// HCI: success illustration, clear next steps, back-to-login CTA.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/route_names.dart';
import '../../shared/hci_components/st_form_widgets.dart';

class PasswordResetSentScreen extends StatelessWidget {
  final String? email;
  const PasswordResetSentScreen({super.key, this.email});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF0B1222), Color(0xFF111D36)]
                : const [Color(0xFFF8FBFF), Color(0xFFECF3FF)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -80,
              right: -70,
              child: _GlowBlob(size: 220, color: Color(0x332563EB)),
            ),
            const Positioned(
              bottom: -90,
              left: -85,
              child: _GlowBlob(size: 250, color: Color(0x221152D4)),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDimensions.spacingXl),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimensions.spacingLg,
                            vertical: AppDimensions.spacingXl,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.white.withValues(alpha: 0.78),
                            borderRadius:
                                BorderRadius.circular(AppDimensions.radiusLg),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : AppColors.primary.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Column(
                            children: [
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.5, end: 1.0),
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.elasticOut,
                                builder: (_, scale, child) =>
                                    Transform.scale(scale: scale, child: child),
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.mark_email_read_rounded,
                                      size: 56, color: AppColors.success),
                                ),
                              ),
                              const SizedBox(height: 28),
                              Text('Check Your Email',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                      color: isDark
                                          ? AppColors.textPrimaryDark
                                          : AppColors.textPrimaryLight)),
                              const SizedBox(height: 12),
                              Text(
                                email == null || email!.isEmpty
                                    ? 'We\'ve sent an email to your MUST address.\n\n'
                                        'Click the link in the email to continue. '
                                        'If you don\'t see it, check your spam or junk folder.'
                                    : 'We\'ve sent an email to:\n$email\n\n'
                                        'Click the link in the email to continue. '
                                        'If you don\'t see it, check your spam or junk folder.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondaryLight,
                                  height: 1.6,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 36),
                              StButton(
                                label: 'Back to Login',
                                onPressed: () => context.go(RouteNames.login),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () => context.go(RouteNames.guestDiscover),
                                child: Text('Explore while you wait',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        color: isDark
                                            ? AppColors.textSecondaryDark
                                            : AppColors.textSecondaryLight)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: 80,
              spreadRadius: 25,
            ),
          ],
        ),
      ),
    );
  }
}

