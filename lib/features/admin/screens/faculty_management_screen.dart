// lib/features/admin/screens/faculty_management_screen.dart
//
// MUST StarTrack — Faculty Management Screen
//
// Admin interface to create, edit, archive, and view faculties.
// Part of the expanded admin dashboard.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/faculty_model.dart';
import '../bloc/faculty_management_cubit.dart';

class FacultyManagementScreen extends StatefulWidget {
  final bool embedded;

  const FacultyManagementScreen({super.key, this.embedded = false});

  @override
  State<FacultyManagementScreen> createState() => _FacultyManagementScreenState();
}

class _FacultyManagementScreenState extends State<FacultyManagementScreen> {
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _loadFaculties();
  }

  void _loadFaculties() {
    context.read<FacultyManagementCubit>().loadFaculties(
          activeOnly: !_showArchived,
        );
  }

  void _toggleArchivedView() {
    setState(() => _showArchived = !_showArchived);
    _loadFaculties();
  }

  void _showFacultyDialog({FacultyModel? existing}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final emailCtrl = TextEditingController(text: existing?.contactEmail ?? '');
    final headCtrl = TextEditingController(text: existing?.headOfFaculty ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
        title: Text(
          existing != null ? 'Edit Faculty' : 'Add Faculty',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField('Faculty Name', nameCtrl, isDark),
              const SizedBox(height: 12),
              _buildTextField('Code (e.g., CSI)', codeCtrl, isDark),
              const SizedBox(height: 12),
              _buildTextField('Description', descCtrl, isDark, maxLines: 3),
              const SizedBox(height: 12),
              _buildTextField('Contact Email', emailCtrl, isDark),
              const SizedBox(height: 12),
              _buildTextField('Head of Faculty', headCtrl, isDark),
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
              final cubit = context.read<FacultyManagementCubit>();
              if (existing != null) {
                cubit.updateFaculty(
                  id: existing.id,
                  name: nameCtrl.text.trim(),
                  code: codeCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  contactEmail: emailCtrl.text.trim().isEmpty
                      ? null
                      : emailCtrl.text.trim(),
                  headOfFaculty: headCtrl.text.trim().isEmpty
                      ? null
                      : headCtrl.text.trim(),
                  activeOnly: !_showArchived,
                );
              } else {
                cubit.createFaculty(
                  name: nameCtrl.text.trim(),
                  code: codeCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  contactEmail: emailCtrl.text.trim().isEmpty
                      ? null
                      : emailCtrl.text.trim(),
                  headOfFaculty: headCtrl.text.trim().isEmpty
                      ? null
                      : headCtrl.text.trim(),
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

    final body = BlocBuilder<FacultyManagementCubit, FacultyManagementState>(
        builder: (context, state) {
          if (state is FacultyManagementLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is FacultyManagementError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    state.message,
                    style: GoogleFonts.plusJakartaSans(color: AppColors.danger),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadFaculties,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (state is FacultiesLoaded) {
            final visibleFaculties = _showArchived
                ? state.faculties
                    .where((faculty) => !faculty.isActive)
                    .toList(growable: false)
                : state.faculties;

            if (visibleFaculties.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.school_outlined,
                      size: 48,
                      color: AppColors.textHintLight,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _showArchived
                          ? 'No archived faculties yet'
                          : 'No faculties yet',
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
              children: visibleFaculties
                  .map(
                    (faculty) => FacultyCard(
                      faculty: faculty,
                      onEdit: () => _showFacultyDialog(existing: faculty),
                      onArchive: () => faculty.isActive
                          ? _showArchiveDialog(faculty)
                          : _showUnarchiveDialog(faculty),
                    ),
                  )
                  .toList(growable: false),
            );
          }

          return const SizedBox.shrink();
        },
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
                  'Faculties',
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
                  onPressed: () => _showFacultyDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Faculty'),
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
          'Faculties',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _toggleArchivedView,
            tooltip: _showArchived ? 'Show active faculties' : 'Show archived faculties',
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
        onPressed: () => _showFacultyDialog(),
        tooltip: 'Add Faculty',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showArchiveDialog(FacultyModel faculty) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Faculty?'),
        content: Text(
          'Faculty will be removed from active listings but kept in records.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<FacultyManagementCubit>().archiveFaculty(
                    faculty.id,
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

  void _showUnarchiveDialog(FacultyModel faculty) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unarchive Faculty?'),
        content: Text(
          'Faculty will be moved back to active listings.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<FacultyManagementCubit>().unarchiveFaculty(
                    faculty.id,
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

// ── Faculty Card Widget ────────────────────────────────────────────────────

class FacultyCard extends StatelessWidget {
  final FacultyModel faculty;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const FacultyCard({
    required this.faculty,
    required this.onEdit,
    required this.onArchive,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final description = (faculty.description ?? '').trim();
    final contactEmail = (faculty.contactEmail ?? '').trim();

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
                        faculty.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        faculty.code,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.textHintLight,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!faculty.isActive)
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
            if (contactEmail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Contact: $contactEmail',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textHintLight,
                  ),
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
                    backgroundColor: faculty.isActive
                        ? AppColors.warning
                        : AppColors.success,
                  ),
                  icon: Icon(
                    faculty.isActive ? Icons.archive : Icons.unarchive,
                    size: 16,
                  ),
                  label: Text(faculty.isActive ? 'Archive' : 'Unarchive'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
