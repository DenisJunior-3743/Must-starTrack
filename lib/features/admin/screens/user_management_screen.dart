import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_screen.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderScreen(
      title: 'User Management',
      subtitle: 'Manage users, roles, restrictions, and account status.',
      sections: [
      'User directory',
      'Role assignment',
      'Account moderation',
      ],
    );
  }
}
