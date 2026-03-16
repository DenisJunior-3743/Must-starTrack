import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class TaskCreationScreen extends StatelessWidget {
  const TaskCreationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'Task Creation',
      subtitle: 'Create and assign collaboration tasks with deadlines and priorities.',
      sections: [
      'Task details',
      'Assignee selection',
      'Due dates and status',
      ],
    );
  }
}
