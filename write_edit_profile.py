content = r"""// lib/features/profile/screens/edit_profile_screen.dart
//
// MUST StarTrack — Edit Profile Screen (Phase 5 — Glow Redesign)
// Light: #F8FBFF -> #ECF3FF  |  Dark: #061845 -> #030D27
// PlusJakartaSans, pill buttons, frosted-glass form cards, glow blobs

import 'dart:async';
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
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/course_dao.dart';
import '../../../data/local/dao/faculty_dao.dart';
import '../../../data/models/course_model.dart';
import '../../../data/models/faculty_model.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../bloc/profile_cubit.dart';
import '../../shared/hci_components/st_form_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Glow blob helper
// ─────────────────────────────────────────────────────────────────────────────

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 80, spreadRadius: 24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class EditProfileScreen extends StatefulWidget {
  final String? targetUserId;

  const EditProfileScreen({super.key, this.targetUserId});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _githubCtrl = TextEditingController();
  final _linkedinCtrl = TextEditingController();

  String _faculty = 'Computing and Informatics';
  String _programme = 'B.Sc. Computer Science';
  int _year = 1;
  List<String> _skills = [];
  String _visibility = 'public';
  bool _isLecturerProfile = false;

  File? _newPhoto;
  String? _existingPhotoUrl;
  bool _saving = false;
  bool _dirty = false;
  bool _seeded = false;
  bool _avatarPressed = false;

  final _picker = ImagePicker();
  final _facultyDao = sl<FacultyDao>();
  final _courseDao = sl<CourseDao>();

  List<FacultyModel> _faculties = const [];
  List<CourseModel> _courses = const [];
  bool _loadingAcademicData = true;

  @override
  void initState() {
    super.initState();
    _loadAcademicData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _departmentCtrl.dispose();
    _githubCtrl.dispose();
    _linkedinCtrl.dispose();
    super.dispose();
  }

  bool get _isAdminEditor =>
      sl<AuthCubit>().isAdmin &&
      widget.targetUserId != null &&
      widget.targetUserId!.isNotEmpty;

  Future<void> _loadAcademicData() async {
    try {
      final faculties = await _facultyDao.getAllFaculties(activeOnly: true);
      if (!mounted) return;
      setState(() {
        _faculties = faculties;
        _loadingAcademicData = false;
      });
      await _loadCoursesForFacultyName(_faculty, preferredCourse: _programme);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAcademicData = false);
    }
  }

  Future<void> _loadCoursesForFacultyName(
    String facultyName, {
    String? preferredCourse,
  }) async {
    final faculty = _faculties.cast<FacultyModel?>().firstWhere(
          (item) => item?.name == facultyName,
          orElse: () => null,
        );
    if (faculty == null) {
      if (!mounted) return;
      setState(() => _courses = const []);
      return;
    }

    final courses = await _courseDao.getCoursesByFaculty(
      faculty.id,
      activeOnly: true,
    );
    if (!mounted) return;
    setState(() {
      _courses = courses;
      if (preferredCourse != null &&
          courses.any((course) => course.name == preferredCourse)) {
        _programme = preferredCourse;
      } else if (!courses.any((course) => course.name == _programme) &&
          courses.isNotEmpty) {
        _programme = courses.first.name;
      }
    });
  }

  void _seedFromState(ProfileLoaded loaded) {
    if (_seeded) return;
    _seeded = true;
    final user = loaded.user;
    final profile = user.profile;
    _isLecturerProfile = user.isLecturer;

    String displayName = user.displayName ?? '';
    if (displayName.isEmpty && user.email.isNotEmpty) {
      displayName = user.email.split('@').first;
    }
    _nameCtrl.text = displayName;
    _bioCtrl.text = profile?.bio ?? '';
    _departmentCtrl.text = profile?.department ?? '';
    _existingPhotoUrl = user.photoUrl;

    final links = profile?.portfolioLinks ?? {};
    _githubCtrl.text = links['github'] ?? '';
    _linkedinCtrl.text = links['linkedin'] ?? '';

    if (profile != null) {
      if (profile.faculty != null && profile.faculty!.isNotEmpty) {
        _faculty = profile.faculty!;
      }
      if (profile.programName != null && profile.programName!.isNotEmpty) {
        _programme = profile.programName!;
      }
      if (profile.yearOfStudy != null) {
        _year = profile.yearOfStudy!;
      }
      _skills = List<String>.from(profile.skills);
      _visibility = profile.profileVisibility;
    }

    unawaited(_loadCoursesForFacultyName(
      _faculty,
      preferredCourse: _programme,
    ));
  }

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _pickPhoto() async {
    debugPrint('[EditProfile] Avatar tapped - opening photo picker');
    try {
      final choice = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _PhotoSourceSheet(),
      );
      if (choice == null || !mounted) return;

      final picked = await _picker.pickImage(
        source: choice,
        imageQuality: 90,
        maxWidth: 1024,
      );
      if (picked == null || !mounted) return;

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
      programme: _isLecturerProfile ? null : _programme,
      department: _isLecturerProfile ? _departmentCtrl.text.trim() : null,
      yearOfStudy: _isLecturerProfile ? null : _year,
      skills: _skills,
      portfolioLinks: links,
      visibility: _visibility,
      photo: _newPhoto,
    );

    if (!mounted) return;
    setState(() => _saving = false);

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgTop = isDark ? const Color(0xFF061845) : const Color(0xFFF8FBFF);
    final bgBottom = isDark ? const Color(0xFF030D27) : const Color(0xFFECF3FF);
    final fgPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final pillBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.80);
    final pillBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE2E8F0);

    final gradient = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [bgTop, bgBottom],
      ),
    );

    return BlocConsumer<ProfileCubit, ProfileState>(
      listener: (context, state) {
        if (state is ProfileLoaded && !_seeded) {
          setState(() => _seedFromState(state));
        }
      },
      builder: (context, state) {
        if (state is ProfileLoading || state is ProfileInitial) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                Positioned.fill(child: DecoratedBox(decoration: gradient)),
                const Center(child: CircularProgressIndicator()),
              ],
            ),
          );
        }

        if (state is ProfileLoaded && !_seeded) {
          _seedFromState(state);
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: pillBg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(Icons.close_rounded, color: fgPrimary),
              onPressed: () => _dirty ? _confirmDiscard() : context.pop(),
            ),
            title: Text(
              _isAdminEditor
                  ? (_isLecturerProfile
                      ? 'Edit Lecturer Profile'
                      : 'Edit Student Profile')
                  : 'Edit Profile',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: fgPrimary),
            ),
            centerTitle: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: pillBorder),
            ),
          ),
          body: Stack(
            children: [
              Positioned.fill(child: DecoratedBox(decoration: gradient)),
              const Positioned(
                  top: -60,
                  right: -50,
                  child: _GlowBlob(color: Color(0x332563EB))),
              const Positioned(
                  bottom: 200,
                  left: -80,
                  child: _GlowBlob(color: Color(0x221152D4))),
              SafeArea(
                child: Form(
                  key: _formKey,
                  onChanged: _markDirty,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Avatar ────────────────────────────────────────
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
                                      // Glow ring
                                      Container(
                                        width: 116,
                                        height: 116,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.28),
                                              blurRadius: 24,
                                              spreadRadius: 4,
                                            ),
                                          ],
                                          border: Border.all(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.50),
                                            width: 2.5,
                                          ),
                                        ),
                                        child: Material(
                                          shape: const CircleBorder(),
                                          clipBehavior: Clip.antiAlias,
                                          color: AppColors.primaryTint10,
                                          child: Ink(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
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
                                            ),
                                            child: InkWell(
                                              onTap: _pickPhoto,
                                              onTapDown: (_) => setState(
                                                  () => _avatarPressed = true),
                                              onTapUp: (_) => setState(
                                                  () => _avatarPressed = false),
                                              onTapCancel: () => setState(
                                                  () => _avatarPressed = false),
                                              splashColor: AppColors.primary
                                                  .withValues(alpha: 0.25),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  if (_newPhoto == null &&
                                                      _existingPhotoUrl == null)
                                                    const Icon(
                                                        Icons.person_rounded,
                                                        size: 52,
                                                        color: AppColors.primary),
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
                                                            Colors.black
                                                                .withValues(
                                                                    alpha: 0.62),
                                                          ],
                                                        ),
                                                      ),
                                                      alignment: Alignment.center,
                                                      child: const Text(
                                                        'EDIT',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w800,
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
                                      ),
                                      // Edit badge
                                      Positioned(
                                        bottom: 2,
                                        right: 2,
                                        child: IgnorePointer(
                                          child: Container(
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF2563EB),
                                                  Color(0xFF1152D4)
                                                ],
                                              ),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color: isDark
                                                      ? const Color(0xFF061845)
                                                      : Colors.white,
                                                  width: 2),
                                            ),
                                            child: const Icon(Icons.camera_alt_rounded,
                                                size: 15, color: Colors.white),
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
                                  color: isDark
                                      ? Colors.white54
                                      : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Personal Info ─────────────────────────────────
                        const SizedBox(height: 8),
                        _SectionHeader(
                            'Personal Info', isDark: isDark, pillBg: pillBg,
                            pillBorder: pillBorder),
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

                        // ── Academic Info ─────────────────────────────────
                        _SectionHeader(
                            'Academic Info', isDark: isDark, pillBg: pillBg,
                            pillBorder: pillBorder),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              if (_isLecturerProfile || _isAdminEditor)
                                DropdownButtonFormField<String>(
                                  initialValue: _faculties.any(
                                          (f) => f.name == _faculty)
                                      ? _faculty
                                      : null,
                                  decoration: const InputDecoration(
                                    labelText: 'Faculty',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _faculties
                                      .map((f) => DropdownMenuItem<String>(
                                            value: f.name,
                                            child: Text(f.name),
                                          ))
                                      .toList(growable: false),
                                  onChanged: _loadingAcademicData
                                      ? null
                                      : (value) async {
                                          if (value == null ||
                                              value == _faculty) return;
                                          setState(() {
                                            _faculty = value;
                                            _dirty = true;
                                            if (!_isLecturerProfile) {
                                              _programme = '';
                                            }
                                          });
                                          if (!_isLecturerProfile) {
                                            await _loadCoursesForFacultyName(
                                                value);
                                          }
                                        },
                                )
                              else
                                StTextField(
                                  label: 'Faculty',
                                  initialValue: _faculty,
                                  enabled: false,
                                  helperText:
                                      'University information cannot be changed.',
                                ),
                              const SizedBox(height: AppDimensions.spacingMd),
                              if (_isLecturerProfile)
                                StTextField(
                                  label: 'Department',
                                  hint: 'e.g. Computer Science',
                                  controller: _departmentCtrl,
                                  onChanged: (_) =>
                                      setState(() => _dirty = true),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Department is required.';
                                    }
                                    return null;
                                  },
                                )
                              else ...[
                                if (_isAdminEditor)
                                  DropdownButtonFormField<String>(
                                    initialValue: _courses.any(
                                            (c) => c.name == _programme)
                                        ? _programme
                                        : null,
                                    decoration: const InputDecoration(
                                      labelText: 'Programme',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: _courses
                                        .map((c) => DropdownMenuItem<String>(
                                              value: c.name,
                                              child: Text(c.name),
                                            ))
                                        .toList(growable: false),
                                    onChanged: _loadingAcademicData ||
                                            _courses.isEmpty
                                        ? null
                                        : (value) {
                                            if (value == null) return;
                                            setState(() {
                                              _programme = value;
                                              _dirty = true;
                                            });
                                          },
                                  )
                                else
                                  StTextField(
                                    label: 'Programme',
                                    initialValue: _programme,
                                    enabled: false,
                                  ),
                                const SizedBox(height: AppDimensions.spacingMd),
                                if (_isAdminEditor)
                                  DropdownButtonFormField<int>(
                                    initialValue: _year,
                                    decoration: const InputDecoration(
                                      labelText: 'Year of Study',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: List.generate(
                                        7,
                                        (i) => DropdownMenuItem<int>(
                                              value: i + 1,
                                              child: Text('Year ' +
                                                  (i + 1).toString()),
                                            )),
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _year = value;
                                        _dirty = true;
                                      });
                                    },
                                  )
                                else
                                  StTextField(
                                    label: 'Year of Study',
                                    initialValue: 'Year ' + _year.toString(),
                                    enabled: false,
                                  ),
                              ],
                            ],
                          ),
                        ),

                        // ── Skills ────────────────────────────────────────
                        _SectionHeader(
                            'Skills', isDark: isDark, pillBg: pillBg,
                            pillBorder: pillBorder),
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

                        // ── Portfolio Links ───────────────────────────────
                        _SectionHeader(
                            'Portfolio Links', isDark: isDark, pillBg: pillBg,
                            pillBorder: pillBorder),
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

                        // ── Privacy ───────────────────────────────────────
                        _SectionHeader(
                            'Privacy', isDark: isDark, pillBg: pillBg,
                            pillBorder: pillBorder),
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
                                isDark: isDark,
                                pillBg: pillBg,
                                pillBorder: pillBorder,
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
                                isDark: isDark,
                                pillBg: pillBg,
                                pillBorder: pillBorder,
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
                                isDark: isDark,
                                pillBg: pillBg,
                                pillBorder: pillBorder,
                                onChanged: (v) => setState(() {
                                  _visibility = v!;
                                  _dirty = true;
                                }),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: pillBg,
              border: Border(top: BorderSide(color: pillBorder)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_dirty && !_saving && state is! ProfileUpdating)
                      ? _save
                      : null,
                  icon: (_saving || state is ProfileUpdating)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _saving || state is ProfileUpdating
                        ? 'Saving...'
                        : 'Save Changes',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusFull),
                    ),
                  ),
                ),
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
        title: Text('Discard changes?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('Your unsaved changes will be lost.',
            style: GoogleFonts.plusJakartaSans()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Keep Editing',
                  style: GoogleFonts.plusJakartaSans())),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Discard',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed == true && mounted) context.pop();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header with frosted pill
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  final Color pillBg;
  final Color pillBorder;

  const _SectionHeader(
    this.title, {
    required this.isDark,
    required this.pillBg,
    required this.pillBorder,
  });

  @override
  Widget build(BuildContext context) {
    final fgSecondary = isDark ? Colors.white60 : const Color(0xFF64748B);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2563EB), Color(0xFF1152D4)],
              ),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: fgSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: pillBorder,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Visibility option card
// ─────────────────────────────────────────────────────────────────────────────

class _VisibilityOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final String value;
  final String groupValue;
  final ValueChanged<String?> onChanged;
  final bool isDark;
  final Color pillBg;
  final Color pillBorder;

  const _VisibilityOption({
    required this.icon,
    required this.label,
    required this.desc,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.isDark,
    required this.pillBg,
    required this.pillBorder,
  });

  @override
  Widget build(BuildContext context) {
    final active = groupValue == value;
    final fgPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final fgSecondary = isDark ? Colors.white60 : const Color(0xFF64748B);

    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.08)
              : pillBg,
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          border: Border.all(
            color: active ? AppColors.primary : pillBorder,
            width: active ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFEFF4FF)),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 18,
                  color: active ? AppColors.primary : fgSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: active ? AppColors.primary : fgPrimary)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: fgSecondary)),
                ],
              ),
            ),
            Icon(
              active
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: active ? AppColors.primary : fgSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo source bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoSourceSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0C1E54) : Colors.white;
    final fgPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final divColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.20)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              Text('Choose Photo',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: fgPrimary)),
              const SizedBox(height: 16),
              Divider(height: 1, color: divColor),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: AppColors.primary, size: 20),
                ),
                title: Text('Take Photo',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: fgPrimary)),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              Divider(height: 1, color: divColor, indent: 16, endIndent: 16),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      color: AppColors.primary, size: 20),
                ),
                title: Text('Choose from Gallery',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: fgPrimary)),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
"""
with open('d:/start_track/must_startrack/lib/features/profile/screens/edit_profile_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('DONE', len(content))
