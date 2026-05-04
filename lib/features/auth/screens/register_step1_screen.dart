// lib/features/auth/screens/register_step1_screen.dart
//
// MUST StarTrack ” Registration Step 1: Biographical Data
//
// Collects: full name, gender, phone, short bio, skills.
// Data is stored in memory and passed to Step 2 via GoRouter extra.
//
// HCI: progress stepper, live validation, skill chip input, footer sticky CTA.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static const _genders = ['Male', 'Female'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
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
    return BlocProvider.value(
      value: sl<AuthCubit>(),
      child: Builder(builder: (ctx) {
        return Scaffold(
          appBar: AppBar(
            title: const Text(AppStrings.onboardingTitle),
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
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 24, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryLight, letterSpacing: -0.3,
                          )),
                        const SizedBox(height: 4),
                        Text('Tell us about yourself',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, color: AppColors.textSecondaryLight)),
                        const SizedBox(height: 24),

                        // 
                        StTextField(
                          label: AppStrings.fullName,
                          hint: 'Enter your legal full name',
                          controller: _nameCtrl,
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          textInputAction: TextInputAction.next,
                          validator: (v) => MustValidators.validateRequired(v, AppStrings.fullName),
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // 
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
                                  autovalidateMode: AutovalidateMode.onUserInteraction,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return 'Phone number is required';
                                    if (!v.startsWith('07')) return 'Must start with 07';
                                    if (v.length < 10) return 'Must be exactly 10 digits';
                                    return null;
                                  },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // 
                        StTextField(
                          label: AppStrings.biography,
                          hint: 'Tell us about yourself, your interests and goals...',
                          controller: _bioCtrl,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        SkillChipInput(
                          initialSkills: _skills,
                          onChanged: (s) => setState(() => _skills = s),
                        ),

                        // Privacy note
                        const SizedBox(height: 16),
                        Text(
                          'All data is securely handled according to MUST StarTrack privacy guidelines.',
                          style: GoogleFonts.plusJakartaSans(
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
              ],
            ),
          ),

          bottomNavigationBar: _StickyFooter(
            onNext: () => _next(ctx),
            showBack: false,
          ),
        );
      }),
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
                  buttonHeight: 48,
                  onPressed: onBack,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : onNext,
                  iconAlignment: IconAlignment.end,
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    nextLabel,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF2E7D32).withValues(alpha: 0.45),
                    disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusMd),
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

