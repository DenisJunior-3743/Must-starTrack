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
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/sync_service.dart';
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

  Future<void> _editOpportunity(PostModel post) async {
    final result = await context.push(
      RouteNames.createPost,
      extra: post,
    );
    if (result != null) {
      _loadData();
    }
  }

  Future<void> _deleteOpportunity(PostModel post) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete opportunity?'),
            content: Text(
              'This permanently removes "${post.title}" from your device and Firebase after sync.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    await sl<SyncQueueDao>().enqueue(
      operation: 'delete',
      entity: 'posts',
      entityId: post.id,
      payload: {'post_id': post.id},
    );
    await sl<PostDao>().deletePost(post.id);
    await sl<SyncService>().processPendingSync();

    if (!mounted) {
      return;
    }

    _loadData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opportunity deleted.')),
    );
  }

  Future<void> _archiveOpportunity(PostModel post) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Archive opportunity?'),
            content: Text(
              '"${post.title}" will be removed from active listings but kept in your archive.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Archive'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    await sl<PostDao>().archivePost(post.id);
    await sl<SyncQueueDao>().enqueue(
      operation: 'archive',
      entity: 'posts',
      entityId: post.id,
      payload: {'post_id': post.id},
    );
    await sl<SyncService>().processPendingSync();

    if (!mounted) {
      return;
    }

    _loadData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opportunity archived.')),
    );
  }

  Future<void> _unarchiveOpportunity(PostModel post) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unarchive opportunity?'),
            content: Text(
              '"${post.title}" will be moved back to your active opportunities.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Unarchive'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    final restored = post.copyWith(
      isArchived: false,
      updatedAt: DateTime.now(),
    );

    await sl<PostDao>().updatePost(restored);
    await sl<SyncQueueDao>().enqueue(
      operation: 'update',
      entity: 'posts',
      entityId: restored.id,
      payload: restored.toMap(),
    );
    await sl<SyncService>().processPendingSync();

    if (!mounted) {
      return;
    }

    _loadData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opportunity unarchived.')),
    );
  }

  Future<void> _showArchivedOpportunities(List<PostModel> archived) async {
    if (archived.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No archived opportunities yet.')),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.82,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textHintLight.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Archived Opportunities',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                          ),
                        ),
                        Text(
                          '${archived.length}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'Unarchive an opportunity to move it back into your active list.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: archived.length,
                      itemBuilder: (context, index) {
                        final opportunity = archived[index];
                        return _OpportunityTile(
                          opportunity: opportunity,
                          onEdit: () => _editOpportunity(opportunity),
                          onArchive: () => _archiveOpportunity(opportunity),
                          onRestore: () async {
                            Navigator.of(sheetContext).pop();
                            await _unarchiveOpportunity(opportunity);
                          },
                          onDelete: () => _deleteOpportunity(opportunity),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
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
            return _DashboardBody(
              state: state,
              onEditOpportunity: _editOpportunity,
              onArchiveOpportunity: _archiveOpportunity,
              onRestoreOpportunity: _unarchiveOpportunity,
              onDeleteOpportunity: _deleteOpportunity,
              onShowArchived: (archived) => _showArchivedOpportunities(archived),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// â”€â”€ Dashboard body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _DashboardBody extends StatelessWidget {
  final LecturerDashboardLoaded state;
  final Future<void> Function(PostModel post) onEditOpportunity;
  final Future<void> Function(PostModel post) onArchiveOpportunity;
  final Future<void> Function(PostModel post) onRestoreOpportunity;
  final Future<void> Function(PostModel post) onDeleteOpportunity;
  final Future<void> Function(List<PostModel> archived) onShowArchived;

  const _DashboardBody({
    required this.state,
    required this.onEditOpportunity,
    required this.onArchiveOpportunity,
    required this.onRestoreOpportunity,
    required this.onDeleteOpportunity,
    required this.onShowArchived,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeOpportunities =
        state.opportunities.where((opp) => !opp.isArchived).toList();
    final archivedOpportunities =
        state.opportunities.where((opp) => opp.isArchived).toList();

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

          // Recent group projects visibility for lecturers
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text(
                'Recent Group Projects',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<List<PostModel>>(
              future: sl<PostDao>().getRecentGroupProjects(limit: 6),
              builder: (context, snapshot) {
                final posts = snapshot.data ?? const <PostModel>[];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (posts.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      'No group projects published yet.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  );
                }
                return SizedBox(
                  height: 126,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    itemCount: posts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final post = posts[index];
                      return GestureDetector(
                        onTap: () => context.push(
                          RouteNames.projectDetail.replaceFirst(':postId', post.id),
                        ),
                        child: Container(
                          width: 244,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.surfaceDark : Colors.white,
                            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                            border: Border.all(
                              color: isDark ? AppColors.borderDark : AppColors.borderLight,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.groupName ?? 'Group Project',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.success,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                post.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'By ${post.authorName ?? 'Unknown'}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),

          // â”€â”€ Section header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Expanded(
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
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () => onShowArchived(archivedOpportunities),
                        icon: const Icon(Icons.unarchive_outlined, size: 18),
                        label: Text(
                          'Archived${archivedOpportunities.isNotEmpty ? ' (${archivedOpportunities.length})' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.24),
                          ),
                          minimumSize: const Size(0, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppDimensions.radiusMd),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (archivedOpportunities.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '${archivedOpportunities.length} archived opportunit${archivedOpportunities.length == 1 ? 'y' : 'ies'} available',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
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
                      'Use the bottom navigation to create your first opportunity',
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
          else ...[
            if (activeOpportunities.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final opp = activeOpportunities[index];
                    return _OpportunityTile(
                      opportunity: opp,
                      onEdit: () => onEditOpportunity(opp),
                      onArchive: () => onArchiveOpportunity(opp),
                      onRestore: null,
                      onDelete: () => onDeleteOpportunity(opp),
                    );
                  },
                  childCount: activeOpportunities.length,
                ),
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    archivedOpportunities.isNotEmpty
                        ? 'No active opportunities. Open Archived to unarchive one.'
                        : 'No active opportunities yet.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                ),
              ),
          ],

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
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback? onRestore;
  final VoidCallback onDelete;

  const _OpportunityTile({
    required this.opportunity,
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isArchived = opportunity.isArchived;
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
                        color: isArchived
                            ? AppColors.warning.withValues(alpha: 0.12)
                            : isExpired
                            ? AppColors.warning.withValues(alpha: 0.12)
                            : AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isArchived ? 'Archived' : (isExpired ? 'Expired' : 'Active'),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isArchived
                              ? AppColors.warning
                              : (isExpired ? AppColors.warning : AppColors.success),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: AppColors.textSecondaryLight,
                      ),
                      onSelected: (value) {
                        if (value == 'edit') {
                          onEdit();
                          return;
                        }
                        if (value == 'delete') {
                          onDelete();
                          return;
                        }
                        if (value == 'restore') {
                          onRestore?.call();
                          return;
                        }
                        if (value == 'archive') {
                          onArchive();
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem<String>(
                          value: 'edit',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit'),
                          ),
                        ),
                        if (isArchived)
                          const PopupMenuItem<String>(
                            value: 'restore',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.unarchive_outlined),
                              title: Text('Unarchive'),
                            ),
                          )
                        else
                          const PopupMenuItem<String>(
                            value: 'archive',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.archive_outlined),
                              title: Text('Archive'),
                            ),
                          ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.danger,
                            ),
                            title: Text(
                              'Delete',
                              style: TextStyle(color: AppColors.danger),
                            ),
                          ),
                        ),
                      ],
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
                if (isArchived && onRestore != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: onRestore,
                      icon: const Icon(Icons.unarchive_outlined, size: 18),
                      label: const Text('Unarchive'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.22),
                        ),
                      ),
                    ),
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

