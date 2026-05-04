import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

import '../../feed/screens/global_student_ranks_screen.dart';

/// Backward-compatible entry point that now reuses the shared leaderboard.
class LecturerRankingScreen extends StatelessWidget {
  const LecturerRankingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);

    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: AppColors.primary,
          secondary: AppColors.mustGreen,
          surface: AppColors.primary,
          onSurface: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.mustGreen,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      child: const GlobalStudentRanksScreen(
        title: 'Student Rankings',
        initialFaculty: 'Faculty of Computing and Informatic',
        searchHint: 'Search student',
        emptyStateText: 'No students found',
        monthTabLabel: 'This Month',
        semesterTabLabel: 'This Semester',
        allTimeTabLabel: 'All Time',
        showCurrentFacultyName: true,
      ),
    );
  }
}
