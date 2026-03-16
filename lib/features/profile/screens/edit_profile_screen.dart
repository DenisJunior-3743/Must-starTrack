// lib/features/profile/screens/edit_profile_screen.dart
//
// MUST StarTrack — Edit Profile Screen (Phase 4)
//
// Matches edit_user_profile.html:
//   • Photo picker with camera/gallery choice
//   • Display name, bio textarea
//   • Faculty / Programme / Year cascading dropdowns
//   • SkillChipInput for skills (reused from Phase 2)
//   • Portfolio links: GitHub + LinkedIn URL fields
//   • Profile visibility toggle
//   • Save changes button with loading state
//
// HCI:
//   • Feedback: dirty state detected → save button activates
//   • Affordance: camera icon overlay on avatar signals tappable
//   • Constraints: save disabled unless changes present

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../shared/hci_components/st_form_widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController(text: 'Student User');
  final _bioCtrl = TextEditingController(text: '');
  final _githubCtrl = TextEditingController();
  final _linkedinCtrl = TextEditingController();

  String _faculty = 'Computing and Informatics';
  String _programme = 'B.Sc. Computer Science';
  int _year = 2;
  List<String> _skills = ['Flutter', 'Python', 'UI/UX Design'];
  String _visibility = 'public';

  File? _newPhoto;
  bool _saving = false;
  bool _dirty = false;

  final _picker = ImagePicker();

  static const _faculties = [
    'Computing and Informatics',
    'Applied Sciences and Technology',
    'Medicine',
    'Business and Management Sciences',
    'Science',
  ];

  static const _programmes = [
    'B.Sc. Computer Science',
    'B.Sc. Software Engineering',
    'B.Sc. Information Technology',
    'B.Eng. Electrical Engineering',
    'B.Sc. Data Science',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _githubCtrl.dispose();
    _linkedinCtrl.dispose();
    super.dispose();
  }

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _pickPhoto() async {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => _PhotoSourceSheet(),
    );
    if (choice == null) return;

    final file = await _picker.pickImage(source: choice, imageQuality: 85);
    if (file != null) {
      setState(() { _newPhoto = File(file.path); _dirty = true; });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // Phase 5: upload photo to Firebase Storage then update Firestore + SQLite
    await Future.delayed(const Duration(seconds: 1)); // simulate network

    setState(() { _saving = false; _dirty = false; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved successfully!')));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _dirty ? _confirmDiscard() : context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        onChanged: _markDirty,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            children: [
              // ── Photo ──────────────────────────────────────────────────
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: AppColors.primaryTint10,
                        backgroundImage: _newPhoto != null
                            ? FileImage(_newPhoto!) : null,
                        child: _newPhoto == null
                            ? const Icon(Icons.person_rounded,
                                size: 52, color: AppColors.primary)
                            : null,
                      ),
                      Positioned(
                        bottom: 2, right: 2,
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2)),
                          child: const Icon(Icons.camera_alt_rounded,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(
                  onPressed: _pickPhoto,
                  child: Text('Change Photo',
                    style: GoogleFonts.lexend(
                      fontSize: 13, color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
                ),
              ),

              const SizedBox(height: 8),
              const _SectionHeader('Personal Info'),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    StTextField(
                      label: 'Display Name',
                      controller: _nameCtrl,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Name is required.' : null,
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    StTextField(
                      label: 'Bio',
                      hint: 'Tell the community about yourself...',
                      controller: _bioCtrl,
                      maxLines: 4,
                    ),
                  ],
                ),
              ),

              const _SectionHeader('Academic Info'),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    StDropdown<String>(
                      label: 'Faculty',
                      value: _faculty,
                      items: _faculties.map((f) =>
                          DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() { _faculty = v ?? _faculty; _dirty = true; }),
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    StDropdown<String>(
                      label: 'Programme',
                      value: _programme,
                      items: _programmes.map((p) =>
                          DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() { _programme = v ?? _programme; _dirty = true; }),
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    StDropdown<int>(
                      label: 'Year of Study',
                      value: _year,
                      items: List.generate(5, (i) => i + 1).map((y) =>
                          DropdownMenuItem(value: y, child: Text('Year $y'))).toList(),
                      onChanged: (v) => setState(() { _year = v ?? _year; _dirty = true; }),
                    ),
                  ],
                ),
              ),

              const _SectionHeader('Skills'),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SkillChipInput(
                  label: '',
                  initialSkills: _skills,
                  onChanged: (s) => setState(() { _skills = s; _dirty = true; }),
                ),
              ),

              const _SectionHeader('Portfolio Links'),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    StTextField(
                      label: 'GitHub URL',
                      hint: 'https://github.com/username',
                      controller: _githubCtrl,
                      textInputAction: TextInputAction.next,
                      prefixIcon: const Icon(Icons.code_rounded),
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    StTextField(
                      label: 'LinkedIn URL',
                      hint: 'https://linkedin.com/in/username',
                      controller: _linkedinCtrl,
                      prefixIcon: const Icon(Icons.link_rounded),
                    ),
                  ],
                ),
              ),

              const _SectionHeader('Privacy'),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _VisibilityOption(
                      icon: Icons.public_rounded,
                      label: 'Public',
                      desc: 'Anyone can view your profile',
                      value: 'public',
                      groupValue: _visibility,
                      onChanged: (v) => setState(() { _visibility = v!; _dirty = true; }),
                    ),
                    _VisibilityOption(
                      icon: Icons.group_rounded,
                      label: 'Followers Only',
                      desc: 'Only your followers can view',
                      value: 'followers',
                      groupValue: _visibility,
                      onChanged: (v) => setState(() { _visibility = v!; _dirty = true; }),
                    ),
                    _VisibilityOption(
                      icon: Icons.lock_outline_rounded,
                      label: 'Private',
                      desc: 'Only you can view',
                      value: 'private',
                      groupValue: _visibility,
                      onChanged: (v) => setState(() { _visibility = v!; _dirty = true; }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: const Border(top: BorderSide(color: AppColors.borderLight))),
        child: SafeArea(
          top: false,
          child: StButton(
            label: 'Save Changes',
            isLoading: _saving,
            onPressed: _dirty ? () => _save() : null,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your unsaved changes will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Editing')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard')),
        ],
      ),
    );
    if (confirmed == true && mounted) context.pop();
  }
}

// Helpers ─────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(title.toUpperCase(),
        style: GoogleFonts.lexend(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondaryLight, letterSpacing: 0.1)),
    ),
  );
}

class _VisibilityOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final String value;
  final String groupValue;
  final ValueChanged<String?> onChanged;

  const _VisibilityOption({
    required this.icon, required this.label, required this.desc,
    required this.value, required this.groupValue, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = groupValue == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.borderLight,
            width: active ? 1.5 : 0.8)),
        child: Row(
          children: [
            Icon(icon,
              color: active ? AppColors.primary : AppColors.textSecondaryLight),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.lexend(
                    fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(desc, style: GoogleFonts.lexend(
                    fontSize: 11, color: AppColors.textSecondaryLight)),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              // ignore: deprecated_member_use
              groupValue: groupValue,
              // ignore: deprecated_member_use
              onChanged: onChanged, activeColor: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _PhotoSourceSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}
