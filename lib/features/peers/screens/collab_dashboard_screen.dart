import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class CollabDashboardScreen extends StatelessWidget {
  const CollabDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Collaboration Dashboard',
      subtitle: 'Track tasks, milestones, and teammate activity for projects.',
      sections: [
      'Active collaborators',
      'Milestones',
      'Shared tasks',
      ],
    );
  }
}
