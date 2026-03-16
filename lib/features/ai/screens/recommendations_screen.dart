import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class RecommendationsScreen extends StatelessWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Recommended for You',
      subtitle: 'AI-ranked projects, collaborators, and opportunities tailored to your profile.',
      sections: [
      'Projects You Might Like',
      'Potential Collaborators',
      'Top Opportunities',
      ],
    );
  }
}
