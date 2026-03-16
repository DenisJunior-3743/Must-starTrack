import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class UniversityEventsScreen extends StatelessWidget {
  const UniversityEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'University Events & Workshops',
      subtitle: 'Find academic events, workshops, and networking sessions.',
      sections: [
      'Upcoming events',
      'Registration status',
      'Event details',
      ],
    );
  }
}
