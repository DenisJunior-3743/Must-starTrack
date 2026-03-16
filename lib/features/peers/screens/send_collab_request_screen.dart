import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class SendCollabRequestScreen extends StatelessWidget {
  const SendCollabRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Send Collaboration Request',
      subtitle: 'Invite peers to collaborate on projects with clear expectations.',
      sections: [
      'Project context',
      'Role expectations',
      'Request message',
      ],
    );
  }
}
