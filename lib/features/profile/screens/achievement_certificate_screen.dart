import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class AchievementCertificateScreen extends StatelessWidget {
  const AchievementCertificateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Achievement Certificate',
      subtitle: 'Preview and verify generated achievement certificates.',
      sections: [
      'Certificate preview',
      'Verification details',
      'Share certificate',
      ],
    );
  }
}
