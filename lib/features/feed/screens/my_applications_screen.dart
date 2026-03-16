import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class MyApplicationsScreen extends StatelessWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'My Applications',
      subtitle: 'Track statuses for internship, project, and opportunity applications.',
      sections: [
      'Application status timeline',
      'Pending reviews',
      'Outcomes',
      ],
    );
  }
}
