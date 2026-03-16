import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class MentorProfileScreen extends StatelessWidget {
  const MentorProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Mentor Profile',
      subtitle: 'Detailed mentor profile with expertise and mentorship slots.',
      sections: [
      'Mentor bio',
      'Skills and focus areas',
      'Request mentorship',
      ],
    );
  }
}
