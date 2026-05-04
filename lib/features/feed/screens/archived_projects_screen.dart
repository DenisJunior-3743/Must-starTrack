import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../shared/hci_components/st_form_widgets.dart';

class ArchivedProjectsScreen extends StatefulWidget {
  const ArchivedProjectsScreen({super.key});

  @override
  State<ArchivedProjectsScreen> createState() => _ArchivedProjectsScreenState();
}

class _ArchivedProjectsScreenState extends State<ArchivedProjectsScreen> {
  final List<_ArchivedProjectView> _projects = [
    _ArchivedProjectView(
      id: 'p-001',
      title: 'Campus Energy Optimization',
      archivedAt: DateTime.now().subtract(const Duration(days: 3)),
      reason: 'Replaced by v2 project strategy.',
    ),
    _ArchivedProjectView(
      id: 'p-002',
      title: 'Student Skills Exchange',
      archivedAt: DateTime.now().subtract(const Duration(days: 11)),
      reason: 'Merged into department collaboration stream.',
    ),
    _ArchivedProjectView(
      id: 'p-003',
      title: 'MUST Transport Insights',
      archivedAt: DateTime.now().subtract(const Duration(days: 24)),
      reason: 'Paused due to missing telemetry data.',
    ),
  ];

  void _restore(_ArchivedProjectView project) {
    setState(() => _projects.removeWhere((p) => p.id == project.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Restored "${project.title}"'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Archived Projects')),
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
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
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
                        'Archive Control',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Review archived posts, inspect archive rationale, and restore when a project becomes relevant again.',
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
                const SizedBox(height: 16),
                if (_projects.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.9),
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusLg),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : AppColors.borderLight,
                      ),
                    ),
                    child: Text(
                      'No archived projects right now.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  )
                else
                  ..._projects.map((project) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ArchiveCard(
                          project: project,
                          onRestore: () => _restore(project),
                        ),
                      )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({required this.project, required this.onRestore});

  final _ArchivedProjectView project;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  project.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Archived',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Reason: ${project.reason}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Archived ${project.ageLabel}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 12),
          StOutlinedButton(
            label: 'Restore Project',
            leadingIcon: Icons.settings_backup_restore_rounded,
            buttonHeight: 44,
            onPressed: onRestore,
          ),
        ],
      ),
    );
  }
}

class _ArchivedProjectView {
  const _ArchivedProjectView({
    required this.id,
    required this.title,
    required this.archivedAt,
    required this.reason,
  });

  final String id;
  final String title;
  final DateTime archivedAt;
  final String reason;

  String get ageLabel {
    final age = DateTime.now().difference(archivedAt).inDays;
    if (age <= 0) return 'today';
    if (age == 1) return '1 day ago';
    return '$age days ago';
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
