import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Notification Settings',
      subtitle: 'Fine-tune in-app and push notification preferences.',
      sections: [
      'Category toggles',
      'Quiet hours',
      'Delivery channels',
      ],
    );
  }
}
