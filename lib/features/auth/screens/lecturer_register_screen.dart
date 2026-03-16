// lib/features/auth/screens/lecturer_register_screen.dart
//
// MUST StarTrack — Lecturer / Staff Registration Screen
//
// Single-step form for staff accounts.
// Validates @must.ac.ug email domain strictly.
// HCI: clear role context, same field components as student registration.

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

class LecturerRegisterScreen extends StatefulWidget {
  const LecturerRegisterScreen({super.key});

  @override
  State<LecturerRegisterScreen> createState() => _LecturerRegisterScreenState();
}

class _LecturerRegisterScreenState extends State<LecturerRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscurePassword = true;
  String? _faculty;
  String? _department;

  static const _faculties = [
    'Computing and Informatics',
    'Applied Sciences and Technology',
    'Medicine',
    'Business Sciences',
  ];

  static const _departments = {
    'Computing and Informatics': ['Computer Science', 'Information Technology', 'Software Engineering'],
    'Applied Sciences and Technology': ['Civil Engineering', 'Electrical Engineering', 'Mechanical Engineering'],
    'Medicine': ['Clinical Medicine', 'Nursing', 'Public Health'],
    'Business Sciences': ['Accounting', 'Management', 'Marketing'],
  };

  List<String> get _currentDepts =>
      _faculty != null ? (_departments[_faculty] ?? []) : [];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit(BuildContext ctx) {
    if (!_formKey.currentState!.validate()) return;
    ctx.read<AuthCubit>().registerLecturer(
      formData: {
        'displayName': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'faculty': _faculty,
        'department': _department,
        'password': _passwordCtrl.text,
        'role': 'lecturer',
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
      GoRouterState.of(context).uri.queryParameters['from'],
    );

    return BlocProvider(
      create: (_) => AuthCubit(authRepository: sl(), guards: sl()),
      child: BlocConsumer<AuthCubit, AuthState>(
        listener: (ctx, state) {
          if (state is AuthEmailVerificationSent) {
            ctx.go(RouteNames.passwordResetSent);
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
              title: const Text('Staff Registration'),
              leading: BackButton(onPressed: () => ctx.pop()),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.spacingMd),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // Branding header
                    Text('Join MUST StarTrack',
                      style: GoogleFonts.lexend(
                        fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                    const SizedBox(height: 8),
                    Text('Create your lecturer or staff account to manage academic tracks and student progress.',
                      style: GoogleFonts.lexend(
                        fontSize: 14, color: AppColors.textSecondaryLight, height: 1.5)),
                    const SizedBox(height: 32),

                    // Full Name
                    StTextField(
                      label: AppStrings.fullName,
                      hint: 'e.g. Dr. John Doe',
                      controller: _nameCtrl,
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      textInputAction: TextInputAction.next,
                      validator: (v) => MustValidators.validateRequired(v, 'Full Name'),
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),

                    // Staff email
                    StTextField(
                      label: 'Staff Email',
                      hint: 'username@must.ac.ug',
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: const Icon(Icons.mail_outline_rounded),
                      helperText: 'Must be a valid @must.ac.ug domain email address.',
                      textInputAction: TextInputAction.next,
                      validator: MustValidators.validateStaffEmail,
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),

                    // Faculty dropdown
                    StDropdown<String>(
                      label: AppStrings.faculty,
                      value: _faculty,
                      hint: 'Select Faculty',
                      items: _faculties.map((f) =>
                        DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() { _faculty = v; _department = null; }),
                      validator: (v) => v == null ? 'Select your faculty.' : null,
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),

                    // Department dropdown (conditional)
                    if (_currentDepts.isNotEmpty) ...[
                      StDropdown<String>(
                        label: AppStrings.department,
                        value: _department,
                        hint: 'Select Department',
                        items: _currentDepts.map((d) =>
                          DropdownMenuItem(value: d, child: Text(d))).toList(),
                        onChanged: (v) => setState(() => _department = v),
                      ),
                      const SizedBox(height: AppDimensions.spacingMd),
                    ],

                    // Password
                    StTextField(
                      label: AppStrings.password,
                      hint: 'Create a strong password',
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      validator: MustValidators.validatePassword,
                    ),

                    // Strength bar
                    ValueListenableBuilder(
                      valueListenable: _passwordCtrl,
                      builder: (_, v, __) => PasswordStrengthBar(password: v.text),
                    ),
                    const SizedBox(height: 32),

                    // Submit
                    StButton(
                      label: 'Create Staff Account',
                      isLoading: loading,
                      trailingIcon: Icons.person_add_rounded,
                      onPressed: () => _submit(ctx),
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),

                    // Login link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(AppStrings.haveAccount,
                          style: GoogleFonts.lexend(
                            fontSize: 13, color: AppColors.textSecondaryLight)),
                        TextButton(
                          onPressed: () => ctx.go(RouteNames.login),
                          child: Text('Back to Login',
                            style: GoogleFonts.lexend(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                        ),
                      ],
                    ),

                    // Footer branding
                    const SizedBox(height: 24),
                    Center(
                      child: Opacity(
                        opacity: 0.4,
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 32, height: 32,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.star_rounded, color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 8),
                                Text(AppStrings.appFullName,
                                  style: GoogleFonts.lexend(fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(AppStrings.university,
                              style: GoogleFonts.lexend(fontSize: 11, color: AppColors.textSecondaryLight)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
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
