// lib/features/auth/screens/register_step2_screen.dart
//
// MUST StarTrack — Registration Step 2: University Information
//
// Collects: registration number, admission year, faculty, program,
//           course name, year of study, student email.
// Cross-validates reg number against email prefix.
// The most important validation step — data matches official MUST records.
//
// HCI: inline reg-number format hint, cross-field validation on submit,
//      error banner if inconsistency detected.

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

class RegisterStep2Screen extends StatefulWidget {
  final Map<String, dynamic> step1Data;
  const RegisterStep2Screen({
    super.key,
    this.step1Data = const {},
  });

  @override
  State<RegisterStep2Screen> createState() => _RegisterStep2ScreenState();
}

class _RegisterStep2ScreenState extends State<RegisterStep2Screen> {
  final _formKey = GlobalKey<FormState>();
  final _regNumCtrl = TextEditingController();
  final _programCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _admissionYear;
  String? _faculty;
  int? _yearOfStudy;
  String? _crossValidationError;

  static const _faculties = [
    'Computing and Informatics',
    'Applied Sciences and Technology',
    'Medicine',
    'Business and Management Sciences',
    'Science',
    'Interdisciplinary Studies',
  ];

  List<String> get _admissionYears => List.generate(
    6, (i) => (DateTime.now().year - i).toString(),
  );

  @override
  void dispose() {
    _regNumCtrl.dispose();
    _programCtrl.dispose();
    _courseCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _validateCrossFields() {
    setState(() {
      _crossValidationError = MustValidators.validateRegNumberEmailConsistency(
        regNumber: _regNumCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
      );
    });
  }

  void _next(BuildContext context) {
    _validateCrossFields();
    if (!_formKey.currentState!.validate()) return;
    if (_crossValidationError != null) return;

    final data = {
      ...widget.step1Data,
      'regNumber': _regNumCtrl.text.trim(),
      'admissionYear': _admissionYear,
      'faculty': _faculty,
      'programName': _programCtrl.text.trim(),
      'courseName': _courseCtrl.text.trim(),
      'yearOfStudy': _yearOfStudy,
      'email': _emailCtrl.text.trim(),
    };

    context.read<AuthCubit>().advanceToStep3(data);
    context.pushNamed(RouteNames.registerStep3Name, extra: data);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthCubit(authRepository: sl(), guards: sl()),
      child: Builder(builder: (ctx) {
        return Scaffold(
          appBar: AppBar(
            title: const Text(AppStrings.step2Title),
            leading: BackButton(onPressed: () => ctx.pop()),
          ),
          body: Form(
            key: _formKey,
            child: Column(
              children: [
                const ProgressStepper(currentStep: 2),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppDimensions.spacingMd),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('University Information',
                          style: GoogleFonts.lexend(
                            fontSize: 24, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryLight, letterSpacing: -0.3,
                          )),
                        const SizedBox(height: 4),
                        Text('Match your official admission letter exactly.',
                          style: GoogleFonts.lexend(
                            fontSize: 13, color: AppColors.textSecondaryLight)),
                        const SizedBox(height: 24),

                        // ── Registration number ────────────────────────────
                        StTextField(
                          label: AppStrings.registrationNumber,
                          hint: '2023/BCS/001/PS',
                          controller: _regNumCtrl,
                          prefixIcon: const Icon(Icons.badge_outlined),
                          helperText: 'Format: YYYY/FacultyCode/Number/PS or GS',
                          validator: MustValidators.validateRegNumber,
                          onChanged: (_) => _crossValidationError != null
                              ? _validateCrossFields()
                              : null,
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // ── Admission year ─────────────────────────────────
                        StDropdown<String>(
                          label: AppStrings.admissionYear,
                          value: _admissionYear,
                          hint: 'Select Year',
                          items: _admissionYears.map((y) =>
                            DropdownMenuItem(value: y, child: Text(y))).toList(),
                          onChanged: (v) => setState(() => _admissionYear = v),
                          validator: (v) => v == null ? 'Select admission year.' : null,
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // ── Faculty ────────────────────────────────────────
                        StDropdown<String>(
                          label: AppStrings.faculty,
                          value: _faculty,
                          hint: 'Select Faculty',
                          items: _faculties.map((f) =>
                            DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) => setState(() => _faculty = v),
                          validator: (v) => v == null ? 'Select your faculty.' : null,
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // ── Program & Course ───────────────────────────────
                        StTextField(
                          label: AppStrings.programName,
                          hint: 'e.g. Bachelor of Computer Science',
                          controller: _programCtrl,
                          textInputAction: TextInputAction.next,
                          validator: (v) => MustValidators.validateRequired(v, AppStrings.programName),
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        StTextField(
                          label: AppStrings.courseName,
                          hint: 'e.g. BCS',
                          controller: _courseCtrl,
                          textInputAction: TextInputAction.next,
                          validator: (v) => MustValidators.validateRequired(v, AppStrings.courseName),
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // ── Year of study ──────────────────────────────────
                        StDropdown<int>(
                          label: AppStrings.yearOfStudy,
                          value: _yearOfStudy,
                          hint: 'Select Year',
                          items: List.generate(5, (i) => DropdownMenuItem(
                            value: i + 1, child: Text('Year ${i + 1}'))).toList(),
                          onChanged: (v) => setState(() => _yearOfStudy = v),
                          validator: (v) => v == null ? 'Select your year of study.' : null,
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // ── Institutional email ────────────────────────────
                        StTextField(
                          label: 'Institutional Email',
                          hint: 'username@std.must.ac.ug',
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: const Icon(Icons.verified_outlined, color: AppColors.primary),
                          helperText: 'Use your official MUST student email ending in @std.must.ac.ug',
                          onChanged: (_) => _crossValidationError != null
                              ? _validateCrossFields()
                              : null,
                          validator: MustValidators.validateStudentEmail,
                        ),

                        // ── Cross-validation error ─────────────────────────
                        if (_crossValidationError != null) ...[
                          const SizedBox(height: 12),
                          InfoBanner.error(message: _crossValidationError!),
                        ],

                        // ── Info note ──────────────────────────────────────
                        const SizedBox(height: 16),
                        const InfoBanner.warning(
                          message: 'Ensure all university details match your official admission letter to avoid delays in profile verification.',
                        ),

                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          bottomNavigationBar: _StepFooter(
            showBack: true,
            onBack: () => ctx.pop(),
            onNext: () => _next(ctx),
          ),
        );
      }),
    );
  }
}

class _StepFooter extends StatelessWidget {
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _StepFooter({
    required this.showBack,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            if (showBack)
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  child: const Text('Back'),
                ),
              ),
            if (showBack) const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: onNext,
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
