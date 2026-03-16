import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class FacultyLeaderboardsScreen extends StatelessWidget {
  const FacultyLeaderboardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Faculty Leaderboards',
      subtitle: 'Rank students and teams by impact, consistency, and outcomes.',
      sections: [
      'Top students',
      'Top teams',
      'Ranking criteria',
      ],
    );
  }
}
