import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class ArchiveProjectConfirmationScreen extends StatelessWidget {
  const ArchiveProjectConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Archive Project Confirmation',
      subtitle: 'Confirm archival of a project and preserve recoverability.',
      sections: [
      'Project impact summary',
      'Confirm archival',
      'Restore policy',
      ],
    );
  }
}
