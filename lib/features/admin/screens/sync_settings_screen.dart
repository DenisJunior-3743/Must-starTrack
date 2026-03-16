import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class SyncSettingsScreen extends StatelessWidget {
  const SyncSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Sync Status Settings',
      subtitle: 'Control sync intervals, retries, and conflict policies.',
      sections: [
      'Sync controls',
      'Retry policy',
      'Queue diagnostics',
      ],
    );
  }
}
