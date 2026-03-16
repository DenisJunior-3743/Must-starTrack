import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class MentorDiscoveryScreen extends StatelessWidget {
  const MentorDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Mentor Discovery',
      subtitle: 'Discover mentors by faculty, expertise, and availability.',
      sections: [
      'Faculty filters',
      'Mentor cards',
      'Request mentorship CTA',
      ],
    );
  }
}
