import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';

class FeaturePlaceholderScreen extends StatelessWidget {
  const FeaturePlaceholderScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.sections = const <String>[],
    this.primaryAction,
    this.primaryLabel,
  });

  final String title;
  final String subtitle;
  final List<String> sections;
  final VoidCallback? primaryAction;
  final String? primaryLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    height: 1.4,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...sections.map((section) => Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline_rounded, color: AppColors.primary),
                  title: Text(
                    section,
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Integrated into the screen flow and ready for data binding.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                ),
              )),
          if (primaryAction != null && primaryLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: primaryAction,
              icon: const Icon(Icons.rocket_launch_rounded),
              label: Text(primaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

