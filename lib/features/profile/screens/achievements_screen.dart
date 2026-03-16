import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Achievements',
      subtitle: 'View badges, streak rewards, and milestone progress.',
      sections: [
      'Badge collection',
      'Streak rewards',
      'XP progress',
      ],
    );
  }
}
