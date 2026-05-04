// lib/features/lecturer/screens/opportunity_applicants_screen.dart
//
// MUST StarTrack â€” Opportunity Applicants
//
// Shows students who applied (joined) a specific opportunity post.
// Lecturer can view each student's skills, faculty, profile.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/recommender_service.dart';
import '../../shared/widgets/settings_drawer.dart';
import '../bloc/lecturer_cubit.dart';

const Color _lecturerCardBlue = AppColors.primary;
const Color _lecturerButtonGreen = AppColors.mustGreen;

class OpportunityApplicantsScreen extends StatefulWidget {
  final PostModel opportunity;

  const OpportunityApplicantsScreen({super.key, required this.opportunity});

  @override
  State<OpportunityApplicantsScreen> createState() =>
      _OpportunityApplicantsScreenState();
}

class _OpportunityApplicantsScreenState
    extends State<OpportunityApplicantsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<LecturerCubit>().loadApplicants(widget.opportunity);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      endDrawer: const SettingsDrawer(),
      backgroundColor: isDark ? AppColors.backgroundDark : const Color(0xFFEAF0FF),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Applicants',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: Colors.white,
              ),
            ),
            Text(
              widget.opportunity.title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Settings',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: BlocBuilder<LecturerCubit, LecturerState>(
        builder: (context, state) {
          if (state is LecturerLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is LecturerError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(state.message, textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }
          if (state is ApplicantsLoaded) {
            return _ApplicantsBody(
              opportunity: state.opportunity,
              applicants: state.applicants,
              recommendations: state.recommendations,
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ApplicantsBody extends StatelessWidget {
  final PostModel opportunity;
  final List<UserModel> applicants;
  final Map<String, RecommendedUser> recommendations;

  const _ApplicantsBody({
    required this.opportunity,
    required this.applicants,
    required this.recommendations,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // â”€â”€ Opportunity header card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _lecturerCardBlue,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              border: Border.all(color: AppColors.primaryDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        opportunity.title,
                        style: GoogleFonts.sora(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                if (opportunity.description != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    opportunity.description!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MetaChip(
                      icon: Icons.people_outline,
                      label:
                          '${applicants.length} applicant${applicants.length == 1 ? '' : 's'}',
                    ),
                    if (opportunity.maxParticipants != null &&
                        opportunity.maxParticipants! > 0) ...[
                      const SizedBox(width: 10),
                      _MetaChip(
                        icon: Icons.group,
                        label: 'Max ${opportunity.maxParticipants}',
                      ),
                    ],
                    if (opportunity.opportunityDeadline != null) ...[
                      const SizedBox(width: 10),
                      _MetaChip(
                        icon: Icons.schedule,
                        label: _formatDate(opportunity.opportunityDeadline!),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

        // â”€â”€ Applicants list â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if (applicants.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                children: [
                  Icon(Icons.person_search_rounded,
                      size: 56,
                      color:
                          AppColors.textSecondaryLight.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                    'No applicants yet',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Students who join this opportunity will appear here',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.textHintLight,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _lecturerCardBlue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Applicants',
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimaryLight,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),

        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final user = applicants[index];
              return _ApplicantCard(
                user: user,
                recommendation: recommendations[user.id],
              );
            },
            childCount: applicants.length,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day}/${d.month}/${d.year}';
  }
}

// â”€â”€ Applicant card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ApplicantCard extends StatelessWidget {
  final UserModel user;
  final RecommendedUser? recommendation;
  const _ApplicantCard({required this.user, this.recommendation});

  @override
  Widget build(BuildContext context) {
    final profile = user.profile;
    final skills = profile?.skills ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: _lecturerCardBlue,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: InkWell(
          onTap: () {
            context.push(
              RouteNames.profile.replaceFirst(':userId', user.id),
            );
          },
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              border: Border.all(color: AppColors.primaryDark),
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primaryTint10,
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: user.photoUrl == null
                      ? Text(
                          user.firstName.isNotEmpty
                              ? user.firstName[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),

                // Name + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? user.email,
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile?.programName ?? profile?.faculty ?? user.email,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (skills.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: skills
                              .take(3)
                              .map(
                                (s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    s,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      if (recommendation != null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _lecturerButtonGreen,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'AI Fit ${(recommendation!.score * 100).round()}%',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (recommendation!.matchedSkills.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  'Match: ${recommendation!.matchedSkills.take(2).join(', ')}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Streak indicator
                if (profile != null && profile.activityStreak > 0) ...[
                  Column(
                    children: [
                      Icon(Icons.local_fire_department,
                          size: 18, color: Colors.orange.shade400),
                      Text(
                        '${profile.activityStreak}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade400,
                        ),
                      ),
                    ],
                  ),
                ],

                // Chat button
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      size: 20, color: Colors.white),
                  tooltip: 'Message ${user.firstName}',
                  onPressed: () {
                    context.push(
                      '/chat/${user.id}',
                      extra: {
                        'peerName': user.displayName ?? user.email,
                        'peerPhotoUrl': user.photoUrl,
                        'isPeerLecturer': false,
                      },
                    );
                  },
                ),

                const Icon(Icons.chevron_right, size: 20, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// â”€â”€ Meta chip â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 3),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

