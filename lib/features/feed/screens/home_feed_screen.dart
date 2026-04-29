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
// Video actions per post: Profile/Follow, Like, Comment, Bookmark, More
// (Share, Report, View Details, View Author Profile).

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/app_route_observer.dart';
import '../../../core/router/route_guards.dart';
import '../../../core/router/route_names.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../core/utils/video_cache_utils.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/comment_dao.dart';
import '../../../data/local/dao/faculty_dao.dart';
import '../../../data/local/dao/message_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/recommender_service.dart';
import '../../../data/remote/sync_service.dart';
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

bool _isAdvertPost(PostModel post) => post.type == 'advert';

String _postTypeLabel(PostModel post) {
  switch (post.type) {
    case 'opportunity':
      return 'Opportunity';
    case 'advert':
      return 'Advert';
    default:
      return 'Project';
  }
}

Color _postTypeAccent(PostModel post) {
  return AppColors.mustGoldDark;
}

Color _postTypeTint(PostModel post) {
  return AppColors.mustGold.withValues(alpha: 0.2);
}

List<PostModel> _rankAdvertsForViewerFaculty(
  List<PostModel> adverts, {
  String? viewerFaculty,
}) {
  if (adverts.isEmpty) return const [];

  final normalizedViewer = viewerFaculty?.trim().toLowerCase();
  final sorted = [...adverts]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  if (normalizedViewer == null || normalizedViewer.isEmpty) {
    return sorted;
  }

  final matched = <PostModel>[];
  final global = <PostModel>[];
  final others = <PostModel>[];

  for (final advert in sorted) {
    final faculties = advert.faculties.map((f) => f.toLowerCase()).toSet();
    if (faculties.contains(normalizedViewer)) {
      matched.add(advert);
    } else if (faculties.contains('all faculties') ||
        faculties.contains('all')) {
      global.add(advert);
    } else {
      others.add(advert);
    }
  }

  return [...matched, ...global, ...others];
}

List<PostModel> _injectAdsIntoStream({
  required List<PostModel> content,
  required List<PostModel> adverts,
  int every = 5,
}) {
  if (content.isEmpty || adverts.isEmpty || every <= 0) {
    return content;
  }

  final injected = <PostModel>[];
  var adIndex = 0;

  for (var i = 0; i < content.length; i++) {
    injected.add(content[i]);
    if ((i + 1) % every == 0) {
      injected.add(adverts[adIndex % adverts.length]);
      adIndex++;
    }
  }

  return injected;
}

bool _photoRailHintShown = false;
bool _collabRailHintShown = false;

bool _isGroupPost(PostModel post) {
  final groupId = post.groupId?.trim() ?? '';
  return groupId.isNotEmpty;
}

String _titleCaseName(String value) {
  final parts = value
      .split(RegExp(r'\s+'))
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';
  return parts
      .map((part) =>
          '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
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
  static final ValueNotifier<bool> searchActive = ValueNotifier<bool>(false);

  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  final _photoScrollCtrl = ScrollController();
  final _showcaseScrollCtrl = ScrollController();
  FeedCubit? _cubit;
  bool _controlsCollapsed = true;
  bool _isSearching = false;
  final bool _immersiveMode = false;

  void _openInlineSearch() {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _controlsCollapsed = true;
    });
    HomeFeedScreen.searchActive.value = true;
  }

  void _closeInlineSearch() {
    if (!mounted) return;
    setState(() => _isSearching = false);
    HomeFeedScreen.searchActive.value = false;
  }

  @override
  void initState() {
    super.initState();
    // Videos is index 0 — default
    _tabCtrl = TabController(length: 3, vsync: this, initialIndex: 0);
    _tabCtrl.addListener(_onTabChanged);
    _photoScrollCtrl.addListener(_onPhotoScroll);
    _showcaseScrollCtrl.addListener(_onShowcaseScroll);
  }

  void _onTabChanged() {
    if (!mounted || _tabCtrl.indexIsChanging || _immersiveMode) return;
    setState(() => _controlsCollapsed = _tabCtrl.index == 0);
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

  @override
  void dispose() {
    HomeFeedScreen.searchActive.value = false;
    _searchCtrl.dispose();
    _tabCtrl.removeListener(_onTabChanged);
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
              if (!_immersiveMode)
                _StaticFeedHeader(
                  isSearching: _isSearching,
                  searchCtrl: _searchCtrl,
                  onSearchTap: _openInlineSearch,
                  onCloseSearch: _closeInlineSearch,
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: (_controlsCollapsed || _immersiveMode || _isSearching)
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
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
                      final scopedPosts = state.filter.groupsOnly
                          ? state.posts
                              .where(_isGroupPost)
                              .toList(growable: false)
                          : state.posts;

                      final advertPool = scopedPosts
                          .where(_isAdvertPost)
                          .toList(growable: false);
                      final contentPool = state.filter.type == 'advert'
                          ? advertPool
                          : scopedPosts
                              .where((post) => !_isAdvertPost(post))
                              .toList(growable: false);

                      final viewerFaculty =
                          sl<AuthCubit>().currentUser?.profile?.faculty;
                      final rankedAdverts = _rankAdvertsForViewerFaculty(
                        advertPool,
                        viewerFaculty: viewerFaculty,
                      );

                      final rawVideoPosts = contentPool
                          .where((p) => _kindOf(p) == _PostKind.video)
                          .toList();
                      final rawPhotoPosts = contentPool
                          .where((p) => _kindOf(p) == _PostKind.photo)
                          .toList();
                      final rawShowcasePosts = contentPool
                          .where((p) => _kindOf(p) == _PostKind.showcase)
                          .toList();

                      final shouldInjectAds = state.filter.type != 'advert' &&
                          !state.filter.groupsOnly;

                      final videoAds = rankedAdverts
                          .where((p) => _kindOf(p) == _PostKind.video)
                          .toList(growable: false);
                      final photoAds = rankedAdverts
                          .where((p) => _kindOf(p) == _PostKind.photo)
                          .toList(growable: false);

                      final videoPosts = shouldInjectAds
                          ? _injectAdsIntoStream(
                              content: rawVideoPosts,
                              adverts: videoAds,
                              every: 5)
                          : rawVideoPosts;
                      final photoPosts = shouldInjectAds
                          ? _injectAdsIntoStream(
                              content: rawPhotoPosts,
                              adverts: photoAds,
                              every: 5)
                          : rawPhotoPosts;
                      final showcasePosts = rawShowcasePosts;

                      if (_isSearching) {
                        return _InlineFeedSearchView(
                          posts: state.posts,
                          cubit: cubit,
                          searchCtrl: _searchCtrl,
                        );
                      }

                      if (contentPool.isEmpty) {
                        return Stack(
                          children: [
                            RefreshIndicator(
                              color: AppColors.primary,
                              onRefresh: cubit.refresh,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                              0.28),
                                  if (state.filter.isActive) ...[
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 32),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.search_off_rounded,
                                                size: 56,
                                                color: AppColors.primary),
                                            const SizedBox(height: 14),
                                            Text(
                                              state.filter.searchedUserName !=
                                                      null
                                                  ? 'No posts from "${state.filter.searchedUserName}"'
                                                  : state.filter.followingOnly
                                                      ? 'No posts from people you follow'
                                                      : state.filter.faculty !=
                                                              null
                                                          ? 'No posts in "${state.filter.faculty}"'
                                                          : 'No posts match your filters',
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Try a different filter or clear to see all posts.',
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                      fontSize: 13,
                                                      color: AppColors
                                                          .textSecondaryLight),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 20),
                                            FilledButton.icon(
                                              onPressed: cubit.clearFilters,
                                              icon: const Icon(
                                                  Icons.clear_all_rounded,
                                                  size: 18),
                                              label:
                                                  const Text('Clear filters'),
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ] else
                                    _EmptyFeed(
                                      isGuest: isGuest,
                                      groupsOnly: state.filter.groupsOnly,
                                    ),
                                ],
                              ),
                            ),
                            if (!_isSearching)
                              Positioned(
                                top: _immersiveMode
                                    ? MediaQuery.of(context).padding.top + 4
                                    : 4,
                                left: 8,
                                right: 8,
                                child: _FilterChips(
                                  cubit: cubit,
                                  currentTabIndex: _tabCtrl.index,
                                  tabsCollapsed: _controlsCollapsed,
                                  onToggleTabs: () => setState(
                                    () => _controlsCollapsed =
                                        !_controlsCollapsed,
                                  ),
                                ),
                              ),
                          ],
                        );
                      }

                      return Stack(
                        children: [
                          RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: cubit.refresh,
                            child: TabBarView(
                              controller: _tabCtrl,
                              physics: const BouncingScrollPhysics(),
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
                          ),
                          if (!_isSearching)
                            Positioned(
                              top: _immersiveMode
                                  ? MediaQuery.of(context).padding.top + 4
                                  : 4,
                              left: 8,
                              right: 8,
                              child: _FilterChips(
                                cubit: cubit,
                                currentTabIndex: _tabCtrl.index,
                                tabsCollapsed: _controlsCollapsed,
                                onToggleTabs: () => setState(
                                  () =>
                                      _controlsCollapsed = !_controlsCollapsed,
                                ),
                              ),
                            ),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
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
          Tab(
              icon: Icon(Icons.play_circle_outline_rounded, size: 18),
              text: 'Videos'),
          Tab(
              icon: Icon(Icons.photo_library_outlined, size: 18),
              text: 'Photos'),
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
  final Set<String> _prefetchingSources = <String>{};
  int _currentPage = 0;
  int _lastHapticPage = 0;

  Future<void> _onRefresh() async {
    await widget.cubit.refresh();
    if (!mounted) return;
    setState(() {
      _currentPage = 0;
      _lastHapticPage = 0;
    });
    if (_pageCtrl.hasClients) {
      _pageCtrl.jumpToPage(0);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefetchAround(0);
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _prefetchAround(int currentIndex) {
    const lookAhead = 2;
    for (var offset = 0; offset <= lookAhead; offset++) {
      final index = currentIndex + offset;
      if (index < 0 || index >= widget.posts.length) continue;

      final post = widget.posts[index];
      final source = _preferredVideoSourceForPost(post);
      if (source == null || !_prefetchingSources.add(source)) continue;

      unawaited(() async {
        try {
          await resolveVideoFile(source);
        } catch (e) {
          debugPrint('[VideoPrefetch] failed for $source: $e');
        } finally {
          _prefetchingSources.remove(source);
        }
      }());
    }
  }

  String? _preferredVideoSourceForPost(PostModel post) {
    for (final mediaUrl in post.mediaUrls) {
      if (_isVideoUrl(mediaUrl)) {
        return getPreferredPlaybackSource(mediaUrl);
      }
    }
    final youtube = post.youtubeUrl?.trim();
    if (youtube != null && youtube.isNotEmpty && _isVideoUrl(youtube)) {
      return getPreferredPlaybackSource(youtube);
    }
    return null;
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
        RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          triggerMode: RefreshIndicatorTriggerMode.onEdge,
          child: NotificationListener<UserScrollNotification>(
            onNotification: (n) {
              widget.onScrollDirectionChanged?.call(n.direction);
              return false;
            },
            child: PageView.builder(
              controller: _pageCtrl,
              scrollDirection: Axis.vertical,
              dragStartBehavior: DragStartBehavior.down,
              allowImplicitScrolling: true,
              physics: const _SoftPagePhysics(
                parent: BouncingScrollPhysics(),
              ),
              itemCount: total,
              onPageChanged: (page) {
                if (page == _currentPage) return;
                setState(() => _currentPage = page);
                _prefetchAround(page);
                if (page != _lastHapticPage) {
                  HapticFeedback.selectionClick();
                  _lastHapticPage = page;
                }
                if (page >= widget.posts.length - 3 && widget.hasMore) {
                  widget.cubit.loadMore();
                }
              },
              itemBuilder: (ctx, i) {
                if (i == widget.posts.length) {
                  if (widget.isLoadingMore) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary));
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
                    if (_pageCtrl.hasClients &&
                        _pageCtrl.position.haveDimensions) {
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
        ),
      ],
    );
  }
}

class _SoftPagePhysics extends PageScrollPhysics {
  const _SoftPagePhysics({super.parent});

  @override
  _SoftPagePhysics applyTo(ScrollPhysics? ancestor) {
    return _SoftPagePhysics(parent: buildParent(ancestor));
  }

  // Use very soft thresholds so one intentional swipe reliably changes video.
  @override
  double get dragStartDistanceMotionThreshold => 0.25;

  @override
  double get minFlingDistance => 0.5;

  @override
  double get minFlingVelocity => 25.0;
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

class _VideoPageState extends State<_VideoPage>
    with RouteAware, WidgetsBindingObserver {
  static const Duration _candidateInitTimeout = Duration(seconds: 8);
  static const Duration _inactiveDisposeDelay = Duration(seconds: 12);
  static const double _bottomNavHeight = 74;

  VideoPlayerController? _ctrl;
  ModalRoute<dynamic>? _modalRoute;
  Timer? _disposeTimer;
  bool _ready = false;
  bool _error = false;
  final bool _isMuted = false;
  bool _resumeOnForeground = false;
  double? _downloadProgress; // null = not downloading; 0-1 = in progress
  bool _showSeekPreview = false;
  bool _clearDisplay = false;
  bool _autoScroll = true;
  double _playbackSpeed = 1.0;
  bool _isFullscreenMode = false;
  double _previewDx = 0;
  Duration _previewPosition = Duration.zero;

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
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) {
      _cancelDeferredDispose();
      _initController();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _modalRoute && route is PageRoute<dynamic>) {
      if (_modalRoute is PageRoute<dynamic>) {
        appRouteObserver.unsubscribe(this);
      }
      _modalRoute = route;
      appRouteObserver.subscribe(this, route);
      _syncPlayback();
    }
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);

    if (widget.post.id != old.post.id) {
      _cancelDeferredDispose();
      _ctrl?.dispose();
      _ctrl = null;
      _ready = false;
      _error = false;
      _downloadProgress = null;
      if (widget.isActive) {
        _initController();
      }
      return;
    }

    // Keep only the visible card's decoder alive. This avoids decoder
    // allocation failures on low-end devices when multiple players coexist.
    if (widget.isActive != old.isActive) {
      if (widget.isActive) {
        _cancelDeferredDispose();
        if (_ctrl == null && !_ready && !_error) {
          _initController();
        } else {
          _syncPlayback();
        }
      } else {
        _scheduleDeferredDispose();
      }
      return;
    }

    _syncPlayback();
  }

  bool get _isCurrentRoute {
    final route = ModalRoute.of(context);
    return route?.isCurrent ?? true;
  }

  void _syncPlayback() {
    if (!_ready || _ctrl == null) {
      if (widget.isActive && _ctrl == null && !_error) {
        _initController();
      }
      return;
    }
    if (widget.isActive && _isCurrentRoute) {
      _ctrl!.play();
    } else {
      _ctrl!.pause();
    }
  }

  @override
  void didPush() {
    _syncPlayback();
  }

  @override
  void didPushNext() {
    _ctrl?.pause();
  }

  @override
  void didPopNext() {
    _syncPlayback();
  }

  @override
  void didPop() {
    _ctrl?.pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_resumeOnForeground) {
        _resumeOnForeground = false;
        _syncPlayback();
      }
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _resumeOnForeground =
          widget.isActive && (_ctrl?.value.isPlaying ?? false);
      _ctrl?.pause();
    }
  }

  Future<void> _initController() async {
    _cancelDeferredDispose();
    final rawUrl = _videoUrl;
    if (rawUrl == null) {
      if (mounted) setState(() => _error = true);
      return;
    }

    final playbackCandidates = getPlaybackSourceCandidates(rawUrl);
    Object? lastError;

    for (final url in playbackCandidates) {
      VideoPlayerController? ctrl;
      var shouldDownloadInBackground = false;
      try {
        if (isLocalMediaPath(url)) {
          final localPath = url.startsWith('file://')
              ? Uri.parse(url).toFilePath(windows: Platform.isWindows)
              : url;
          ctrl = VideoPlayerController.file(File(localPath));
        } else {
          final cachedFile = await getCachedVideoFile(url);
          final hasCache = cachedFile != null &&
              await cachedFile.exists() &&
              await cachedFile.length() > 1024;

          if (hasCache) {
            debugPrint('[VideoPage] playing from cache: ${cachedFile.path}');
            ctrl = VideoPlayerController.file(cachedFile);
          } else {
            debugPrint('[VideoPage] no cache, streaming:$url');
            ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
            shouldDownloadInBackground = true;
          }
        }

        await ctrl.initialize().timeout(_candidateInitTimeout);
        if (!mounted) {
          await ctrl.dispose();
          return;
        }

        ctrl.setLooping(true);
        ctrl.setVolume(_isMuted ? 0 : 1);
        setState(() {
          _ctrl = ctrl;
          _ready = true;
          _error = false;
        });
        if (shouldDownloadInBackground) {
          unawaited(_downloadInBackground(url));
        }
        _syncPlayback();
        return;
      } catch (e) {
        lastError = e;
        debugPrint('[VideoPage] init failed for source=$url: $e');
        await ctrl?.dispose();
      }
    }

    debugPrint('[VideoPage] all playback sources failed: $lastError');
    if (mounted) setState(() => _error = true);
  }

  void _scheduleDeferredDispose() {
    _disposeTimer?.cancel();
    _disposeTimer = Timer(_inactiveDisposeDelay, () {
      if (!mounted) return;
      _ctrl?.dispose();
      _ctrl = null;
      _ready = false;
      _downloadProgress = null;
    });
  }

  void _cancelDeferredDispose() {
    _disposeTimer?.cancel();
    _disposeTimer = null;
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

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds.clamp(0, 359999);
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _setSpeed(double speed) {
    _ctrl?.setPlaybackSpeed(speed);
    setState(() => _playbackSpeed = speed);
    Navigator.pop(context);
  }

  void _toggleFullscreenMode() {
    setState(() {
      _isFullscreenMode = !_isFullscreenMode;
      _clearDisplay = _isFullscreenMode;
    });
  }

  Widget _menuTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? iconColor,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? Colors.white),
      title: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          color: textColor ?? Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }

  void _showVideoOptionsMenu() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final colorScheme = theme.colorScheme;
        final surfaceColor = colorScheme.surface;
        final onSurfaceColor = colorScheme.onSurface;
        final dividerColor = theme.dividerColor.withValues(alpha: 0.35);
        final chipBgColor = colorScheme.surfaceContainerHighest;

        return SafeArea(
          top: false,
          child: Container(
            color: surfaceColor,
            child: SizedBox(
              height: MediaQuery.of(sheetCtx).size.height * 0.45,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  _menuTile(
                    Icons.download_rounded,
                    'Download',
                    () => Navigator.pop(sheetCtx),
                    iconColor: onSurfaceColor,
                    textColor: onSurfaceColor,
                  ),
                  _menuTile(
                    Icons.block_rounded,
                    'Not interested',
                    () => Navigator.pop(sheetCtx),
                    iconColor: onSurfaceColor,
                    textColor: onSurfaceColor,
                  ),
                  _menuTile(
                    Icons.flag_rounded,
                    'Report',
                    () {
                      Navigator.pop(sheetCtx);
                      _showReportSheet(context, widget.post);
                    },
                    iconColor: onSurfaceColor,
                    textColor: onSurfaceColor,
                  ),
                  Divider(color: dividerColor),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                    child: Text(
                      'Speed',
                      style: GoogleFonts.plusJakartaSans(
                        color: onSurfaceColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                    child: Row(
                      children: [
                        for (final speed in const [0.5, 1.0, 1.5, 2.0])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('${speed.toStringAsFixed(1)}x'),
                              selected: _playbackSpeed == speed,
                              onSelected: (_) => _setSpeed(speed),
                              selectedColor:
                                  AppColors.primary.withValues(alpha: 0.2),
                              backgroundColor: chipBgColor,
                              side: BorderSide(
                                color: _playbackSpeed == speed
                                    ? AppColors.primary
                                    : dividerColor,
                              ),
                              labelStyle: GoogleFonts.plusJakartaSans(
                                color: onSurfaceColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Divider(color: dividerColor),
                  _menuTile(
                    Icons.cleaning_services_rounded,
                    _clearDisplay ? 'Exit clear display' : 'Clear display',
                    () {
                      setState(() {
                        _clearDisplay = !_clearDisplay;
                        if (!_clearDisplay) {
                          _isFullscreenMode = false;
                        }
                      });
                      Navigator.pop(sheetCtx);
                    },
                    iconColor: onSurfaceColor,
                    textColor: onSurfaceColor,
                  ),
                  _menuTile(
                    Icons.swap_vert_circle_rounded,
                    _autoScroll ? 'Auto scroll: On' : 'Auto scroll: Off',
                    () {
                      setState(() => _autoScroll = !_autoScroll);
                      Navigator.pop(sheetCtx);
                    },
                    iconColor: onSurfaceColor,
                    textColor: onSurfaceColor,
                  ),
                  _menuTile(
                    Icons.closed_caption_rounded,
                    'Captions & translation',
                    () => Navigator.pop(sheetCtx),
                    iconColor: onSurfaceColor,
                    textColor: onSurfaceColor,
                  ),
                  _menuTile(
                    Icons.picture_in_picture_alt_rounded,
                    'Picture in picture',
                    () => Navigator.pop(sheetCtx),
                    iconColor: onSurfaceColor,
                    textColor: onSurfaceColor,
                  ),
                  _menuTile(
                    Icons.headphones_rounded,
                    'Background audio',
                    () => Navigator.pop(sheetCtx),
                    iconColor: onSurfaceColor,
                    textColor: onSurfaceColor,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomSeekBar() {
    if (!_ready || _ctrl == null || _error) return const SizedBox.shrink();

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _ctrl!,
      builder: (context, value, _) {
        final durationMs = value.duration.inMilliseconds <= 0
            ? 1
            : value.duration.inMilliseconds;
        final positionMs = value.position.inMilliseconds.clamp(0, durationMs);

        return LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              height: _showSeekPreview ? 76 : 14,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (_showSeekPreview)
                    Positioned(
                      bottom: 14,
                      left: (_previewDx - 55)
                          .clamp(0.0, constraints.maxWidth - 110),
                      child: Container(
                        width: 110,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 50,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.play_circle_fill_rounded,
                                  color: Colors.white70, size: 22),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_formatDuration(_previewPosition)} / ${_formatDuration(value.duration)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                          pressedElevation: 2,
                        ),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 12),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white24,
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: Colors.white24,
                      ),
                      child: Slider(
                        value: positionMs.toDouble(),
                        min: 0,
                        max: durationMs.toDouble(),
                        onChangeStart: (v) {
                          final ratio = (v / durationMs).clamp(0.0, 1.0);
                          setState(() {
                            _showSeekPreview = true;
                            _previewPosition =
                                Duration(milliseconds: v.toInt());
                            _previewDx = constraints.maxWidth * ratio;
                          });
                        },
                        onChanged: (v) {
                          final ratio = (v / durationMs).clamp(0.0, 1.0);
                          setState(() {
                            _previewPosition =
                                Duration(milliseconds: v.toInt());
                            _previewDx = constraints.maxWidth * ratio;
                          });
                        },
                        onChangeEnd: (v) async {
                          await _ctrl!
                              .seekTo(Duration(milliseconds: v.toInt()));
                          if (mounted) {
                            setState(() => _showSeekPreview = false);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _cancelDeferredDispose();
    WidgetsBinding.instance.removeObserver(this);
    if (_modalRoute is PageRoute<dynamic>) {
      appRouteObserver.unsubscribe(this);
    }
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final currentUserId = sl<AuthCubit>().currentUser?.id ?? '';
    final isOwnPost = currentUserId == post.authorId;
    final viewerFaculty =
        sl<AuthCubit>().currentUser?.profile?.faculty?.trim().toLowerCase();
    final postFaculty = post.faculty?.trim().toLowerCase();
    final isCrossFacultyPick = viewerFaculty != null &&
        viewerFaculty.isNotEmpty &&
        postFaculty != null &&
        postFaculty.isNotEmpty &&
        postFaculty != viewerFaculty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Toggle play/pause on tap
        if (_ctrl == null) return;
        if (!_isCurrentRoute || !widget.isActive) return;
        if (_ctrl!.value.isPlaying) {
          _ctrl!.pause();
        } else {
          _ctrl!.play();
        }
        setState(() {});
      },
      onLongPress: () {
        if (_ctrl == null) return;
        _showVideoOptionsMenu();
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
          if (!_clearDisplay)
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
                                ? CachedNetworkImageProvider(
                                    post.authorPhotoUrl!)
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _postTypeAccent(post),
                            borderRadius:
                                BorderRadius.circular(AppDimensions.radiusFull),
                          ),
                          child: Text(
                            _postTypeLabel(post),
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            post.title,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

          // ── Bottom seek line ──────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomSeekBar(),
          ),

          // ── Right-side action column ───────────────────────────────────────
          if (!_clearDisplay)
            Positioned(
              right: 6,
              bottom: 28,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.42,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (isOwnPost) {
                          context.push(
                            RouteNames.profile
                                .replaceFirst(':userId', post.authorId),
                          );
                          return;
                        }
                        if (widget.isGuest) {
                          _promptLogin(context);
                          return;
                        }
                        if (!post.isFollowingAuthor) {
                          _showFollowSheet(context, post, () {
                            widget.cubit.followAuthor(post.id);
                          });
                        } else {
                          context.push(
                            RouteNames.profile
                                .replaceFirst(':userId', post.authorId),
                          );
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.primaryTint10,
                            backgroundImage: post.authorPhotoUrl != null
                                ? CachedNetworkImageProvider(
                                    post.authorPhotoUrl!)
                                : null,
                            child: post.authorPhotoUrl == null
                                ? Text(
                                    (post.authorName ?? '?')[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: post.isFollowingAuthor
                                  ? Colors.white24
                                  : AppColors.danger,
                              borderRadius: BorderRadius.circular(
                                  AppDimensions.radiusFull),
                            ),
                            child: Text(
                              isOwnPost
                                  ? 'You'
                                  : (post.isFollowingAuthor
                                      ? 'Following'
                                      : 'Follow'),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _VideoActionBtn(
                      icon: post.isLikedByMe
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: _compact(post.likeCount),
                      color: post.isLikedByMe
                          ? Colors.redAccent
                          : Colors.white.withValues(alpha: 0.9),
                      enabled: !isOwnPost,
                      iconSize: 21,
                      onTap: () {
                        if (widget.isGuest) {
                          _promptLogin(context);
                        } else if (!isOwnPost) {
                          widget.cubit.likePost(post.id);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _VideoActionBtn(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: _compact(post.commentCount),
                      color: Colors.white.withValues(alpha: 0.9),
                      enabled: true,
                      iconSize: 21,
                      onTap: () async {
                        if (widget.isGuest) {
                          _promptLogin(context);
                        } else {
                          _ctrl?.pause();
                          if (mounted) setState(() {});
                          await _showCommentSheet(context, post, widget.cubit);
                          if (mounted) {
                            _syncPlayback();
                            setState(() {});
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _VideoActionBtn(
                      icon: post.isSavedByMe
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      label: post.isSavedByMe ? 'Saved' : 'Save',
                      color: post.isSavedByMe
                          ? AppColors.primary
                          : Colors.white.withValues(alpha: 0.9),
                      enabled: true,
                      iconSize: 21,
                      onTap: () {
                        if (widget.isGuest) {
                          _promptLogin(context);
                        } else {
                          widget.cubit.toggleSavePost(post.id);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _VideoActionBtn(
                      icon: _isFullscreenMode
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      label: _isFullscreenMode ? 'Exit' : 'Full',
                      color: Colors.white.withValues(alpha: 0.9),
                      iconSize: 21,
                      onTap: _toggleFullscreenMode,
                    ),
                    const SizedBox(height: 12),
                    _VideoActionBtn(
                      icon: Icons.more_vert_rounded,
                      label: 'More',
                      color: Colors.white.withValues(alpha: 0.9),
                      iconSize: 21,
                      onTap: () => _showMoreSheet(
                          context, post, widget.cubit, widget.isGuest),
                    ),
                  ],
                ),
              ),
            ),

          if (_clearDisplay)
            Positioned(
              right: 10,
              bottom: _bottomNavHeight + 18,
              child: SafeArea(
                top: false,
                child: _VideoActionBtn(
                  icon: Icons.visibility_rounded,
                  label: 'Restore UI',
                  color: Colors.white.withValues(alpha: 0.95),
                  iconSize: 21,
                  onTap: () {
                    setState(() {
                      _clearDisplay = false;
                      _isFullscreenMode = false;
                    });
                  },
                ),
              ),
            ),

          if (!_clearDisplay && isCrossFacultyPick)
            Positioned(
              top: 42,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  'Cross Faculty',
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
            onPressed: () =>
                setState(() => _displayStyle = _PhotoDisplayStyle.mixed),
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
            onPressed: () =>
                setState(() => _displayStyle = _PhotoDisplayStyle.grid),
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
    final children = <Widget>[
      const SizedBox(height: 92),
      _buildToolbar(),
    ];

    children.add(
      _FeaturedPhotoCard(
          post: posts.first, cubit: widget.cubit, isGuest: widget.isGuest),
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
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
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
    final sections = <Widget>[
      const SizedBox(height: 92),
      _buildToolbar(),
    ];

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
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
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
                  dragStartBehavior: DragStartBehavior.down,
                  physics: const BouncingScrollPhysics(),
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
      onTap: () => _openPostDetails(context, post, context.read<FeedCubit>()),
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
      onTap: () => _openPostDetails(context, post, context.read<FeedCubit>()),
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
      onTap: () => _openPostDetails(context, post, context.read<FeedCubit>()),
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
            Expanded(
                child:
                    _PhotoGridCell(post: left, cubit: cubit, isGuest: isGuest)),
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
      onTap: () => _openPostDetails(context, post, context.read<FeedCubit>()),
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
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(12, 98, 12, 24),
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
            child:
                _ShowcaseCard(post: posts[gi], cubit: cubit, isGuest: isGuest),
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
      onTap: () => _openPostDetails(context, post, context.read<FeedCubit>()),
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
                          color: _postTypeTint(post),
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusFull),
                        ),
                        child: Text(
                          _postTypeLabel(post),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _postTypeAccent(post),
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
                        ...post.skillsUsed.take(3).map(
                            (s) => _TagChip(s, color: accent, dark: false)),
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
                            size: 13, color: AppColors.textSecondaryLight),
                        const SizedBox(width: 4),
                        Text(
                          '${post.type == 'advert' ? 'Runs until' : 'Deadline'}: ${_formatDate(post.opportunityDeadline!)}',
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
                        fontSize: 11, color: AppColors.textHintLight),
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

  static String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
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
          _SmallFollowButton(post: post, isGuest: isGuest),
        ],
      ),
    );
  }
}

/// Horizontal action bar: Follow, Like, Comment, Share, More
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
  @override
  Widget build(BuildContext context) {
    final currentUserId = sl<AuthCubit>().currentUser?.id ?? '';
    final isOwnPost = currentUserId == widget.post.authorId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      child: Row(
        children: [
          _ActionBarBtn(
            icon: widget.post.isFollowingAuthor
                ? Icons.check_circle_rounded
                : Icons.person_add_alt_1_rounded,
            label: widget.post.isFollowingAuthor ? 'Following' : 'Follow',
            color: widget.post.isFollowingAuthor
                ? AppColors.success
                : (isOwnPost ? Colors.grey : AppColors.textSecondaryLight),
            enabled: widget.isGuest ||
                (!isOwnPost && !widget.post.isFollowingAuthor),
            onTap: () {
              if (widget.isGuest) {
                _promptLogin(context);
              } else if (!isOwnPost && !widget.post.isFollowingAuthor) {
                _showFollowSheet(context, widget.post, () {
                  widget.cubit.followAuthor(widget.post.id);
                });
              }
            },
          ),
          const SizedBox(width: 4),
          // Like
          _ActionBarBtn(
            icon: widget.post.isLikedByMe
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: _compact(widget.post.likeCount),
            color: widget.post.isLikedByMe
                ? Colors.red
                : (isOwnPost ? Colors.grey : AppColors.textSecondaryLight),
            enabled: !isOwnPost,
            onTap: () {
              if (widget.isGuest) {
                _promptLogin(context);
              } else if (!isOwnPost) {
                widget.cubit.likePost(widget.post.id);
              }
            },
          ),
          const SizedBox(width: 4),
          // Comment
          _ActionBarBtn(
            icon: Icons.chat_bubble_outline_rounded,
            label: _compact(widget.post.commentCount),
            color: AppColors.textSecondaryLight,
            enabled: true,
            onTap: () => widget.isGuest
                ? _promptLogin(context)
                : _showCommentSheet(context, widget.post, widget.cubit),
          ),
          const SizedBox(width: 4),
          // Share
          _ActionBarBtn(
            icon: Icons.share_rounded,
            label: 'Share',
            color: AppColors.textSecondaryLight,
            enabled: true,
            onTap: () => Share.share(
              '${widget.post.title}\n\n${widget.post.description ?? ''}\n\nShared from MUST StarTrack',
              subject: widget.post.title,
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
            onPressed: () => _showMoreSheet(
                context, widget.post, widget.cubit, widget.isGuest),
          ),
        ],
      ),
    );
  }
}

/// Inline follow button for video overlay
class _SmallFollowButton extends StatefulWidget {
  final PostModel post;
  final bool isGuest;

  const _SmallFollowButton({required this.post, required this.isGuest});

  @override
  State<_SmallFollowButton> createState() => _SmallFollowButtonState();
}

class _SmallFollowButtonState extends State<_SmallFollowButton> {
  @override
  Widget build(BuildContext context) {
    final isFollowing = widget.post.isFollowingAuthor;
    final isOwnPost = widget.post.authorId ==
        (context.read<AuthCubit>().currentUser?.id ?? '');

    if (isOwnPost) return const SizedBox.shrink();

    return GestureDetector(
      onTap: isFollowing
          ? null
          : () {
              if (widget.isGuest) {
                _promptLogin(context);
                return;
              }
              final cubit = context.read<FeedCubit>();
              _showFollowSheet(context, widget.post, () {
                cubit.followAuthor(widget.post.id);
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isFollowing ? Colors.white24 : Colors.white,
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        ),
        child: Text(
          isFollowing ? 'Following' : '+ Follow',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isFollowing ? Colors.white : AppColors.primary,
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
        ? Image.file(File(url!),
            fit: BoxFit.cover,
            width: double.infinity,
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
            placeholder: (_, __) => Container(color: AppColors.primaryTint10),
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
  final bool enabled;

  const _ActionBarBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : Colors.grey;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: effectiveColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: effectiveColor,
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
  final VoidCallback? onTap;
  final bool enabled;
  final double iconSize;

  const _VideoActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : Colors.grey;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: effectiveColor, size: iconSize),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style:
                GoogleFonts.plusJakartaSans(color: effectiveColor, fontSize: 9),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                    onPressed:
                        _submitting ? null : () => Navigator.pop(context),
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
                            await widget.cubit
                                .ratePost(post: widget.post, stars: _stars);
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
    final currentUserId = sl<AuthCubit>().currentUser?.id ?? '';
    final isOwnPost = currentUserId == post.authorId;

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
              leading:
                  const Icon(Icons.share_outlined, color: AppColors.primary),
              title: Text('Share',
                  style:
                      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Share.share(
                  '${post.title}\n\n${post.description ?? ''}\n\nShared from MUST StarTrack',
                  subject: post.title,
                );
              },
            ),
            ListTile(
              leading: Icon(
                post.isViewedByMe
                    ? Icons.visibility_rounded
                    : Icons.open_in_new_rounded,
                color:
                    post.isViewedByMe ? AppColors.success : AppColors.primary,
              ),
              title: Text(post.isViewedByMe ? 'Viewed Details' : 'View Details',
                  style:
                      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(context);
                await _openPostDetails(parentCtx, post, cubit);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined,
                  color: AppColors.primary),
              title: Text('View Author Profile',
                  style:
                      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                parentCtx.push(
                    RouteNames.profile.replaceFirst(':userId', post.authorId));
              },
            ),
            if (!isOwnPost)
              ListTile(
                leading: Icon(
                    post.isFollowingAuthor
                        ? Icons.check_circle_rounded
                        : Icons.person_add_alt_1_rounded,
                    color: post.isFollowingAuthor
                        ? AppColors.success
                        : AppColors.primary),
                title: Text(
                    post.isFollowingAuthor
                        ? 'Following Author'
                        : 'Follow Author',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600)),
                onTap: post.isFollowingAuthor
                    ? null
                    : () {
                        Navigator.pop(context);
                        if (isGuest) {
                          _promptLogin(parentCtx);
                          return;
                        }
                        _showFollowSheet(parentCtx, post, () {
                          cubit.followAuthor(post.id);
                        });
                      },
              ),
            ListTile(
              leading: Icon(
                post.isDislikedByMe
                    ? Icons.thumb_down_rounded
                    : Icons.thumb_down_outlined,
                color: post.isDislikedByMe ? AppColors.primary : null,
              ),
              title: Text(
                post.isDislikedByMe ? 'Disliked' : 'Dislike Post',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
              ),
              onTap: isOwnPost
                  ? null
                  : () {
                      Navigator.pop(context);
                      if (isGuest) {
                        _promptLogin(parentCtx);
                      } else {
                        cubit.dislikePost(post.id);
                      }
                    },
            ),
            ListTile(
              leading: Icon(
                post.isRatedByMe
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: post.isRatedByMe ? AppColors.warning : null,
              ),
              title: Text(
                post.isRatedByMe
                    ? 'Your Rating: ${post.myRatingStars}★'
                    : 'Rate Post',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
              ),
              onTap: (isOwnPost || post.isRatedByMe)
                  ? null
                  : () {
                      Navigator.pop(context);
                      if (isGuest) {
                        _promptLogin(parentCtx);
                      } else {
                        _showRatePostSheet(
                          parentCtx,
                          post,
                          cubit,
                          initialStars: post.myRatingStars,
                          onRated: (_) {},
                        );
                      }
                    },
            ),
            ListTile(
              leading: Icon(
                post.hasCollaborationRequest
                    ? Icons.check_circle_rounded
                    : Icons.people_outline_rounded,
                color: post.hasCollaborationRequest ? AppColors.success : null,
              ),
              title: Text(
                post.hasCollaborationRequest
                    ? 'Collaboration Pending'
                    : 'Collaborate',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
              ),
              onTap: (isOwnPost || post.hasCollaborationRequest)
                  ? null
                  : () {
                      Navigator.pop(context);
                      if (isGuest) {
                        _promptLogin(parentCtx);
                      } else {
                        _showCollaborateRequestSheet(parentCtx, post, cubit);
                      }
                    },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppColors.danger),
              title: Text('Report Suspicious Content',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600, color: AppColors.danger)),
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
    builder: (ctx) =>
        _FollowSheet(post: post, onConfirmed: onConfirmed, parentCtx: context),
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
                                userId: sl<AuthCubit>().currentUser?.id ?? '',
                                action: 'follow_user',
                                entityType: 'users',
                                entityId: widget.post.authorId,
                                metadata: {
                                  'author_name': widget.post.authorName ?? '',
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
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm)),
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
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: (_selected == null || _loading)
                    ? null
                    : () async {
                        setState(() => _loading = true);
                        try {
                          await sl<ActivityLogDao>().logAction(
                            userId: sl<AuthCubit>().currentUser?.id ?? '',
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

Future<void> _openPostDetails(
  BuildContext context,
  PostModel post,
  FeedCubit cubit,
) async {
  final currentUser = sl<AuthCubit>().currentUser;
  if (post.type == 'advert' && currentUser != null) {
    try {
      await sl<ActivityLogDao>().logAction(
        userId: currentUser.id,
        action: 'open_advert',
        entityType: 'posts',
        entityId: post.id,
        metadata: {
          'title': post.title,
          'target_faculty': post.faculty,
          'deadline': post.opportunityDeadline?.toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('[Advert Analytics] open_advert logging failed: $e');
    }
  }
  await cubit.recordPostView(post.id);
  if (!context.mounted) return;
  context.push('/project/${post.id}');
}

Future<void> _showCommentSheet(
    BuildContext context, PostModel post, FeedCubit cubit) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _CommentSheet(
      post: post,
      cubit: cubit,
      parentCtx: context,
    ),
  );
}

class _CommentSheet extends StatefulWidget {
  final PostModel post;
  final FeedCubit cubit;
  final BuildContext parentCtx;

  const _CommentSheet({
    required this.post,
    required this.cubit,
    required this.parentCtx,
  });

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  late Future<List<CommentRecord>> _commentsFuture;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  Future<List<CommentRecord>> _loadComments({
    bool syncRemote = true,
  }) async {
    if (syncRemote) {
      await sl<SyncService>().syncCommentsForPost(widget.post.id);
      await widget.cubit.refreshPostFromLocal(widget.post.id);
    }
    return sl<CommentDao>().getCommentsForPost(widget.post.id);
  }

  @override
  void initState() {
    super.initState();
    _commentsFuture = _loadComments(syncRemote: true);
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final content = _commentCtrl.text.trim();
    if (content.isEmpty) return;

    setState(() => _submitting = true);

    try {
      final userId = sl<AuthCubit>().currentUser?.id ?? '';
      final userName = sl<AuthCubit>().currentUser?.displayName ?? 'Unknown';
      final userPhotoUrl = sl<AuthCubit>().currentUser?.photoUrl;
      _traceFeedAction(
        userId: userId,
        action: 'comment',
        step: 'ui_submit',
        details: {
          'postId': widget.post.id,
          'contentLength': content.length,
        },
      );

      // Add comment locally
      final commentId = const Uuid().v4();
      await sl<CommentDao>().addLocalComment(
        postId: widget.post.id,
        authorId: userId,
        content: content,
        commentId: commentId,
      );
      _traceFeedAction(
        userId: userId,
        action: 'comment',
        step: 'local_persisted',
        details: {
          'postId': widget.post.id,
          'commentId': commentId,
        },
      );

      // Log activity
      await sl<ActivityLogDao>().logAction(
        userId: userId,
        action: 'comment_post',
        entityType: 'posts',
        entityId: widget.post.id,
        metadata: {
          'comment_id': commentId,
          'comment_text': content,
          'post_title': widget.post.title,
          'author_id': widget.post.authorId,
        },
      );
      _traceFeedAction(
        userId: userId,
        action: 'comment',
        step: 'activity_logged',
        details: {
          'postId': widget.post.id,
          'commentId': commentId,
        },
      );

      // Queue for sync
      await sl<SyncQueueDao>().enqueue(
        operation: 'create',
        entity: 'comments',
        entityId: commentId,
        payload: {
          'id': commentId,
          'post_id': widget.post.id,
          'author_id': userId,
          'receiver_id': widget.post.authorId,
          'content': content,
          'created_at': DateTime.now().toIso8601String(),
          'author_name': userName,
          'commenter_name': userName,
          'author_photo_url': userPhotoUrl,
          'post_title': widget.post.title,
        },
      );

      // Push immediately so the post author receives notification now.
      unawaited(sl<SyncService>().processPendingSync());
      _traceFeedAction(
        userId: userId,
        action: 'comment',
        step: 'remote_queued',
        details: {
          'postId': widget.post.id,
          'commentId': commentId,
        },
      );

      if (userId != widget.post.authorId) {
        debugPrint(
          '[Comment Notification] Deferred to remote sync fan-out '
          'sender=$userId receiver=${widget.post.authorId} post=${widget.post.id}',
        );
      }

      // Update feed cubit with incremented comment count
      await widget.cubit.addCommentToPost(widget.post.id);
      _traceFeedAction(
        userId: userId,
        action: 'comment',
        step: 'render_updated',
        details: {
          'postId': widget.post.id,
          'commentId': commentId,
        },
      );

      if (mounted) {
        _commentCtrl.clear();
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Comment posted!', style: GoogleFonts.plusJakartaSans()),
            duration: const Duration(seconds: 2),
          ),
        );
        // Refresh comments
        setState(() {
          _commentsFuture = _loadComments(syncRemote: false);
        });
      }
    } catch (e) {
      debugPrint('[Comment] Error: $e');
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post comment: $e',
                style: GoogleFonts.plusJakartaSans()),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
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
                    'Comments',
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
                  const SizedBox(height: 12),
                ],
              ),
            ),
            // Comments list
            Flexible(
              child: FutureBuilder<List<CommentRecord>>(
                future: _commentsFuture,
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final comments = snapshot.data ?? [];

                  if (comments.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No comments yet. Be the first!',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textSecondaryLight,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _commentsFuture =
                                      _loadComments(syncRemote: true);
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Refresh comments'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: comments.length,
                    itemBuilder: (ctx, i) {
                      final comment = comments[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Avatar
                            Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primaryTint10,
                              ),
                              child: comment.authorPhotoUrl != null &&
                                      comment.authorPhotoUrl!.isNotEmpty
                                  ? ClipOval(
                                      child: isLocalMediaPath(
                                              comment.authorPhotoUrl!)
                                          ? Image.file(
                                              File(comment.authorPhotoUrl!),
                                              fit: BoxFit.cover,
                                            )
                                          : CachedNetworkImage(
                                              imageUrl: comment.authorPhotoUrl!,
                                              fit: BoxFit.cover,
                                            ),
                                    )
                                  : Center(
                                      child: Text(
                                        (comment.authorName?.isNotEmpty == true)
                                            ? comment.authorName![0]
                                                .toUpperCase()
                                            : '?',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            // Comment content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          comment.authorName ?? 'Unknown',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        timeago.format(comment.createdAt),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          color: AppColors.textSecondaryLight,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceLight,
                                      borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusMd,
                                      ),
                                      border: Border.all(
                                        color: AppColors.borderLight,
                                      ),
                                    ),
                                    child: Text(
                                      comment.content,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        height: 1.45,
                                        color: AppColors.textPrimaryLight,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // Comment input
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.borderLight, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      maxLines: 1,
                      enabled: !_submitting,
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppColors.textHintLight,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusSm),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _submitting ? null : _submitComment,
                    icon: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send_rounded,
                            color: AppColors.primary),
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

void _showCollaborateRequestSheet(
    BuildContext context, PostModel post, FeedCubit cubit) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _CollaborateRequestSheet(
      post: post,
      cubit: cubit,
      parentCtx: context,
    ),
  );
}

class _CollaborateRequestSheet extends StatefulWidget {
  final PostModel post;
  final FeedCubit cubit;
  final BuildContext parentCtx;

  const _CollaborateRequestSheet({
    required this.post,
    required this.cubit,
    required this.parentCtx,
  });

  @override
  State<_CollaborateRequestSheet> createState() =>
      _CollaborateRequestSheetState();
}

class _CollaborateRequestSheetState extends State<_CollaborateRequestSheet> {
  final _messageCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final message = _messageCtrl.text.trim();
    final currentUserId = sl<AuthCubit>().currentUser?.id ?? '';
    final userName = sl<AuthCubit>().currentUser?.displayName ?? 'A user';

    if (currentUserId.isEmpty) return;

    setState(() => _loading = true);
    _traceFeedAction(
      userId: currentUserId,
      action: 'collaborate',
      step: 'ui_submit',
      details: {
        'postId': widget.post.id,
        'authorId': widget.post.authorId,
        'messageLength': message.length,
      },
    );

    try {
      // Log activity
      await sl<ActivityLogDao>().logAction(
        userId: currentUserId,
        action: 'request_collaborate',
        entityType: 'posts',
        entityId: widget.post.id,
        metadata: {
          'target_user_id': widget.post.authorId,
          'message': message,
          'post_title': widget.post.title,
        },
      );
      _traceFeedAction(
        userId: currentUserId,
        action: 'collaborate',
        step: 'activity_logged',
        details: {
          'postId': widget.post.id,
          'authorId': widget.post.authorId,
        },
      );

      // Queue for sync
      await sl<SyncQueueDao>().enqueue(
        operation: 'create',
        entity: 'collab_requests',
        entityId:
            '${currentUserId}_${widget.post.id}_${DateTime.now().millisecondsSinceEpoch}',
        payload: {
          'sender_id': currentUserId,
          'receiver_id': widget.post.authorId,
          'sender_name': userName,
          'post_id': widget.post.id,
          'post_title': widget.post.title,
          'message': message,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      // Push immediately so remote collab + receiver notification are
      // created now (not only after a connectivity-change event).
      unawaited(sl<SyncService>().processPendingSync());
      _traceFeedAction(
        userId: currentUserId,
        action: 'collaborate',
        step: 'remote_queued',
        details: {
          'postId': widget.post.id,
          'authorId': widget.post.authorId,
        },
      );

      debugPrint(
        '[Collaborate Notification] Deferred to remote sync fan-out '
        'sender=$currentUserId receiver=${widget.post.authorId} post=${widget.post.id}',
      );

      // Update feed cubit with collaboration request state
      await widget.cubit.requestCollaborationWithPost(
        widget.post.id,
        message: message,
      );
      _traceFeedAction(
        userId: currentUserId,
        action: 'collaborate',
        step: 'render_updated',
        details: {
          'postId': widget.post.id,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Collaboration request sent!',
                style: GoogleFonts.plusJakartaSans()),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Collaborate Request] Error: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send request: $e',
                style: GoogleFonts.plusJakartaSans()),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
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
              'Request to Collaborate',
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
            TextField(
              controller: _messageCtrl,
              maxLines: 3,
              enabled: !_loading,
              decoration: InputDecoration(
                hintText: 'Tell them why you\'d like to collaborate (optional)',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.textHintLight,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _loading ? null : _sendRequest,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Send Request'),
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

// ─────────────────────────────────────────────────────────────────────────────
// Utility
// ─────────────────────────────────────────────────────────────────────────────

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

void _traceFeedAction({
  required String userId,
  required String action,
  required String step,
  Map<String, Object?> details = const {},
}) {
  debugPrint('=========== user=$userId action=$action step=$step ===========');
  if (details.isNotEmpty) {
    debugPrint('[FeedUI][$action][$step] $details');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Static header (non-scrollable)
// ─────────────────────────────────────────────────────────────────────────────

class _StaticFeedHeader extends StatelessWidget {
  final bool isSearching;
  final TextEditingController searchCtrl;
  final VoidCallback onSearchTap;
  final VoidCallback onCloseSearch;

  const _StaticFeedHeader({
    required this.isSearching,
    required this.searchCtrl,
    required this.onSearchTap,
    required this.onCloseSearch,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, authState) {
        final user = authState is AuthAuthenticated ? authState.user : null;
        final isGuest = user == null;
        final photoUrl = user?.photoUrl?.trim() ?? '';
        ImageProvider<Object>? avatarImage;
        if (photoUrl.isNotEmpty) {
          if (isLocalMediaPath(photoUrl)) {
            avatarImage = FileImage(File(photoUrl));
          } else {
            avatarImage = CachedNetworkImageProvider(photoUrl);
          }
        }
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final searchFill =
            isDark ? const Color(0xFF1A2230) : Theme.of(context).cardColor;
        final searchBorder = isDark
            ? AppColors.institutionalGreen.withValues(alpha: 0.55)
            : AppColors.borderLight;
        final searchTextColor =
            isDark ? Colors.white : AppColors.textSecondaryLight;

        return Material(
          color:
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.96),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    if (isSearching)
                      IconButton(
                        onPressed: onCloseSearch,
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'Back',
                      )
                    else if (isGuest)
                      TextButton(
                        onPressed: () => context.push(RouteNames.login),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppDimensions.radiusFull),
                            side: BorderSide(
                              color: AppColors.institutionalGreen
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                          backgroundColor: AppColors.institutionalGreen
                              .withValues(alpha: 0.14),
                        ),
                        child: Text(
                          'Sign in',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.mustGreenDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      InkWell(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusFull),
                        onTap: () => context.push(
                          RouteNames.profile.replaceFirst(':userId', user.id),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.primaryTint10,
                            backgroundImage: avatarImage,
                            child: avatarImage == null
                                ? Text(
                                    (user.displayName?.trim().isNotEmpty == true
                                            ? user.displayName!
                                            : user.email)[0]
                                        .toUpperCase(),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (isSearching)
                      Expanded(
                        child: TextField(
                          controller: searchCtrl,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          style: GoogleFonts.plusJakartaSans(
                            color: searchTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          cursorColor: isDark
                              ? AppColors.institutionalGreen
                              : AppColors.primary,
                          decoration: InputDecoration(
                            hintText: 'Search materials, projects, people',
                            hintStyle: GoogleFonts.plusJakartaSans(
                              color: searchTextColor.withValues(alpha: 0.75),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: searchTextColor,
                            ),
                            suffixIcon: searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    onPressed: () => searchCtrl.clear(),
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: searchTextColor,
                                    ),
                                  )
                                : null,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            filled: true,
                            fillColor: searchFill,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppDimensions.radiusFull,
                              ),
                              borderSide:
                                  BorderSide(color: searchBorder, width: 1.1),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppDimensions.radiusFull,
                              ),
                              borderSide:
                                  BorderSide(color: searchBorder, width: 1.3),
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusFull),
                          onTap: onSearchTap,
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: searchFill,
                              borderRadius: BorderRadius.circular(
                                AppDimensions.radiusFull,
                              ),
                              border:
                                  Border.all(color: searchBorder, width: 1.1),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search_rounded,
                                  size: 18,
                                  color: searchTextColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Search materials, projects, people',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: searchTextColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (!isSearching && !isGuest) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        constraints: const BoxConstraints.tightFor(
                            width: 34, height: 34),
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
                                          minWidth: 16, minHeight: 16),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.danger,
                                        borderRadius:
                                            BorderRadius.circular(999),
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
                    ],
                    if (!isSearching)
                      Builder(
                        builder: (ctx) => IconButton(
                          constraints: const BoxConstraints.tightFor(
                              width: 34, height: 34),
                          padding: EdgeInsets.zero,
                          iconSize: 20,
                          icon: const Icon(Icons.menu_rounded),
                          onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                          tooltip: 'Settings',
                        ),
                      )
                    else
                      TextButton(
                        onPressed: null,
                        child: Text(
                          'Search',
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
            ),
          ),
        );
      },
    );
  }
}

class _InlineFeedSearchView extends StatelessWidget {
  final List<PostModel> posts;
  final FeedCubit cubit;
  final TextEditingController searchCtrl;

  const _InlineFeedSearchView({
    required this.posts,
    required this.cubit,
    required this.searchCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _FeedSearchSheetBody(
            posts: posts,
            cubit: cubit,
            searchCtrl: searchCtrl,
            parentContext: context,
          ),
        ),
      ],
    );
  }
}

class _FeedSearchSheetBody extends StatefulWidget {
  final List<PostModel> posts;
  final FeedCubit cubit;
  final TextEditingController searchCtrl;
  final BuildContext parentContext;

  const _FeedSearchSheetBody({
    required this.posts,
    required this.cubit,
    required this.searchCtrl,
    required this.parentContext,
  });

  @override
  State<_FeedSearchSheetBody> createState() => _FeedSearchSheetBodyState();
}

class _FeedSearchSheetBodyState extends State<_FeedSearchSheetBody> {
  Timer? _debounce;
  String _query = '';
  bool _loadingUsers = false;
  List<UserModel> _users = const <UserModel>[];

  @override
  void initState() {
    super.initState();
    _query = widget.searchCtrl.text.trim();
    widget.searchCtrl.addListener(_handleQueryChanged);
    if (_query.isNotEmpty) {
      unawaited(_searchUsers(_query));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.searchCtrl.removeListener(_handleQueryChanged);
    super.dispose();
  }

  void _handleQueryChanged() {
    final value = widget.searchCtrl.text;
    if (_query == value.trim()) return;
    setState(() => _query = value.trim());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_searchUsers(_query));
    });
  }

  Future<void> _searchUsers(String query) async {
    final safe = query.trim();
    if (safe.length < 2) {
      if (!mounted) return;
      setState(() {
        _loadingUsers = false;
        _users = const <UserModel>[];
      });
      return;
    }
    setState(() => _loadingUsers = true);
    try {
      final found = await sl<UserDao>().searchUsers(query: safe, pageSize: 20);
      if (!mounted) return;
      setState(() {
        _users = found;
        _loadingUsers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingUsers = false);
    }
  }

  List<({PostModel post, int score})> _matchedPosts(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <({PostModel post, int score})>[];
    final qNoHash = q.startsWith('#') ? q.substring(1) : q;
    final scored = <({PostModel post, int score})>[];

    for (final post in widget.posts) {
      var score = 0;
      final title = post.title.toLowerCase();
      final desc = (post.description ?? '').toLowerCase();
      final category = (post.category ?? '').toLowerCase();
      final author = (post.authorName ?? '').toLowerCase();
      final type = post.type.toLowerCase();
      final haystackTags = post.tags.map((t) => t.toLowerCase()).join(' ');

      if (title.contains(q) || title.contains(qNoHash)) score += 80;
      if (desc.contains(q) || desc.contains(qNoHash)) score += 30;
      if (category.contains(qNoHash)) score += 35;
      if (author.contains(qNoHash)) score += 20;
      if (type.contains(qNoHash)) score += 12;
      if (haystackTags.contains(qNoHash)) score += 40;
      if (title.startsWith(qNoHash)) score += 30;

      if (score > 0) {
        scored.add((post: post, score: score));
      }
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.post.createdAt.compareTo(a.post.createdAt);
    });
    return scored;
  }

  List<String> _matchedHashtags(String query, List<PostModel> posts) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <String>[];
    final qNoHash = q.startsWith('#') ? q.substring(1) : q;
    final tags = <String>{};

    for (final post in posts) {
      for (final tag in post.tags) {
        final clean = tag.trim().replaceAll(RegExp(r'^#+'), '');
        if (clean.isEmpty) continue;
        if (clean.toLowerCase().contains(qNoHash)) {
          tags.add(clean);
        }
      }
    }

    final out = tags.toList()..sort();
    return out;
  }

  Future<void> _openPost(PostModel post) async {
    await _openPostDetails(widget.parentContext, post, widget.cubit);
  }

  Future<void> _openUser(UserModel user) async {
    final uid = user.id;
    if (uid.isEmpty) return;
    widget.parentContext.push(RouteNames.profile.replaceFirst(':userId', uid));
  }

  @override
  Widget build(BuildContext context) {
    final matched = _matchedPosts(_query);
    final matchedPosts = matched.map((e) => e.post).toList(growable: false);
    final videos =
        matchedPosts.where((p) => _kindOf(p) == _PostKind.video).toList();
    final photos =
        matchedPosts.where((p) => _kindOf(p) == _PostKind.photo).toList();
    final projects =
        matchedPosts.where((p) => p.type.toLowerCase() == 'project').toList();
    final hashtags = _matchedHashtags(_query, matchedPosts);

    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          const SizedBox(height: 8),
          if (_query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Results for "$_query"',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),
            ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Top'),
              Tab(text: 'Videos'),
              Tab(text: 'Photos'),
              Tab(text: 'Users'),
              Tab(text: 'Projects'),
              Tab(text: 'Hashtags'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _SearchTopTab(
                  query: _query,
                  posts: matchedPosts,
                  users: _users,
                  loadingUsers: _loadingUsers,
                  hashtags: hashtags,
                  onPostTap: _openPost,
                  onUserTap: _openUser,
                ),
                _SearchPostGridTab(
                  query: _query,
                  posts: videos,
                  showPlayIcon: true,
                  onPostTap: _openPost,
                ),
                _SearchPostGridTab(
                  query: _query,
                  posts: photos,
                  onPostTap: _openPost,
                ),
                _SearchUsersTab(
                  query: _query,
                  users: _users,
                  loading: _loadingUsers,
                  onUserTap: _openUser,
                ),
                _SearchPostGridTab(
                  query: _query,
                  posts: projects,
                  onPostTap: _openPost,
                ),
                _SearchHashtagTab(
                  query: _query,
                  hashtags: hashtags,
                  posts: matchedPosts,
                  onPostTap: _openPost,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchTopTab extends StatelessWidget {
  final String query;
  final List<PostModel> posts;
  final List<UserModel> users;
  final bool loadingUsers;
  final List<String> hashtags;
  final ValueChanged<PostModel> onPostTap;
  final ValueChanged<UserModel> onUserTap;

  const _SearchTopTab({
    required this.query,
    required this.posts,
    required this.users,
    required this.loadingUsers,
    required this.hashtags,
    required this.onPostTap,
    required this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const _SearchHint(text: 'Type a keyword to search all content.');
    }
    if (posts.isEmpty && users.isEmpty && !loadingUsers) {
      return _SearchHint(text: 'No results found for "$query".');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        if (posts.isNotEmpty) ...[
          Text('Top posts',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          ...posts.take(6).map(
                (post) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _SearchThumb(
                      post: post,
                      showPlayIcon: _kindOf(post) == _PostKind.video),
                  title: Text(post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  subtitle: Text(
                    [post.authorName, post.category]
                        .whereType<String>()
                        .where((e) => e.trim().isNotEmpty)
                        .join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onPostTap(post),
                ),
              ),
        ],
        if (users.isNotEmpty || loadingUsers) ...[
          const SizedBox(height: 10),
          Text('Users',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          if (loadingUsers)
            const Center(child: CircularProgressIndicator())
          else
            ...users.take(5).map(
                  (user) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundImage: (user.photoUrl != null &&
                              user.photoUrl!.trim().isNotEmpty)
                          ? CachedNetworkImageProvider(user.photoUrl!.trim())
                          : null,
                      child: (user.photoUrl == null ||
                              user.photoUrl!.trim().isEmpty)
                          ? const Icon(Icons.person_rounded)
                          : null,
                    ),
                    title: Text(
                      (user.displayName?.trim().isNotEmpty == true)
                          ? user.displayName!.trim()
                          : user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(user.email,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => onUserTap(user),
                  ),
                ),
        ],
        if (hashtags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Hashtags',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: hashtags
                .take(12)
                .map((tag) => Chip(label: Text('#$tag')))
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}

class _SearchPostGridTab extends StatelessWidget {
  final String query;
  final List<PostModel> posts;
  final bool showPlayIcon;
  final ValueChanged<PostModel> onPostTap;

  const _SearchPostGridTab({
    required this.query,
    required this.posts,
    required this.onPostTap,
    this.showPlayIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const _SearchHint(text: 'Enter a keyword to start searching.');
    }
    if (posts.isEmpty) {
      return _SearchHint(text: 'No matching results for "$query".');
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.76,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onPostTap(post),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SearchThumb(post: post, showPlayIcon: showPlayIcon),
              ),
              const SizedBox(height: 6),
              Text(
                post.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchUsersTab extends StatelessWidget {
  final String query;
  final List<UserModel> users;
  final bool loading;
  final ValueChanged<UserModel> onUserTap;

  const _SearchUsersTab({
    required this.query,
    required this.users,
    required this.loading,
    required this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const _SearchHint(text: 'Search users by name or email.');
    }
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (users.isEmpty) {
      return _SearchHint(text: 'No users match "$query".');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      itemCount: users.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final user = users[index];
        final name = (user.displayName?.trim().isNotEmpty == true)
            ? user.displayName!.trim()
            : user.email;
        return ListTile(
          leading: CircleAvatar(
            backgroundImage:
                (user.photoUrl != null && user.photoUrl!.trim().isNotEmpty)
                    ? CachedNetworkImageProvider(user.photoUrl!.trim())
                    : null,
            child: (user.photoUrl == null || user.photoUrl!.trim().isEmpty)
                ? const Icon(Icons.person_rounded)
                : null,
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [user.email, user.profile?.faculty]
                .where((e) => e != null && e.trim().isNotEmpty)
                .join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => onUserTap(user),
        );
      },
    );
  }
}

class _SearchHashtagTab extends StatelessWidget {
  final String query;
  final List<String> hashtags;
  final List<PostModel> posts;
  final ValueChanged<PostModel> onPostTap;

  const _SearchHashtagTab({
    required this.query,
    required this.hashtags,
    required this.posts,
    required this.onPostTap,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const _SearchHint(
          text: 'Search hashtags, for example #innovation.');
    }
    if (hashtags.isEmpty) {
      return _SearchHint(text: 'No hashtags found for "$query".');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: hashtags
              .map((tag) => Chip(label: Text('#$tag')))
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        ...posts.take(10).map(
              (post) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _SearchThumb(
                  post: post,
                  showPlayIcon: _kindOf(post) == _PostKind.video,
                ),
                title: Text(
                  post.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  post.tags
                      .map((t) => '#${t.replaceAll(RegExp(r'^#+'), '')}')
                      .join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onPostTap(post),
              ),
            ),
      ],
    );
  }
}

class _SearchThumb extends StatelessWidget {
  final PostModel post;
  final bool showPlayIcon;

  const _SearchThumb({required this.post, this.showPlayIcon = false});

  String? get _thumbUrl {
    for (final media in post.mediaUrls) {
      if (!_isVideoUrl(media)) return media;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final thumb = _thumbUrl;
    return AspectRatio(
      aspectRatio: 9 / 14,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumb == null)
              Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child: Icon(
                  showPlayIcon
                      ? Icons.play_circle_fill_rounded
                      : Icons.image_rounded,
                  color: Colors.white70,
                  size: 28,
                ),
              )
            else if (isLocalMediaPath(thumb))
              Image.file(File(thumb), fit: BoxFit.cover)
            else
              CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover),
            if (showPlayIcon)
              const Align(
                alignment: Alignment.center,
                child: Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white70, size: 28),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  final String text;
  const _SearchHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: AppColors.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chips (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

enum _FeedTopFilterMode { faculty, following, search }

class _FilterChips extends StatefulWidget {
  final FeedCubit cubit;
  final int currentTabIndex;
  final bool tabsCollapsed;
  final VoidCallback? onToggleTabs;
  const _FilterChips({
    required this.cubit,
    this.currentTabIndex = 0,
    this.tabsCollapsed = false,
    this.onToggleTabs,
  });

  @override
  State<_FilterChips> createState() => _FilterChipsState();
}

class _FilterChipsState extends State<_FilterChips> {
  List<String> _dbFaculties = const <String>[];
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _loadFacultiesFromDatabase();
  }

  Future<void> _loadFacultiesFromDatabase() async {
    try {
      final faculties =
          await sl<FacultyDao>().getAllFaculties(activeOnly: true);
      final names = faculties
          .map((f) => f.name.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (!mounted) return;
      setState(() => _dbFaculties = names);
    } catch (e) {
      debugPrint('[FilterChips] failed to load faculties from DB: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeedCubit, FeedState>(
      builder: (_, state) {
        final current = state is FeedLoaded ? state.filter : const FeedFilter();
        final feedPosts =
            state is FeedLoaded ? state.posts : const <PostModel>[];
        final fallbackFaculties = <String>{
          ...feedPosts
              .map((post) => post.faculty?.trim() ?? '')
              .where((faculty) => faculty.isNotEmpty),
          ...feedPosts
              .expand((post) => post.faculties)
              .map((faculty) => faculty.trim())
              .where((faculty) => faculty.isNotEmpty),
        }.toList()
          ..sort();
        final faculties =
            _dbFaculties.isNotEmpty ? _dbFaculties : fallbackFaculties;

        final topMode = current.followingOnly
            ? _FeedTopFilterMode.following
            : (current.searchedUserId != null
                ? _FeedTopFilterMode.search
                : _FeedTopFilterMode.faculty);

        // Video tab (0) = dark background → white text; others = light → dark text
        final onDark = widget.currentTabIndex == 0;
        final activeColor = onDark ? Colors.white : Colors.black87;
        final inactiveColor = onDark ? Colors.white70 : Colors.black54;
        final textShadows = onDark
            ? const <Shadow>[
                Shadow(color: Colors.black54, blurRadius: 6),
                Shadow(color: Colors.black26, blurRadius: 12),
              ]
            : const <Shadow>[
                Shadow(color: Colors.white70, blurRadius: 4),
              ];

        return Column(
          children: [
            // ── Top row: Faculty / Following + Filters toggle ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TopModeChip(
                          label: 'Faculty',
                          active: topMode == _FeedTopFilterMode.faculty,
                          onTap: () {
                            if (_dbFaculties.isEmpty) {
                              unawaited(_loadFacultiesFromDatabase());
                            }
                            widget.cubit.applyFilter(
                              current.copyWith(
                                clearFollowingOnly: true,
                                clearSearchedUser: true,
                              ),
                            );
                          },
                          compact: true,
                          activeColor: activeColor,
                          inactiveColor: inactiveColor,
                          shadows: textShadows,
                        ),
                        const SizedBox(width: 22),
                        _TopModeChip(
                          label: 'Following',
                          active: topMode == _FeedTopFilterMode.following,
                          onTap: () => widget.cubit.applyFilter(
                            current.copyWith(
                              followingOnly: true,
                              clearFaculty: true,
                              clearSearchedUser: true,
                              groupsOnly: false,
                            ),
                          ),
                          compact: true,
                          activeColor: activeColor,
                          inactiveColor: inactiveColor,
                          shadows: textShadows,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _showFilters = !_showFilters),
                        style: TextButton.styleFrom(
                          foregroundColor:
                              _showFilters ? activeColor : inactiveColor,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: _showFilters ? activeColor : inactiveColor,
                          shadows: textShadows,
                        ),
                        label: Text(
                          'Filters',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _showFilters ? activeColor : inactiveColor,
                            shadows: textShadows,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      TextButton.icon(
                        onPressed: widget.onToggleTabs,
                        style: TextButton.styleFrom(
                          foregroundColor: widget.tabsCollapsed
                              ? inactiveColor
                              : activeColor,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          widget.tabsCollapsed
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_up_rounded,
                          size: 18,
                          color: widget.tabsCollapsed
                              ? inactiveColor
                              : activeColor,
                          shadows: textShadows,
                        ),
                        label: Text(
                          'Tabs',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: widget.tabsCollapsed
                                ? inactiveColor
                                : activeColor,
                            shadows: textShadows,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_showFilters)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Row(
                  children: [
                    _Chip(
                      label: 'All',
                      active: current.type == null && !current.groupsOnly,
                      onDark: onDark,
                      onTap: () => widget.cubit.applyFilter(
                        current.copyWith(
                          clearType: true,
                          clearGroupsOnly: true,
                        ),
                      ),
                    ),
                    _Chip(
                      label: 'Projects',
                      active: current.type == 'project' && !current.groupsOnly,
                      onDark: onDark,
                      onTap: () => widget.cubit.applyFilter(
                        current.copyWith(type: 'project', groupsOnly: false),
                      ),
                    ),
                    _Chip(
                      label: 'Opportunities',
                      active:
                          current.type == 'opportunity' && !current.groupsOnly,
                      onDark: onDark,
                      onTap: () => widget.cubit.applyFilter(
                        current.copyWith(
                            type: 'opportunity', groupsOnly: false),
                      ),
                    ),
                    _Chip(
                      label: 'Adverts',
                      active: current.type == 'advert' && !current.groupsOnly,
                      onDark: onDark,
                      onTap: () => widget.cubit.applyFilter(
                        current.copyWith(type: 'advert', groupsOnly: false),
                      ),
                    ),
                    _Chip(
                      label: 'Groups',
                      active: current.groupsOnly,
                      onDark: onDark,
                      onTap: () => widget.cubit.applyFilter(
                        current.copyWith(
                          type: 'project',
                          groupsOnly: true,
                        ),
                      ),
                    ),
                    if (topMode == _FeedTopFilterMode.search)
                      _Chip(
                        label: current.searchedUserName == null
                            ? 'Pick User'
                            : 'User: ${current.searchedUserName}',
                        active: current.searchedUserId != null,
                        onDark: onDark,
                        onTap: () async {
                          final selected =
                              await _showFeedUserSearchSheet(context);
                          if (selected == null) return;
                          if (!context.mounted) return;
                          await widget.cubit.applyFilter(
                            current.copyWith(
                              searchedUserId: selected.id,
                              searchedUserName: selected.name,
                              clearFaculty: true,
                              clearFollowingOnly: true,
                              groupsOnly: false,
                            ),
                          );
                        },
                      ),
                    if (topMode == _FeedTopFilterMode.faculty)
                      _FacultyDropdown(
                        faculties: faculties,
                        selected: current.faculty,
                        onDark: onDark,
                        onSelected: (faculty) => widget.cubit.applyFilter(
                          faculty == null || faculty.isEmpty
                              ? current.copyWith(clearFaculty: true)
                              : current.copyWith(
                                  faculty: faculty,
                                  clearType: true,
                                  groupsOnly: false,
                                  clearFollowingOnly: true,
                                  clearSearchedUser: true,
                                ),
                        ),
                      ),
                    if (current.isActive)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: GestureDetector(
                          onTap: widget.cubit.clearFilters,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(
                                  AppDimensions.radiusFull),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.close,
                                    size: 12, color: Colors.redAccent),
                                const SizedBox(width: 3),
                                Text(
                                  'Clear',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FacultyDropdown extends StatelessWidget {
  final List<String> faculties;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final bool onDark;

  const _FacultyDropdown({
    required this.faculties,
    required this.selected,
    required this.onSelected,
    this.onDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final options = faculties.toSet().toList()..sort();
    final hasSelection = selected != null && selected!.trim().isNotEmpty;
    final selectedValue =
        hasSelection && options.contains(selected) ? selected : null;

    final bgColor = onDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final textColor = onDark ? Colors.white : Colors.black87;
    final hintColor = onDark ? Colors.white60 : Colors.black45;
    final dropBg = onDark ? const Color(0xFF1A1A2E) : Colors.white;
    final iconColor = onDark ? Colors.white70 : Colors.black54;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedValue,
          isDense: true,
          dropdownColor: dropBg,
          iconEnabledColor: iconColor,
          hint: Text(
            'Faculty',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: hintColor,
            ),
          ),
          items: options
              .map(
                (faculty) => DropdownMenuItem<String>(
                  value: faculty,
                  child: Text(
                    faculty,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: onSelected,
        ),
      ),
    );
  }
}

class _TopModeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool compact;
  final Color? activeColor;
  final Color? inactiveColor;
  final List<Shadow>? shadows;

  const _TopModeChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.compact = false,
    this.activeColor,
    this.inactiveColor,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final aColor = activeColor ?? Colors.white;
    final iColor = inactiveColor ?? Colors.white70;

    if (compact) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? aColor : iColor,
                  shadows: shadows,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: active ? 26 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: aColor,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                  boxShadow: shadows != null
                      ? [BoxShadow(color: shadows!.first.color, blurRadius: 4)]
                      : null,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.institutionalGreen.withValues(alpha: 0.16),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: active
              ? AppColors.institutionalGreen
              : AppColors.textSecondaryLight,
        ),
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          side: BorderSide(
            color:
                active ? AppColors.institutionalGreen : AppColors.borderLight,
          ),
        ),
      ),
    );
  }
}

class _FeedUserChoice {
  final String id;
  final String name;

  const _FeedUserChoice({required this.id, required this.name});
}

Future<_FeedUserChoice?> _showFeedUserSearchSheet(BuildContext context) async {
  final searchCtrl = TextEditingController();
  final users = ValueNotifier<List<UserModel>>(const <UserModel>[]);
  final loading = ValueNotifier<bool>(false);

  int matchScore(UserModel user, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 0;
    final display = (user.displayName ?? '').trim().toLowerCase();
    final email = user.email.trim().toLowerCase();
    final localPart = email.split('@').first;
    var score = 0;
    if (display == q) score += 120;
    if (email == q) score += 120;
    if (localPart == q) score += 100;
    if (display.startsWith(q)) score += 70;
    if (localPart.startsWith(q)) score += 65;
    if (email.startsWith(q)) score += 60;
    if (display.contains(q)) score += 40;
    if (localPart.contains(q)) score += 35;
    if (email.contains(q)) score += 30;
    return score;
  }

  Future<void> runSearch(String query) async {
    final safe = query.trim();
    if (safe.length < 2) {
      users.value = const <UserModel>[];
      return;
    }
    loading.value = true;
    try {
      final found = await sl<UserDao>().searchUsers(query: safe, pageSize: 12);
      final scored = found
          .map((user) => (user: user, score: matchScore(user, safe)))
          .where((entry) => entry.score > 0)
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      users.value = scored.map((entry) => entry.user).toList(growable: false);
    } finally {
      loading.value = false;
    }
  }

  final selected = await showModalBottomSheet<_FeedUserChoice>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SizedBox(
            height: 460,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter By Searched User',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  onChanged: runSearch,
                  decoration: const InputDecoration(
                    hintText: 'Search by name or email',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: loading,
                    builder: (_, isLoading, __) {
                      return ValueListenableBuilder<List<UserModel>>(
                        valueListenable: users,
                        builder: (_, items, __) {
                          if (isLoading) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (items.isEmpty) {
                            return Center(
                              child: Text(
                                'Type at least 2 characters to search users.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final user = items[index];
                              final name =
                                  (user.displayName?.trim().isNotEmpty == true)
                                      ? user.displayName!.trim()
                                      : user.email;
                              final subtitle = [
                                user.profile?.faculty,
                                user.profile?.programName,
                              ]
                                  .whereType<String>()
                                  .where((e) => e.trim().isNotEmpty)
                                  .join(' • ');

                              return ListTile(
                                onTap: () => Navigator.of(ctx).pop(
                                  _FeedUserChoice(id: user.id, name: name),
                                ),
                                title: Text(
                                  name,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: subtitle.isEmpty
                                    ? null
                                    : Text(
                                        subtitle,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          color: AppColors.textSecondaryLight,
                                        ),
                                      ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  searchCtrl.dispose();
  users.dispose();
  loading.dispose();
  return selected;
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool onDark;

  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.onDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final bgActive = onDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.10);
    final bgInactive = onDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final textActive = onDark ? Colors.white : Colors.black87;
    final textInactive = onDark ? Colors.white70 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? bgActive : bgInactive,
            borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? textActive : textInactive,
            ),
          ),
        ),
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
        if (items.isEmpty && snapshot.connectionState == ConnectionState.done) {
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
                        onPressed: () =>
                            setState(() => _collapsed = !_collapsed),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint10,
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusFull),
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
                                    onPageChanged: (i) =>
                                        setState(() => _currentIndex = i),
                                    itemBuilder: (_, i) {
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          left: i == 0 ? 16 : 6,
                                          right: i == items.length - 1 ? 16 : 6,
                                        ),
                                        child: AnimatedBuilder(
                                          animation: pageCtrl,
                                          child:
                                              _CollaboratorCard(item: items[i]),
                                          builder: (context, child) {
                                            double page =
                                                _currentIndex.toDouble();
                                            if (pageCtrl.hasClients &&
                                                pageCtrl
                                                    .position.haveDimensions) {
                                              page = pageCtrl.page ??
                                                  _currentIndex.toDouble();
                                            }
                                            final distance = (page - i)
                                                .abs()
                                                .clamp(0.0, 1.0);
                                            final scale = 1 - (0.04 * distance);
                                            final opacity =
                                                1 - (0.14 * distance);
                                            return Transform.scale(
                                              scale: scale,
                                              child: Opacity(
                                                  opacity: opacity,
                                                  child: child),
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
                                        duration:
                                            const Duration(milliseconds: 220),
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
                                                style:
                                                    GoogleFonts.plusJakartaSans(
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
                      if (snapshot.connectionState == ConnectionState.done &&
                          items.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              items.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
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
            onTap: () => context
                .push(RouteNames.profile.replaceFirst(':userId', user.id)),
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryTint10,
              borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
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
  final bool groupsOnly;

  const _EmptyFeed({
    this.isGuest = false,
    this.groupsOnly = false,
  });

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
              groupsOnly
                  ? 'No group posts yet'
                  : (isGuest ? 'Discover MUST Projects' : 'No posts yet'),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              groupsOnly
                  ? 'Only projects published under a group will appear here.'
                  : (isGuest
                      ? 'Projects are loading. Pull down to refresh, or join the community to collaborate.'
                      : 'Be the first to share a project!'),
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
              const Icon(Icons.wifi_off_rounded,
                  size: 56, color: AppColors.danger),
              const SizedBox(height: 16),
              Text('Could not load feed',
                  style:
                      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: AppColors.textSecondaryLight),
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

class _GuestCtaBanner extends StatefulWidget {
  const _GuestCtaBanner();

  @override
  State<_GuestCtaBanner> createState() => _GuestCtaBannerState();
}

class _GuestCtaBannerState extends State<_GuestCtaBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.055).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

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
            const SizedBox(height: 14),
            // ── Signifier label ──────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.touch_app_rounded,
                    color: Colors.white70, size: 15),
                const SizedBox(width: 5),
                Text(
                  'Tap a button below to get started',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: Colors.white70,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // ── Pulsing "Create Account" button ──────────────────────────
                Expanded(
                  child: ScaleTransition(
                    scale: _pulseAnim,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => context.push(RouteNames.registerStep1),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_add_rounded, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Create Account',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.institutionalGreen,
                      side: const BorderSide(
                          color: AppColors.institutionalGreen, width: 1.5),
                      backgroundColor:
                          AppColors.institutionalGreen.withValues(alpha: 0.12),
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
                          color: AppColors.institutionalGreen),
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
