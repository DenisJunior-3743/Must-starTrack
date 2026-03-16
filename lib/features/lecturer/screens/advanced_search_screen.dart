import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class AdvancedSearchScreen extends StatelessWidget {
  const AdvancedSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Advanced Talent Search',
      subtitle: 'Recruiter-style student search across skill, faculty, and availability.',
      sections: [
      'Multi-filter search',
      'Result cards',
      'Shortlist actions',
      ],
    );
  }
}
