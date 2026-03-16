// lib/features/auth/screens/login_screen.dart
//
// MUST StarTrack — Login Screen (Phase 2)
//
// HCI: Affordance, Feedback, Constraints, Natural Mapping, Universal Design

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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit(BuildContext ctx) {
    if (!_formKey.currentState!.validate()) return;
    ctx.read<AuthCubit>().login(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
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
      GoRouterState.of(context).uri.queryParameters['from'],
    );

    return BlocProvider(
      create: (_) => AuthCubit(authRepository: sl(), guards: sl()),
      child: BlocConsumer<AuthCubit, AuthState>(
        listener: (ctx, state) {
          if (state is AuthAuthenticated) {
            ctx.go(requestedFrom ?? RouteNames.home);
          } else if (state is AuthError) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
            ));
          }
        },
        builder: (ctx, state) {
          final loading = state is AuthLoading;
          return Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.screenHPadding),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),

                      // Logo + branding
                      Center(child: _Branding()),
                      const SizedBox(height: 40),

                      // Email
                      StTextField(
                        label: 'Email Address',
                        hint: 'Your MUST email address',
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        focusNode: _emailFocus,
                        textInputAction: TextInputAction.next,
                        prefixIcon: const Icon(Icons.mail_outline_rounded),
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                        validator: MustValidators.validateEmail,
                      ),
                      const SizedBox(height: AppDimensions.spacingMd),

                      // Password
                      StTextField(
                        label: AppStrings.password,
                        hint: 'Enter your password',
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        focusNode: _passwordFocus,
                        textInputAction: TextInputAction.done,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        onFieldSubmitted: (_) => _submit(ctx),
                        validator: (v) => (v == null || v.isEmpty) ? 'Password is required.' : null,
                      ),

                      // Forgot password
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => ctx.push(RouteNames.forgotPassword),
                          child: Text(AppStrings.forgotPassword,
                              style: GoogleFonts.lexend(
                                fontSize: 13, fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              )),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Login button
                      StButton(
                        label: AppStrings.login,
                        isLoading: loading,
                        trailingIcon: Icons.arrow_forward_rounded,
                        onPressed: () => _submit(ctx),
                      ),
                      const SizedBox(height: AppDimensions.spacingMd),

                      const OrDivider(),
                      const SizedBox(height: AppDimensions.spacingMd),

                      // Google
                      GoogleSignInButton(
                        isLoading: loading,
                        onPressed: () => ctx.read<AuthCubit>().signInWithGoogle(),
                      ),
                      const SizedBox(height: 24),

                      // Info banner
                      const InfoBanner(
                        message: 'Use your MUST institutional email (@std.must.ac.ug or @must.ac.ug) to access your academic records.',
                      ),
                      const SizedBox(height: 32),

                      // Register links
                      _RegisterLinks(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Branding extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: AppColors.primaryTint10,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.rocket_launch_rounded, size: 40, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Text(AppStrings.appFullName,
          style: GoogleFonts.lexend(
            fontSize: 28, fontWeight: FontWeight.w700,
            color: AppColors.primary, letterSpacing: -0.4,
          )),
        const SizedBox(height: 4),
        Text(AppStrings.appTagline,
          style: GoogleFonts.lexend(fontSize: 13, color: AppColors.textSecondaryLight),
          textAlign: TextAlign.center),
      ],
    );
  }
}

class _RegisterLinks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(AppStrings.noAccount,
              style: GoogleFonts.lexend(fontSize: 13, color: AppColors.textSecondaryLight)),
            TextButton(
              onPressed: () => context.push(RouteNames.registerStep1),
              style: TextButton.styleFrom(padding: const EdgeInsets.only(left: 4)),
              child: Text('Register as Student',
                style: GoogleFonts.lexend(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
          ],
        ),
        TextButton(
          onPressed: () => context.push(RouteNames.lecturerRegister),
          child: Text('Staff / Lecturer Registration →',
            style: GoogleFonts.lexend(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryLight, decoration: TextDecoration.underline,
              decorationColor: AppColors.textSecondaryLight,
            )),
        ),
        TextButton(
          onPressed: () => context.go(RouteNames.guestDiscover),
          child: Text(AppStrings.exploreAsGuest,
            style: GoogleFonts.lexend(fontSize: 12, color: AppColors.textSecondaryLight)),
        ),
      ],
    );
  }
}
