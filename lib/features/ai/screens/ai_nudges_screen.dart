import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class AiNudgesScreen extends StatelessWidget {
  const AiNudgesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'AI Activity Nudges',
      subtitle: 'Gemini-powered engagement nudges for streaks, collaboration, and visibility.',
      sections: [
      'Streak nudges',
      'Collaboration nudges',
      'Badge nudges',
      ],
    );
  }
}
