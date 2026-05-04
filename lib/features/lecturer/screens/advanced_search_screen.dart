// lib/features/lecturer/screens/advanced_search_screen.dart
//
// MUST StarTrack — Advanced Student Search (Lecturer)
//
// Multi-filter search: query text, faculty, course, specific skill.
// Results show student cards with profile links.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/course_dao.dart';
import '../../../data/local/dao/faculty_dao.dart';
import '../../../data/models/course_model.dart';
import '../../../data/models/faculty_model.dart';
import '../../../data/models/user_model.dart';
import '../../shared/widgets/settings_drawer.dart';
import '../bloc/lecturer_cubit.dart';

const _lecturerCardBlue = AppColors.primary;
const _lecturerButtonGreen = AppColors.mustGreen;

class AdvancedSearchScreen extends StatefulWidget {
  const AdvancedSearchScreen({super.key});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  final _queryCtrl = TextEditingController();
  final _facultyDao = sl<FacultyDao>();
  final _courseDao = sl<CourseDao>();

  String? _selectedFacultyId;
  String? _selectedCourseId;
  String? _selectedSkill;
  bool _hasSearched = false;

  List<FacultyModel> _faculties = const [];
  List<CourseModel> _courses = const [];

  @override
  void initState() {
    super.initState();
    _loadFaculties();
    _loadInitialStudents();
  }

  void _loadInitialStudents() {
    _hasSearched = true;
    context.read<LecturerCubit>().searchStudents(query: '');
  }

  Future<void> _loadFaculties() async {
    try {
      final faculties = await _facultyDao.getAllFaculties(activeOnly: true);
      if (!mounted) return;
      setState(() {
        _faculties = faculties;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load faculties: $e')),
      );
    }
  }

  Future<void> _loadCoursesForFaculty(String facultyId) async {
    try {
      final courses =
          await _courseDao.getCoursesByFaculty(facultyId, activeOnly: true);
      if (!mounted) return;
      setState(() {
        _courses = courses;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load courses: $e')),
      );
    }
  }

  FacultyModel? get _selectedFaculty {
    for (final faculty in _faculties) {
      if (faculty.id == _selectedFacultyId) {
        return faculty;
      }
    }
    return null;
  }

  CourseModel? get _selectedCourse {
    for (final course in _courses) {
      if (course.id == _selectedCourseId) {
        return course;
      }
    }
    return null;
  }

  void _doSearch() {
    final query = _queryCtrl.text.trim();
    setState(() => _hasSearched = true);

    context.read<LecturerCubit>().searchStudents(
          query: query,
          faculty: _selectedFaculty?.name,
          course: _selectedCourse?.name,
          skill: _selectedSkill,
        );
  }

  String _sortKeyForStudent(UserModel user) {
    final display = user.displayName?.trim() ?? '';
    if (display.isNotEmpty) return display.toLowerCase();
    return user.email.trim().toLowerCase();
  }

  List<UserModel> _sortedStudents(List<UserModel> results) {
    final sorted = List<UserModel>.from(results);
    sorted.sort((a, b) {
      final byName = _sortKeyForStudent(a).compareTo(_sortKeyForStudent(b));
      if (byName != 0) return byName;
      return a.email.toLowerCase().compareTo(b.email.toLowerCase());
    });
    return sorted;
  }

  String _buildResultMeta(List<UserModel> results) {
    final faculties = <String>{};
    final programs = <String>{};

    for (final user in results) {
      final faculty = user.profile?.faculty?.trim();
      if (faculty != null && faculty.isNotEmpty) {
        faculties.add(faculty);
      }

      final program = user.profile?.programName?.trim();
      if (program != null && program.isNotEmpty) {
        programs.add(program);
      }
    }

    return '${results.length} students • ${faculties.length} faculties • ${programs.length} programs';
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      endDrawer: const SettingsDrawer(),
      backgroundColor: isDark ? AppColors.backgroundDark : const Color(0xFFEAF0FF),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Search Students',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.2,
          ),
        ),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Settings',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: _lecturerCardBlue,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.24),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _queryCtrl,
                  onSubmitted: (_) => _doSearch(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by name or skill...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20, color: Colors.white),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.tune, size: 20, color: Colors.white),
                      onPressed: () => _showFilterSheet(context),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.16),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_selectedFaculty != null ||
                    _selectedCourse != null ||
                    _selectedSkill != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (_selectedFaculty != null)
                        InputChip(
                          backgroundColor: Colors.white.withValues(alpha: 0.18),
                          deleteIconColor: Colors.white,
                          label: Text(
                            _selectedFaculty!.name,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onDeleted: () {
                            setState(() {
                              _selectedFacultyId = null;
                              _selectedCourseId = null;
                              _courses = const [];
                            });
                            if (_hasSearched) _doSearch();
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      if (_selectedCourse != null)
                        InputChip(
                          backgroundColor: Colors.white.withValues(alpha: 0.18),
                          deleteIconColor: Colors.white,
                          label: Text(
                            _selectedCourse!.name,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onDeleted: () {
                            setState(() => _selectedCourseId = null);
                            if (_hasSearched) _doSearch();
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      if (_selectedSkill != null)
                        InputChip(
                          backgroundColor: Colors.white.withValues(alpha: 0.18),
                          deleteIconColor: Colors.white,
                          label: Text(
                            _selectedSkill!,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onDeleted: () {
                            setState(() => _selectedSkill = null);
                            if (_hasSearched) _doSearch();
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _doSearch,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Search'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _lecturerButtonGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusMd),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: BlocBuilder<LecturerCubit, LecturerState>(
              builder: (context, state) {
                if (state is LecturerLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is LecturerError) {
                  return Center(child: Text(state.message));
                }
                if (state is StudentSearchLoaded) {
                  final sortedResults = _sortedStudents(state.results);

                  if (state.results.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_search_outlined,
                            size: 56,
                            color: AppColors.textSecondaryLight
                                .withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No students found',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try adjusting your filters',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.textHintLight,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                        color: _lecturerCardBlue,
                        child: Text(
                          _buildResultMeta(sortedResults),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: sortedResults.length,
                          itemBuilder: (context, index) {
                            return _SearchResultCard(user: sortedResults[index]);
                          },
                        ),
                      ),
                    ],
                  );
                }

                if (!_hasSearched) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: 56,
                          color:
                              AppColors.textSecondaryLight.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Find talented students',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Search by name, skill, faculty, or course',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textHintLight,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final skillCtrl = TextEditingController(text: _selectedSkill ?? '');

    String? tempFacultyId = _selectedFacultyId;
    String? tempCourseId = _selectedCourseId;
    List<CourseModel> tempCourses = List<CourseModel>.from(_courses);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                20,
                16,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filters',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Faculty',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: tempFacultyId,
                    isExpanded: true,
                    hint: Text(
                      'All faculties',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          'All faculties',
                          style: GoogleFonts.plusJakartaSans(fontSize: 13),
                        ),
                      ),
                      ..._faculties.map(
                        (f) => DropdownMenuItem<String>(
                          value: f.id,
                          child: Text(
                            f.name,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) async {
                      setSheetState(() {
                        tempFacultyId = v;
                        tempCourseId = null;
                        tempCourses = const [];
                      });

                      if (v != null) {
                        final courses =
                            await _courseDao.getCoursesByFaculty(v, activeOnly: true);
                        setSheetState(() {
                          tempCourses = courses;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusMd),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Course',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: tempCourseId,
                    isExpanded: true,
                    hint: Text(
                      tempFacultyId == null
                          ? 'Select faculty first'
                          : 'All courses',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13),
                    ),
                    items: tempFacultyId == null
                        ? const []
                        : [
                            DropdownMenuItem<String>(
                              value: null,
                              child: Text(
                                'All courses',
                                style: GoogleFonts.plusJakartaSans(fontSize: 13),
                              ),
                            ),
                            ...tempCourses.map(
                              (c) => DropdownMenuItem<String>(
                                value: c.id,
                                child: Text(
                                  c.name,
                                  style:
                                      GoogleFonts.plusJakartaSans(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                    onChanged: tempFacultyId == null
                        ? null
                        : (v) {
                            setSheetState(() => tempCourseId = v);
                          },
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusMd),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Skill',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: skillCtrl,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. Flutter, Python, ML',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: AppColors.textHintLight,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusMd),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        setState(() {
                          _selectedFacultyId = tempFacultyId;
                          _selectedCourseId = tempCourseId;
                          _selectedSkill = skillCtrl.text.trim().isNotEmpty
                              ? skillCtrl.text.trim()
                              : null;
                          _courses = tempCourses;
                        });

                        if (_selectedFacultyId != null && _courses.isEmpty) {
                          await _loadCoursesForFaculty(_selectedFacultyId!);
                        }

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _doSearch();
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _lecturerButtonGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Apply Filters'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final UserModel user;

  const _SearchResultCard({required this.user});

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = user.profile;
    final skills = profile?.skills ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: _lecturerCardBlue,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: InkWell(
          onTap: () {
            context.push(
              RouteNames.profile.replaceFirst(':userId', user.id),
            );
          },
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              border: Border.all(
                color: AppColors.primaryDark,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primaryTint10,
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: user.photoUrl == null
                      ? Text(
                          user.firstName.isNotEmpty
                              ? user.firstName[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? user.email,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (profile?.faculty != null ||
                          profile?.programName != null)
                        Text(
                          profile?.programName ?? profile?.faculty ?? '',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (skills.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: skills
                              .take(4)
                              .map(
                                (s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    s,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (profile != null && profile.activityStreak > 0) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            size: 14,
                            color: Colors.orange.shade400,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${profile.activityStreak}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade100,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (profile != null && profile.totalPosts > 0) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.article_outlined,
                            size: 14,
                            color: AppColors.textHintLight,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${profile.totalPosts}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
