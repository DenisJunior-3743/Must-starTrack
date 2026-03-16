import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class SystemReportsScreen extends StatelessWidget {
  const SystemReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'System Reports',
      subtitle: 'Generate and export platform-level moderation and usage reports.',
      sections: [
      'Report templates',
      'Export actions',
      'Generated history',
      ],
    );
  }
}
