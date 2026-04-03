// lib/features/auth/screens/forgot_password_screen.dart
//
// MUST StarTrack â€” Forgot Password Screen
//
// Manual reset fallback (SMTP unavailable):
// user enters username, new password, and confirmation.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/must_validators.dart';
import '../../../core/di/injection_container.dart';
import '../../shared/hci_components/st_form_widgets.dart';
import '../bloc/auth_cubit.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _applyAfterGoogle = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: sl<AuthCubit>(),
      child: BlocConsumer<AuthCubit, AuthState>(
        listener: (ctx, state) {
          if (state is AuthAuthenticated && _applyAfterGoogle) {
            _applyAfterGoogle = false;
            ctx.read<AuthCubit>().resetPasswordManually(
                  username: _usernameCtrl.text.trim(),
                  newPassword: _newPasswordCtrl.text,
                );
          } else if (state is AuthPasswordResetSuccess) {
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
              content: Text('Password updated successfully.'),
              backgroundColor: AppColors.success,
            ));
            ctx.pop();
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
              title: const Text(AppStrings.forgotPassword),
              leading: BackButton(onPressed: () => ctx.pop()),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.spacingMd),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),

                    // Icon
                    Center(
                      child: Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primaryTint10,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.lock_reset_rounded, size: 44, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(AppStrings.resetPassword,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                    const SizedBox(height: 8),
                    Text('Enter your username and set a new password. We will update local storage and sync remotely.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textSecondaryLight, height: 1.5)),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint10,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Important: Password update is applied after you continue with Google using the same account.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    StTextField(
                      label: 'Username',
                      hint: 'Display name or email',
                      controller: _usernameCtrl,
                      keyboardType: TextInputType.text,
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Username is required.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    StTextField(
                      label: AppStrings.password,
                      hint: 'Enter your new password',
                      controller: _newPasswordCtrl,
                      keyboardType: TextInputType.visiblePassword,
                      obscureText: _obscureNewPassword,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNewPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscureNewPassword = !_obscureNewPassword,
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: MustValidators.validatePassword,
                    ),
                    const SizedBox(height: 16),

                    StTextField(
                      label: AppStrings.confirmPassword,
                      hint: 'Confirm your new password',
                      controller: _confirmPasswordCtrl,
                      keyboardType: TextInputType.visiblePassword,
                      obscureText: _obscureConfirmPassword,
                      prefixIcon: const Icon(Icons.lock_reset_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscureConfirmPassword =
                              !_obscureConfirmPassword,
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      validator: (v) => MustValidators.validatePasswordMatch(
                        _newPasswordCtrl.text,
                        v,
                      ),
                      onFieldSubmitted: (_) {
                        if (_formKey.currentState!.validate()) {
                          ctx.read<AuthCubit>().resetPasswordManually(
                                username: _usernameCtrl.text.trim(),
                                newPassword: _newPasswordCtrl.text,
                              );
                        }
                      },
                    ),
                    const SizedBox(height: 24),

                    StButton(
                      label: 'Update Password',
                      isLoading: loading,
                      trailingIcon: Icons.check_circle_outline_rounded,
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          ctx.read<AuthCubit>().resetPasswordManually(
                                username: _usernameCtrl.text.trim(),
                                newPassword: _newPasswordCtrl.text,
                              );
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    GoogleSignInButton(
                      isLoading: loading,
                      onPressed: () {
                        if (!_formKey.currentState!.validate()) return;
                        _applyAfterGoogle = true;
                        ctx.read<AuthCubit>().signInWithGoogle();
                      },
                    ),
                    const SizedBox(height: 16),

                    Center(
                      child: TextButton(
                        onPressed: () => ctx.pop(),
                        child: Text('Back to Login',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

