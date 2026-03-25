// lib/features/lecturer/screens/lecturer_ranking_screen.dart
//
// MUST StarTrack — Student Ranking / Leaderboard
//
// Lecturers can view students ranked by:
//   • Activity streak
//   • Total posts
//   • Collaborations
//   • Followers
// Tapping a student navigates to their profile.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/user_model.dart';
import '../bloc/lecturer_cubit.dart';

class LecturerRankingScreen extends StatefulWidget {
  const LecturerRankingScreen({super.key});

  @override
  State<LecturerRankingScreen> createState() => _LecturerRankingScreenState();
}

class _LecturerRankingScreenState extends State<LecturerRankingScreen> {
  String _sortBy = 'fit';

  static const _sortOptions = {
    'fit': 'AI Fit',
    'streak': 'Activity Streak',
    'posts': 'Total Posts',
    'collabs': 'Collaborations',
    'followers': 'Followers',
  };

  @override
  void initState() {
    super.initState();
    context.read<LecturerCubit>().loadRanking(sortBy: _sortBy);
  }

  void _onSortChanged(String? value) {
    if (value == null || value == _sortBy) return;
    setState(() => _sortBy = value);
    context.read<LecturerCubit>().loadRanking(sortBy: value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'Student Rankings',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // ── Sort controls ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  'Rank by:',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _sortOptions.entries.map((e) {
                        final isActive = e.key == _sortBy;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              e.value,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isActive
                                    ? Colors.white
                                    : AppColors.textSecondaryLight,
                              ),
                            ),
                            selected: isActive,
                            selectedColor: AppColors.roleLecturer,
                            onSelected: (_) => _onSortChanged(e.key),
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Rankings list ──────────────────────────────────────────────
          Expanded(
            child: BlocBuilder<LecturerCubit, LecturerState>(
              builder: (context, state) {
                if (state is LecturerLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is LecturerError) {
                  return Center(child: Text(state.message));
                }
                if (state is StudentRankingLoaded) {
                  if (state.students.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.leaderboard_outlined,
                              size: 56,
                              color: AppColors.textSecondaryLight
                                  .withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No students found',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.students.length,
                    itemBuilder: (context, index) {
                      return _RankedStudentTile(
                        rank: index + 1,
                        user: state.students[index],
                        sortBy: _sortBy,
                        aiScore: state.aiScores[state.students[index].id],
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ranked student tile ───────────────────────────────────────────────────────

class _RankedStudentTile extends StatelessWidget {
  final int rank;
  final UserModel user;
  final String sortBy;
  final double? aiScore;

  const _RankedStudentTile({
    required this.rank,
    required this.user,
    required this.sortBy,
    this.aiScore,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = user.profile;

    // Determine the ranking value
    String rankValue;
    IconData rankIcon;
    Color rankColor;
    switch (sortBy) {
      case 'fit':
        rankValue = '${((aiScore ?? 0) * 100).round()}%';
        rankIcon = Icons.auto_awesome_rounded;
        rankColor = AppColors.roleLecturer;
        break;
      case 'posts':
        rankValue = '${profile?.totalPosts ?? 0}';
        rankIcon = Icons.article_outlined;
        rankColor = AppColors.primary;
        break;
      case 'collabs':
        rankValue = '${profile?.totalCollabs ?? 0}';
        rankIcon = Icons.handshake_outlined;
        rankColor = AppColors.success;
        break;
      case 'followers':
        rankValue = '${profile?.totalFollowers ?? 0}';
        rankIcon = Icons.group_outlined;
        rankColor = AppColors.roleLecturer;
        break;
      case 'streak':
      default:
        rankValue = '${profile?.activityStreak ?? 0}';
        rankIcon = Icons.local_fire_department;
        rankColor = Colors.orange;
    }

    // Medal colors for top 3
    Color? medalColor;
    if (rank == 1) medalColor = const Color(0xFFFFD700);
    if (rank == 2) medalColor = const Color(0xFFC0C0C0);
    if (rank == 3) medalColor = const Color(0xFFCD7F32);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: InkWell(
          onTap: () {
            context.push(
              RouteNames.profile.replaceFirst(':userId', user.id),
            );
          },
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              border: Border.all(
                color: medalColor?.withValues(alpha: 0.4) ??
                    (isDark ? AppColors.borderDark : AppColors.borderLight),
                width: medalColor != null ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Rank badge
                SizedBox(
                  width: 32,
                  child: medalColor != null
                      ? Icon(Icons.emoji_events, color: medalColor, size: 24)
                      : Text(
                          '#$rank',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                ),
                const SizedBox(width: 10),

                // Avatar
                CircleAvatar(
                  radius: 20,
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
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),

                // Name + program
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? user.email,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (profile?.programName != null)
                        Text(
                          profile!.programName!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.textSecondaryLight,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                // Rank value
                Column(
                  children: [
                    Icon(rankIcon, size: 18, color: rankColor),
                    Text(
                      rankValue,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: rankColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

