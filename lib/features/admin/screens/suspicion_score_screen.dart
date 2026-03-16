import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class SuspicionScoreScreen extends StatelessWidget {
  const SuspicionScoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Suspicion Score Detail',
      subtitle: 'Admin moderation panel with score breakdown and AI reasoning.',
      sections: [
      'Overall suspicion score',
      'Category risk bars',
      'Approve / Delete / Ban actions',
      ],
    );
  }
}
