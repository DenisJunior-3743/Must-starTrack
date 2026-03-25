// lib/features/profile/screens/edit_profile_screen.dart
//
// MUST StarTrack — Edit Profile Screen
//
// WhatsApp-style profile editing:
//   - Tappable avatar with camera overlay → image_picker → image_cropper (1:1)
//   - Cropped photo is uploaded to Cloudinary immediately on save
//   - All fields are pre-populated from SQLite (ProfileCubit / UserDao)
//   - Faculty / Programme / Year cascading dropdowns
//   - Skills chip input, GitHub + LinkedIn URLs
//   - Profile visibility toggle
//   - Save calls ProfileCubit.updateProfile() → writes SQLite + Firestore

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../bloc/profile_cubit.dart';
import '../../shared/hci_components/st_form_widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _githubCtrl = TextEditingController();
  final _linkedinCtrl = TextEditingController();

  String _faculty = 'Computing and Informatics';
  String _programme = 'B.Sc. Computer Science';
  int _year = 1;
  List<String> _skills = [];
  String _visibility = 'public';

  File? _newPhoto;           // picked + cropped local file
  String? _existingPhotoUrl; // current Cloudinary URL from DB
  bool _saving = false;
  bool _dirty = false;
  bool _seeded = false;      // true once fields are populated from cubit

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
    'B.Sc. Nursing',
    'MBChB Medicine and Surgery',
    'B.Sc. Business Administration',
    'Other',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _githubCtrl.dispose();
    _linkedinCtrl.dispose();
    super.dispose();
  }

  // Populate form fields once the cubit emits ProfileLoaded
  void _seedFromState(ProfileLoaded loaded) {
    if (_seeded) return;
    _seeded = true;
    final user = loaded.user;
    final profile = user.profile;

    _nameCtrl.text = user.displayName ?? '';
    _bioCtrl.text = profile?.bio ?? '';
    _existingPhotoUrl = user.photoUrl;

    final links = profile?.portfolioLinks ?? {};
    _githubCtrl.text = links['github'] ?? '';
    _linkedinCtrl.text = links['linkedin'] ?? '';

    if (profile != null) {
      if (_faculties.contains(profile.faculty)) {
        _faculty = profile.faculty!;
      }
      if (profile.programName != null &&
          _programmes.contains(profile.programName)) {
        _programme = profile.programName!;
      }
      if (profile.yearOfStudy != null) {
        _year = profile.yearOfStudy!.clamp(1, 5);
      }
      _skills = List<String>.from(profile.skills);
      _visibility = profile.profileVisibility;
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  // ── Photo pick + crop ─────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _PhotoSourceSheet(),
    );
    if (choice == null || !mounted) return;

    final picked = await _picker.pickImage(
      source: choice,
      imageQuality: 90,
      maxWidth: 1024,
    );
    if (picked == null || !mounted) return;

    // Crop to 1:1 square — WhatsApp style
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          toolbarColor: AppColors.primary,
          toolbarWidgetColor: Colors.white,
          statusBarColor: AppColors.primary,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped != null && mounted) {
      setState(() {
        _newPhoto = File(cropped.path);
        _dirty = true;
      });
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final links = <String, String>{};
    if (_githubCtrl.text.trim().isNotEmpty) {
      links['github'] = _githubCtrl.text.trim();
    }
    if (_linkedinCtrl.text.trim().isNotEmpty) {
      links['linkedin'] = _linkedinCtrl.text.trim();
    }

    final cubit = context.read<ProfileCubit>();
    await cubit.updateProfile(
      displayName: _nameCtrl.text.trim(),
      bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
      faculty: _faculty,
      programme: _programme,
      yearOfStudy: _year,
      skills: _skills,
      portfolioLinks: links,
      visibility: _visibility,
      photo: _newPhoto,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    // Navigate back on success; on error the cubit emits ProfileError
    final newState = cubit.state;
    if (newState is ProfileLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved!')));
      context.pop();
    } else if (newState is ProfileError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newState.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileCubit, ProfileState>(
      listener: (context, state) {
        if (state is ProfileLoaded && !_seeded) {
          setState(() => _seedFromState(state));
        }
      },
      builder: (context, state) {
        if (state is ProfileLoading || state is ProfileInitial) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Seed once on first loaded state
        if (state is ProfileLoaded && !_seeded) {
          _seedFromState(state);
        }

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
                  // ── Avatar ──────────────────────────────────────────────
                  const SizedBox(height: 24),
                  Center(
                    child: GestureDetector(
                      onTap: _pickPhoto,
                      child: Stack(
                        children: [
                          // Photo circle
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: AppColors.primaryTint10,
                            backgroundImage: _newPhoto != null
                                ? FileImage(_newPhoto!) as ImageProvider
                                : (_existingPhotoUrl != null
                                    ? CachedNetworkImageProvider(_existingPhotoUrl!)
                                    : null),
                            child: (_newPhoto == null && _existingPhotoUrl == null)
                                ? const Icon(Icons.person_rounded,
                                    size: 56, color: AppColors.primary)
                                : null,
                          ),
                          // Camera badge
                          Positioned(
                            bottom: 2, right: 2,
                            child: Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
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
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                    ),
                  ),

                  // ── Personal Info ───────────────────────────────────────
                  const SizedBox(height: 8),
                  const _SectionHeader('Personal Info'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        StTextField(
                          label: 'Display Name',
                          controller: _nameCtrl,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Name is required.' : null,
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

                  // ── Academic Info ───────────────────────────────────────
                  const _SectionHeader('Academic Info'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        StDropdown<String>(
                          label: 'Faculty',
                          value: _faculty,
                          items: _faculties.map((f) => DropdownMenuItem(
                            value: f,
                            child: Text(f, overflow: TextOverflow.ellipsis),
                          )).toList(),
                          onChanged: (v) => setState(() {
                            _faculty = v ?? _faculty;
                            _dirty = true;
                          }),
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),
                        StDropdown<String>(
                          label: 'Programme',
                          value: _programme,
                          items: _programmes.map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p, overflow: TextOverflow.ellipsis),
                          )).toList(),
                          onChanged: (v) => setState(() {
                            _programme = v ?? _programme;
                            _dirty = true;
                          }),
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),
                        StDropdown<int>(
                          label: 'Year of Study',
                          value: _year,
                          items: List.generate(5, (i) => i + 1).map((y) =>
                            DropdownMenuItem(
                              value: y, child: Text('Year $y'))).toList(),
                          onChanged: (v) => setState(() {
                            _year = v ?? _year;
                            _dirty = true;
                          }),
                        ),
                      ],
                    ),
                  ),

                  // ── Skills ──────────────────────────────────────────────
                  const _SectionHeader('Skills'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SkillChipInput(
                      label: '',
                      initialSkills: _skills,
                      onChanged: (s) => setState(() {
                        _skills = s; _dirty = true;
                      }),
                    ),
                  ),

                  // ── Portfolio Links ─────────────────────────────────────
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

                  // ── Privacy ─────────────────────────────────────────────
                  const _SectionHeader('Privacy'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _VisibilityOption(
                          icon: Icons.public_rounded, label: 'Public',
                          desc: 'Anyone can view your profile',
                          value: 'public', groupValue: _visibility,
                          onChanged: (v) => setState(() {
                            _visibility = v!; _dirty = true;
                          }),
                        ),
                        _VisibilityOption(
                          icon: Icons.group_rounded, label: 'Followers Only',
                          desc: 'Only your followers can view',
                          value: 'followers', groupValue: _visibility,
                          onChanged: (v) => setState(() {
                            _visibility = v!; _dirty = true;
                          }),
                        ),
                        _VisibilityOption(
                          icon: Icons.lock_outline_rounded, label: 'Private',
                          desc: 'Only you can view',
                          value: 'private', groupValue: _visibility,
                          onChanged: (v) => setState(() {
                            _visibility = v!; _dirty = true;
                          }),
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
                isLoading: _saving || state is ProfileUpdating,
                onPressed: (_dirty && !_saving && state is! ProfileUpdating)
                    ? _save : null,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your unsaved changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Editing')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard')),
        ],
      ),
    );
    if (confirmed == true && mounted) context.pop();
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(title.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
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
                  Text(label, style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(desc, style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: AppColors.textSecondaryLight)),
                ],
              ),
            ),
            Icon(
              active
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: active ? AppColors.primary : AppColors.textSecondaryLight,
            ),
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
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: AppColors.primary),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

