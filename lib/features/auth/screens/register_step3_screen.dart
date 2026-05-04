// lib/features/auth/screens/register_step3_screen.dart
//
// MUST StarTrack â€” Registration Step 3: Security & Authentication
//
// Collects: password, confirm password, terms agreement.
// Includes: password strength meter, Google signup alternative.
// Submits: all collected data to AuthCubit â†’ AuthRepository.
//
// HCI: real-time strength bar, check-before-submit constraint,
//      terms must be accepted (constraint), verification email notice.

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/must_validators.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../shared/hci_components/st_form_widgets.dart';
import '../bloc/auth_cubit.dart';

class RegisterStep3Screen extends StatefulWidget {
  final Map<String, dynamic> combinedData;
  const RegisterStep3Screen({
    super.key,
    this.combinedData = const {},
  });

  @override
  State<RegisterStep3Screen> createState() => _RegisterStep3ScreenState();
}

class _RegisterStep3ScreenState extends State<RegisterStep3Screen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _termsAccepted = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit(BuildContext ctx) {
    if (!_formKey.currentState!.validate()) return;
    if (!_termsAccepted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Please accept the Terms of Service to continue.'),
        backgroundColor: AppColors.danger,
      ));
      return;
    }
    ctx.read<AuthCubit>().completeStudentRegistration(
      step3Data: {
        ...widget.combinedData,
        'password': _passwordCtrl.text,
      },
    );
  }

  void _showPolicyDialog({required bool isPrivacy}) {
    final title = isPrivacy ? 'Privacy Policy' : 'Terms of Service';
    final sections = isPrivacy
        ? _privacySections
        : _termsSections;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Effective date: ${DateTime.now().year}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: AppColors.border(context)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: sections
                            .map(
                              (section) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      section.$1,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary(context),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      section.$2,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12.5,
                                        height: 1.45,
                                        color:
                                            AppColors.textSecondary(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        'Close',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static const List<(String, String)> _termsSections = [
    (
      '1. Platform Scope',
      'MUST StarTrack supports academic portfolios, collaboration, and opportunity discovery inside the app. Activities, agreements, or disputes outside this system are outside MUST StarTrack operational control.',
    ),
    (
      '2. Project Ownership & Licensing',
      'You retain ownership of projects and content you upload. By posting, you grant MUST StarTrack a limited, non-exclusive license to store, process, and display your content within platform features such as feeds, profiles, and search.',
    ),
    (
      '3. Integrity & Contextualization',
      'You must represent contributions truthfully. Do not misattribute authorship, fabricate achievements, or remove essential context that changes meaning. If AI or third-party help was used, disclose it appropriately where required.',
    ),
    (
      '4. Acceptable Use',
      'Do not upload illegal, harmful, discriminatory, or infringing content. Do not impersonate others, abuse messaging, or attempt to manipulate ranking, reputation, or engagement metrics.',
    ),
    (
      '5. External Services Disclaimer',
      'Links, files, and interactions that move outside MUST StarTrack are handled by third-party services. Their terms and policies apply, and outcomes outside our system are not our responsibility.',
    ),
    (
      '6. Enforcement & Updates',
      'We may moderate content, restrict access, or suspend accounts for policy violations. Terms may be updated periodically; continued use indicates acceptance of updates.',
    ),
  ];

  static const List<(String, String)> _privacySections = [
    (
      '1. Data We Collect',
      'We collect profile data, authentication details, portfolio content, and interaction signals needed to provide core features such as authentication, messaging, recommendations, and collaboration.',
    ),
    (
      '2. How Data Is Used',
      'Data is used to run the platform, personalize relevant content, improve reliability, and protect account security. We use only what is necessary for platform function and academic experience quality.',
    ),
    (
      '3. Visibility & Sharing',
      'Profile and project visibility follows in-app settings and role-based access. We do not treat your private credentials as public content. Authorized administrators may access required operational data under governance rules.',
    ),
    (
      '4. Security & Retention',
      'We apply technical and organizational safeguards to protect stored data. Retention periods depend on operational, academic, and legal requirements, after which eligible data may be deleted or anonymized.',
    ),
    (
      '5. Your Responsibilities',
      'Keep your credentials secure, submit accurate information, and report suspected account misuse. Protecting integrity is a shared responsibility between users and the platform.',
    ),
    (
      '6. Third-Party Boundaries',
      'When you leave MUST StarTrack (external links, cloud tools, third-party sites), their privacy and security rules apply. Events outside our system are not controlled by MUST StarTrack.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    String? sanitizedFrom(String? candidate) {
      if (candidate == null || candidate.isEmpty) return null;
      if (!candidate.startsWith('/')) return null;
      return candidate;
    }

    final requestedFrom = sanitizedFrom(
      widget.combinedData['returnTo']?.toString(),
    );

    return BlocProvider.value(
      // Use the global singleton so sl<AuthCubit>().currentUser is set
      // everywhere (e.g. create_post_screen) after registration completes.
      value: sl<AuthCubit>(),
      child: BlocConsumer<AuthCubit, AuthState>(
        listener: (ctx, state) {
          if (state is AuthEmailVerificationSent) {
            final encodedEmail = Uri.encodeComponent(state.email);
            ctx.go('${RouteNames.passwordResetSent}?email=$encodedEmail');
          } else if (state is AuthAuthenticated) {
            ctx.go(requestedFrom ?? RouteNames.home);
          } else if (state is AuthError) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.danger,
            ));
          }
        },
        builder: (ctx, state) {
          final loading = state is AuthLoading;

          return Scaffold(
            appBar: AppBar(
              title: const Text('Security & Authentication'),
              leading: BackButton(onPressed: () => ctx.pop()),
            ),
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF8FBFF), Color(0xFFECF3FF)],
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
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const ProgressStepper(currentStep: 3),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(AppDimensions.spacingMd),
                            child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),

                          Text('Secure Your Account',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 24, fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            )),
                          const SizedBox(height: 4),
                          Text('Set a strong password for your MUST StarTrack account.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, color: AppColors.textSecondaryLight)),
                          const SizedBox(height: 24),

                          // â”€â”€ Password â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                          StTextField(
                            label: AppStrings.password,
                            hint: 'Enter your password',
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                                foregroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                minimumSize: const Size(40, 40),
                              ),
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                transitionBuilder: (child, animation) =>
                                    ScaleTransition(scale: animation, child: child),
                                child: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  key: ValueKey(_obscurePassword),
                                ),
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}), // rebuild strength bar
                            validator: MustValidators.validatePassword,
                          ),

                          // Strength bar
                          ValueListenableBuilder(
                            valueListenable: _passwordCtrl,
                            builder: (_, v, __) => PasswordStrengthBar(password: v.text),
                          ),
                          const SizedBox(height: AppDimensions.spacingMd),

                          // â”€â”€ Confirm password â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                          StTextField(
                            label: AppStrings.confirmPassword,
                            hint: 'Re-enter your password',
                            controller: _confirmCtrl,
                            obscureText: _obscureConfirm,
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscureConfirm
                                  ? 'Show password'
                                  : 'Hide password',
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                                foregroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                minimumSize: const Size(40, 40),
                              ),
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                transitionBuilder: (child, animation) =>
                                    ScaleTransition(scale: animation, child: child),
                                child: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  key: ValueKey(_obscureConfirm),
                                ),
                              ),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                            textInputAction: TextInputAction.done,
                            validator: (v) => MustValidators.validatePasswordMatch(
                                _passwordCtrl.text, v),
                          ),
                          const SizedBox(height: 20),

                          // â”€â”€ Terms checkbox â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                          _TermsCheckbox(
                            value: _termsAccepted,
                            onChanged: (v) => setState(() => _termsAccepted = v ?? false),
                            onOpenTerms: () => _showPolicyDialog(isPrivacy: false),
                            onOpenPrivacy: () => _showPolicyDialog(isPrivacy: true),
                          ),

                          // â”€â”€ Verification notice â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  size: 16, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'A verification link will be sent to your institutional email.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12, fontStyle: FontStyle.italic,
                                    color: AppColors.textSecondaryLight),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // â”€â”€ Complete button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: loading ? null : () => _submit(ctx),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    const Color(0xFF2E7D32)
                                        .withValues(alpha: 0.45),
                                disabledForegroundColor:
                                    Colors.white.withValues(alpha: 0.75),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusMd),
                                ),
                              ),
                              child: loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      AppStrings.completeRegistration,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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

class _TermsCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;

  const _TermsCheckbox({
    required this.value,
    required this.onChanged,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: AppColors.textSecondaryLight),
                children: [
                  const TextSpan(text: 'I agree to the '),
                  TextSpan(
                    text: 'Terms of Service',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.primary,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = onOpenTerms,
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.primary,
                    ),
                    recognizer: TapGestureRecognizer()..onTap = onOpenPrivacy,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

