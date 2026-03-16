import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class LecturerRankingScreen extends StatelessWidget {
  const LecturerRankingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Lecturer Student Ranking',
      subtitle: 'Lecturer tools for ranking students by skills and project quality.',
      sections: [
      'Ranking controls',
      'Scoring dimensions',
      'Invite top candidates',
      ],
    );
  }
}
