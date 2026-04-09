import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
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
import '../../shared/screens/offline_video_player_screen.dart';
import '../../shared/widgets/guest_auth_required_view.dart';

enum _MyProjectsFilter { all, active, opportunities, applied, archived }

class MyProjectsScreen extends StatefulWidget {
  const MyProjectsScreen({super.key});

  @override
  State<MyProjectsScreen> createState() => _MyProjectsScreenState();
}

class _MyProjectsScreenState extends State<MyProjectsScreen> {
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
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) {
      setState(() {
        _loading = false;
        _posts = const [];
        _error = 'Sign in to manage your posts.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

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
        return _posts.where((p) => p.type == 'opportunity' && !p.isArchived).toList();
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
            Text(
              'Manage everything you have posted: update titles, descriptions, media, archive older work, or remove posts you no longer want visible.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textSecondary(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _MyProjectsFilter.values.map((filter) {
                final selected = _filter == filter;
                return ChoiceChip(
                  label: Text(_filterLabel(filter)),
                  selected: selected,
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700),
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
    final cover = post.mediaUrls.isNotEmpty ? post.mediaUrls.first : null;
    final isVideo = cover != null && isVideoMediaPath(cover);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: cover == null
                ? onOpen
                : () {
                    if (isVideo) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OfflineVideoPlayerScreen(
                            source: cover,
                            title: post.title,
                          ),
                        ),
                      );
                    } else {
                      onOpen();
                    }
                  },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLg)),
            child: Container(
              height: 170,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.primaryTint10,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLg)),
              ),
              child: cover == null
                  ? const Icon(Icons.perm_media_rounded, size: 40, color: AppColors.primary)
                  : isVideo
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: Colors.black12),
                            const Center(
                              child: Icon(Icons.play_circle_fill_rounded, size: 54, color: Colors.white),
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLg)),
                          child: isLocalMediaPath(cover)
                              ? Image.file(File(_toFilePath(cover)), fit: BoxFit.cover)
                              : Image.network(cover, fit: BoxFit.cover),
                        ),
            ),
          ),
          Padding(
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
                        style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(post: post),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  post.description?.trim().isNotEmpty == true
                      ? post.description!
                      : 'No description yet.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppColors.textSecondary(context),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricChip(icon: Icons.thumb_up_alt_outlined, label: '${post.likeCount} likes'),
                    _MetricChip(icon: Icons.comment_outlined, label: '${post.commentCount} comments'),
                    _MetricChip(icon: Icons.visibility_outlined, label: '${post.viewCount} views'),
                    if (post.type == 'opportunity')
                      _MetricChip(icon: Icons.people_outline, label: '${post.joinCount} applicants'),
                    _MetricChip(icon: Icons.schedule_rounded, label: timeago.format(post.updatedAt)),
                  ],
                ),
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
                        side: BorderSide(color: AppColors.roleLecturer.withValues(alpha: 0.4)),
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
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                        label: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.post});

  final PostModel post;

  @override
  Widget build(BuildContext context) {
    final isArchived = post.isArchived;
    final background = isArchived ? AppColors.warning.withValues(alpha: 0.14) : AppColors.success.withValues(alpha: 0.14);
    final foreground = isArchived ? AppColors.warning : AppColors.success;
    final label = isArchived ? 'Archived' : (post.type == 'opportunity' ? 'Opportunity' : 'Live');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: foreground),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primaryTint10,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600),
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
    final isExpired = post.opportunityDeadline != null &&
        post.opportunityDeadline!.isBefore(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: AppColors.roleLecturer.withValues(alpha: 0.25),
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
