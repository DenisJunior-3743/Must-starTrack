import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class ProjectApplicationScreen extends StatelessWidget {
  const ProjectApplicationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Project Application',
      subtitle: 'Submit complete applications for project and opportunity posts.',
      sections: [
      'Applicant details',
      'Motivation message',
      'Attachment summary',
      ],
    );
  }
}
