import 'package:flutter/material.dart';

import '../../feed/screens/global_student_ranks_screen.dart';

/// Backward-compatible entry point that now reuses the shared leaderboard.
class LecturerRankingScreen extends StatelessWidget {
  const LecturerRankingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GlobalStudentRanksScreen(
      title: 'Student Rankings',
      initialFaculty: 'Faculty of Computing and Informatic',
      searchHint: 'Search student',
      emptyStateText: 'No students found',
      monthTabLabel: 'This Month',
      semesterTabLabel: 'This Semester',
      allTimeTabLabel: 'All Time',
      showCurrentFacultyName: true,
    );
  }
}
