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
            body: Form(
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
                          // Step dots (active = 3rd)
                          const _StepDots(currentStep: 3),
                          const SizedBox(height: 20),

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
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
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
                              icon: Icon(_obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
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
                          StButton(
                            label: AppStrings.completeRegistration,
                            isLoading: loading,
                            onPressed: () => _submit(ctx),
                          ),
                          const SizedBox(height: AppDimensions.spacingMd),

                          // â”€â”€ Or divider â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                          const OrDivider(),
                          const SizedBox(height: AppDimensions.spacingMd),

                          // â”€â”€ Google signup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                          GoogleSignInButton(
                            label: 'Sign up with Google',
                            isLoading: loading,
                            onPressed: () => ctx.read<AuthCubit>().signInWithGoogle(),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
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

class _StepDots extends StatelessWidget {
  final int currentStep;
  const _StepDots({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final isActive = i + 1 == currentStep;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            width: isActive ? 32 : 8, height: 8,
            decoration: BoxDecoration(
              color: (i + 1 <= currentStep)
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
            ),
          ),
        );
      }),
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _TermsCheckbox({required this.value, required this.onChanged});

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
                      color: AppColors.primary, fontWeight: FontWeight.w600),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () async {
                        // launch terms URL
                      },
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600),
                    recognizer: TapGestureRecognizer()..onTap = () {},
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

