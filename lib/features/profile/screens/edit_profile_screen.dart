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

  File? _newPhoto; // picked + cropped local file
  String? _existingPhotoUrl; // current Cloudinary URL from DB
  bool _saving = false;
  bool _dirty = false;
  bool _seeded = false; // true once fields are populated from cubit
  bool _avatarPressed = false; // drives zoom-on-press animation

  final _picker = ImagePicker();

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

    // Use displayName, fallback to email prefix if empty
    String displayName = user.displayName ?? '';
    if (displayName.isEmpty && user.email.isNotEmpty) {
      displayName = user.email.split('@').first;
    }
    _nameCtrl.text = displayName;

    // Bio can be null, use empty string
    _bioCtrl.text = profile?.bio ?? '';
    _existingPhotoUrl = user.photoUrl;

    final links = profile?.portfolioLinks ?? {};
    _githubCtrl.text = links['github'] ?? '';
    _linkedinCtrl.text = links['linkedin'] ?? '';

    // Handle missing or incomplete profile data gracefully
    if (profile != null) {
      // Faculty
      if (profile.faculty != null && profile.faculty!.isNotEmpty) {
        _faculty = profile.faculty!;
      }
      // Programme
      if (profile.programName != null && profile.programName!.isNotEmpty) {
        _programme = profile.programName!;
      }
      // Year of study
      if (profile.yearOfStudy != null) {
        _year = profile.yearOfStudy!;
      }
      _skills = List<String>.from(profile.skills);
      _visibility = profile.profileVisibility;
        }
  }

  void _markDirty() => setState(() => _dirty = true);

  // ── Photo pick + crop ─────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    debugPrint('📸 [EditProfile] Avatar tapped — opening photo picker');
    try {
      final choice = await showModalBottomSheet<ImageSource>(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (_) => _PhotoSourceSheet(),
      );
      if (choice == null || !mounted) {
        debugPrint('📸 [EditProfile] Photo picker cancelled — no source chosen');
        return;
      }
      debugPrint('📸 [EditProfile] Source chosen: $choice');

      final picked = await _picker.pickImage(
        source: choice,
        imageQuality: 90,
        maxWidth: 1024,
      );
      if (picked == null || !mounted) {
        debugPrint('📸 [EditProfile] No image picked from source');
        return;
      }
      debugPrint('📸 [EditProfile] Image picked: ${picked.path}');

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
        debugPrint('📸 [EditProfile] Crop done → ${cropped.path}');
        setState(() {
          _newPhoto = File(cropped.path);
          _dirty = true;
        });
      }
    } catch (e) {
      debugPrint('Error picking/cropping photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to select photo. Please try again.')),
        );
      }
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile saved!')));
      context.pop();
    } else if (newState is ProfileError) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(newState.message)));
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
                  const SizedBox(height: 28),
                  Center(
                    child: Column(
                      children: [
                        Semantics(
                          label: 'Change profile photo',
                          button: true,
                          child: AnimatedScale(
                            scale: _avatarPressed ? 1.08 : 1.0,
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOut,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.bottomRight,
                              children: [
                                // The whole circle is one Material button with ripple
                                Material(
                                  shape: const CircleBorder(),
                                  clipBehavior: Clip.antiAlias,
                                  color: Colors.transparent,
                                  child: Ink(
                                    width: 112,
                                    height: 112,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.primary,
                                        width: 2,
                                      ),
                                      image: _newPhoto != null
                                          ? DecorationImage(
                                              image: FileImage(_newPhoto!),
                                              fit: BoxFit.cover,
                                            )
                                          : _existingPhotoUrl != null
                                              ? DecorationImage(
                                                  image: CachedNetworkImageProvider(
                                                      _existingPhotoUrl!),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                      color: AppColors.primaryTint10,
                                    ),
                                    child: InkWell(
                                      onTap: _pickPhoto,
                                      onTapDown: (_) =>
                                          setState(() => _avatarPressed = true),
                                      onTapUp: (_) =>
                                          setState(() => _avatarPressed = false),
                                      onTapCancel: () =>
                                          setState(() => _avatarPressed = false),
                                      splashColor:
                                          AppColors.primary.withValues(alpha: 0.25),
                                      highlightColor:
                                          AppColors.primary.withValues(alpha: 0.1),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          // Placeholder icon when no photo
                                          if (_newPhoto == null &&
                                              _existingPhotoUrl == null)
                                            const Icon(Icons.person_rounded,
                                                size: 52,
                                                color: AppColors.primary),
                                          // Always-visible bottom edit strip
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              height: 36,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.black.withValues(alpha: 0.62),
                                                  ],
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: const Text(
                                                'EDIT',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Edit pencil badge — bottom-right
                                Positioned(
                                  bottom: 2,
                                  right: 2,
                                  child: IgnorePointer(
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.18),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(Icons.edit_rounded,
                                          size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Tap photo to change',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textSecondaryLight,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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
                              ? 'Name is required.'
                              : null,
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
                        StTextField(
                          label: 'Faculty',
                          initialValue: _faculty,
                          enabled: false,
                          helperText: 'University information cannot be changed.',
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),
                        StTextField(
                          label: 'Programme',
                          initialValue: _programme,
                          enabled: false,
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),
                        StTextField(
                          label: 'Year of Study',
                          initialValue: 'Year $_year',
                          enabled: false,
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
                        _skills = s;
                        _dirty = true;
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
                          icon: Icons.public_rounded,
                          label: 'Public',
                          desc: 'Anyone can view your profile',
                          value: 'public',
                          groupValue: _visibility,
                          onChanged: (v) => setState(() {
                            _visibility = v!;
                            _dirty = true;
                          }),
                        ),
                        _VisibilityOption(
                          icon: Icons.group_rounded,
                          label: 'Followers Only',
                          desc: 'Only your followers can view',
                          value: 'followers',
                          groupValue: _visibility,
                          onChanged: (v) => setState(() {
                            _visibility = v!;
                            _dirty = true;
                          }),
                        ),
                        _VisibilityOption(
                          icon: Icons.lock_outline_rounded,
                          label: 'Private',
                          desc: 'Only you can view',
                          value: 'private',
                          groupValue: _visibility,
                          onChanged: (v) => setState(() {
                            _visibility = v!;
                            _dirty = true;
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
                border: const Border(
                    top: BorderSide(color: AppColors.borderLight))),
            child: SafeArea(
              top: false,
              child: StButton(
                label: 'Save Changes',
                isLoading: _saving || state is ProfileUpdating,
                onPressed: (_dirty && !_saving && state is! ProfileUpdating)
                    ? _save
                    : null,
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
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryLight,
                  letterSpacing: 0.1)),
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
    required this.icon,
    required this.label,
    required this.desc,
    required this.value,
    required this.groupValue,
    required this.onChanged,
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
                color:
                    active ? AppColors.primary : AppColors.textSecondaryLight),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(desc,
                      style: GoogleFonts.plusJakartaSans(
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
              width: 40,
              height: 4,
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