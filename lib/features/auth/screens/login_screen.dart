// lib/features/auth/screens/login_screen.dart
//
// MUST StarTrack Login Screen (Phase 2)
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
import '../../../core/router/route_guards.dart';
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
  final _emailTooltipKey = GlobalKey<TooltipState>();
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

  void _showEmailTooltip() {
    _emailTooltipKey.currentState?.ensureTooltipVisible();
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

    return BlocProvider.value(
      // Use the global singleton so sl<AuthCubit>().currentUser is set
      // everywhere (e.g. create_post_screen) after a successful login.
      value: sl<AuthCubit>(),
      child: BlocConsumer<AuthCubit, AuthState>(
        listener: (ctx, state) {
          if (state is AuthAuthenticated) {
            // Role-aware landing keeps privileged users in their dedicated consoles.
            final role = sl<RouteGuards>().currentRole;
            final dest = switch (role) {
              UserRole.lecturer => RouteNames.lecturerDashboard,
              UserRole.admin => RouteNames.adminDashboard,
              UserRole.superAdmin => RouteNames.superAdminDashboard,
              _ => requestedFrom ?? RouteNames.home,
            };
            ctx.go(dest);
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
                  SafeArea(
                    child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.screenHPadding,
                  24,
                  AppDimensions.screenHPadding,
                  32,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo + branding hero card
                      _Branding(),
                      const SizedBox(height: 32),

                      Text(
                        'Welcome back',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in to your account',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Email
                      Tooltip(
                        key: _emailTooltipKey,
                        triggerMode: TooltipTriggerMode.manual,
                        showDuration: const Duration(seconds: 4),
                        waitDuration: Duration.zero,
                        verticalOffset: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Colors.white,
                          height: 1.35,
                        ),
                        message:
                            'Use your MUST institutional email (student: @std.must.ac.ug, staff: @must.ac.ug).',
                        child: StTextField(
                          label: 'Email Address',
                          hint: 'Your MUST email address',
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          focusNode: _emailFocus,
                          textInputAction: TextInputAction.next,
                          prefixIcon: const Icon(Icons.mail_outline_rounded),
                          onTap: _showEmailTooltip,
                          onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                          validator: MustValidators.validateEmail,
                        ),
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
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
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
                              style: GoogleFonts.plusJakartaSans(
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
                      

                      // Register links
                      _RegisterLinks(),
                      const SizedBox(height: 32),
                    ],
                  ),
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

class _Branding extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 20),
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C3B93), Color(0xFF1152D4), Color(0xFF3B82F6)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.30),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 88,
              height: 88,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/icons/icon.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Column(
                children: [
                  Text(
                    'MUST StarTrack',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your skills, Your story, Your network.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.86),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
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

class _RegisterLinks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(AppStrings.noAccount,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textSecondaryLight)),
            TextButton(
              onPressed: () => context.push(RouteNames.registerStep1),
              style: TextButton.styleFrom(padding: const EdgeInsets.only(left: 4)),
              child: Text('Register as Student',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
          ],
        ),
        TextButton(
          onPressed: () => context.push(RouteNames.lecturerRegister),
          child: Text('Register as Staff',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            )),
        ),
      ],
    );
  }
}

