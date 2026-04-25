import 'package:flutter/material.dart';

import '../../feed/screens/global_student_ranks_screen.dart';

/// Reuses the global leaderboard UI/logic to avoid maintaining two
/// near-identical implementations.
class FacultyLeaderboardsScreen extends StatelessWidget {
  const FacultyLeaderboardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GlobalStudentRanksScreen(
      title: 'Leaderboard',
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
