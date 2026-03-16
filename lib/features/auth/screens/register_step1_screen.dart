// lib/features/auth/screens/register_step1_screen.dart
//
// MUST StarTrack — Registration Step 1: Biographical Data
//
// Collects: full name, gender, phone, short bio, skills.
// Optional: profile photo.
// Data is stored in memory and passed to Step 2 via GoRouter extra.
//
// HCI: progress stepper, live validation, skill chip input,
//      photo affordance, footer sticky CTA.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/must_validators.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../shared/hci_components/st_form_widgets.dart';
import '../bloc/auth_cubit.dart';

class RegisterStep1Screen extends StatefulWidget {
  const RegisterStep1Screen({super.key});

  @override
  State<RegisterStep1Screen> createState() => _RegisterStep1ScreenState();
}

class _RegisterStep1ScreenState extends State<RegisterStep1Screen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  String? _selectedGender;
  List<String> _skills = [];
  File? _photoFile;
  final _picker = ImagePicker();

  static const _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800, maxHeight: 800, imageQuality: 80,
    );
    if (xFile != null) setState(() => _photoFile = File(xFile.path));
  }

  void _next(BuildContext context) {
    if (!_formKey.currentState!.validate()) return;
    final from = GoRouterState.of(context).uri.queryParameters['from'];
    final data = {
      'displayName': _nameCtrl.text.trim(),
      'gender': _selectedGender,
      'phone': _phoneCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
      'skills': _skills,
      'photoPath': _photoFile?.path,
      if (from != null && from.isNotEmpty) 'returnTo': from,
    };
    context.read<AuthCubit>().advanceToStep2(data);
    context.pushNamed(
      RouteNames.registerStep2Name,
      extra: data,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthCubit(authRepository: sl(), guards: sl()),
      child: Builder(builder: (ctx) {
        return Scaffold(
          appBar: AppBar(
            title: const Text(AppStrings.onboardingTitle),
            leading: BackButton(onPressed: () => ctx.pop()),
          ),
          body: Form(
            key: _formKey,
            child: Column(
              children: [
                // Sticky progress stepper
                const ProgressStepper(currentStep: 1),

                // Scrollable form
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppDimensions.spacingMd),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Step heading
                        Text('Your Profile',
                          style: GoogleFonts.lexend(
                            fontSize: 24, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryLight, letterSpacing: -0.3,
                          )),
                        const SizedBox(height: 4),
                        Text('Tell us about yourself',
                          style: GoogleFonts.lexend(
                            fontSize: 14, color: AppColors.textSecondaryLight)),
                        const SizedBox(height: 24),

                        // ── Photo picker ───────────────────────────────────
                        Center(child: _PhotoPicker(
                          photoFile: _photoFile,
                          onTap: _pickPhoto,
                        )),
                        const SizedBox(height: 24),

                        // ── Full Name ──────────────────────────────────────
                        StTextField(
                          label: AppStrings.fullName,
                          hint: 'Enter your legal full name',
                          controller: _nameCtrl,
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          textInputAction: TextInputAction.next,
                          validator: (v) => MustValidators.validateRequired(v, AppStrings.fullName),
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // ── Gender + Phone side-by-side ────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: StDropdown<String>(
                                label: AppStrings.gender,
                                value: _selectedGender,
                                hint: 'Select',
                                items: _genders.map((g) => DropdownMenuItem(
                                  value: g, child: Text(g),
                                )).toList(),
                                onChanged: (v) => setState(() => _selectedGender = v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: StTextField(
                                label: AppStrings.phone,
                                hint: '+256 7XX XXX XXX',
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                prefixIcon: const Icon(Icons.phone_outlined),
                                validator: MustValidators.validatePhone,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // ── Short Bio ──────────────────────────────────────
                        StTextField(
                          label: AppStrings.biography,
                          hint: 'Tell us about yourself, your interests and goals...',
                          controller: _bioCtrl,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // ── Skills tag input ───────────────────────────────
                        SkillChipInput(
                          initialSkills: _skills,
                          onChanged: (s) => setState(() => _skills = s),
                        ),

                        // Privacy note
                        const SizedBox(height: 16),
                        Text(
                          'All data is securely handled according to MUST StarTrack privacy guidelines.',
                          style: GoogleFonts.lexend(
                            fontSize: 11, color: AppColors.textSecondaryLight),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 100), // space for sticky footer
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Sticky footer CTA ──────────────────────────────────────────
          bottomNavigationBar: _StickyFooter(
            onNext: () => _next(ctx),
            showBack: false,
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo picker widget
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoPicker extends StatelessWidget {
  final File? photoFile;
  final VoidCallback onTap;

  const _PhotoPicker({required this.photoFile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 52,
            backgroundColor: AppColors.primaryTint10,
            backgroundImage: photoFile != null ? FileImage(photoFile!) : null,
            child: photoFile == null
                ? const Icon(Icons.person_outline_rounded, size: 48, color: AppColors.primary)
                : null,
          ),
          Positioned(
            bottom: 0, right: 0,
            child: Container(
              width: 32, height: 32,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky footer — reused across all 3 steps
// ─────────────────────────────────────────────────────────────────────────────

class _StickyFooter extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final bool showBack;
  final bool isLoading;
  final String nextLabel;

  const _StickyFooter({
    required this.onNext,
    // ignore: unused_element_parameter
    this.onBack,
    this.showBack = true,
    // ignore: unused_element_parameter
    this.isLoading = false,
    // ignore: unused_element_parameter
    this.nextLabel = 'Next Step',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: AppColors.primary.withValues(alpha: 0.10))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (showBack && onBack != null) ...[
              Expanded(
                child: StOutlinedButton(
                  label: AppStrings.previousStep,
                  leadingIcon: Icons.arrow_back_rounded,
                  onPressed: onBack,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: StButton(
                label: nextLabel,
                trailingIcon: Icons.arrow_forward_rounded,
                isLoading: isLoading,
                onPressed: onNext,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
