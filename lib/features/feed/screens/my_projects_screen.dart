import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_guards.dart';
import '../../../core/router/route_names.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/post_join_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/sync_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../shared/widgets/guest_auth_required_view.dart';

enum _MyProjectsFilter { all, active, opportunities, applied, archived }

class MyProjectsScreen extends StatefulWidget {
  const MyProjectsScreen({super.key});

  static void invalidateCache() {
    _MyProjectsScreenState.invalidateCache();
  }

  @override
  State<MyProjectsScreen> createState() => _MyProjectsScreenState();
}

class _MyProjectsScreenState extends State<MyProjectsScreen> {
  static const Duration _staleAfter = Duration(minutes: 2);
  static DateTime? _cacheLoadedAt;
  static String? _cacheUserId;
  static List<PostModel> _cachedPosts = const [];
  static List<PostModel> _cachedAppliedPosts = const [];

  /// Call this after creating or editing a post so the screen reloads fresh data.
  static void invalidateCache() {
    _cacheLoadedAt = null;
  }

  final _postDao = sl<PostDao>();
  final _postJoinDao = sl<PostJoinDao>();
  final _syncQueue = sl<SyncQueueDao>();
  final _syncService = sl<SyncService>();

  bool _loading = true;
  String? _error;
  _MyProjectsFilter _filter = _MyProjectsFilter.all;
  List<PostModel> _posts = const [];
  List<PostModel> _appliedPosts = const [];

  String? get _currentUserId => sl<AuthCubit>().currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadPosts(useCacheFirst: true);
  }

  Future<void> _loadPosts({
    bool useCacheFirst = false,
    bool silentRefresh = false,
  }) async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) {
      setState(() {
        _loading = false;
        _posts = const [];
        _error = 'Sign in to manage your posts.';
      });
      _cacheUserId = null;
      _cacheLoadedAt = null;
      _cachedPosts = const [];
      _cachedAppliedPosts = const [];
      return;
    }

    if (useCacheFirst && _cacheUserId == userId && _cacheLoadedAt != null) {
      final cachedPosts = await _postDao.hydrateEngagementCounts(_cachedPosts);
      final cachedAppliedPosts =
          await _postDao.hydrateEngagementCounts(_cachedAppliedPosts);
      if (mounted) {
        _cachedPosts = cachedPosts;
        _cachedAppliedPosts = cachedAppliedPosts;
        setState(() {
          _posts = cachedPosts;
          _appliedPosts = cachedAppliedPosts;
          _loading = false;
          _error = null;
        });
      }

      final age = DateTime.now().difference(_cacheLoadedAt!);
      if (age >= _staleAfter) {
        unawaited(_loadPosts(useCacheFirst: false, silentRefresh: true));
      }
      return;
    }

    if (!silentRefresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        _postDao.getPostsByAuthor(
          userId,
          pageSize: 200,
          includeArchived: true,
        ),
        _postJoinDao.getJoinedPosts(userId),
      ]);

      if (!mounted) return;
      _cacheUserId = userId;
      _cacheLoadedAt = DateTime.now();
      _cachedPosts = results[0];
      _cachedAppliedPosts = results[1];
      setState(() {
        _posts = results[0];
        _appliedPosts = results[1];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your projects right now.';
      });
    }
  }

  List<PostModel> get _visiblePosts {
    switch (_filter) {
      case _MyProjectsFilter.active:
        return _posts.where((p) => !p.isArchived).toList();
      case _MyProjectsFilter.opportunities:
        return _posts
            .where((p) => p.type == 'opportunity' && !p.isArchived)
            .toList();
      case _MyProjectsFilter.applied:
        return _appliedPosts;
      case _MyProjectsFilter.archived:
        return _posts.where((p) => p.isArchived).toList();
      case _MyProjectsFilter.all:
        return _posts;
    }
  }

  bool get _isAppliedFilter => _filter == _MyProjectsFilter.applied;

  Future<void> _openEditor([PostModel? post]) async {
    final result = await context.push(
      RouteNames.createPost,
      extra: post,
    );
    if (result != null) {
      await _loadPosts();
    }
  }

  Future<void> _archivePost(PostModel post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive post?'),
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
    );

    if (confirmed != true) return;

    await _postDao.archivePost(post.id);
    await _syncQueue.enqueue(
      operation: 'archive',
      entity: 'posts',
      entityId: post.id,
      payload: {'post_id': post.id},
    );
    await _syncService.processPendingSync();
    await _loadPosts();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Post archived.')),
    );
  }

  Future<void> _deletePost(PostModel post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
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
    );

    if (confirmed != true) return;

    await _syncQueue.enqueue(
      operation: 'delete',
      entity: 'posts',
      entityId: post.id,
      payload: {'post_id': post.id},
    );
    await _postDao.deletePost(post.id);
    await _syncService.processPendingSync();
    await _loadPosts();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Post deleted.')),
    );
  }

  Future<void> _restorePost(PostModel post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore post?'),
        content: Text(
          '"${post.title}" will be moved back to your active listings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final restored = post.copyWith(
      isArchived: false,
      updatedAt: DateTime.now(),
    );

    await _postDao.updatePost(restored);
    await _syncQueue.enqueue(
      operation: 'update',
      entity: 'posts',
      entityId: restored.id,
      payload: restored.toMap(),
    );
    await _syncService.processPendingSync();
    await _loadPosts();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Post restored.')),
    );
  }

  void _openPost(PostModel post) {
    context.push('/project/${post.id}');
  }

  void _viewApplicants(PostModel post) {
    context.push(RouteNames.lecturerApplicants, extra: post);
  }

  @override
  Widget build(BuildContext context) {
    final guards = sl<RouteGuards>();
    final isGuest = sl<AuthCubit>().currentUser == null;
    final posts = _visiblePosts;

    if (isGuest) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'My Projects',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
        ),
        body: const GuestAuthRequiredView(
          icon: Icons.lock_outline_rounded,
          title: 'Sign in to access My Projects',
          subtitle:
              'You need an account to manage your project posts, applications, and archived work.',
          fromRoute: RouteNames.projects,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(
          'My Projects',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadPosts,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPosts,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _MyProjectsOverviewHeader(
              totalPosts: _posts.length,
              activePosts: _posts.where((p) => !p.isArchived).length,
              appliedPosts: _appliedPosts.length,
              onCreate: guards.canCreatePost() ? () => _openEditor() : null,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _MyProjectsFilter.values.map((filter) {
                final selected = _filter == filter;
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return ChoiceChip(
                  label: Text(_filterLabel(filter)),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  backgroundColor:
                      isDark ? AppColors.surfaceDark2 : AppColors.surfaceLight,
                  side: BorderSide(
                    color: selected
                        ? AppColors.primary
                        : AppColors.border(context),
                  ),
                  labelStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : AppColors.textPrimary(context),
                  ),
                  onSelected: (_) => setState(() => _filter = filter),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _MyProjectsMessageCard(
                icon: Icons.error_outline_rounded,
                title: 'Unable to load posts',
                subtitle: _error!,
                actionLabel: 'Try Again',
                onAction: _loadPosts,
              )
            else if (posts.isEmpty)
              _MyProjectsMessageCard(
                icon: Icons.folder_open_rounded,
                title: _isAppliedFilter
                    ? 'No applications yet'
                    : 'No posts here yet',
                subtitle: _isAppliedFilter
                    ? 'Opportunities you join will appear here so you can track your applications.'
                    : _filter == _MyProjectsFilter.archived
                        ? 'Archived posts will appear here once you archive them.'
                        : _filter == _MyProjectsFilter.opportunities
                            ? 'Opportunities you post will appear here.'
                            : 'Create your first project post and it will appear here for editing and management.',
                actionLabel: guards.canCreatePost() && !_isAppliedFilter
                    ? 'Create Post'
                    : null,
                onAction: guards.canCreatePost() && !_isAppliedFilter
                    ? () => _openEditor()
                    : null,
              )
            else
              ...posts.map(
                (post) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _isAppliedFilter
                      ? _AppliedOpportunityCard(
                          post: post,
                          onOpen: () => _openPost(post),
                          onMessage: () {
                            context.push(
                              '/chat/${post.authorId}',
                              extra: {
                                'peerName': post.authorName ?? '',
                                'peerPhotoUrl': post.authorPhotoUrl,
                                'isPeerLecturer': true,
                              },
                            );
                          },
                        )
                      : _MyProjectCard(
                          post: post,
                          onOpen: () => _openPost(post),
                          onEdit: () => _openEditor(post),
                          onArchive:
                              post.isArchived ? null : () => _archivePost(post),
                          onRestore:
                              post.isArchived ? () => _restorePost(post) : null,
                          onDelete: () => _deletePost(post),
                          onViewApplicants:
                              post.type == 'opportunity' && !post.isArchived
                                  ? () => _viewApplicants(post)
                                  : null,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _filterLabel(_MyProjectsFilter filter) {
    switch (filter) {
      case _MyProjectsFilter.all:
        return 'All';
      case _MyProjectsFilter.active:
        return 'Active';
      case _MyProjectsFilter.opportunities:
        return 'Opportunities';
      case _MyProjectsFilter.applied:
        return 'Applied';
      case _MyProjectsFilter.archived:
        return 'Archived';
    }
  }
}

class _MyProjectsMessageCard extends StatelessWidget {
  const _MyProjectsMessageCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark2 : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.borderLight,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppColors.textSecondary(context),
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _MyProjectsOverviewHeader extends StatelessWidget {
  const _MyProjectsOverviewHeader({
    required this.totalPosts,
    required this.activePosts,
    required this.appliedPosts,
    required this.onCreate,
  });

  final int totalPosts;
  final int activePosts;
  final int appliedPosts;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark2 : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                      AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.10),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                ),
                child: const Icon(
                  Icons.dashboard_customize_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project workspace',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Update posts, review media, and manage visibility.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (onCreate != null)
                IconButton.filled(
                  tooltip: 'Create post',
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeaderStat(
                  label: 'Total',
                  value: '$totalPosts',
                  icon: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeaderStat(
                  label: 'Active',
                  value: '$activePosts',
                  icon: Icons.check_circle_outline_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeaderStat(
                  label: 'Applied',
                  value: '$appliedPosts',
                  icon: Icons.how_to_reg_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : AppColors.primaryTint10,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyProjectCard extends StatelessWidget {
  const _MyProjectCard({
    required this.post,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.onArchive,
    this.onRestore,
    this.onViewApplicants,
  });

  final PostModel post;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final VoidCallback? onViewApplicants;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark2 : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.borderLight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: isDark ? 18 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    post.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(post: post),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Description',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isDark ? const Color(0xFF7EA7FF) : AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              post.description?.trim().isNotEmpty == true
                  ? post.description!
                  : 'No description yet.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textSecondary(context),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                    icon: Icons.thumb_up_alt_outlined,
                    label: '${post.likeCount} likes'),
                _MetricChip(
                    icon: Icons.comment_outlined,
                    label: '${post.commentCount} comments'),
                _MetricChip(
                    icon: Icons.visibility_outlined,
                    label: '${post.viewCount} views'),
                if (post.type == 'opportunity')
                  _MetricChip(
                      icon: Icons.people_outline,
                      label: '${post.joinCount} applicants'),
                _MetricChip(
                    icon: Icons.schedule_rounded,
                    label: timeago.format(post.updatedAt)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Media',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            _MyProjectMediaTabs(post: post),
            if (onViewApplicants != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onViewApplicants,
                  icon: const Icon(Icons.people_rounded, size: 18),
                  label: Text('View Applicants (${post.joinCount})'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.roleLecturer,
                    side: BorderSide(
                        color: AppColors.roleLecturer.withValues(alpha: 0.4)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (onRestore != null) ...[
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onRestore,
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('Restore'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else if (onArchive != null) ...[
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onArchive,
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Archive'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.danger),
                    label: const Text('Delete',
                        style: TextStyle(color: AppColors.danger)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _MyProjectMediaType { image, video }

class _MyProjectMediaItem {
  const _MyProjectMediaItem({
    required this.source,
    required this.title,
    required this.type,
  });

  final String source;
  final String title;
  final _MyProjectMediaType type;

  bool get isVideo => type == _MyProjectMediaType.video;
}

List<_MyProjectMediaItem> _myProjectVideosFor(PostModel post) {
  final items = <_MyProjectMediaItem>[
    for (final url in post.mediaUrls.where(_isMyProjectVideoUrl))
      _MyProjectMediaItem(
        source: url,
        title: post.title,
        type: _MyProjectMediaType.video,
      ),
  ];

  final youtube = post.youtubeUrl?.trim();
  if (youtube != null && youtube.isNotEmpty) {
    items.add(
      _MyProjectMediaItem(
        source: youtube,
        title: post.title,
        type: _MyProjectMediaType.video,
      ),
    );
  }
  return items;
}

List<_MyProjectMediaItem> _myProjectPicturesFor(PostModel post) {
  return post.mediaUrls
      .where((url) => !_isMyProjectVideoUrl(url))
      .map(
        (url) => _MyProjectMediaItem(
          source: url,
          title: post.title,
          type: _MyProjectMediaType.image,
        ),
      )
      .toList(growable: false);
}

class _MyProjectMediaTabs extends StatefulWidget {
  const _MyProjectMediaTabs({required this.post});

  final PostModel post;

  @override
  State<_MyProjectMediaTabs> createState() => _MyProjectMediaTabsState();
}

class _MyProjectMediaTabsState extends State<_MyProjectMediaTabs> {
  int _selected = 0;

  void _openMedia(List<_MyProjectMediaItem> items, int index) {
    if (items.isEmpty || index < 0 || index >= items.length) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MyProjectMediaPreviewScreen(
          items: items,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final videos = _myProjectVideosFor(widget.post);
    final pictures = _myProjectPicturesFor(widget.post);
    final showcase = [...pictures, ...videos];
    final tabs = [
      ('Videos', Icons.play_circle_outline_rounded, videos),
      ('Pictures', Icons.image_outlined, pictures),
      ('Showcase', Icons.auto_awesome_motion_rounded, showcase),
    ];
    final currentItems = tabs[_selected].$3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(tabs.length, (index) {
              final selected = _selected == index;
              final tab = tabs[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: selected,
                  showCheckmark: false,
                  avatar: Icon(
                    tab.$2,
                    size: 17,
                    color: selected
                        ? Colors.white
                        : isDark
                            ? const Color(0xFF8FB2FF)
                            : AppColors.primary,
                  ),
                  label: Text('${tab.$1} (${tab.$3.length})'),
                  selectedColor: AppColors.primary,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : AppColors.primaryTint10,
                  side: BorderSide(
                    color: selected
                        ? AppColors.primary
                        : isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : AppColors.borderLight,
                  ),
                  labelStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : AppColors.textPrimary(context),
                  ),
                  onSelected: (_) => setState(() => _selected = index),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 10),
        if (currentItems.isEmpty)
          _MyProjectEmptyMediaPanel(label: tabs[_selected].$1)
        else
          _MyProjectMediaGrid(
            items: currentItems,
            onOpen: (index) => _openMedia(currentItems, index),
          ),
      ],
    );
  }
}

class _MyProjectEmptyMediaPanel extends StatelessWidget {
  const _MyProjectEmptyMediaPanel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : AppColors.primaryTint10,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.primary.withValues(alpha: 0.10),
        ),
      ),
      child: Text(
        'No ${label.toLowerCase()} added yet.',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: AppColors.textSecondary(context),
        ),
      ),
    );
  }
}

class _MyProjectMediaGrid extends StatelessWidget {
  const _MyProjectMediaGrid({
    required this.items,
    required this.onOpen,
  });

  final List<_MyProjectMediaItem> items;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: () => onOpen(index),
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _MyProjectMediaThumbnail(item: item),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusFull),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.isVideo
                              ? Icons.play_arrow_rounded
                              : Icons.zoom_out_map_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.isVideo ? 'Watch' : 'View',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MyProjectMediaThumbnail extends StatelessWidget {
  const _MyProjectMediaThumbnail({required this.item});

  final _MyProjectMediaItem item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (item.isVideo) {
      return Container(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : AppColors.primaryTint10,
        child: const Center(
          child: Icon(
            Icons.play_circle_outline_rounded,
            size: 48,
            color: AppColors.primary,
          ),
        ),
      );
    }

    if (isLocalMediaPath(item.source)) {
      return Image.file(
        File(_toFilePath(item.source)),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _MyProjectMediaErrorThumbnail(),
      );
    }

    return Image.network(
      item.source,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _MyProjectMediaErrorThumbnail(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(color: AppColors.primaryTint10);
      },
    );
  }
}

class _MyProjectMediaErrorThumbnail extends StatelessWidget {
  const _MyProjectMediaErrorThumbnail();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : AppColors.primaryTint10,
      child: const Icon(
        Icons.broken_image_outlined,
        size: 36,
        color: AppColors.primary,
      ),
    );
  }
}

class _MyProjectMediaPreviewScreen extends StatefulWidget {
  const _MyProjectMediaPreviewScreen({
    required this.items,
    required this.initialIndex,
  });

  final List<_MyProjectMediaItem> items;
  final int initialIndex;

  @override
  State<_MyProjectMediaPreviewScreen> createState() =>
      _MyProjectMediaPreviewScreenState();
}

class _MyProjectMediaPreviewScreenState
    extends State<_MyProjectMediaPreviewScreen> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} of ${widget.items.length}',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_isExternalMyProjectWebVideo(item.source))
            IconButton(
              tooltip: 'Open video',
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () async {
                final uri = Uri.tryParse(item.source);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return item.isVideo
                  ? _MyProjectInlineVideoPreview(item: item)
                  : _MyProjectImagePreview(item: item);
            },
          ),
          if (widget.items.length > 1) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: _MyProjectPreviewNavButton(
                icon: Icons.chevron_left_rounded,
                onPressed: _index == 0
                    ? null
                    : () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _MyProjectPreviewNavButton(
                icon: Icons.chevron_right_rounded,
                onPressed: _index == widget.items.length - 1
                    ? null
                    : () => _pageController.nextPage(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MyProjectPreviewNavButton extends StatelessWidget {
  const _MyProjectPreviewNavButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      icon: Icon(icon, size: 32),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.46),
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.black.withValues(alpha: 0.14),
      ),
    );
  }
}

class _MyProjectImagePreview extends StatelessWidget {
  const _MyProjectImagePreview({required this.item});

  final _MyProjectMediaItem item;

  @override
  Widget build(BuildContext context) {
    final child = isLocalMediaPath(item.source)
        ? Image.file(
            File(_toFilePath(item.source)),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const _MyProjectPreviewError(),
          )
        : Image.network(
            item.source,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
            errorBuilder: (_, __, ___) => const _MyProjectPreviewError(),
          );

    return Center(
      child: InteractiveViewer(
        minScale: 0.7,
        maxScale: 4,
        child: child,
      ),
    );
  }
}

class _MyProjectInlineVideoPreview extends StatefulWidget {
  const _MyProjectInlineVideoPreview({required this.item});

  final _MyProjectMediaItem item;

  @override
  State<_MyProjectInlineVideoPreview> createState() =>
      _MyProjectInlineVideoPreviewState();
}

class _MyProjectInlineVideoPreviewState
    extends State<_MyProjectInlineVideoPreview> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_isExternalMyProjectWebVideo(widget.item.source)) {
      setState(() {
        _loading = false;
        _error = 'Open this hosted video in your browser.';
      });
      return;
    }

    try {
      final source = widget.item.source;
      final controller = isLocalMediaPath(source)
          ? VideoPlayerController.file(File(_toFilePath(source)))
          : VideoPlayerController.networkUrl(Uri.parse(source));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null ||
        controller == null ||
        !controller.value.isInitialized) {
      return _MyProjectVideoFallback(
        source: widget.item.source,
        message: _error ?? 'This video could not be loaded.',
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: AppColors.primary,
                bufferedColor: Colors.white38,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          IconButton.filled(
            onPressed: () {
              setState(() {
                controller.value.isPlaying
                    ? controller.pause()
                    : controller.play();
              });
            },
            icon: Icon(
              controller.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyProjectVideoFallback extends StatelessWidget {
  const _MyProjectVideoFallback({
    required this.source,
    required this.message,
  });

  final String source;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_outline_rounded,
              size: 72,
              color: Colors.white70,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final uri = Uri.tryParse(source);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open video'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyProjectPreviewError extends StatelessWidget {
  const _MyProjectPreviewError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.broken_image_outlined, size: 64, color: Colors.white70),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.post});

  final PostModel post;

  @override
  Widget build(BuildContext context) {
    final isArchived = post.isArchived;
    final isPending =
        !isArchived && post.moderationStatus == ModerationStatus.pending;

    final Color background;
    final Color foreground;
    final String label;

    final isRejected =
        !isArchived && post.moderationStatus == ModerationStatus.rejected;

    if (isArchived) {
      background = AppColors.warning.withValues(alpha: 0.14);
      foreground = AppColors.warning;
      label = 'Archived';
    } else if (isRejected) {
      background = AppColors.danger.withValues(alpha: 0.14);
      foreground = AppColors.danger;
      label = 'Rejected';
    } else if (isPending) {
      background = AppColors.primary.withValues(alpha: 0.12);
      foreground = AppColors.primary;
      label = 'Pending Review';
    } else {
      background = AppColors.success.withValues(alpha: 0.14);
      foreground = AppColors.success;
      label = post.type == 'opportunity' ? 'Opportunity' : 'Live';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 11, fontWeight: FontWeight.w700, color: foreground),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.primaryTint10,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Applied opportunity card (student view) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AppliedOpportunityCard extends StatelessWidget {
  const _AppliedOpportunityCard({
    required this.post,
    required this.onOpen,
    required this.onMessage,
  });

  final PostModel post;
  final VoidCallback onOpen;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExpired = post.opportunityDeadline != null &&
        post.opportunityDeadline!.isBefore(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark2 : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: isDark
              ? AppColors.roleLecturer.withValues(alpha: 0.35)
              : AppColors.roleLecturer.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_rounded,
                    color: AppColors.roleLecturer, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    post.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isExpired
                        ? AppColors.danger.withValues(alpha: 0.12)
                        : AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isExpired ? 'Expired' : 'Active',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isExpired ? AppColors.danger : AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
            if (post.description != null &&
                post.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                post.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (post.authorName != null)
                  _MetricChip(
                    icon: Icons.person_outline,
                    label: post.authorName!,
                  ),
                if (post.opportunityDeadline != null)
                  _MetricChip(
                    icon: Icons.schedule,
                    label:
                        '${post.opportunityDeadline!.day}/${post.opportunityDeadline!.month}/${post.opportunityDeadline!.year}',
                  ),
                _MetricChip(
                  icon: Icons.people_outline,
                  label: '${post.joinCount} joined',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('View'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onMessage,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Message'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.roleLecturer,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _toFilePath(String source) {
  return source.startsWith('file://') ? Uri.parse(source).toFilePath() : source;
}

bool _isMyProjectVideoUrl(String url) {
  return isVideoMediaPath(url) || _isExternalMyProjectWebVideo(url);
}

bool _isExternalMyProjectWebVideo(String url) {
  final lower = url.toLowerCase();
  return lower.contains('youtube.com') ||
      lower.contains('youtu.be') ||
      lower.contains('vimeo.com');
}
