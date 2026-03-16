import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class PlatformSettingsScreen extends StatelessWidget {
  const PlatformSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Platform Settings',
      subtitle: 'Super-admin controls for global policy and feature flags.',
      sections: [
      'Global policies',
      'Feature toggles',
      'Security defaults',
      ],
    );
  }
}
