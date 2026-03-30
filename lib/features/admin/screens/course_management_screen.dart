// lib/features/admin/screens/course_management_screen.dart
//
// MUST StarTrack — Course Management Screen
//
// Admin interface to create, edit, archive, and view courses within faculties.
// Part of the expanded admin dashboard.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/faculty_dao.dart';
import '../../../data/models/course_model.dart';
import '../../../data/models/faculty_model.dart';
import '../bloc/course_management_cubit.dart';

class CourseManagementScreen extends StatefulWidget {
  final bool embedded;

  const CourseManagementScreen({super.key, this.embedded = false});

  @override
  State<CourseManagementScreen> createState() => _CourseManagementScreenState();
}

class _CourseManagementScreenState extends State<CourseManagementScreen> {
  String? _selectedFacultyId;
  List<FacultyModel> _faculties = [];
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _loadFaculties();
  }

  Future<void> _loadFaculties() async {
    final facultyDao = sl<FacultyDao>();
    final faculties = await facultyDao.getAllFaculties(
      activeOnly: !_showArchived,
    );
    final keepSelection = faculties.any((faculty) => faculty.id == _selectedFacultyId);
    final nextSelectedFacultyId = keepSelection
        ? _selectedFacultyId
        : (faculties.isNotEmpty ? faculties.first.id : null);

    if (!mounted) {
      return;
    }

    setState(() {
      _faculties = faculties;
      _selectedFacultyId = nextSelectedFacultyId;
    });

    if (nextSelectedFacultyId != null) {
      await context.read<CourseManagementCubit>().loadCourses(
            facultyId: nextSelectedFacultyId,
            activeOnly: !_showArchived,
          );
    }
  }

  void _toggleArchivedView() {
    setState(() => _showArchived = !_showArchived);
    _loadFaculties();
  }

  void _showCourseDialog({CourseModel? existing}) {
    if (_selectedFacultyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a faculty first')),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
        title: Text(
          existing != null ? 'Edit Course' : 'Add Course',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField('Course Name', nameCtrl, isDark),
              const SizedBox(height: 12),
              _buildTextField('Code (e.g., CSC101)', codeCtrl, isDark),
              const SizedBox(height: 12),
              _buildTextField('Description', descCtrl, isDark, maxLines: 3),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final cubit = context.read<CourseManagementCubit>();
              if (existing != null) {
                cubit.updateCourse(
                  id: existing.id,
                  name: nameCtrl.text.trim(),
                  code: codeCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  activeOnly: !_showArchived,
                );
              } else {
                cubit.createCourse(
                  facultyId: _selectedFacultyId!,
                  name: nameCtrl.text.trim(),
                  code: codeCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  activeOnly: !_showArchived,
                );
              }
              Navigator.pop(ctx);
            },
            child: Text(existing != null ? 'Update' : 'Create'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    bool isDark, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: GoogleFonts.plusJakartaSans(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_faculties.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _showArchived
                      ? 'No faculties with archived courses yet'
                      : 'No faculties available yet',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AppColors.textHintLight,
                  ),
                ),
              ),
            )
          else ...[
          // Faculty selector
          Container(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Faculty',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedFacultyId,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedFacultyId = value);
                      context.read<CourseManagementCubit>().loadCourses(
                            facultyId: value,
                            activeOnly: !_showArchived,
                          );
                    }
                  },
                  items: _faculties
                      .map((f) => DropdownMenuItem(
                            value: f.id,
                            child: Text(f.name,
                                style: GoogleFonts.plusJakartaSans()),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          // Courses list
          Expanded(
            child: BlocBuilder<CourseManagementCubit, CourseManagementState>(
              builder: (context, state) {
                if (state is CourseManagementLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is CourseManagementError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          state.message,
                          style: GoogleFonts.plusJakartaSans(
                              color: AppColors.danger),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => context
                              .read<CourseManagementCubit>()
                              .loadCourses(
                                facultyId: _selectedFacultyId,
                                activeOnly: !_showArchived,
                              ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (state is CoursesLoaded) {
                  final visibleCourses = _showArchived
                      ? state.courses
                          .where((course) => !course.isActive)
                          .toList(growable: false)
                      : state.courses;

                  if (visibleCourses.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.book_outlined,
                            size: 48,
                            color: AppColors.textHintLight,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _showArchived
                                ? 'No archived courses for this faculty'
                                : 'No courses for this faculty',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: AppColors.textHintLight,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: visibleCourses
                        .map(
                          (course) => CourseCard(
                            course: course,
                            onEdit: () => _showCourseDialog(existing: course),
                            onArchive: () => course.isActive
                                ? _showArchiveDialog(course)
                                : _showUnarchiveDialog(course),
                          ),
                        )
                        .toList(growable: false),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ),
          ],
        ],
      );

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'Courses',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _toggleArchivedView,
                  icon: Icon(
                    _showArchived
                        ? Icons.visibility_outlined
                        : Icons.archive_outlined,
                    size: 16,
                  ),
                  label: Text(_showArchived ? 'Show Active' : 'Archived'),
                ),
                FilledButton.icon(
                  onPressed: () => _showCourseDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Course'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'Courses',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _toggleArchivedView,
            tooltip: _showArchived ? 'Show active courses' : 'Show archived courses',
            icon: Icon(
              _showArchived
                  ? Icons.visibility_outlined
                  : Icons.archive_outlined,
            ),
          ),
        ],
        elevation: 0,
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCourseDialog(),
        tooltip: 'Add Course',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showArchiveDialog(CourseModel course) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Course?'),
        content: Text(
          'Course will be removed from active listings but kept in records.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<CourseManagementCubit>().archiveCourse(
                    course.id,
                    activeOnly: !_showArchived,
                  );
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  void _showUnarchiveDialog(CourseModel course) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unarchive Course?'),
        content: Text(
          'Course will be moved back to active listings.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<CourseManagementCubit>().unarchiveCourse(
                    course.id,
                    activeOnly: !_showArchived,
                  );
              Navigator.pop(ctx);
            },
            child: const Text('Unarchive'),
          ),
        ],
      ),
    );
  }
}

// ── Course Card Widget ─────────────────────────────────────────────────────

class CourseCard extends StatelessWidget {
  final CourseModel course;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const CourseCard({
    required this.course,
    required this.onEdit,
    required this.onArchive,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final description = (course.description ?? '').trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? AppColors.surfaceDark : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        course.code,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.textHintLight,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!course.isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Archived',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            if (description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  description,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppColors.textHintLight,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                ),
                ElevatedButton.icon(
                  onPressed: onArchive,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: course.isActive
                        ? AppColors.warning
                        : AppColors.success,
                  ),
                  icon: Icon(
                    course.isActive ? Icons.archive : Icons.unarchive,
                    size: 16,
                  ),
                  label: Text(course.isActive ? 'Archive' : 'Unarchive'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
