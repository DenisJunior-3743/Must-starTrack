// lib/features/lecturer/screens/shortlisted_talent_screen.dart
//
// MUST StarTrack — Shortlisted Talent
//
// Shows all the lecturer's active opportunities with their applicants
// ranked by the AI recommender. Grouped into tiers:
//   • Top Match  (score >= 0.65)
//   • Good Match (score >= 0.35)
//   • Other      (score < 0.35)
//
// Data flow:
//   1. Load lecturer's opp posts from PostDao
//   2. For each opp, load applicants from PostJoinDao
//   3. Rank with RecommenderService.rankStudentsForOpportunity()
//   4. Log to RecommendationLogDao (SQLite + Firestore)
//   5. Render tiered cards

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/post_join_dao.dart';
import '../../../data/local/dao/recommendation_log_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/recommender_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../shared/widgets/settings_drawer.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class _OppWithRanking {
  final PostModel opportunity;
  final List<RecommendedUser> topMatch;    // score >= 0.65
  final List<RecommendedUser> goodMatch;   // score >= 0.35
  final List<RecommendedUser> other;       // score < 0.35

  const _OppWithRanking({
    required this.opportunity,
    required this.topMatch,
    required this.goodMatch,
    required this.other,
  });

  int get total => topMatch.length + goodMatch.length + other.length;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ShortlistedTalentScreen extends StatefulWidget {
  const ShortlistedTalentScreen({super.key});

  @override
  State<ShortlistedTalentScreen> createState() =>
      _ShortlistedTalentScreenState();
}

class _ShortlistedTalentScreenState extends State<ShortlistedTalentScreen> {
  late Future<List<_OppWithRanking>> _future;
  String? _selectedOppId; // null = all

  @override
  void initState() {
    super.initState();
    _future = _loadAll();
  }

  Future<List<_OppWithRanking>> _loadAll() async {
    final lecturerId = sl<AuthCubit>().currentUser?.id ?? '';
    if (lecturerId.isEmpty) return [];

    final posts = await sl<PostDao>().getPostsByAuthor(
      lecturerId,
      pageSize: 100,
      includeArchived: false,
    );
    final opps = posts.where((p) => p.type == 'opportunity').toList();
    if (opps.isEmpty) return [];

    final results = <_OppWithRanking>[];
    final logEntries = <RecommendationLogEntry>[];

    for (final opp in opps) {
      final applicants =
          await sl<PostJoinDao>().getApplicantsForPost(opp.id);
      if (applicants.isEmpty) {
        results.add(_OppWithRanking(
          opportunity: opp,
          topMatch: [],
          goodMatch: [],
          other: [],
        ));
        continue;
      }

      final ranked = sl<RecommenderService>().rankStudentsForOpportunity(
        opportunity: opp,
        candidates: applicants,
      );

      for (final r in ranked) {
        logEntries.add(RecommendationLogEntry(
          userId: lecturerId,
          itemId: r.user.id,
          itemType: 'user',
          algorithm: 'applicant',
          score: r.score,
          reasons: r.reasons,
        ));
      }

      results.add(_OppWithRanking(
        opportunity: opp,
        topMatch: ranked.where((r) => r.score >= 0.65).toList(),
        goodMatch:
            ranked.where((r) => r.score >= 0.35 && r.score < 0.65).toList(),
        other: ranked.where((r) => r.score < 0.35).toList(),
      ));
    }

    // Log all ranked applicants (fire-and-forget)
    if (logEntries.isNotEmpty) {
      sl<RecommendationLogDao>().insertBatch(logEntries).ignore();
    }

    return results;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      endDrawer: const SettingsDrawer(),
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'Shortlisted Talent',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh rankings',
            onPressed: () => setState(() => _future = _loadAll()),
          ),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Settings',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<_OppWithRanking>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error.toString());
          }
          final data = snapshot.data ?? [];
          if (data.isEmpty) {
            return _EmptyView(isDark: isDark);
          }

          // Filter selector
          final opps = data.map((d) => d.opportunity).toList();

          return Column(
            children: [
              _OppFilterBar(
                opportunities: opps,
                selectedId: _selectedOppId,
                onSelect: (id) => setState(() => _selectedOppId = id),
              ),
              Expanded(
                child: _RankingList(
                  data: _selectedOppId == null
                      ? data
                      : data
                          .where((d) => d.opportunity.id == _selectedOppId)
                          .toList(),
                  isDark: isDark,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Opportunity filter bar ────────────────────────────────────────────────────

class _OppFilterBar extends StatelessWidget {
  final List<PostModel> opportunities;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  const _OppFilterBar({
    required this.opportunities,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: 'All',
            selected: selectedId == null,
            onTap: () => onSelect(null),
          ),
          ...opportunities.map(
            (o) => _FilterChip(
              label: o.title,
              selected: selectedId == o.id,
              onTap: () => onSelect(o.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.22),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.primary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// ── Ranking list ──────────────────────────────────────────────────────────────

class _RankingList extends StatelessWidget {
  final List<_OppWithRanking> data;
  final bool isDark;

  const _RankingList({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        for (final opp in data) ...[
          // Opportunity header
          SliverToBoxAdapter(
            child: _OppHeader(opp: opp, isDark: isDark),
          ),

          // Top Match tier
          if (opp.topMatch.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _TierLabel(
                label: 'Top Match',
                color: AppColors.success,
                icon: Icons.star_rounded,
                count: opp.topMatch.length,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _ApplicantTile(
                  rec: opp.topMatch[i],
                  tier: _Tier.top,
                  isDark: isDark,
                ),
                childCount: opp.topMatch.length,
              ),
            ),
          ],

          // Good Match tier
          if (opp.goodMatch.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _TierLabel(
                label: 'Good Match',
                color: AppColors.primary,
                icon: Icons.check_circle_outline_rounded,
                count: opp.goodMatch.length,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _ApplicantTile(
                  rec: opp.goodMatch[i],
                  tier: _Tier.good,
                  isDark: isDark,
                ),
                childCount: opp.goodMatch.length,
              ),
            ),
          ],

          // Other tier (collapsed by default)
          if (opp.other.isNotEmpty)
            SliverToBoxAdapter(
              child: _CollapsibleOther(
                items: opp.other,
                isDark: isDark,
              ),
            ),

          // Empty state for this opportunity
          if (opp.total == 0)
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'No applicants yet',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppColors.textSecondaryLight,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

// ── Opportunity header card ───────────────────────────────────────────────────

class _OppHeader extends StatelessWidget {
  final _OppWithRanking opp;
  final bool isDark;

  const _OppHeader({required this.opp, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(
          color: AppColors.roleLecturer.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.roleLecturer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: AppColors.roleLecturer,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  opp.opportunity.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${opp.total} applicant${opp.total == 1 ? '' : 's'}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (opp.total > 0) ...[
            const SizedBox(height: 10),
            _MatchBar(
              topCount: opp.topMatch.length,
              goodCount: opp.goodMatch.length,
              otherCount: opp.other.length,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Visual match bar showing tier proportions ─────────────────────────────────

class _MatchBar extends StatelessWidget {
  final int topCount;
  final int goodCount;
  final int otherCount;

  const _MatchBar({
    required this.topCount,
    required this.goodCount,
    required this.otherCount,
  });

  @override
  Widget build(BuildContext context) {
    final total = topCount + goodCount + otherCount;
    if (total == 0) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (topCount > 0)
                    Flexible(
                      flex: topCount * 100 ~/ total,
                      child: Container(color: AppColors.success),
                    ),
                  if (goodCount > 0)
                    Flexible(
                      flex: goodCount * 100 ~/ total,
                      child: Container(color: AppColors.primary),
                    ),
                  if (otherCount > 0)
                    Flexible(
                      flex: otherCount * 100 ~/ total,
                      child: Container(
                        color: AppColors.textSecondaryLight.withValues(alpha: 0.3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${topCount}T · ${goodCount}G · ${otherCount}O',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }
}

// ── Tier label row ────────────────────────────────────────────────────────────

class _TierLabel extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final int count;

  const _TierLabel({
    required this.label,
    required this.color,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Collapsible "Other" section ───────────────────────────────────────────────

class _CollapsibleOther extends StatefulWidget {
  final List<RecommendedUser> items;
  final bool isDark;

  const _CollapsibleOther({required this.items, required this.isDark});

  @override
  State<_CollapsibleOther> createState() => _CollapsibleOtherState();
}

class _CollapsibleOtherState extends State<_CollapsibleOther> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 14,
                  color: AppColors.textSecondaryLight,
                ),
                const SizedBox(width: 6),
                Text(
                  'Other (${widget.items.length})',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          ...widget.items.map(
            (r) => _ApplicantTile(
              rec: r,
              tier: _Tier.other,
              isDark: widget.isDark,
            ),
          ),
      ],
    );
  }
}

// ── Applicant tile ────────────────────────────────────────────────────────────

enum _Tier { top, good, other }

class _ApplicantTile extends StatelessWidget {
  final RecommendedUser rec;
  final _Tier tier;
  final bool isDark;

  const _ApplicantTile({
    required this.rec,
    required this.tier,
    required this.isDark,
  });

  Color get _tierColor => switch (tier) {
        _Tier.top => AppColors.success,
        _Tier.good => AppColors.primary,
        _Tier.other => AppColors.textSecondaryLight,
      };

  @override
  Widget build(BuildContext context) {
    final user = rec.user;
    final profile = user.profile;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: InkWell(
          onTap: () => context.push(
            RouteNames.profile.replaceFirst(':userId', user.id),
          ),
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Row(
              children: [
                // Tier accent bar
                Container(
                  width: 3,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _tierColor,
                    borderRadius: BorderRadius.circular(2),
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
                          (user.displayName ?? user.email)
                                  .substring(0, 1)
                                  .toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),

                // Info
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
                      ),
                      if (profile?.programName != null || profile?.faculty != null)
                        Text(
                          profile?.programName ?? profile?.faculty ?? '',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.textSecondaryLight,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (rec.matchedSkills.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: rec.matchedSkills.take(3).map((s) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                s,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.success,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // AI score badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _tierColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(rec.score * 100).round()}%',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _tierColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.chevron_right,
                        size: 16, color: AppColors.textHintLight),
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

// ── Empty / error views ───────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final bool isDark;
  const _EmptyView({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.campaign_outlined,
              size: 64,
              color: AppColors.textSecondaryLight.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No active opportunities',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Post an opportunity to see ranked applicants here.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textSecondaryLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

