import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class FacultyDetailScreen extends StatelessWidget {
  const FacultyDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Faculty Detail',
      subtitle: 'Deep view of a faculty with analytics, events, and projects.',
      sections: [
      'Faculty overview',
      'Active initiatives',
      'Skill hotspots',
      ],
    );
  }
}
