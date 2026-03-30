// lib/features/feed/screens/home_feed_screen.dart
//
// MUST StarTrack — Home Feed Screen (Phase 3)
//
// Layout (matches ai_recommendations_feed.html exactly):
//   • Sticky header: greeting + notification bell
//   • Horizontal collaborator suggestions strip
//   • Vertical paginated project cards
//   • Infinite scroll with load-more indicator
//   • Filter chips (All / Projects / Opportunities)
//   • Pull-to-refresh
//
// HCI: Progressive disclosure (collaborators above feed),
//      Chunking (sections), Feedback (optimistic likes),
//      Affordance (FAB for creating posts).

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart';
import 'dart:io';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../core/router/route_guards.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/message_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/recommender_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../shared/screens/offline_video_player_screen.dart';
import '../../shared/widgets/settings_drawer.dart';
import '../bloc/feed_cubit.dart';
import '../../notifications/bloc/notification_cubit.dart';

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  final _scrollCtrl = ScrollController();
  FeedCubit? _cubit;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit ??= context.read<FeedCubit>();
  }

  void _onScroll() {
    if (_cubit == null) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _cubit!.loadMore();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _cubit ?? context.read<FeedCubit>();
    return Scaffold(
      endDrawer: const SettingsDrawer(),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: cubit.refresh,
        child: CustomScrollView(
            controller: _scrollCtrl,
            slivers: [
              // ── Sticky App Bar ───────────────────────────────────────────
              _FeedAppBar(),

              // ── Filter chips ─────────────────────────────────────────────
              SliverToBoxAdapter(child: _FilterChips(cubit: cubit)),

              // ── Collaborator suggestions strip ────────────────────────────
              const SliverToBoxAdapter(child: _CollaboratorStrip()),

              // ── Section header ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_special_rounded,
                          size: 20, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Projects You Might Like',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: () => context.push(RouteNames.discover),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text('View all',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Feed ──────────────────────────────────────────────────────
              BlocBuilder<FeedCubit, FeedState>(
                builder: (ctx, state) {
                  if (state is FeedLoaded) {
                    // Eagerly precache all image URLs so tiles render
                    // instantly as the user scrolls (TikTok-style warm cache).
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!ctx.mounted) return;
                      for (final post in state.posts) {
                        for (final url in post.mediaUrls) {
                          if (!_isVideoUrl(url) && url.startsWith('http')) {
                            precacheImage(
                              CachedNetworkImageProvider(url), ctx);
                          }
                        }
                      }
                    });
                  }
                  if (state is FeedLoading) {
                    return const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (state is FeedError) {
                    return SliverFillRemaining(
                      child: _ErrorView(
                        message: state.message,
                        onRetry: cubit.refresh,
                      ),
                    );
                  }
                  if (state is FeedLoaded) {
                    final isGuest = sl<AuthCubit>().currentUser == null;
                    if (state.posts.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyFeed(isGuest: isGuest),
                      );
                    }
                    final authorGroups = _groupPostsByAuthor(state.posts);
                    // Insert guest CTA after 2nd author group (or at end if
                    // fewer groups exist). ctaAt == -1 means no CTA (authed).
                    final ctaAt = isGuest
                        ? authorGroups.length.clamp(0, 2)
                        : -1;
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          // Inject the branded CTA card at ctaAt slot.
                          if (i == ctaAt) return const _GuestCtaBanner();
                          // Shift group index past the injected CTA slot.
                          final gi = (ctaAt >= 0 && i > ctaAt) ? i - 1 : i;
                          if (gi == authorGroups.length) {
                            return state.isLoadingMore
                                ? const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : state.hasMore
                                    ? const SizedBox(height: 80)
                                    : const _EndOfFeed();
                          }
                          final group = authorGroups[gi];
                          return _AuthorMediaShelf(
                            group: group,
                            onOpenPost: (post) => ctx.push('/project/${post.id}'),
                              onOpenAuthor: () => ctx.push(
                                RouteNames.profile.replaceFirst(':userId', group.authorId),
                              ),
                          );
                        },
                        childCount: authorGroups.length + (ctaAt >= 0 ? 2 : 1),
                      ),
                    );
                  }
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                },
              ),
            ],
          ),
        ),
    );
  }
}

List<_AuthorPostGroup> _groupPostsByAuthor(List<PostModel> posts) {
  final grouped = <String, List<PostModel>>{};
  final orderedAuthorIds = <String>[];

  for (final post in posts) {
    if (!grouped.containsKey(post.authorId)) {
      grouped[post.authorId] = <PostModel>[];
      orderedAuthorIds.add(post.authorId);
    }
    grouped[post.authorId]!.add(post);
  }

  return orderedAuthorIds
      .map((authorId) => _AuthorPostGroup(authorId, grouped[authorId]!))
      .toList();
}

class _AuthorPostGroup {
  final String authorId;
  final List<PostModel> posts;

  const _AuthorPostGroup(this.authorId, this.posts);

  PostModel get leadPost => posts.first;
  String get authorName => leadPost.authorName ?? 'Unknown author';
  String? get authorPhotoUrl => leadPost.authorPhotoUrl;
  List<PostModel> get photoPosts =>
      posts.where((post) => post.mediaUrls.any((url) => !_isVideoUrl(url))).toList();
  List<PostModel> get videoPosts =>
      posts.where((post) => post.mediaUrls.any(_isVideoUrl)).toList();
}

bool _isVideoUrl(String url) {
  return isVideoMediaPath(url);
}

class _AuthorMediaShelf extends StatelessWidget {
  final _AuthorPostGroup group;
  final void Function(PostModel post) onOpenPost;
  final VoidCallback onOpenAuthor;

  const _AuthorMediaShelf({
    required this.group,
    required this.onOpenPost,
    required this.onOpenAuthor,
  });

  @override
  Widget build(BuildContext context) {
    final postRows = (group.posts.length / 2).ceil();
    final postsGridHeight = (postRows * 178.0) + ((postRows - 1) * 12.0) + 30.0;
    final tabViewHeight = postsGridHeight > 228 ? postsGridHeight : 228.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: AppColors.borderLight, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: DefaultTabController(
        length: 3,
        initialIndex: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onOpenAuthor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppDimensions.radiusLg),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.primaryTint10,
                      backgroundImage: group.authorPhotoUrl != null
                          ? CachedNetworkImageProvider(group.authorPhotoUrl!)
                          : null,
                      child: group.authorPhotoUrl == null
                          ? Text(
                              group.authorName.isNotEmpty
                                  ? group.authorName[0].toUpperCase()
                                  : '?',
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
                            group.authorName,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${group.posts.length} posts',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      timeago.format(group.leadPost.createdAt),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondaryLight,
              indicatorColor: AppColors.primary,
              tabs: [
                Tab(text: 'Photos'),
                Tab(text: 'Videos'),
                Tab(text: 'Posts'),
              ],
            ),
            SizedBox(
              height: tabViewHeight,
              child: TabBarView(
                children: [
                  _MediaStrip(
                    posts: group.photoPosts,
                    onOpenPost: onOpenPost,
                    emptyLabel: 'No photos shared yet.',
                    mode: _MediaStripMode.photos,
                  ),
                  _MediaStrip(
                    posts: group.videoPosts,
                    onOpenPost: onOpenPost,
                    emptyLabel: 'No videos shared yet.',
                    mode: _MediaStripMode.videos,
                  ),
                  _PostsGrid(
                    posts: group.posts,
                    onOpenPost: onOpenPost,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostsGrid extends StatelessWidget {
  final List<PostModel> posts;
  final void Function(PostModel post) onOpenPost;

  const _PostsGrid({
    required this.posts,
    required this.onOpenPost,
  });

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Text(
          'No posts yet.',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondaryLight),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 178,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return _MediaShelfTile(
          post: post,
          onTap: () => onOpenPost(post),
          mode: _MediaStripMode.posts,
        );
      },
    );
  }
}

enum _MediaStripMode { photos, videos, posts }

class _MediaStrip extends StatelessWidget {
  final List<PostModel> posts;
  final void Function(PostModel post) onOpenPost;
  final String emptyLabel;
  final _MediaStripMode mode;

  const _MediaStrip({
    required this.posts,
    required this.onOpenPost,
    required this.emptyLabel,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondaryLight),
        ),
      );
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      itemBuilder: (context, index) {
        final post = posts[index];
        return _MediaShelfTile(
          post: post,
          onTap: () {
            if (mode == _MediaStripMode.videos) {
              final videoUrl = post.mediaUrls.where(_isVideoUrl).cast<String?>().firstWhere(
                (_) => true,
                orElse: () => null,
              );
              if (videoUrl != null) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OfflineVideoPlayerScreen(
                      source: videoUrl,
                      title: post.title,
                    ),
                  ),
                );
                return;
              }
            }
            onOpenPost(post);
          },
          mode: mode,
        );
      },
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemCount: posts.length,
    );
  }
}

class _MediaShelfTile extends StatelessWidget {
  final PostModel post;
  final VoidCallback onTap;
  final _MediaStripMode mode;

  const _MediaShelfTile({
    required this.post,
    required this.onTap,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final width = mode == _MediaStripMode.posts ? 220.0 : 180.0;
    final previewUrl = _previewUrl();

    // For horizontal strips (photos/videos) the tile must NOT use Expanded —
    // the parent ListView has unbounded height driven by the Posts-tab height,
    // which causes Expanded to stretch the image absurdly.  Fix: fixed image
    // height for strip modes; Expanded only for the Posts grid (mainAxisExtent
    // already pins each tile to 178 px there).
    final isStrip = mode != _MediaStripMode.posts;
    const stripImageHeight = 120.0;

    final imageChild = ClipRRect(
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: Container(
        color: AppColors.primaryTint10,
        child: previewUrl != null && mode != _MediaStripMode.videos
            ? isLocalMediaPath(previewUrl)
                ? Image.file(
                    File(previewUrl),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => _MediaFallback(mode: mode),
                  )
                : CachedNetworkImage(
                    imageUrl: previewUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorWidget: (_, __, ___) => _MediaFallback(mode: mode),
                    placeholder: (_, __) => Container(
                      color: AppColors.primaryTint10,
                    ),
                  )
            : mode == _MediaStripMode.videos && _videoUrl() != null
                ? _VideoThumbTile(url: _videoUrl()!)
                : _MediaFallback(mode: mode),
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: isStrip ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (isStrip)
              SizedBox(height: stripImageHeight, child: imageChild)
            else
              Expanded(child: imageChild),
            const SizedBox(height: 8),
            Text(
              post.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              post.category ?? post.type,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _previewUrl() {
    if (mode == _MediaStripMode.videos) return null;
    for (final url in post.mediaUrls) {
      if (!_isVideoUrl(url)) return url;
    }
    return null;
  }

  String? _videoUrl() {
    for (final url in post.mediaUrls) {
      if (_isVideoUrl(url)) return url;
    }
    return null;
  }
}

class _VideoThumbTile extends StatefulWidget {
  final String url;
  const _VideoThumbTile({required this.url});

  @override
  State<_VideoThumbTile> createState() => _VideoThumbTileState();
}

class _VideoThumbTileState extends State<_VideoThumbTile> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      // Seek to first frame and pause — shows a real thumbnail, not a black screen.
      await ctrl.seekTo(Duration.zero);
      setState(() {
        _ctrl = ctrl;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) return const _MediaFallback(mode: _MediaStripMode.videos);
    if (!_ready || _ctrl == null) {
      return Container(
        color: AppColors.primaryTint10,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _ctrl!.value.size.width,
            height: _ctrl!.value.size.height,
            child: VideoPlayer(_ctrl!),
          ),
        ),
        Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 26),
          ),
        ),
      ],
    );
  }
}

class _MediaFallback extends StatelessWidget {
  final _MediaStripMode mode;

  const _MediaFallback({required this.mode});

  @override
  Widget build(BuildContext context) {
    final icon = switch (mode) {
      _MediaStripMode.photos => Icons.image_outlined,
      _MediaStripMode.videos => Icons.play_circle_outline_rounded,
      _MediaStripMode.posts => Icons.article_outlined,
    };

    return Center(
      child: Icon(
        icon,
        size: 40,
        color: AppColors.primary,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky app bar
// ─────────────────────────────────────────────────────────────────────────────

class _FeedAppBar extends StatelessWidget {
  String _greetingName() {
    final user = sl<AuthCubit>().currentUser;
    final displayName = user?.displayName?.trim();
    if (displayName == null || displayName.isEmpty) {
      return 'there';
    }
    return displayName.split(' ').first;
  }




  @override
  Widget build(BuildContext context) {
    final greetingName = _greetingName();
    return SliverAppBar(
      floating: true,
      snap: true,
      automaticallyImplyLeading: false,
      actions: const [SizedBox.shrink()],
      backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.92),
      elevation: 0,
      titleSpacing: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Recommended for You',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Sign-in icon — visible only to guests so they always
                    // have a clear path to log in / create an account.
                    BlocBuilder<AuthCubit, AuthState>(
                      builder: (_, authState) {
                        final isGuest = sl<AuthCubit>().currentUser == null;
                        if (!isGuest) return const SizedBox.shrink();
                        return IconButton(
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          padding: EdgeInsets.zero,
                          iconSize: 22,
                          icon: const Icon(
                            Icons.account_circle_outlined,
                            color: AppColors.primary,
                          ),
                          onPressed: () => context.push(RouteNames.login),
                          tooltip: 'Sign in',
                        );
                      },
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 19,
                      icon: BlocBuilder<NotificationCubit, NotificationState>(
                        builder: (_, state) {
                          final unread = state is NotificationsLoaded
                              ? state.unreadCount
                              : 0;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.notifications_outlined),
                              if (unread > 0)
                                Positioned(
                                  right: -4,
                                  top: -4,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.danger,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      unread > 99 ? '99+' : '$unread',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      onPressed: () => context.push(RouteNames.notifications),
                      tooltip: 'Notifications',
                    ),
                    // Hamburger — opens the settings end-drawer
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      icon: const Icon(Icons.menu_rounded),
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                      tooltip: 'Settings',
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Hi $greetingName 👋',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  )),
                Text(
                  'Based on your research interests and skills',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      expandedHeight: 128,
      collapsedHeight: 60,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chips
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final FeedCubit cubit;
  const _FilterChips({required this.cubit});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeedCubit, FeedState>(
      builder: (_, state) {
        final current = state is FeedLoaded ? state.filter : const FeedFilter();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              _Chip(
                label: 'All',
                active: current.type == null,
                onTap: () => cubit.applyFilter(current.copyWith(clearType: true)),
              ),
              _Chip(
                label: 'Projects',
                active: current.type == 'project',
                onTap: () => cubit.applyFilter(current.copyWith(type: 'project')),
              ),
              _Chip(
                label: 'Opportunities',
                active: current.type == 'opportunity',
                onTap: () => cubit.applyFilter(current.copyWith(type: 'opportunity')),
              ),
              if (current.isActive)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ActionChip(
                    label: const Text('Clear'),
                    avatar: const Icon(Icons.close, size: 14),
                    onPressed: cubit.clearFilters,
                    backgroundColor: AppColors.danger.withValues(alpha: 0.10),
                    labelStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: AppColors.danger,
                      fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : AppColors.textSecondaryLight,
        ),
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          side: BorderSide(
            color: active ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collaborator suggestions horizontal strip
// ─────────────────────────────────────────────────────────────────────────────

class _CollaboratorStrip extends StatefulWidget {
  const _CollaboratorStrip();

  @override
  State<_CollaboratorStrip> createState() => _CollaboratorStripState();
}

class _CollaboratorStripState extends State<_CollaboratorStrip> {
  late final Future<List<RecommendedUser>> _future = _loadRecommendations();

  Future<List<RecommendedUser>> _loadRecommendations() async {
    final currentUserId = sl<AuthCubit>().currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      return const [];
    }

    final userDao = sl<UserDao>();
    final currentUser = await userDao.getUserById(currentUserId);
    if (currentUser == null || currentUser.profile == null) {
      return const [];
    }

    final allStudents = await userDao.getAllUsers(
      role: UserRole.student.name,
      includeSuspended: false,
      pageSize: 120,
    );
    final accepted = await sl<MessageDao>().getAcceptedCollaborators(
      userId: currentUserId,
      limit: 100,
    );
    final searchTerms = await sl<ActivityLogDao>().getRecentSearchTerms(
      currentUserId,
    );

    final excludedIds = accepted.map((item) => item.peerId).toSet();
    return sl<RecommenderService>()
        .rankCollaborators(
          currentUser: currentUser,
          candidates: allStudents,
          excludedUserIds: excludedIds,
          recentSearchTerms: searchTerms,
        )
        .take(8)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecommendedUser>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <RecommendedUser>[];
        if (items.isEmpty && snapshot.connectionState == ConnectionState.done) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.group_add_rounded, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('Potential Collaborators',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            SizedBox(
              height: 150,
              child: snapshot.connectionState != ConnectionState.done
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _CollaboratorCard(item: items[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CollaboratorCard extends StatelessWidget {
  final RecommendedUser item;

  const _CollaboratorCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = item.user;
    final name = user.displayName ?? user.email;
    final skill = item.matchedSkills.isNotEmpty
        ? item.matchedSkills.first
        : (user.profile?.skills.isNotEmpty == true
            ? user.profile!.skills.first
            : 'Student');
    return Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 0.8,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryTint10,
            backgroundImage: user.photoUrl != null
                ? CachedNetworkImageProvider(user.photoUrl!)
                : null,
            child: user.photoUrl == null
                ? Text(
                    name[0].toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => context.push(RouteNames.profile.replaceFirst(':userId', user.id)),
            child: Text(name,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryTint10,
              borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
            ),
            child: Text(skill,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.primary),
              maxLines: 1),
          ),
          const SizedBox(height: 6),
          Text(
            item.reasons.contains('complementary_skills')
                ? 'Strong complement'
                : 'Shared interests',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              color: AppColors.textSecondaryLight,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Utility widgets
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyFeed extends StatelessWidget {
  final bool isGuest;
  const _EmptyFeed({this.isGuest = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isGuest ? Icons.explore_rounded : Icons.search_off_rounded,
              size: 64,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              isGuest ? 'Discover MUST Projects' : 'No posts yet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isGuest
                  ? 'Projects are loading. Pull down to refresh, or join the community to collaborate.'
                  : 'Be the first to share a project!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppColors.textSecondaryLight,
              ),
              textAlign: TextAlign.center,
            ),
            if (isGuest) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => context.push(RouteNames.registerStep1),
                    child: const Text('Create Account'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => context.push(RouteNames.login),
                    child: const Text('Sign In'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.danger),
              const SizedBox(height: 16),
              Text('Could not load feed', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                message,
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textSecondaryLight),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndOfFeed extends StatelessWidget {
  const _EndOfFeed();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text("You're all caught up! ✨",
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14, color: AppColors.textSecondaryLight)),
      ),
    );
  }
}

// ── Guest call-to-action banner ────────────────────────────────────────────────
// Shown between the 2nd and 3rd author groups for unauthenticated visitors.
// Mirrors the login hero gradient, giving a consistent brand feel.

class _GuestCtaBanner extends StatelessWidget {
  const _GuestCtaBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D3FA8), Color(0xFF1152D4), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Join MUST StarTrack',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Like projects, collaborate with peers, and showcase your skills to the entire MUST community.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => context.push(RouteNames.registerStep1),
                    child: Text(
                      'Create Account',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white60, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => context.push(RouteNames.login),
                    child: Text(
                      'Sign In',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.white,
                      ),
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

