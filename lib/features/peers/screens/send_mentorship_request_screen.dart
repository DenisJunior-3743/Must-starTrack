import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class SendMentorshipRequestScreen extends StatelessWidget {
  const SendMentorshipRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Send Mentorship Request',
      subtitle: 'Compose and send a mentorship request with goals and timeline.',
      sections: [
      'Goal summary',
      'Availability selection',
      'Submit request',
      ],
    );
  }
}
