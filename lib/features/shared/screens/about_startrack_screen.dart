import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';

class AboutStarTrackScreen extends StatelessWidget {
  const AboutStarTrackScreen({super.key});

  static const Color _mustGreen = Color(0xFF8CC63F);
  static const Color _mustBlue = Color(0xFF1A237E);
  static const Color _mustGold = Color(0xFFF4B400);
  static const Color _pageGray = Color(0xFFF2F2F2);

  static const List<String> _developers = [
    'Denis Junior',
    'Ainamaani Allan Mwesigye',
    'Mwunvaneeza Godfrey',
    'Murungi Kevin Tumaini',
    'Mbabazi Patience',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : _pageGray,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _mustGreen,
        foregroundColor: const Color(0xFF143A17),
        title: Text(
          'About MUST StarTrack',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset + 20),
          children: [
            _HeroBanner(isDark: isDark),
            const SizedBox(height: 12),
            const _SectionCard(
              title: 'Project Overview',
              icon: Icons.rocket_launch_rounded,
              content:
                  'MUST StarTrack is a skill-centric academic networking platform '
                  'built for Mbarara University of Science and Technology. '
                  'It helps students and lecturers showcase projects, discover '
                  'collaboration opportunities, and build meaningful academic '
                  'and professional connections.',
              accentColor: _mustGreen,
            ),
            const SizedBox(height: 12),
            const _SectionCard(
              title: 'Purpose and Relevance',
              icon: Icons.track_changes_rounded,
              content:
                  'The platform addresses a common campus challenge: talented '
                  'students often build strong work, but visibility and team '
                  'discovery remain limited. StarTrack creates a structured digital '
                  'space where projects, skills, and opportunities are easier to '
                  'find, which supports peer learning, innovation, and career '
                  'readiness within the university community.',
              accentColor: _mustBlue,
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Development Team',
              icon: Icons.groups_rounded,
              content:
                  'MUST StarTrack was developed as a third-year group mini project '
                  'by five Software Engineering students at Mbarara University of '
                  'Science and Technology (MUST).',
              accentColor: _mustGold,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _developers
                    .map(
                      (name) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.circle,
                                size: 8,
                                color: _mustGold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                name,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.content,
    required this.icon,
    required this.accentColor,
    this.child,
  });

  final String title;
  final String content;
  final IconData icon;
  final Color accentColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.30)),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: accentColor.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 3,
            width: 64,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              height: 1.45,
              color: AppColors.textSecondary(context),
            ),
          ),
          if (child != null) ...[
            const SizedBox(height: 8),
            child!,
          ],
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [
            AboutStarTrackScreen._mustGreen,
            AboutStarTrackScreen._mustBlue,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AboutStarTrackScreen._mustBlue.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AboutStarTrackScreen._mustGold,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'MUST Innovation Project',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3E2B00),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Built to spotlight skills, projects, and collaboration at MUST.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'MUST StarTrack connects learners and opportunities through a modern, skill-first campus platform.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.4,
              color: Colors.white.withValues(alpha: isDark ? 0.90 : 0.96),
            ),
          ),
        ],
      ),
    );
  }
}
