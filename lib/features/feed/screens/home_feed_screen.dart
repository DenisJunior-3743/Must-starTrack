// lib/features/feed/screens/home_feed_screen.dart
//
// MUST StarTrack — Home Feed Screen (Phase 4 — Immersive Redesign)
//
// Tabs:
//   • Videos   → Full-height vertical PageView, TikTok/Shorts style
//   • Photos   → Featured card + staggered 2-col grid, Instagram/Facebook style
//   • Showcase → Rich info cards for text-only posts
//
// Unchanged: sticky app bar, filter chips (All/Projects/Opp), collaborator
// strip, FeedCubit wiring, infinite scroll, pull-to-refresh, guest CTA.
//
// Actions per post: Like, Dislike, Comment, Share, Follow, More (Report,
// View Details, View Author Profile).

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_guards.dart';
import '../../../core/router/route_names.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../core/utils/video_cache_utils.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/message_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/recommender_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../notifications/bloc/notification_cubit.dart';
import '../../shared/widgets/settings_drawer.dart';
import '../bloc/feed_cubit.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

bool _isVideoUrl(String url) {
  if (isVideoMediaPath(url)) return true;
  final lower = url.toLowerCase();
  if (RegExp(r'\.(mp4|mov|m4v|3gp|webm|mkv)(\?|$)').hasMatch(lower)) {
    return true;
  }
  return lower.contains('/videos/') || lower.contains('video/upload');
}

enum _PostKind { video, photo, showcase }

_PostKind _kindOf(PostModel post) {
  if (post.mediaUrls.any(_isVideoUrl)) return _PostKind.video;
  if (post.youtubeUrl != null && post.youtubeUrl!.trim().isNotEmpty) {
    return _PostKind.video;
  }
  if (post.mediaUrls.any((u) => !_isVideoUrl(u))) return _PostKind.photo;
  return _PostKind.showcase;
}

bool _photoRailHintShown = false;
bool _collabRailHintShown = false;

String _titleCaseName(String value) {
  final parts = value
      .split(RegExp(r'\s+'))
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';
  return parts
      .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

String _bestDisplayName({String? displayName, String? email, String? userId}) {
  final cleanDisplay = displayName?.trim() ?? '';
  if (cleanDisplay.isNotEmpty) return cleanDisplay;

  final local = (email ?? '').split('@').first.trim();
  if (local.isNotEmpty) {
    final normalized = local.replaceAll(RegExp(r'[_\-.]+'), ' ');
    final title = _titleCaseName(normalized);
    if (title.isNotEmpty) return title;
    return local;
  }

  final id = userId?.trim() ?? '';
  if (id.isEmpty) return 'Student';
  if (id.contains('-') || id.contains('_')) {
    final normalized = id.replaceAll(RegExp(r'[_\-.]+'), ' ');
    final title = _titleCaseName(normalized);
    if (title.isNotEmpty) return title;
  }
  return id.length > 8 ? '${id.substring(0, 8)}…' : id;
}

// ─────────────────────────────────────────────────────────────────────────────
// Root screen
// ─────────────────────────────────────────────────────────────────────────────

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _photoScrollCtrl = ScrollController();
  final _showcaseScrollCtrl = ScrollController();
  FeedCubit? _cubit;
  bool _controlsCollapsed = false;
  bool _immersiveMode = false;

  @override
  void initState() {
    super.initState();
    // Videos is index 0 — default
    _tabCtrl = TabController(length: 3, vsync: this, initialIndex: 0);
    _photoScrollCtrl.addListener(_onPhotoScroll);
    _showcaseScrollCtrl.addListener(_onShowcaseScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit ??= context.read<FeedCubit>();
  }

  void _onPhotoScroll() => _tryLoadMore(_photoScrollCtrl);
  void _onShowcaseScroll() => _tryLoadMore(_showcaseScrollCtrl);

  void _tryLoadMore(ScrollController c) {
    if (_cubit == null) return;
    if (c.position.pixels >= c.position.maxScrollExtent - 400) {
      _cubit!.loadMore();
    }
  }

  void _handleContentScrollDirection(ScrollDirection direction) {
    if (!mounted) return;
    if (_immersiveMode) return;
    if (direction == ScrollDirection.reverse && !_controlsCollapsed) {
      setState(() => _controlsCollapsed = true);
    } else if (direction == ScrollDirection.forward && _controlsCollapsed) {
      setState(() => _controlsCollapsed = false);
    }
  }

  void _toggleImmersiveMode() {
    if (!mounted) return;
    setState(() {
      _immersiveMode = !_immersiveMode;
      _controlsCollapsed = _immersiveMode;
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _photoScrollCtrl.dispose();
    _showcaseScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _cubit ?? context.read<FeedCubit>();
    return Scaffold(
      endDrawer: const SettingsDrawer(),
      body: Stack(
        children: [
          Column(
            children: [
              if (!_immersiveMode) const _StaticFeedHeader(),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: (_controlsCollapsed || _immersiveMode)
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          _FilterChips(cubit: cubit),
                          const _CollaboratorStrip(),
                          _ContentTabBar(tabCtrl: _tabCtrl),
                        ],
                      ),
              ),
              Expanded(
                child: BlocBuilder<FeedCubit, FeedState>(
                  builder: (ctx, state) {
                    if (state is FeedLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is FeedError) {
                      return _ErrorView(
                        message: state.message,
                        onRetry: cubit.refresh,
                      );
                    }
                    if (state is FeedLoaded) {
                      final isGuest = sl<AuthCubit>().currentUser == null;

                      final videoPosts = state.posts
                          .where((p) => _kindOf(p) == _PostKind.video)
                          .toList();
                      final photoPosts = state.posts
                          .where((p) => _kindOf(p) == _PostKind.photo)
                          .toList();
                      final showcasePosts = state.posts
                          .where((p) => _kindOf(p) == _PostKind.showcase)
                          .toList();

                      if (state.posts.isEmpty) {
                        return RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: cubit.refresh,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.35),
                              _EmptyFeed(isGuest: isGuest),
                            ],
                          ),
                        );
                      }

                      return RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: cubit.refresh,
                        child: TabBarView(
                          controller: _tabCtrl,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _VideoFeedTab(
                              posts: videoPosts,
                              cubit: cubit,
                              isGuest: isGuest,
                              isLoadingMore: state.isLoadingMore,
                              hasMore: state.hasMore,
                              onScrollDirectionChanged:
                                  _handleContentScrollDirection,
                            ),
                            _PhotoFeedTab(
                              posts: photoPosts,
                              cubit: cubit,
                              isGuest: isGuest,
                              scrollCtrl: _photoScrollCtrl,
                              isLoadingMore: state.isLoadingMore,
                              hasMore: state.hasMore,
                              onScrollDirectionChanged:
                                  _handleContentScrollDirection,
                            ),
                            _ShowcaseFeedTab(
                              posts: showcasePosts,
                              cubit: cubit,
                              isGuest: isGuest,
                              scrollCtrl: _showcaseScrollCtrl,
                              isLoadingMore: state.isLoadingMore,
                              hasMore: state.hasMore,
                              onScrollDirectionChanged:
                                  _handleContentScrollDirection,
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
          if (_controlsCollapsed && !_immersiveMode)
            Positioned(
              top: MediaQuery.of(context).padding.top + 72,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() => _controlsCollapsed = false),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusFull),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Show tabs & filters',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            right: 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                onTap: _toggleImmersiveMode,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusFull),
                  ),
                  child: Icon(
                    _immersiveMode
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Content tab bar
// ─────────────────────────────────────────────────────────────────────────────

class _ContentTabBar extends StatelessWidget {
  final TabController tabCtrl;
  const _ContentTabBar({required this.tabCtrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: TabBar(
        controller: tabCtrl,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondaryLight,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2.5,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        tabs: const [
          Tab(icon: Icon(Icons.play_circle_outline_rounded, size: 18), text: 'Videos'),
          Tab(icon: Icon(Icons.photo_library_outlined, size: 18), text: 'Photos'),
          Tab(icon: Icon(Icons.article_outlined, size: 18), text: 'Showcase'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIDEO TAB — TikTok / YouTube Shorts style
// ─────────────────────────────────────────────────────────────────────────────

class _VideoFeedTab extends StatefulWidget {
  final List<PostModel> posts;
  final FeedCubit cubit;
  final bool isGuest;
  final bool isLoadingMore;
  final bool hasMore;
  final ValueChanged<ScrollDirection>? onScrollDirectionChanged;

  const _VideoFeedTab({
    required this.posts,
    required this.cubit,
    required this.isGuest,
    required this.isLoadingMore,
    required this.hasMore,
    this.onScrollDirectionChanged,
  });

  @override
  State<_VideoFeedTab> createState() => _VideoFeedTabState();
}

class _VideoFeedTabState extends State<_VideoFeedTab> {
  final _pageCtrl = PageController();
  int _currentPage = 0;
  int _lastHapticPage = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl.addListener(() {
      final page = _pageCtrl.page?.round() ?? 0;
      if (page != _currentPage) {
        setState(() => _currentPage = page);
        if (page != _lastHapticPage) {
          HapticFeedback.selectionClick();
          _lastHapticPage = page;
        }
        // Load more when near end
        if (page >= widget.posts.length - 3 && widget.hasMore) {
          widget.cubit.loadMore();
        }
      }
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) {
      return const _EmptyTab(
        icon: Icons.videocam_off_outlined,
        label: 'No videos yet',
        sublabel: 'Videos posted by the community will appear here.',
      );
    }

    final total = widget.posts.length +
        (widget.isLoadingMore ? 1 : 0) +
        (!widget.hasMore && widget.posts.isNotEmpty ? 1 : 0);

    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (n) {
            widget.onScrollDirectionChanged?.call(n.direction);
            return false;
          },
          child: PageView.builder(
            controller: _pageCtrl,
            scrollDirection: Axis.vertical,
            physics: const BouncingScrollPhysics(),
            itemCount: total,
            itemBuilder: (ctx, i) {
              if (i == widget.posts.length) {
                if (widget.isLoadingMore) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.primary));
                }
                return const _EndOfFeed();
              }
              final post = widget.posts[i];
              return AnimatedBuilder(
                animation: _pageCtrl,
                child: _VideoPage(
                  post: post,
                  isActive: i == _currentPage,
                  isGuest: widget.isGuest,
                  cubit: widget.cubit,
                ),
                builder: (context, child) {
                  double page = _currentPage.toDouble();
                  if (_pageCtrl.hasClients && _pageCtrl.position.haveDimensions) {
                    page = _pageCtrl.page ?? _currentPage.toDouble();
                  }
                  final distance = (page - i).abs();
                  final t = distance.clamp(0.0, 1.0).toDouble();
                  final scale = 1 - (0.06 * t);
                  final opacity = 1 - (0.22 * t);
                  final translateY = 22 * t;
                  return Transform.translate(
                    offset: Offset(0, translateY),
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(opacity: opacity, child: child),
                    ),
                  );
                },
              );
            },
          ),
        ),
        // Page counter badge
        if (widget.posts.isNotEmpty)
          Positioned(
            top: 12,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
              ),
              child: Text(
                '${(_currentPage + 1).clamp(1, widget.posts.length)} / ${widget.posts.length}',
                style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}

class _VideoPage extends StatefulWidget {
  final PostModel post;
  final bool isActive;
  final bool isGuest;
  final FeedCubit cubit;

  const _VideoPage({
    required this.post,
    required this.isActive,
    required this.isGuest,
    required this.cubit,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _error = false;
  bool _isMuted = false;
  double? _downloadProgress;   // null = not downloading; 0-1 = in progress
  int? _myRating;

  String? get _videoUrl {
    for (final u in widget.post.mediaUrls) {
      if (_isVideoUrl(u)) return u;
    }
    final youtube = widget.post.youtubeUrl?.trim();
    if (youtube != null && youtube.isNotEmpty && _isVideoUrl(youtube)) {
      return youtube;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _initController();
    _loadMyRating();
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl?.play();
    } else if (!widget.isActive && old.isActive) {
      _ctrl?.pause();
    }
    if (widget.post.id != old.post.id) {
      _ctrl?.dispose();
      _ctrl = null;
      _ready = false;
      _error = false;
      _downloadProgress = null;
      _initController();
      _myRating = null;
      _loadMyRating();
    }
  }

  Future<void> _loadMyRating() async {
    final uid = sl<AuthCubit>().currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    final rating = await sl<ActivityLogDao>().getMyLatestPostRating(
      userId: uid,
      postId: widget.post.id,
    );
    if (!mounted) return;
    setState(() => _myRating = rating);
  }

  Future<void> _initController() async {
    final rawUrl = _videoUrl;
    if (rawUrl == null) {
      if (mounted) setState(() => _error = true);
      return;
    }

    // Apply Cloudinary H.264 transform when applicable
    final url = getPreferredPlaybackSource(rawUrl);

    try {
      VideoPlayerController ctrl;

      if (isLocalMediaPath(url)) {
        // Local file – play directly
        final localPath = url.startsWith('file://')
            ? Uri.parse(url).toFilePath(windows: Platform.isWindows)
            : url;
        ctrl = VideoPlayerController.file(File(localPath));
      } else {
        // Check for an existing local cache
        final cachedFile = await getCachedVideoFile(url);
        final hasCache = cachedFile != null &&
            await cachedFile.exists() &&
            await cachedFile.length() > 1024;

        if (hasCache) {
          debugPrint('[VideoPage] playing from cache: ${cachedFile.path}');
          // ignore: unnecessary_non_null_assertion
          ctrl = VideoPlayerController.file(cachedFile);
        } else {
          // No cache yet – stream from network and download in bakground
          debugPrint('[VideoPage] no cache, streaming:$url');
          ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
          unawaited(_downloadInBackground(url));
        }
      }

      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      ctrl.setLooping(true);
      if (widget.isActive) ctrl.play();
      setState(() {
        _ctrl = ctrl;
        _ready = true;
      });
    } catch (e) {
      debugPrint('[VideoPage] init error url=$url: $e');
      if (mounted) setState(() => _error = true);
    }
  }

  /// Downloads [url] to the local cache in the background while playback
  /// continues from the network stream. On the next view the cached file is used.
  Future<void> _downloadInBackground(String url) async {
    try {
      await resolveVideoFile(
        url,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _downloadProgress = received / total);
        },
      );
      if (mounted) {
        setState(() {
          _downloadProgress = null;
        });
      }
      debugPrint('[VideoPage] background cache complete: $url');
    } catch (e) {
      debugPrint('[VideoPage] background download failed: $e');
      if (mounted) setState(() => _downloadProgress = null);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return GestureDetector(
      onTap: () {
        // Toggle play/pause on tap
        if (_ctrl == null) return;
        if (_ctrl!.value.isPlaying) {
          _ctrl!.pause();
        } else {
          _ctrl!.play();
        }
        setState(() {});
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video background ─────────────────────────────────────────────
          Container(color: Colors.black),
          if (_error)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle_outline_rounded,
                      color: Colors.white54, size: 64),
                  const SizedBox(height: 8),
                  Text('Video unavailable',
                      style: GoogleFonts.plusJakartaSans(
                          color: Colors.white54, fontSize: 13)),
                ],
              ),
            )
          else if (!_ready)
            const Center(
                child: CircularProgressIndicator(color: Colors.white54))
          else
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _ctrl!.value.size.width,
                height: _ctrl!.value.size.height,
                child: VideoPlayer(_ctrl!),
              ),
            ),

          // ── Pause indicator ───────────────────────────────────────────────
          if (_ready &&
              _ctrl != null &&
              !_ctrl!.value.isPlaying &&
              !_error)
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 36),
              ),
            ),

          // ── Bottom gradient overlay ───────────────────────────────────────
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45, 1.0],
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),

          // ── Bottom info overlay ───────────────────────────────────────────
          Positioned(
            left: 0,
            right: 72,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Author row
                  GestureDetector(
                    onTap: () => context.push(
                      RouteNames.profile
                          .replaceFirst(':userId', post.authorId),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.primaryTint10,
                          backgroundImage: post.authorPhotoUrl != null
                              ? CachedNetworkImageProvider(post.authorPhotoUrl!)
                              : null,
                          child: post.authorPhotoUrl == null
                              ? Text(
                                  (post.authorName ?? '?')[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            post.authorName ?? 'Unknown',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!widget.isGuest)
                          _SmallFollowButton(post: post),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    post.title,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (post.description != null &&
                      post.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      post.description!,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (post.category != null)
                        _TagChip(post.category!, color: AppColors.primary),
                      ...post.tags
                          .take(3)
                          .map((t) => _TagChip(t, color: Colors.white30)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeago.format(post.createdAt),
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Right-side action column ───────────────────────────────────────
          Positioned(
            right: 8,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _VideoActionBtn(
                  icon: post.isLikedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: _compact(post.likeCount),
                  color: post.isLikedByMe ? Colors.red : Colors.white,
                  onTap: () => widget.isGuest
                      ? _promptLogin(context)
                      : widget.cubit.likePost(post.id),
                ),
                const SizedBox(height: 16),
                _VideoActionBtn(
                  icon: post.isDislikedByMe
                      ? Icons.thumb_down_rounded
                      : Icons.thumb_down_outlined,
                  label: _compact(post.dislikeCount),
                  color:
                      post.isDislikedByMe ? AppColors.primary : Colors.white,
                  onTap: () => widget.isGuest
                      ? _promptLogin(context)
                      : widget.cubit.dislikePost(post.id),
                ),
                const SizedBox(height: 16),
                _VideoActionBtn(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: _compact(post.commentCount),
                  color: Colors.white,
                  onTap: () => context.push('/project/${post.id}'),
                ),
                const SizedBox(height: 16),
                _VideoActionBtn(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  color: Colors.white,
                  onTap: () => Share.share(
                    '${post.title}\n\n${post.description ?? ''}\n\nShared from MUST StarTrack',
                    subject: post.title,
                  ),
                ),
                const SizedBox(height: 16),
                _VideoActionBtn(
                  icon: Icons.star_border_rounded,
                  label: _myRating == null ? 'Rate' : '${_myRating!}★',
                  color: Colors.white,
                  onTap: () => widget.isGuest
                      ? _promptLogin(context)
                      : _showRatePostSheet(
                          context,
                          post,
                          widget.cubit,
                          initialStars: _myRating ?? 0,
                          onRated: (stars) {
                            if (!mounted) return;
                            setState(() => _myRating = stars);
                          },
                        ),
                ),
                const SizedBox(height: 16),
                _VideoActionBtn(
                  icon: Icons.more_vert_rounded,
                  label: 'More',
                  color: Colors.white,
                  onTap: () => _showMoreSheet(context, post, widget.cubit,
                      widget.isGuest),
                ),
                const SizedBox(height: 16),
                // Mute toggle
                _VideoActionBtn(
                  icon: _isMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  label: _isMuted ? 'Unmute' : 'Mute',
                  color: Colors.white,
                  onTap: () {
                    setState(() {
                      _isMuted = !_isMuted;
                      _ctrl?.setVolume(_isMuted ? 0 : 1);
                    });
                  },
                ),
              ],
            ),
          ),

          // ── Type badge ─────────────────────────────────────────────────────
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: post.type == 'opportunity'
                    ? AppColors.mustGreen
                    : AppColors.primary,
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusFull),
              ),
              child: Text(
                post.type == 'opportunity' ? 'Opportunity' : 'Project',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          // ── Background-download progress indicator ────────────────────────
          if (_downloadProgress != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _downloadProgress,
                minHeight: 2,
                backgroundColor: Colors.white24,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PHOTO TAB — Instagram / Facebook style
// ─────────────────────────────────────────────────────────────────────────────

enum _PhotoDisplayStyle { mixed, grid }

class _PhotoFeedTab extends StatefulWidget {
  final List<PostModel> posts;
  final FeedCubit cubit;
  final bool isGuest;
  final ScrollController scrollCtrl;
  final bool isLoadingMore;
  final bool hasMore;
  final ValueChanged<ScrollDirection>? onScrollDirectionChanged;

  const _PhotoFeedTab({
    required this.posts,
    required this.cubit,
    required this.isGuest,
    required this.scrollCtrl,
    required this.isLoadingMore,
    required this.hasMore,
    this.onScrollDirectionChanged,
  });

  @override
  State<_PhotoFeedTab> createState() => _PhotoFeedTabState();
}

class _PhotoFeedTabState extends State<_PhotoFeedTab> {
  _PhotoDisplayStyle _displayStyle = _PhotoDisplayStyle.mixed;

  List<PostModel> get _recentFirst {
    final sorted = [...widget.posts];
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Photos · Most recent first',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Mixed display',
            onPressed: () => setState(() => _displayStyle = _PhotoDisplayStyle.mixed),
            icon: Icon(
              Icons.view_stream_rounded,
              size: 20,
              color: _displayStyle == _PhotoDisplayStyle.mixed
                  ? AppColors.primary
                  : AppColors.textSecondaryLight,
            ),
          ),
          IconButton(
            tooltip: 'Grid display',
            onPressed: () => setState(() => _displayStyle = _PhotoDisplayStyle.grid),
            icon: Icon(
              Icons.grid_view_rounded,
              size: 20,
              color: _displayStyle == _PhotoDisplayStyle.grid
                  ? AppColors.primary
                  : AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    if (widget.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.hasMore ? const SizedBox(height: 80) : const _EndOfFeed();
  }

  Widget _buildGrid(List<PostModel> posts) {
    final children = <Widget>[_buildToolbar()];

    children.add(
      _FeaturedPhotoCard(post: posts.first, cubit: widget.cubit, isGuest: widget.isGuest),
    );

    for (var i = 1; i < posts.length; i += 2) {
      final left = posts[i];
      final right = (i + 1 < posts.length) ? posts[i + 1] : null;
      children.add(
        _PhotoGridRow(
          left: left,
          right: right,
          cubit: widget.cubit,
          isGuest: widget.isGuest,
        ),
      );
    }

    children.add(_buildFooter());

    return NotificationListener<UserScrollNotification>(
      onNotification: (n) {
        widget.onScrollDirectionChanged?.call(n.direction);
        return false;
      },
      child: ListView(
        controller: widget.scrollCtrl,
        padding: const EdgeInsets.only(bottom: 24),
        children: children,
      ),
    );
  }

  Widget _buildMixed(List<PostModel> posts) {
    final grouped = <String, List<PostModel>>{};
    for (final p in posts) {
      grouped.putIfAbsent(p.authorId, () => <PostModel>[]).add(p);
    }

    final renderedRailAuthors = <String>{};
    final sections = <Widget>[_buildToolbar()];

    for (final post in posts) {
      final authorPosts = grouped[post.authorId] ?? const <PostModel>[];
      if (authorPosts.length > 1) {
        if (renderedRailAuthors.add(post.authorId)) {
          sections.add(
            _AuthorPhotoRail(posts: authorPosts),
          );
        }
      } else {
        sections.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: _SinglePhotoPostCard(
              post: post,
              cubit: widget.cubit,
              isGuest: widget.isGuest,
            ),
          ),
        );
      }
    }

    sections.add(_buildFooter());

    return NotificationListener<UserScrollNotification>(
      onNotification: (n) {
        widget.onScrollDirectionChanged?.call(n.direction);
        return false;
      },
      child: ListView(
        controller: widget.scrollCtrl,
        padding: const EdgeInsets.only(bottom: 24),
        children: sections,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) {
      return const _EmptyTab(
        icon: Icons.hide_image_outlined,
        label: 'No photo posts yet',
        sublabel: 'Photo projects will appear here.',
      );
    }

    final posts = _recentFirst;
    if (_displayStyle == _PhotoDisplayStyle.grid) return _buildGrid(posts);
    return _buildMixed(posts);
  }
}

class _AuthorPhotoRail extends StatefulWidget {
  final List<PostModel> posts;

  const _AuthorPhotoRail({
    required this.posts,
  });

  @override
  State<_AuthorPhotoRail> createState() => _AuthorPhotoRailState();
}

class _AuthorPhotoRailState extends State<_AuthorPhotoRail> {
  late final PageController _pageCtrl;
  int _currentIndex = 0;
  bool _showSwipeHint = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.86);
    if (widget.posts.length > 1 && !_photoRailHintShown) {
      _photoRailHintShown = true;
      _showSwipeHint = true;
      _hintTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showSwipeHint = false);
      });
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authorName = widget.posts.first.authorName ?? 'Unknown';
    final authorId = widget.posts.first.authorId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => context.push(
                  RouteNames.profile.replaceFirst(':userId', authorId),
                ),
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    authorName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.posts.length} photo${widget.posts.length == 1 ? '' : 's'}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: AppColors.textSecondaryLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 244,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageCtrl,
                  padEnds: false,
                  itemCount: widget.posts.length,
                  onPageChanged: (i) => setState(() => _currentIndex = i),
                  itemBuilder: (context, i) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _AuthorPhotoCard(post: widget.posts[i]),
                    );
                  },
                ),
                Positioned(
                  right: 14,
                  top: 10,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _showSwipeHint ? 1 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusFull,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.swipe_left_alt_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Swipe',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.posts.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.posts.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _currentIndex ? 14 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _currentIndex
                          ? AppColors.primary
                          : AppColors.borderLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AuthorPhotoCard extends StatelessWidget {
  final PostModel post;

  const _AuthorPhotoCard({
    required this.post,
  });

  String? get _photoUrl {
    for (final u in post.mediaUrls) {
      if (!_isVideoUrl(u)) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/project/${post.id}'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppDimensions.radiusMd),
              ),
              child: SizedBox(
                height: 128,
                width: double.infinity,
                child: _PhotoWidget(url: _photoUrl, radius: 0),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
              child: Text(
                post.title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (post.description != null && post.description!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
                child: Text(
                  post.description!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.favorite_border_rounded,
                    size: 14,
                    color: AppColors.textSecondaryLight,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _compact(post.likeCount),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 14,
                    color: AppColors.textSecondaryLight,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _compact(post.commentCount),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeago.format(post.createdAt),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: AppColors.textHintLight,
                    ),
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

class _SinglePhotoPostCard extends StatelessWidget {
  final PostModel post;
  final FeedCubit cubit;
  final bool isGuest;

  const _SinglePhotoPostCard({
    required this.post,
    required this.cubit,
    required this.isGuest,
  });

  String? get _photoUrl {
    for (final u in post.mediaUrls) {
      if (!_isVideoUrl(u)) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/project/${post.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: _AuthorRow(post: post, cubit: cubit, isGuest: isGuest),
            ),
            SizedBox(
              height: 220,
              width: double.infinity,
              child: _PhotoWidget(url: _photoUrl, radius: 0),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                post.title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (post.description != null && post.description!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Text(
                  post.description!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            _PostActionBar(post: post, cubit: cubit, isGuest: isGuest),
          ],
        ),
      ),
    );
  }
}

class _FeaturedPhotoCard extends StatelessWidget {
  final PostModel post;
  final FeedCubit cubit;
  final bool isGuest;

  const _FeaturedPhotoCard({
    required this.post,
    required this.cubit,
    required this.isGuest,
  });

  String? get _photoUrl {
    for (final u in post.mediaUrls) {
      if (!_isVideoUrl(u)) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final url = _photoUrl;
    return GestureDetector(
      onTap: () => context.push('/project/${post.id}'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: _AuthorRow(post: post, cubit: cubit, isGuest: isGuest),
            ),
            // Full-width image
            SizedBox(
              height: 320,
              width: double.infinity,
              child: _PhotoWidget(url: url, radius: 0),
            ),
            // Title + description
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (post.description != null &&
                      post.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      post.description!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: AppColors.textSecondaryLight,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (post.category != null)
                        _TagChip(post.category!,
                            color: AppColors.primary, dark: false),
                    ],
                  ),
                ],
              ),
            ),
            // Action bar
            _PostActionBar(post: post, cubit: cubit, isGuest: isGuest),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

class _PhotoGridRow extends StatelessWidget {
  final PostModel left;
  final PostModel? right;
  final FeedCubit cubit;
  final bool isGuest;

  const _PhotoGridRow({
    required this.left,
    required this.right,
    required this.cubit,
    required this.isGuest,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _PhotoGridCell(post: left, cubit: cubit, isGuest: isGuest)),
            const SizedBox(width: 6),
            Expanded(
              child: right != null
                  ? _PhotoGridCell(post: right!, cubit: cubit, isGuest: isGuest)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoGridCell extends StatelessWidget {
  final PostModel post;
  final FeedCubit cubit;
  final bool isGuest;

  const _PhotoGridCell({
    required this.post,
    required this.cubit,
    required this.isGuest,
  });

  String? get _photoUrl {
    for (final u in post.mediaUrls) {
      if (!_isVideoUrl(u)) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/project/${post.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppDimensions.radiusMd)),
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: _PhotoWidget(url: _photoUrl, radius: 0),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(
                post.title,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (post.category != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Text(
                  post.category!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Row(
                children: [
                  const Icon(Icons.favorite_border_rounded,
                      size: 14, color: AppColors.textSecondaryLight),
                  const SizedBox(width: 3),
                  Text(
                    _compact(post.likeCount),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: AppColors.textSecondaryLight),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.chat_bubble_outline_rounded,
                      size: 14, color: AppColors.textSecondaryLight),
                  const SizedBox(width: 3),
                  Text(
                    _compact(post.commentCount),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: AppColors.textSecondaryLight),
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

// ─────────────────────────────────────────────────────────────────────────────
// SHOWCASE TAB — rich info cards for text-only posts
// ─────────────────────────────────────────────────────────────────────────────

class _ShowcaseFeedTab extends StatelessWidget {
  final List<PostModel> posts;
  final FeedCubit cubit;
  final bool isGuest;
  final ScrollController scrollCtrl;
  final bool isLoadingMore;
  final bool hasMore;
  final ValueChanged<ScrollDirection>? onScrollDirectionChanged;

  const _ShowcaseFeedTab({
    required this.posts,
    required this.cubit,
    required this.isGuest,
    required this.scrollCtrl,
    required this.isLoadingMore,
    required this.hasMore,
    this.onScrollDirectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const _EmptyTab(
        icon: Icons.description_outlined,
        label: 'No showcase posts yet',
        sublabel: 'Text-based projects and opportunities will appear here.',
      );
    }

    final ctaAt = isGuest ? posts.length.clamp(0, 2) : -1;
    final itemCount = posts.length + (ctaAt >= 0 ? 2 : 1);

    return NotificationListener<UserScrollNotification>(
      onNotification: (n) {
        onScrollDirectionChanged?.call(n.direction);
        return false;
      },
      child: ListView.builder(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: itemCount,
        itemBuilder: (ctx, i) {
          if (i == ctaAt) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: _GuestCtaBanner(),
            );
          }
          final gi = (ctaAt >= 0 && i > ctaAt) ? i - 1 : i;
          if (gi == posts.length) {
            if (isLoadingMore) {
              return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()));
            }
            return hasMore ? const SizedBox(height: 80) : const _EndOfFeed();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ShowcaseCard(
                post: posts[gi], cubit: cubit, isGuest: isGuest),
          );
        },
      ),
    );
  }
}

class _ShowcaseCard extends StatelessWidget {
  final PostModel post;
  final FeedCubit cubit;
  final bool isGuest;

  const _ShowcaseCard({
    required this.post,
    required this.cubit,
    required this.isGuest,
  });

  // Category → accent color mapping
  static Color _accentFor(String? category) {
    if (category == null) return AppColors.primary;
    final c = category.toLowerCase();
    if (c.contains('innov')) return const Color(0xFF7C3AED);
    if (c.contains('tech') || c.contains('software') || c.contains('ai')) {
      return AppColors.primary;
    }
    if (c.contains('health') || c.contains('bio')) {
      return AppColors.mustGreen;
    }
    if (c.contains('art') || c.contains('design')) {
      return const Color(0xFFDB2777);
    }
    if (c.contains('business') || c.contains('finance')) {
      return AppColors.mustGold;
    }
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(post.category);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => context.push('/project/${post.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coloured accent top bar + type badge
            Container(
              height: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppDimensions.radiusLg)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author row + type badge
                  Row(
                    children: [
                      Expanded(
                          child: _AuthorRow(
                              post: post, cubit: cubit, isGuest: isGuest)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: post.type == 'opportunity'
                              ? AppColors.mustGreenLight
                              : AppColors.primaryTint10,
                          borderRadius: BorderRadius.circular(
                              AppDimensions.radiusFull),
                        ),
                        child: Text(
                          post.type == 'opportunity'
                              ? 'Opportunity'
                              : 'Project',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: post.type == 'opportunity'
                                ? AppColors.mustGreen
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Title
                  Text(
                    post.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (post.description != null &&
                      post.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      post.description!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: AppColors.textSecondaryLight,
                        height: 1.45,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Skills/tags chips
                  if (post.skillsUsed.isNotEmpty || post.tags.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ...post.skillsUsed
                            .take(3)
                            .map((s) => _TagChip(s,
                                color: accent, dark: false)),
                        ...post.tags
                            .take(2)
                            .map((t) => _TagChip(t, dark: false)),
                      ],
                    ),
                  if (post.opportunityDeadline != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 13,
                            color: AppColors.textSecondaryLight),
                        const SizedBox(width: 4),
                        Text(
                          'Deadline: ${_formatDate(post.opportunityDeadline!)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    timeago.format(post.createdAt),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: AppColors.textHintLight),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _PostActionBar(post: post, cubit: cubit, isGuest: isGuest),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Author row: avatar, name, time ago, optional follow button
class _AuthorRow extends StatelessWidget {
  final PostModel post;
  final FeedCubit cubit;
  final bool isGuest;

  const _AuthorRow(
      {required this.post, required this.cubit, required this.isGuest});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(
        RouteNames.profile.replaceFirst(':userId', post.authorId),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryTint10,
            backgroundImage: post.authorPhotoUrl != null
                ? CachedNetworkImageProvider(post.authorPhotoUrl!)
                : null,
            child: post.authorPhotoUrl == null
                ? Text(
                    (post.authorName ?? '?')[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.authorName ?? 'Unknown',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  timeago.format(post.createdAt),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          if (!isGuest) _SmallFollowButton(post: post),
        ],
      ),
    );
  }
}

/// Horizontal action bar: Like, Dislike, Comment, Share, More
class _PostActionBar extends StatefulWidget {
  final PostModel post;
  final FeedCubit cubit;
  final bool isGuest;

  const _PostActionBar({
    required this.post,
    required this.cubit,
    required this.isGuest,
  });

  @override
  State<_PostActionBar> createState() => _PostActionBarState();
}

class _PostActionBarState extends State<_PostActionBar> {
  int? _myRating;

  @override
  void initState() {
    super.initState();
    _loadMyRating();
  }

  @override
  void didUpdateWidget(covariant _PostActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _myRating = null;
      _loadMyRating();
    }
  }

  Future<void> _loadMyRating() async {
    final uid = sl<AuthCubit>().currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    final rating = await sl<ActivityLogDao>().getMyLatestPostRating(
      userId: uid,
      postId: widget.post.id,
    );
    if (!mounted) return;
    setState(() => _myRating = rating);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      child: Row(
        children: [
          // Like
          _ActionBarBtn(
            icon: widget.post.isLikedByMe
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: _compact(widget.post.likeCount),
            color: widget.post.isLikedByMe ? Colors.red : AppColors.textSecondaryLight,
            onTap: () => widget.isGuest
                ? _promptLogin(context)
                : widget.cubit.likePost(widget.post.id),
          ),
          // Dislike
          _ActionBarBtn(
            icon: widget.post.isDislikedByMe
                ? Icons.thumb_down_rounded
                : Icons.thumb_down_outlined,
            label: _compact(widget.post.dislikeCount),
            color: widget.post.isDislikedByMe
                ? AppColors.primary
                : AppColors.textSecondaryLight,
            onTap: () => widget.isGuest
                ? _promptLogin(context)
                : widget.cubit.dislikePost(widget.post.id),
          ),
          // Comment
          _ActionBarBtn(
            icon: Icons.chat_bubble_outline_rounded,
            label: _compact(widget.post.commentCount),
            color: AppColors.textSecondaryLight,
            onTap: () => context.push('/project/${widget.post.id}'),
          ),
          // Share
          _ActionBarBtn(
            icon: Icons.share_rounded,
            label: 'Share',
            color: AppColors.textSecondaryLight,
            onTap: () => Share.share(
              '${widget.post.title}\n\n${widget.post.description ?? ''}\n\nShared from MUST StarTrack',
              subject: widget.post.title,
            ),
          ),
          // Rate
          _ActionBarBtn(
            icon: Icons.star_border_rounded,
            label: _myRating == null ? 'Rate' : '${_myRating!}★',
            color: AppColors.textSecondaryLight,
            onTap: () => widget.isGuest
                ? _promptLogin(context)
                : _showRatePostSheet(
                    context,
                    widget.post,
                    widget.cubit,
                    initialStars: _myRating ?? 0,
                    onRated: (stars) {
                      if (!mounted) return;
                      setState(() => _myRating = stars);
                    },
                  ),
          ),
          const Spacer(),
          // More (Report / Details / Profile)
          IconButton(
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            icon: const Icon(Icons.more_horiz_rounded,
                color: AppColors.textSecondaryLight),
            onPressed: () =>
                _showMoreSheet(context, widget.post, widget.cubit, widget.isGuest),
          ),
        ],
      ),
    );
  }
}

/// Inline follow button for video overlay
class _SmallFollowButton extends StatefulWidget {
  final PostModel post;
  const _SmallFollowButton({required this.post});

  @override
  State<_SmallFollowButton> createState() => _SmallFollowButtonState();
}

class _SmallFollowButtonState extends State<_SmallFollowButton> {
  bool _following = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_following) return;
        _showFollowSheet(context, widget.post, () {
          setState(() => _following = true);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _following ? Colors.white24 : Colors.white,
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        ),
        child: Text(
          _following ? 'Following' : '+ Follow',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _following ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

/// Photo display widget — handles local paths, network, and fallback
class _PhotoWidget extends StatelessWidget {
  final String? url;
  final double radius;

  const _PhotoWidget({required this.url, required this.radius});

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return Container(
        color: AppColors.primaryTint10,
        child: const Center(
          child: Icon(Icons.image_outlined, color: AppColors.primary, size: 40),
        ),
      );
    }
    final child = isLocalMediaPath(url!)
        ? Image.file(File(url!), fit: BoxFit.cover, width: double.infinity,
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.primaryTint10,
              child: const Center(
                  child: Icon(Icons.image_outlined,
                      color: AppColors.primary, size: 40)),
            ))
        : CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (_, __) =>
                Container(color: AppColors.primaryTint10),
            errorWidget: (_, __, ___) => Container(
              color: AppColors.primaryTint10,
              child: const Center(
                  child: Icon(Icons.image_outlined,
                      color: AppColors.primary, size: 40)),
            ),
          );

    return radius > 0
        ? ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: child,
          )
        : child;
  }
}

/// Small colour tag chip
class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool dark;

  const _TagChip(this.label,
      {this.color = AppColors.textSecondaryLight, this.dark = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: dark ? Colors.white24 : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: dark ? Colors.white : color,
        ),
      ),
    );
  }
}

/// Action bar icon+label button
class _ActionBarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBarBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Video overlay action button (icon + caption)
class _VideoActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _VideoActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheets
// ─────────────────────────────────────────────────────────────────────────────

void _showMoreSheet(
    BuildContext context, PostModel post, FeedCubit cubit, bool isGuest) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _MoreSheet(
        post: post, cubit: cubit, isGuest: isGuest, parentCtx: context),
  );
}

void _showRatePostSheet(
  BuildContext context,
  PostModel post,
  FeedCubit cubit, {
  int initialStars = 0,
  ValueChanged<int>? onRated,
}) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _RatePostSheet(
      post: post,
      cubit: cubit,
      initialStars: initialStars,
      onRated: onRated,
    ),
  );
}

class _RatePostSheet extends StatefulWidget {
  final PostModel post;
  final FeedCubit cubit;
  final int initialStars;
  final ValueChanged<int>? onRated;

  const _RatePostSheet({
    required this.post,
    required this.cubit,
    this.initialStars = 0,
    this.onRated,
  });

  @override
  State<_RatePostSheet> createState() => _RatePostSheetState();
}

class _RatePostSheetState extends State<_RatePostSheet> {
  int _stars = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _stars = widget.initialStars.clamp(0, 5);
  }

  @override
  Widget build(BuildContext context) {
    final isLecturer = sl<AuthCubit>().currentUser?.role == UserRole.lecturer;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Rate this post',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.post.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final filled = index < _stars;
                return IconButton(
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _stars = index + 1),
                  icon: Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    color: filled ? AppColors.warning : AppColors.borderLight,
                    size: 34,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _stars == 0
                    ? 'Select 1 to 5 stars'
                    : 'You selected $_stars star${_stars == 1 ? '' : 's'}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ),
            if (isLecturer) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint10,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Lecturer ratings currently influence recommendation ranking more heavily.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: (_stars == 0 || _submitting)
                        ? null
                        : () async {
                            setState(() => _submitting = true);
                            await widget.cubit.ratePost(post: widget.post, stars: _stars);
                          widget.onRated?.call(_stars);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Thanks! Your rating was recorded.',
                                  style: GoogleFonts.plusJakartaSans(),
                                ),
                              ),
                            );
                          },
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Submit Rating'),
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

class _MoreSheet extends StatelessWidget {
  final PostModel post;
  final FeedCubit cubit;
  final bool isGuest;
  final BuildContext parentCtx;

  const _MoreSheet({
    required this.post,
    required this.cubit,
    required this.isGuest,
    required this.parentCtx,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded,
                  color: AppColors.primary),
              title: Text('View Details',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                parentCtx.push('/project/${post.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined,
                  color: AppColors.primary),
              title: Text('View Author Profile',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                parentCtx.push(RouteNames.profile
                    .replaceFirst(':userId', post.authorId));
              },
            ),
            if (!isGuest)
              ListTile(
                leading:
                    const Icon(Icons.person_add_alt_1_rounded,
                        color: AppColors.primary),
                title: Text('Follow Author',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _showFollowSheet(parentCtx, post, () {});
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppColors.danger),
              title: Text('Report Suspicious Content',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger)),
              onTap: () {
                Navigator.pop(context);
                if (isGuest) {
                  _promptLogin(parentCtx);
                } else {
                  _showReportSheet(parentCtx, post);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

void _showFollowSheet(
    BuildContext context, PostModel post, VoidCallback onConfirmed) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _FollowSheet(
        post: post, onConfirmed: onConfirmed, parentCtx: context),
  );
}

class _FollowSheet extends StatefulWidget {
  final PostModel post;
  final VoidCallback onConfirmed;
  final BuildContext parentCtx;

  const _FollowSheet({
    required this.post,
    required this.onConfirmed,
    required this.parentCtx,
  });

  @override
  State<_FollowSheet> createState() => _FollowSheetState();
}

class _FollowSheetState extends State<_FollowSheet> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.primaryTint10,
              backgroundImage: widget.post.authorPhotoUrl != null
                  ? CachedNetworkImageProvider(widget.post.authorPhotoUrl!)
                  : null,
              child: widget.post.authorPhotoUrl == null
                  ? Text(
                      (widget.post.authorName ?? '?')[0].toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 24),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              'Follow ${widget.post.authorName ?? 'this author'}?',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 17, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'You\'ll receive updates on their new projects and posts.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: AppColors.textSecondaryLight),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _loading
                        ? null
                        : () async {
                            setState(() => _loading = true);
                            // Queue follow via sync — no direct DAO method
                            // required here; activity log captures the intent
                            try {
                              await sl<ActivityLogDao>().logAction(
                                userId:
                                    sl<AuthCubit>().currentUser?.id ?? '',
                                action: 'follow_user',
                                entityType: 'users',
                                entityId: widget.post.authorId,
                                metadata: {
                                  'author_name':
                                      widget.post.authorName ?? '',
                                },
                              );
                            } catch (_) {}
                            if (context.mounted) Navigator.pop(context);
                            widget.onConfirmed();
                          },
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Follow'),
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

void _showReportSheet(BuildContext context, PostModel post) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ReportSheet(post: post, parentCtx: context),
  );
}

class _ReportSheet extends StatefulWidget {
  final PostModel post;
  final BuildContext parentCtx;

  const _ReportSheet({required this.post, required this.parentCtx});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _reasons = [
    'Stolen / plagiarised project',
    'Inappropriate content',
    'Spam or misleading',
    'Fake project data',
    'Other',
  ];
  String? _selected;
  final _noteCtrl = TextEditingController();
  bool _loading = false;
  bool _submitted = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: _submitted ? _submitted_() : _form(),
        ),
      ),
    );
  }

  Widget _submitted_() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded,
            color: AppColors.mustGreen, size: 56),
        const SizedBox(height: 12),
        Text('Report submitted',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'Thank you. Our moderation team will review this post.',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: AppColors.textSecondaryLight),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }

  Widget _form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            const Icon(Icons.flag_outlined, color: AppColors.danger, size: 20),
            const SizedBox(width: 8),
            Text(
              'Report Content',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '"${widget.post.title}"',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppColors.textSecondaryLight,
              fontStyle: FontStyle.italic),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 14),
        Text('Reason',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: _selected,
          onChanged: (v) => setState(() => _selected = v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _reasons
                .map((r) => RadioListTile<String>(
                      value: r,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(r,
                          style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                      activeColor: AppColors.primary,
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Additional notes (optional)',
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: AppColors.textHintLight),
            border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusSm)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger),
                onPressed: (_selected == null || _loading)
                    ? null
                    : () async {
                        setState(() => _loading = true);
                        try {
                          await sl<ActivityLogDao>().logAction(
                            userId:
                                sl<AuthCubit>().currentUser?.id ?? '',
                            action: 'report_post',
                            entityType: 'posts',
                            entityId: widget.post.id,
                            metadata: {
                              'reason': _selected!,
                              'note': _noteCtrl.text.trim(),
                              'post_title': widget.post.title,
                              'author_id': widget.post.authorId,
                            },
                          );
                        } catch (_) {}
                        if (mounted) setState(() => _submitted = true);
                      },
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Submit'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

void _promptLogin(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Sign in to interact with posts',
          style: GoogleFonts.plusJakartaSans()),
      action: SnackBarAction(
        label: 'Sign In',
        onPressed: () => context.push(RouteNames.login),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Utility
// ─────────────────────────────────────────────────────────────────────────────

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

// ─────────────────────────────────────────────────────────────────────────────
// Static header (non-scrollable)
// ─────────────────────────────────────────────────────────────────────────────

class _StaticFeedHeader extends StatelessWidget {
  const _StaticFeedHeader();

  String _greetingName() {
    final user = sl<AuthCubit>().currentUser;
    final displayName = user?.displayName?.trim();
    if (displayName == null || displayName.isEmpty) return 'there';
    return displayName.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final greetingName = _greetingName();
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.96),
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                  BlocBuilder<AuthCubit, AuthState>(
                    builder: (_, authState) {
                      final isGuest = sl<AuthCubit>().currentUser == null;
                      if (!isGuest) return const SizedBox.shrink();
                      return IconButton(
                        constraints: const BoxConstraints.tightFor(
                            width: 34, height: 34),
                        padding: EdgeInsets.zero,
                        iconSize: 22,
                        icon: const Icon(Icons.account_circle_outlined,
                            color: AppColors.primary),
                        onPressed: () => context.push(RouteNames.login),
                        tooltip: 'Sign in',
                      );
                    },
                  ),
                  IconButton(
                    constraints:
                        const BoxConstraints.tightFor(width: 34, height: 34),
                    padding: EdgeInsets.zero,
                    iconSize: 19,
                    icon: BlocBuilder<NotificationCubit, NotificationState>(
                      builder: (_, state) {
                        final unread =
                            state is NotificationsLoaded ? state.unreadCount : 0;
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
                                      minWidth: 16, minHeight: 16),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
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
                  Builder(
                    builder: (ctx) => IconButton(
                      constraints:
                          const BoxConstraints.tightFor(width: 34, height: 34),
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      icon: const Icon(Icons.menu_rounded),
                      onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                      tooltip: 'Settings',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Hi $greetingName 👋',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chips (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final FeedCubit cubit;
  const _FilterChips({required this.cubit});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeedCubit, FeedState>(
      builder: (_, state) {
        final current =
            state is FeedLoaded ? state.filter : const FeedFilter();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              _Chip(
                label: 'All',
                active: current.type == null,
                onTap: () =>
                    cubit.applyFilter(current.copyWith(clearType: true)),
              ),
              _Chip(
                label: 'Projects',
                active: current.type == 'project',
                onTap: () =>
                    cubit.applyFilter(current.copyWith(type: 'project')),
              ),
              _Chip(
                label: 'Opportunities',
                active: current.type == 'opportunity',
                onTap: () => cubit
                    .applyFilter(current.copyWith(type: 'opportunity')),
              ),
              if (current.isActive)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ActionChip(
                    label: const Text('Clear'),
                    avatar: const Icon(Icons.close, size: 14),
                    onPressed: cubit.clearFilters,
                    backgroundColor:
                        AppColors.danger.withValues(alpha: 0.10),
                    labelStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.danger,
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

  const _Chip(
      {required this.label, required this.active, required this.onTap});

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
          borderRadius:
              BorderRadius.circular(AppDimensions.radiusFull),
          side: BorderSide(
            color: active ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collaborator strip (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _CollaboratorStrip extends StatefulWidget {
  const _CollaboratorStrip();

  @override
  State<_CollaboratorStrip> createState() => _CollaboratorStripState();
}

class _CollaboratorStripState extends State<_CollaboratorStrip> {
  late final Future<List<RecommendedUser>> _future = _loadRecommendations();
  PageController? _pageCtrl;
  int _currentIndex = 0;
  bool _showSwipeHint = false;
  bool _collapsed = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.70);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _pageCtrl?.dispose();
    super.dispose();
  }

  Future<List<RecommendedUser>> _loadRecommendations() async {
    final currentUserId = sl<AuthCubit>().currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) return const [];

    final userDao = sl<UserDao>();
    final currentUser = await userDao.getUserById(currentUserId);
    if (currentUser == null || currentUser.profile == null) return const [];

    final allStudents = await userDao.getAllUsers(
      role: UserRole.student.name,
      includeSuspended: false,
      pageSize: 120,
    );
    final accepted = await sl<MessageDao>().getAcceptedCollaborators(
      userId: currentUserId,
      limit: 100,
    );
    final searchTerms =
        await sl<ActivityLogDao>().getRecentSearchTerms(currentUserId);

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
    final pageCtrl = _pageCtrl ??= PageController(viewportFraction: 0.70);

    return FutureBuilder<List<RecommendedUser>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <RecommendedUser>[];
        if (items.isEmpty &&
            snapshot.connectionState == ConnectionState.done) {
          return const SizedBox.shrink();
        }

        if (snapshot.connectionState == ConnectionState.done &&
            items.length > 1 &&
            !_collabRailHintShown) {
          _collabRailHintShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _showSwipeHint = true);
            _hintTimer?.cancel();
            _hintTimer = Timer(const Duration(seconds: 2), () {
              if (mounted) setState(() => _showSwipeHint = false);
            });
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.group_add_rounded,
                          size: 20, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Potential Collaborators',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: _collapsed
                            ? 'Show suggestions'
                            : 'Hide suggestions',
                        onPressed: () => setState(() => _collapsed = !_collapsed),
                        icon: Icon(
                          _collapsed
                              ? Icons.expand_more_rounded
                              : Icons.expand_less_rounded,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items.length > 1
                        ? 'Swipe sideways to browse strong matches.'
                        : 'A strong match based on skills and shared interests.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.textSecondaryLight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (_collapsed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint10,
                      borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                    ),
                    child: Text(
                      '${items.length} suggestion${items.length == 1 ? '' : 's'} hidden',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              )
            else
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 176,
                        child: snapshot.connectionState != ConnectionState.done
                            ? const Center(child: CircularProgressIndicator())
                            : Stack(
                                children: [
                                  PageView.builder(
                                    controller: pageCtrl,
                                    padEnds: false,
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: items.length,
                                    onPageChanged: (i) => setState(() => _currentIndex = i),
                                    itemBuilder: (_, i) {
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          left: i == 0 ? 16 : 6,
                                          right: i == items.length - 1 ? 16 : 6,
                                        ),
                                        child: AnimatedBuilder(
                                          animation: pageCtrl,
                                          child: _CollaboratorCard(item: items[i]),
                                          builder: (context, child) {
                                            double page = _currentIndex.toDouble();
                                            if (pageCtrl.hasClients &&
                                                pageCtrl.position.haveDimensions) {
                                              page = pageCtrl.page ?? _currentIndex.toDouble();
                                            }
                                            final distance = (page - i).abs().clamp(0.0, 1.0);
                                            final scale = 1 - (0.04 * distance);
                                            final opacity = 1 - (0.14 * distance);
                                            return Transform.scale(
                                              scale: scale,
                                              child: Opacity(opacity: opacity, child: child),
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                  Positioned(
                                    right: 22,
                                    top: 8,
                                    child: IgnorePointer(
                                      child: AnimatedOpacity(
                                        opacity: _showSwipeHint ? 1 : 0,
                                        duration: const Duration(milliseconds: 220),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius: BorderRadius.circular(
                                              AppDimensions.radiusFull,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.swipe_left_alt_rounded,
                                                color: Colors.white,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Swipe',
                                                style: GoogleFonts.plusJakartaSans(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      if (snapshot.connectionState == ConnectionState.done && items.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              items.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: i == _currentIndex ? 16 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i == _currentIndex
                                      ? AppColors.primary
                                      : AppColors.borderLight,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
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
    final name = _bestDisplayName(
      displayName: user.displayName,
      email: user.email,
      userId: user.id,
    );
    final fitPercent = (item.score * 100).round();
    final skill = item.matchedSkills.isNotEmpty
        ? item.matchedSkills.first
        : (user.profile?.skills.isNotEmpty == true
            ? user.profile!.skills.first
            : 'Student');
    return Container(
      width: double.infinity,
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
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryTint10,
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
              ),
              child: Text(
                '$fitPercent% fit',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          CircleAvatar(
            radius: 22,
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
          const SizedBox(height: 4),
          InkWell(
            onTap: () => context.push(
                RouteNames.profile.replaceFirst(':userId', user.id)),
            child: Text(
              name,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryTint10,
              borderRadius:
                  BorderRadius.circular(AppDimensions.radiusFull),
            ),
            child: Text(
              skill,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.reasons.contains('complementary_skills')
                ? 'Strong complement'
                : 'Shared interests',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 9, color: AppColors.textSecondaryLight),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
            child: LinearProgressIndicator(
              value: item.score.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.primary.withValues(alpha: 0.10),
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / error states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;

  const _EmptyTab(
      {required this.icon, required this.label, required this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(sublabel,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppColors.textSecondaryLight),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

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
                    onPressed: () =>
                        context.push(RouteNames.registerStep1),
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
              const Icon(Icons.wifi_off_rounded,
                  size: 56, color: AppColors.danger),
              const SizedBox(height: 16),
              Text('Could not load feed',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight),
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
        child: Text(
          "You're all caught up! ✨",
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14, color: AppColors.textSecondaryLight),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Guest CTA banner (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _GuestCtaBanner extends StatelessWidget {
  const _GuestCtaBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 4),
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
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 20),
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
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () =>
                        context.push(RouteNames.registerStep1),
                    child: Text(
                      'Create Account',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(
                          color: Colors.white60, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => context.push(RouteNames.login),
                    child: Text(
                      'Sign In',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.white),
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
