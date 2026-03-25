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
import '../../../data/remote/gemini_service.dart';
import '../../../data/remote/recommender_service.dart';
import '../../auth/bloc/auth_cubit.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  late Future<_RecommendationsViewData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<_RecommendationsViewData> _loadData() async {
    final currentUserId = sl<AuthCubit>().currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      return const _RecommendationsViewData.empty();
    }

    final userDao = sl<UserDao>();
    final currentUser = await userDao.getUserById(currentUserId);
    if (currentUser == null || currentUser.profile == null) {
      return const _RecommendationsViewData.empty();
    }

    final activityLogDao = sl<ActivityLogDao>();
    await activityLogDao.logAction(
      userId: currentUserId,
      action: 'open_ai_recommendations',
      entityType: 'screen',
      entityId: 'recommendations',
    );

    final recentCategories =
        await activityLogDao.getRecentCategorySignals(currentUserId);
    final recentSearchTerms =
        await activityLogDao.getRecentSearchTerms(currentUserId);

    final posts = await sl<PostDao>().getFeedPage(
      pageSize: 80,
      currentUserId: currentUserId,
    );
    final rankedPosts = await sl<RecommenderService>().rankHybrid(
      user: currentUser,
      candidates: posts,
      recentlyViewedCategories: recentCategories,
      recentSearchTerms: recentSearchTerms,
    );

    final allStudents = await userDao.getAllUsers(
      role: 'student',
      includeSuspended: false,
      pageSize: 120,
    );
    final acceptedCollaborators = await sl<MessageDao>().getAcceptedCollaborators(
      userId: currentUserId,
      limit: 100,
    );
    final collaboratorSuggestions = sl<RecommenderService>()
        .rankCollaborators(
          currentUser: currentUser,
          candidates: allStudents,
          excludedUserIds: acceptedCollaborators.map((item) => item.peerId).toSet(),
          recentSearchTerms: recentSearchTerms,
        )
        .take(6)
        .toList();

    return _RecommendationsViewData(
      userName: currentUser.firstName.isNotEmpty
          ? currentUser.firstName
          : (currentUser.displayName ?? currentUser.email),
      profileCompletion: _profileCompletion(currentUser),
      recentSearchTerms: recentSearchTerms.toList()..sort(),
      recentCategories: recentCategories.toList()..sort(),
      geminiEnabled: sl<GeminiService>().isConfigured,
      projects: rankedPosts.where((item) => item.post.type != 'opportunity').take(4).toList(),
      opportunities: rankedPosts.where((item) => item.post.type == 'opportunity').take(4).toList(),
      collaborators: collaboratorSuggestions,
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
          'Recommended for You',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: FutureBuilder<_RecommendationsViewData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data ?? const _RecommendationsViewData.empty();
          if (!data.hasContent) {
            return _EmptyRecommendations(onRefresh: _refresh);
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _HeroPanel(data: data),
                const SizedBox(height: 18),
                const _SectionHeader(
                  title: 'Projects You Might Like',
                  subtitle: 'Blended from your profile, recent activity, and live engagement.',
                ),
                const SizedBox(height: 10),
                ...data.projects.map((item) => _PostRecommendationCard(item: item)),
                const SizedBox(height: 18),
                const _SectionHeader(
                  title: 'Potential Collaborators',
                  subtitle: 'Students whose skills and momentum fit your current direction.',
                ),
                const SizedBox(height: 10),
                ...data.collaborators
                    .map((item) => _CollaboratorRecommendationCard(item: item)),
                const SizedBox(height: 18),
                const _SectionHeader(
                  title: 'Top Opportunities',
                  subtitle: 'Open calls with the strongest signal match right now.',
                ),
                const SizedBox(height: 10),
                ...data.opportunities
                    .map((item) => _PostRecommendationCard(item: item, accent: AppColors.roleLecturer)),
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

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.data});

  final _RecommendationsViewData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F4BC8), Color(0xFF1B7AE6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        boxShadow: const [
          BoxShadow(
            color: Color(0x221152D4),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Priority stack for ${data.userName}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.geminiEnabled
                          ? 'Local ranking is active with Gemini reranking when useful.'
                          : 'Local ranking is active. Add Gemini later for remote reranking.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Profile strength',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: data.profileCompletion,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF8FAFC)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(data.profileCompletion * 100).round()}% of your ranking profile is filled in.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          if (data.recentSearchTerms.isNotEmpty || data.recentCategories.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...data.recentSearchTerms.take(3).map(
                      (term) => _SignalChip(label: term, icon: Icons.search_rounded),
                    ),
                ...data.recentCategories.take(2).map(
                      (term) => _SignalChip(label: term, icon: Icons.category_outlined),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

class _PostRecommendationCard extends StatelessWidget {
  const _PostRecommendationCard({required this.item, this.accent = AppColors.primary});

  final RecommendedPost item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final post = item.post;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        child: InkWell(
          onTap: () => context.push(
            RouteNames.projectDetail.replaceFirst(':postId', post.id),
          ),
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        post.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${(item.score * 100).round()}%',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  post.description ?? 'No description provided yet.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (post.category != null)
                      _MetaPill(label: post.category!, color: accent),
                    if (post.faculty != null)
                      _MetaPill(label: post.faculty!, color: AppColors.info),
                    ...item.reasons.take(2).map(
                          (reason) => _MetaPill(
                            label: _reasonLabel(reason),
                            color: AppColors.success,
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

class _CollaboratorRecommendationCard extends StatelessWidget {
  const _CollaboratorRecommendationCard({required this.item});

  final RecommendedUser item;

  @override
  Widget build(BuildContext context) {
    final user = item.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        child: InkWell(
          onTap: () => context.push(
            RouteNames.profile.replaceFirst(':userId', user.id),
          ),
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primaryTint10,
                  backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                  child: user.photoUrl == null
                      ? Text(
                          (user.firstName.isNotEmpty ? user.firstName[0] : '?').toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? user.email,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user.profile?.programName ?? user.profile?.faculty ?? user.email,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.textSecondary(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...item.matchedSkills.take(2).map(
                                (skill) => _MetaPill(label: skill, color: AppColors.primary),
                              ),
                          ...item.reasons.take(1).map(
                                (reason) => _MetaPill(
                                  label: _reasonLabel(reason),
                                  color: AppColors.roleLecturer,
                                ),
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(item.score * 100).round()}%',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecommendations extends StatelessWidget {
  const _EmptyRecommendations({required this.onRefresh});

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
            Icons.auto_awesome_outlined,
            size: 64,
            color: AppColors.textSecondary(context),
          ),
          const SizedBox(height: 16),
          Text(
            'No personalized recommendations yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use Discover, complete your profile, and interact with projects to build stronger signals.',
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

class _RecommendationsViewData {
  const _RecommendationsViewData({
    required this.userName,
    required this.profileCompletion,
    required this.recentSearchTerms,
    required this.recentCategories,
    required this.geminiEnabled,
    required this.projects,
    required this.opportunities,
    required this.collaborators,
  });

  const _RecommendationsViewData.empty()
      : userName = 'Student',
        profileCompletion = 0,
        recentSearchTerms = const [],
        recentCategories = const [],
        geminiEnabled = false,
        projects = const [],
        opportunities = const [],
        collaborators = const [];

  final String userName;
  final double profileCompletion;
  final List<String> recentSearchTerms;
  final List<String> recentCategories;
  final bool geminiEnabled;
  final List<RecommendedPost> projects;
  final List<RecommendedPost> opportunities;
  final List<RecommendedUser> collaborators;

  bool get hasContent =>
      projects.isNotEmpty || opportunities.isNotEmpty || collaborators.isNotEmpty;
}

String _reasonLabel(String reason) {
  switch (reason) {
    case 'skill_match':
      return 'Skill match';
    case 'faculty_match':
      return 'Same faculty';
    case 'program_match':
      return 'Same program';
    case 'search_intent':
      return 'Matches search intent';
    case 'collaborative_signal':
      return 'Based on recent activity';
    case 'opportunity_fit':
      return 'Opportunity fit';
    case 'complementary_skills':
      return 'Complementary skills';
    case 'gemini_rerank':
      return 'Gemini reranked';
    default:
      return 'Recommended';
  }
}

