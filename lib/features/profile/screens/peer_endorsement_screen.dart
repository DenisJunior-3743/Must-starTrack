import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class PeerEndorsementScreen extends StatelessWidget {
  const PeerEndorsementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Peer Endorsements',
      subtitle: 'Manage endorsements received from peers and lecturers.',
      sections: [
      'Recent endorsements',
      'Skill-level endorsement',
      'Visibility controls',
      ],
    );
  }
}
