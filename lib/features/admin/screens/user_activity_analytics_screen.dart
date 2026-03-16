import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class UserActivityAnalyticsScreen extends StatelessWidget {
  const UserActivityAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'User Activity Analytics',
      subtitle: 'Detailed analytics for engagement and productivity metrics.',
      sections: [
      'Engagement charts',
      'Usage trends',
      'Retention signals',
      ],
    );
  }
}
