import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Privacy Settings',
      subtitle: 'Control profile visibility and data-sharing preferences.',
      sections: [
      'Profile visibility',
      'Public fields',
      'Data permissions',
      ],
    );
  }
}
