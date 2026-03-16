import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Digital Portfolio',
      subtitle: 'Structured student portfolio with projects, links, and competencies.',
      sections: [
      'Portfolio summary',
      'Project gallery',
      'External links',
      ],
    );
  }
}
