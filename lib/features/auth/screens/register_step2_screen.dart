// lib/features/auth/screens/register_step2_screen.dart
//
// MUST StarTrack â€” Registration Step 2: University Information
//
// Collects: registration number, admission year, faculty, program,
//           year of study, student email.
// Cross-validates reg number against email prefix.
// The most important validation step â€” data matches official MUST records.
//
// HCI: inline reg-number format hint, cross-field validation on submit,
//      error banner if inconsistency detected.

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
import '../../../data/local/dao/faculty_dao.dart';
import '../../../data/local/dao/course_dao.dart';
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
  final _emailCtrl = TextEditingController();
  final _regNumberFormatter = const _RegNumberFormatter();
  String? _lastAutoEmail;

  String? _admissionYear;
  String? _faculty;
  String? _selectedProgramCode;
  int? _yearOfStudy;
  String? _crossValidationError;

  // DB-backed faculty/program data
  bool _loadingFaculties = true;
  Map<String, List<_ProgramOption>> _facultyPrograms = {};

  @override
  void initState() {
    super.initState();
    _loadFacultyData();
  }

  Future<void> _loadFacultyData() async {
    try {
      final faculties = await sl<FacultyDao>().getAllFaculties();
      final courseDao = sl<CourseDao>();
      final map = <String, List<_ProgramOption>>{};

      for (final faculty in faculties) {
        final courses = await courseDao.getCoursesByFaculty(faculty.id);
        map[faculty.name] = courses
            .map((c) => _ProgramOption(code: c.code, name: '${c.name} (${c.code})'))
            .toList();
      }

      if (mounted) {
        setState(() {
          _facultyPrograms = map;
          _loadingFaculties = false;
        });
      }
    } catch (_) {
      // Fallback to hardcoded data if DB is empty / unavailable
      if (mounted) {
        setState(() {
          _facultyPrograms = _fallbackFacultyPrograms;
          _loadingFaculties = false;
        });
      }
    }
  }

  /// Fallback used only when the DB has no seeded faculties yet.
  static const Map<String, List<_ProgramOption>> _fallbackFacultyPrograms = {
    'Faculty of Computing and Informatics': [
      _ProgramOption(code: 'BSE', name: 'Bachelor of Software Engineering (BSE)'),
      _ProgramOption(code: 'BCS', name: 'Bachelor of Computer Science (BCS)'),
      _ProgramOption(code: 'BIT', name: 'Bachelor of Information Technology (BIT)'),
    ],
    'Faculty of Applied Sciences and Technology': [
      _ProgramOption(code: 'CVE', name: 'Civil Engineering (CVE)'),
      _ProgramOption(code: 'EEE', name: 'Electrical and Electronics Engineering (EEE)'),
      _ProgramOption(code: 'BME', name: 'Biomedical Engineering (BME)'),
    ],
    'Faculty of Business and Management Sciences': [
      _ProgramOption(code: 'ECO', name: 'Bachelor of Science in Economics (ECO)'),
      _ProgramOption(code: 'BAE', name: 'Bachelor of Arts in Economics (BAE)'),
      _ProgramOption(code: 'BAF', name: 'Bachelor of Accounting and Finance (BAF)'),
    ],
  };

  List<String> get _faculties => _facultyPrograms.keys.toList(growable: false);
  List<_ProgramOption> get _programsForSelectedFaculty =>
      _faculty == null ? const [] : (_facultyPrograms[_faculty] ?? const []);
  _ProgramOption? get _selectedProgram {
    if (_selectedProgramCode == null) return null;
    for (final option in _programsForSelectedFaculty) {
      if (option.code == _selectedProgramCode) return option;
    }
    return null;
  }

  _ProgramSelection? _findProgramByCode(String code) {
    for (final entry in _facultyPrograms.entries) {
      for (final option in entry.value) {
        if (option.code == code) {
          return _ProgramSelection(
            faculty: entry.key,
            program: option,
          );
        }
      }
    }
    return null;
  }

  List<String> get _admissionYears => List.generate(
    6, (i) => (DateTime.now().year - i).toString(),
  );

  @override
  void dispose() {
    _regNumCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String get _normalizedRegNumber =>
      _RegNumberFormatter.extractValue(_regNumCtrl.text);

  void _validateCrossFields() {
    final regNumber = _normalizedRegNumber;
    final email = _emailCtrl.text.trim();
    final admissionYear = _admissionYear;
    final faculty = _faculty;
    final selectedProgramCode = _selectedProgramCode;

    setState(() {
      _crossValidationError = MustValidators.parseRegNumber(regNumber).fold(
        (err) => err,
        (parsedReg) {
          final emailError = MustValidators.validateStudentEmail(email);
          if (emailError != null) return emailError;

          if (admissionYear != null && parsedReg.year != admissionYear) {
            return 'Admission year must match your registration number year '
                '(${parsedReg.year}).';
          }

          if (selectedProgramCode != null &&
              parsedReg.programCode != selectedProgramCode) {
            return 'Program code in registration number '
                '(${parsedReg.programCode}) must match selected program '
                '($selectedProgramCode).';
          }

          if (faculty != null) {
            final allowedCodes =
                (_facultyPrograms[faculty] ?? const []).map((p) => p.code);
            if (!allowedCodes.contains(parsedReg.programCode)) {
              return 'Program code ${parsedReg.programCode} does not belong to '
                  'selected faculty $faculty.';
            }
          }

          final expectedEmail =
              '${parsedReg.expectedEmailPrefix.toLowerCase()}@std.must.ac.ug';
          if (email.toLowerCase() != expectedEmail) {
            return 'Institutional email must match registration number.\n'
              'Expected: $expectedEmail';
          }

          return null;
        },
      );
    });
  }

  void _autoFillFromRegNumber() {
    final parsed = MustValidators.parseRegNumber(_normalizedRegNumber);
    parsed.fold(
      (_) {},
      (reg) {
        final selection = _findProgramByCode(reg.programCode);
        final expectedEmail =
            '${reg.expectedEmailPrefix.toLowerCase()}@std.must.ac.ug';

        setState(() {
          _admissionYear = reg.year;
          if (selection != null) {
            _faculty = selection.faculty;
            _selectedProgramCode = selection.program.code;
          }
        });

        final canOverwriteEmail = _emailCtrl.text.trim().isEmpty ||
            _emailCtrl.text.trim().toLowerCase() ==
                (_lastAutoEmail ?? '').toLowerCase();
        if (canOverwriteEmail) {
          _emailCtrl.text = expectedEmail;
          _lastAutoEmail = expectedEmail;
        }
      },
    );
  }

  void _next(BuildContext context) {
    if (!_formKey.currentState!.validate()) return;
    _validateCrossFields();
    if (_crossValidationError != null) return;

    final selectedProgram = _selectedProgram;
    if (selectedProgram == null) return;

    final data = {
      ...widget.step1Data,
      'regNumber': _normalizedRegNumber,
      'admissionYear': _admissionYear,
      'faculty': _faculty,
      'programName': selectedProgram.name,
      'programCode': selectedProgram.code,
      'courseName': selectedProgram.name,
      'yearOfStudy': _yearOfStudy,
      'email': _emailCtrl.text.trim(),
    };

    context.read<AuthCubit>().advanceToStep3(data);
    context.pushNamed(RouteNames.registerStep3Name, extra: data);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: sl<AuthCubit>(),
      child: Builder(builder: (ctx) {
        return Scaffold(
          appBar: AppBar(
            title: const Text(AppStrings.step2Title),
            leading: BackButton(onPressed: () => ctx.pop()),
          ),
          body: _loadingFaculties
              ? const Center(child: CircularProgressIndicator())
              : Form(
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
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 24, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryLight, letterSpacing: -0.3,
                          )),
                        const SizedBox(height: 4),
                        Text('Match your official admission letter exactly.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: AppColors.textSecondaryLight)),
                        const SizedBox(height: 24),

                        // â”€â”€ Registration number â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        StTextField(
                          label: AppStrings.registrationNumber,
                          hint: '2023/BSE/164/PS',
                          controller: _regNumCtrl,
                          prefixIcon: const Icon(Icons.badge_outlined),
                          keyboardType: TextInputType.visiblePassword,
                          inputFormatters: [_regNumberFormatter],
                          helperText:
                              'Format: YYYY/FacultyCode/Number/PS or GS (auto-fills year/program)',
                          validator: (_) => MustValidators.validateRegNumber(_normalizedRegNumber),
                          onChanged: (_) {
                            _autoFillFromRegNumber();
                            if (_crossValidationError != null) _validateCrossFields();
                          },
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // â”€â”€ Admission year â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        StDropdown<String>(
                          label: AppStrings.admissionYear,
                          value: _admissionYear,
                          hint: 'Select Year',
                          items: _admissionYears.map((y) =>
                            DropdownMenuItem(value: y, child: Text(y))).toList(),
                          onChanged: (_) {},
                          enabled: false,
                          helperText: 'Auto-filled from your registration number.',
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // â”€â”€ Faculty â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        StDropdown<String>(
                          label: AppStrings.faculty,
                          value: _faculty,
                          hint: 'Select Faculty',
                          items: _faculties.map((f) =>
                            DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (_) {},
                          enabled: false,
                          helperText: 'Locked to the program encoded in your registration number.',
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // â”€â”€ Program â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        StDropdown<String>(
                          label: AppStrings.programName,
                          value: _selectedProgramCode,
                          hint: _faculty == null
                              ? 'Select faculty first'
                              : 'Select Program',
                          items: _programsForSelectedFaculty
                              .map((p) => DropdownMenuItem<String>(
                                    value: p.code,
                                    child: Text(
                                      p.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (_) {},
                          enabled: false,
                          helperText: 'Locked to the program encoded in your registration number.',
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),

                        // â”€â”€ Year of study â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

                        // â”€â”€ Institutional email â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        StTextField(
                          label: 'Institutional Email',
                          hint: 'username@std.must.ac.ug',
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: const Icon(Icons.verified_outlined, color: AppColors.primary),
                          enabled: false,
                          helperText: 'Auto-generated from the registration number and cannot be edited.',
                        ),

                        // â”€â”€ Cross-validation error â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        if (_crossValidationError != null) ...[
                          const SizedBox(height: 12),
                          InfoBanner.error(message: _crossValidationError!),
                        ],

                        // â”€â”€ Info note â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

class _ProgramOption {
  final String code;
  final String name;

  const _ProgramOption({required this.code, required this.name});
}

class _ProgramSelection {
  final String faculty;
  final _ProgramOption program;

  const _ProgramSelection({required this.faculty, required this.program});
}

class _RegNumberFormatter extends TextInputFormatter {
  const _RegNumberFormatter();

  static const List<int> _segmentLengths = [4, 3, 3, 2];
  static const String _mask = '----/---/---/--';

  static String extractValue(String value) =>
      value.replaceAll('-', '').trim();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = _sanitize(newValue.text);

    final formatted = _format(raw);
    final rawCursor =
        _countAcceptedCharsBeforeCursor(newValue.text, newValue.selection.baseOffset);
    final selectionOffset =
        _formattedOffsetForRawIndex(rawCursor.clamp(0, raw.length), formatted);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: selectionOffset),
      composing: TextRange.empty,
    );
  }

  String _sanitize(String value) {
    final cleaned = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final buffer = StringBuffer();
    var segmentIndex = 0;
    var segmentCharCount = 0;

    for (final char in cleaned.characters) {
      if (segmentIndex >= _segmentLengths.length) break;
      if (!_isAllowedForSegment(char, segmentIndex, segmentCharCount)) {
        continue;
      }

      buffer.write(char);
      segmentCharCount++;

      if (segmentCharCount == _segmentLengths[segmentIndex]) {
        segmentIndex++;
        segmentCharCount = 0;
      }
    }

    return buffer.toString();
  }

  bool _isAllowedForSegment(
    String char,
    int segmentIndex,
    int segmentCharCount,
  ) {
    final isDigit = RegExp(r'\d').hasMatch(char);
    final isLetter = RegExp(r'[A-Z]').hasMatch(char);
    return switch (segmentIndex) {
      0 || 2 => isDigit,
      1 => isLetter,
      3 => switch (segmentCharCount) {
          0 => char == 'P' || char == 'G',
          1 => char == 'S',
          _ => false,
        },
      _ => false,
    };
  }

  String _format(String raw) {
    final chars = _mask.split('');
    final rawChars = raw.characters.toList(growable: false);
    var rawIndex = 0;

    for (var i = 0; i < chars.length && rawIndex < rawChars.length; i++) {
      if (chars[i] == '-') {
        chars[i] = rawChars[rawIndex++];
      }
    }

    return chars.join();
  }

  int _countAcceptedCharsBeforeCursor(String value, int cursor) {
    if (cursor <= 0) return 0;
    final safeCursor = cursor.clamp(0, value.length);
    return _sanitize(value.substring(0, safeCursor)).length;
  }

  int _formattedOffsetForRawIndex(int rawIndex, String formatted) {
    if (rawIndex <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      final char = formatted[i];
      if (RegExp(r'[A-Z0-9]').hasMatch(char)) {
        seen++;
        if (seen == rawIndex) {
          return i + 1;
        }
      }
    }
    return formatted.contains('-') ? formatted.indexOf('-') : formatted.length;
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

