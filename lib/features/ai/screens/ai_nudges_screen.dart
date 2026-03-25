import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/message_dao.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/remote/recommender_service.dart';
import '../../auth/bloc/auth_cubit.dart';

class AiNudgesScreen extends StatefulWidget {
  const AiNudgesScreen({super.key});

  @override
  State<AiNudgesScreen> createState() => _AiNudgesScreenState();
}

class _AiNudgesScreenState extends State<AiNudgesScreen> {
  late Future<_NudgesViewData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<_NudgesViewData> _loadData() async {
    final currentUserId = sl<AuthCubit>().currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      return const _NudgesViewData.empty();
    }

    final user = await sl<UserDao>().getUserById(currentUserId);
    if (user == null || user.profile == null) {
      return const _NudgesViewData.empty();
    }

    final activityDao = sl<ActivityLogDao>();
    await activityDao.logAction(
      userId: currentUserId,
      action: 'open_ai_nudges',
      entityType: 'screen',
      entityId: 'ai_nudges',
    );

    final ownPosts = await sl<PostDao>().getPostsByAuthor(currentUserId, pageSize: 20);
    final collaborators = await sl<MessageDao>().getAcceptedCollaborators(
      userId: currentUserId,
      limit: 100,
    );
    final recentSearchTerms = await activityDao.getRecentSearchTerms(currentUserId);
    final recentCategories = await activityDao.getRecentCategorySignals(currentUserId);

    final opportunities = await sl<PostDao>().getFeedPage(
      pageSize: 40,
      filterType: 'opportunity',
      currentUserId: currentUserId,
    );
    final rankedOpportunities = await sl<RecommenderService>().rankHybrid(
      user: user,
      candidates: opportunities,
      recentlyViewedCategories: recentCategories,
      recentSearchTerms: recentSearchTerms,
    );
    final topOpportunity = rankedOpportunities.isNotEmpty ? rankedOpportunities.first.post : null;

    final profile = user.profile!;
    final profileCompletion = _profileCompletion(user);
    final nudges = <_NudgeItem>[];

    if (profileCompletion < 0.75) {
      nudges.add(const _NudgeItem(
        title: 'Tighten your profile signal',
        message:
            'Your recommendation quality will improve once your bio, faculty, program, and skills are fully filled in.',
        ctaLabel: 'Update profile',
        route: RouteNames.editProfile,
        icon: Icons.edit_note_rounded,
        color: AppColors.primary,
      ));
    }

    if (profile.activityStreak < 3) {
      nudges.add(const _NudgeItem(
        title: 'Restart your activity streak',
        message:
            'A fresh post, comment, or opportunity response today will strengthen your feed ranking over the next few days.',
        ctaLabel: 'Create a post',
        route: RouteNames.createPost,
        icon: Icons.local_fire_department_rounded,
        color: AppColors.warning,
      ));
    }

    if (ownPosts.isEmpty) {
      nudges.add(const _NudgeItem(
        title: 'Publish your first visible project',
        message:
            'You have profile signals, but no public work to rank yet. Posting once gives the engine something to amplify.',
        ctaLabel: 'Post now',
        route: RouteNames.createPost,
        icon: Icons.rocket_launch_rounded,
        color: AppColors.success,
      ));
    }

    if (collaborators.isEmpty) {
      nudges.add(const _NudgeItem(
        title: 'Open a collaboration lane',
        message:
            'You have no accepted collaborators yet. Start one conversation with a likely fit to unlock stronger peer recommendations.',
        ctaLabel: 'Explore peers',
        route: RouteNames.peers,
        icon: Icons.group_add_rounded,
        color: AppColors.roleLecturer,
      ));
    }

    if (recentSearchTerms.isNotEmpty) {
      final searchLead = recentSearchTerms.take(2).join(' and ');
      nudges.add(_NudgeItem(
        title: 'Convert search intent into action',
        message:
            'You recently searched for $searchLead. Re-open Discover and engage with one matching post so the ranking model gets a stronger signal.',
        ctaLabel: 'Open Discover',
        route: RouteNames.discover,
        icon: Icons.travel_explore_rounded,
        color: AppColors.info,
      ));
    }

    if (topOpportunity != null) {
      nudges.add(_NudgeItem(
        title: 'High-fit opportunity is available',
        message:
            '"${topOpportunity.title}" currently has the strongest skill overlap with your profile and activity pattern.',
        ctaLabel: 'Review opportunity',
        route: RouteNames.projectDetail.replaceFirst(':postId', topOpportunity.id),
        icon: Icons.campaign_rounded,
        color: AppColors.roleLecturer,
      ));
    }

    if (nudges.isEmpty) {
      nudges.add(const _NudgeItem(
        title: 'Keep the signal warm',
        message:
            'Your account already has healthy recommendation inputs. Keep posting, replying, and following up on matches to maintain ranking quality.',
        ctaLabel: 'Browse feed',
        route: RouteNames.home,
        icon: Icons.insights_rounded,
        color: AppColors.primary,
      ));
    }

    return _NudgesViewData(
      userName: user.firstName.isNotEmpty ? user.firstName : (user.displayName ?? user.email),
      activityStreak: profile.activityStreak,
      collaboratorsCount: collaborators.length,
      recentSearchTerms: recentSearchTerms.toList()..sort(),
      nudges: nudges.take(5).toList(),
    );
  }

  Future<void> _refresh() async {
    final future = _loadData();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(
          'AI Activity Nudges',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: FutureBuilder<_NudgesViewData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data ?? const _NudgesViewData.empty();
          if (!data.hasContent) {
            return _EmptyNudges(onRefresh: _refresh);
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _NudgesHero(data: data),
                const SizedBox(height: 18),
                Text(
                  'Action queue',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'These nudges are derived from your profile strength, streak, collaboration state, and recent search behavior.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 12),
                ...data.nudges.map((nudge) => _NudgeCard(item: nudge)),
              ],
            ),
          );
        },
      ),
    );
  }

  double _profileCompletion(dynamic user) {
    final profile = user.profile;
    if (profile == null) return 0;
    final completed = [
      profile.bio?.trim().isNotEmpty == true,
      profile.faculty?.trim().isNotEmpty == true,
      profile.programName?.trim().isNotEmpty == true,
      profile.skills.isNotEmpty,
    ].where((value) => value).length;
    return completed / 4.0;
  }
}

class _NudgesHero extends StatelessWidget {
  const _NudgesHero({required this.data});

  final _NudgesViewData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: AppColors.warningText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next-best actions for ${data.userName}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your current streak is ${data.activityStreak} and you have ${data.collaboratorsCount} accepted collaborators.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (data.recentSearchTerms.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: data.recentSearchTerms
                  .take(3)
                  .map(
                    (term) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint10,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        term,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _NudgeCard extends StatelessWidget {
  const _NudgeCard({required this.item});

  final _NudgeItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.message,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                      onPressed: () => context.push(item.route),
                      style: FilledButton.styleFrom(
                        backgroundColor: item.color.withValues(alpha: 0.12),
                        foregroundColor: item.color,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        item.ctaLabel,
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNudges extends StatelessWidget {
  const _EmptyNudges({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.bolt_outlined,
            size: 64,
            color: AppColors.textSecondary(context),
          ),
          const SizedBox(height: 16),
          Text(
            'No nudges available yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the app a bit more so activity signals can drive next-best-action guidance.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _NudgesViewData {
  const _NudgesViewData({
    required this.userName,
    required this.activityStreak,
    required this.collaboratorsCount,
    required this.recentSearchTerms,
    required this.nudges,
  });

  const _NudgesViewData.empty()
      : userName = 'Student',
        activityStreak = 0,
        collaboratorsCount = 0,
        recentSearchTerms = const [],
        nudges = const [];

  final String userName;
  final int activityStreak;
  final int collaboratorsCount;
  final List<String> recentSearchTerms;
  final List<_NudgeItem> nudges;

  bool get hasContent => nudges.isNotEmpty;
}

class _NudgeItem {
  const _NudgeItem({
    required this.title,
    required this.message,
    required this.ctaLabel,
    required this.route,
    required this.icon,
    required this.color,
  });

  final String title;
  final String message;
  final String ctaLabel;
  final String route;
  final IconData icon;
  final Color color;
}

