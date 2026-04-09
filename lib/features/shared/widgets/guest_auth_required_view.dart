import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';

class GuestAuthRequiredView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String fromRoute;

  const GuestAuthRequiredView({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.fromRoute,
  });

  @override
  Widget build(BuildContext context) {
    final encodedFrom = Uri.encodeComponent(fromRoute);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 62, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.push(
                    '${RouteNames.registerStep1}?from=$encodedFrom',
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Create Account'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.push('${RouteNames.login}?from=$encodedFrom'),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Sign In'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}