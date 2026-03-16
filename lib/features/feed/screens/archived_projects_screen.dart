import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class ArchivedProjectsScreen extends StatelessWidget {
  const ArchivedProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Archived Projects',
      subtitle: 'Browse archived projects with restore and audit options.',
      sections: [
      'Archived project list',
      'Restore action',
      'Archive metadata',
      ],
    );
  }
}
