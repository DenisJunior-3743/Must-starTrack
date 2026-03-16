import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class ShortlistedTalentScreen extends StatelessWidget {
  const ShortlistedTalentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Shortlisted Talent',
      subtitle: 'View and manage shortlisted students for opportunities.',
      sections: [
      'Shortlist table',
      'Comparison view',
      'Invite and message',
      ],
    );
  }
}
