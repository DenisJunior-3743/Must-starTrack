import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class SkillSearchResultsScreen extends StatelessWidget {
  const SkillSearchResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Skill Search Results',
      subtitle: 'Search results page for specific skills and competencies.',
      sections: [
      'Matched profiles',
      'Related projects',
      'Opportunity matches',
      ],
    );
  }
}
