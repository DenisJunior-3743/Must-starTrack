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
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.spacingXl),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              // Animated success icon
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.5, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mark_email_read_rounded,
                      size: 56, color: AppColors.success),
                ),
              ),
              const SizedBox(height: 32),

              Text('Check Your Email',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
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
                  fontSize: 14, color: AppColors.textSecondaryLight, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              StButton(
                label: 'Back to Login',
                onPressed: () => context.go(RouteNames.login),
              ),
              const SizedBox(height: 16),

              TextButton(
                onPressed: () => context.go(RouteNames.guestDiscover),
                child: Text('Explore while you wait',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppColors.textSecondaryLight)),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

