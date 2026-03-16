import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class FacultyDiscoverScreen extends StatelessWidget {
  const FacultyDiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Discover by Faculty',
      subtitle: 'Explore opportunities and projects by faculty and department.',
      sections: [
      'Faculty chips',
      'Featured projects',
      'Top contributors',
      ],
    );
  }
}
