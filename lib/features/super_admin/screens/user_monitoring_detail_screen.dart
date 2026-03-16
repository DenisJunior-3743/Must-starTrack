import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class UserMonitoringDetailScreen extends StatelessWidget {
  const UserMonitoringDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'User Monitoring Detail',
      subtitle: 'Investigate user activity, anomalies, and moderation history.',
      sections: [
      'User timeline',
      'Risk indicators',
      'Admin actions',
      ],
    );
  }
}
