import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../shared/hci_components/st_form_widgets.dart';

class ProjectApplicationScreen extends StatefulWidget {
  const ProjectApplicationScreen({super.key});

  @override
  State<ProjectApplicationScreen> createState() => _ProjectApplicationScreenState();
}

class _ProjectApplicationScreenState extends State<ProjectApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _motivationCtrl = TextEditingController();
  final _attachmentsCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _motivationCtrl.dispose();
    _attachmentsCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Application draft captured. Integration step is next.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Project Application')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF0B1222), Color(0xFF111D36)]
                : const [Color(0xFFF8FBFF), Color(0xFFECF3FF)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -70,
              right: -70,
              child: _GlowBlob(size: 220, color: Color(0x332563EB)),
            ),
            const Positioned(
              bottom: -80,
              left: -90,
              child: _GlowBlob(size: 250, color: Color(0x221152D4)),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppDimensions.spacingLg),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : AppColors.primary.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Apply with confidence',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Share your details, motivation, and supporting files. Your draft can be reviewed before final submission.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              height: 1.5,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    StTextField(
                      label: 'Applicant Name',
                      hint: 'Your full name',
                      controller: _nameCtrl,
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Name is required.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    StTextField(
                      label: 'Contact Email',
                      hint: 'you@must.ac.ug',
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: const Icon(Icons.mail_outline_rounded),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return 'Email is required.';
                        if (!value.contains('@')) return 'Enter a valid email.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    StTextField(
                      label: 'Motivation Message',
                      hint: 'Why are you a great fit for this project?',
                      controller: _motivationCtrl,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      prefixIcon: const Icon(Icons.edit_note_rounded),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.length < 30) {
                          return 'Please write at least 30 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    StTextField(
                      label: 'Attachment Summary',
                      hint: 'CV.pdf, Portfolio.zip, DemoLink...',
                      controller: _attachmentsCtrl,
                      prefixIcon: const Icon(Icons.attach_file_rounded),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Add at least one attachment reference.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    StButton(
                      label: 'Submit Application Draft',
                      trailingIcon: Icons.send_rounded,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 12),
                    StOutlinedButton(
                      label: 'Clear Form',
                      leadingIcon: Icons.refresh_rounded,
                      onPressed: () {
                        _nameCtrl.clear();
                        _emailCtrl.clear();
                        _motivationCtrl.clear();
                        _attachmentsCtrl.clear();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

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
              spreadRadius: 24,
            ),
          ],
        ),
      ),
    );
  }
}
