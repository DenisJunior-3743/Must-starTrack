// lib/features/auth/screens/forgot_password_screen.dart
//
// MUST StarTrack â€” Forgot Password Screen
//
// Sends a password reset email to the provided MUST address.
// HCI: single focused action, clear email format hint, loading state.

import 'package:flutter/material.dart';
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

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthCubit(authRepository: sl(), guards: sl()),
      child: BlocConsumer<AuthCubit, AuthState>(
        listener: (ctx, state) {
          if (state is AuthEmailVerificationSent) {
            ctx.go(RouteNames.passwordResetSent);
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
                    Text('Enter your MUST email address and we\'ll send you a link to reset your password.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textSecondaryLight, height: 1.5)),
                    const SizedBox(height: 32),

                    StTextField(
                      label: 'Email Address',
                      hint: 'Your MUST email address',
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: const Icon(Icons.mail_outline_rounded),
                      textInputAction: TextInputAction.done,
                      validator: MustValidators.validateEmail,
                      onFieldSubmitted: (_) {
                        if (_formKey.currentState!.validate()) {
                          ctx.read<AuthCubit>().sendPasswordReset(_emailCtrl.text.trim());
                        }
                      },
                    ),
                    const SizedBox(height: 24),

                    StButton(
                      label: 'Send Reset Link',
                      isLoading: loading,
                      trailingIcon: Icons.send_rounded,
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          ctx.read<AuthCubit>().sendPasswordReset(_emailCtrl.text.trim());
                        }
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

