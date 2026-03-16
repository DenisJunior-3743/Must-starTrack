import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class MentorshipRequestSentScreen extends StatelessWidget {
  const MentorshipRequestSentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Mentorship Request Sent',
      subtitle: 'Confirmation of mentorship request and expected response timeline.',
      sections: [
      'Request summary',
      'Expected response window',
      'Next steps',
      ],
    );
  }
}
