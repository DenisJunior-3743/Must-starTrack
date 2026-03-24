// lib/features/lecturer/screens/lecturer_dashboard_screen.dart
//
// MUST StarTrack â€” Lecturer Dashboard
//
// Overview for lecturers:
//   â€¢ Stat cards: Active opps | Total applicants | Expired
//   â€¢ List of own opportunity posts with applicant counts
//   â€¢ Quick actions: Create opportunity, Search students, Rankings

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/post_model.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../bloc/lecturer_cubit.dart';

class LecturerDashboardScreen extends StatefulWidget {
  const LecturerDashboardScreen({super.key});

  @override
  State<LecturerDashboardScreen> createState() =>
      _LecturerDashboardScreenState();
}

class _LecturerDashboardScreenState extends State<LecturerDashboardScreen> {
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final authState = context.read<AuthCubit>().state;
    if (authState is AuthAuthenticated) {
      context.read<LecturerCubit>().loadDashboard(authState.user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'Lecturer Dashboard',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
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
                    const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(state.message, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _loadData, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }
          if (state is LecturerDashboardLoaded) {
            return _DashboardBody(state: state);
          }
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RouteNames.createPost),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Opportunity'),
        backgroundColor: AppColors.roleLecturer,
      ),
    );
  }
}

// â”€â”€ Dashboard body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _DashboardBody extends StatelessWidget {
  final LecturerDashboardLoaded state;
  const _DashboardBody({required this.state});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        final authState = context.read<AuthCubit>().state;
        if (authState is AuthAuthenticated) {
          await context
              .read<LecturerCubit>()
              .loadDashboard(authState.user.id);
        }
      },
      child: CustomScrollView(
        slivers: [
          // â”€â”€ Stat cards â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Active',
                      value: '${state.activeOpportunities}',
                      icon: Icons.campaign_rounded,
                      color: AppColors.success,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'Applicants',
                      value: '${state.totalApplicants}',
                      icon: Icons.people_rounded,
                      color: AppColors.primary,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'Expired',
                      value: '${state.expiredOpportunities}',
                      icon: Icons.schedule_rounded,
                      color: AppColors.warning,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // â”€â”€ Quick actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.search_rounded,
                      label: 'Search Students',
                      onTap: () =>
                          context.push(RouteNames.lecturerSearch),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.leaderboard_rounded,
                      label: 'Rankings',
                      onTap: () =>
                          context.push(RouteNames.lecturerRanking),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // â”€â”€ Section header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'Your Opportunities',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
              ),
            ),
          ),

          // â”€â”€ Opportunity list â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (state.opportunities.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.campaign_outlined,
                        size: 56,
                        color: AppColors.textSecondaryLight.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text(
                      'No opportunities posted yet',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap the button below to create your first opportunity',
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
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final opp = state.opportunities[index];
                  return _OpportunityTile(opportunity: opp);
                },
                childCount: state.opportunities.length,
              ),
            ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

// â”€â”€ Stat card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Action tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? AppColors.surfaceDark : Colors.white,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.roleLecturer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 14, color: AppColors.textSecondaryLight),
            ],
          ),
        ),
      ),
    );
  }
}

// â”€â”€ Opportunity tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _OpportunityTile extends StatelessWidget {
  final PostModel opportunity;
  const _OpportunityTile({required this.opportunity});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExpired = opportunity.opportunityDeadline != null &&
        opportunity.opportunityDeadline!.isBefore(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: InkWell(
          onTap: () {
            context.push(
              RouteNames.lecturerApplicants,
              extra: opportunity,
            );
          },
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        opportunity.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isExpired
                            ? AppColors.warning.withValues(alpha: 0.12)
                            : AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isExpired ? 'Expired' : 'Active',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isExpired ? AppColors.warning : AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Meta row
                Row(
                  children: [
                    const Icon(Icons.people_outline,
                        size: 15, color: AppColors.textSecondaryLight),
                    const SizedBox(width: 4),
                    Text(
                      '${opportunity.joinCount} applicant${opportunity.joinCount == 1 ? '' : 's'}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    if (opportunity.areaOfExpertise != null) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.work_outline,
                          size: 15, color: AppColors.textSecondaryLight),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          opportunity.areaOfExpertise!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textSecondaryLight,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (opportunity.opportunityDeadline != null) ...[
                      const Spacer(),
                      const Icon(Icons.schedule,
                          size: 14, color: AppColors.textHintLight),
                      const SizedBox(width: 3),
                      Text(
                        _formatDeadline(opportunity.opportunityDeadline!),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.textHintLight,
                        ),
                      ),
                    ],
                  ],
                ),

                // Skills row
                if (opportunity.skillsUsed.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: opportunity.skillsUsed
                        .take(4)
                        .map(
                          (s) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primaryTint10,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              s,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDeadline(DateTime d) {
    final diff = d.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inDays > 30) return '${d.day}/${d.month}/${d.year}';
    if (diff.inDays > 0) return '${diff.inDays}d left';
    if (diff.inHours > 0) return '${diff.inHours}h left';
    return 'Soon';
  }
}

