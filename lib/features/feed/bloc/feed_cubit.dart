// lib/features/feed/bloc/feed_cubit.dart
//
// MUST StarTrack — Feed Cubit
//
// Manages the home feed: pagination, optimistic likes,
// filter state, create-post flow.
//
// Optimistic Like pattern (HCI — Feedback):
//   1. User taps like → likePost() called
//   2. Cubit immediately emits updated post list with toggled
//      like state (UI updates in <16ms — user sees it instantly)
//   3. PostDao.toggleLike() runs async in background (SQLite)
//   4. SyncQueueDao.enqueue() schedules Firestore write
//   5. If step 3/4 fails → rollback to previous state + error snackbar
//
// Pagination (cursor-based):
//   • loadMore() called when ListView reaches bottom
//   • Uses createdAt of last item as cursor
//   • hasMore flag stops unnecessary calls

import 'dart:async';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../data/local/schema/database_schema.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/recommendation_log_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../core/router/route_guards.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/remote/recommender_service.dart';
import '../../../data/remote/sync_service.dart';
import '../../auth/bloc/auth_cubit.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class FeedState extends Equatable {
  const FeedState();
  @override
  List<Object?> get props => [];
}

class FeedInitial extends FeedState {
  const FeedInitial();
}

class FeedLoading extends FeedState {
  const FeedLoading();
}

class FeedLoaded extends FeedState {
  final List<PostModel> posts;
  final bool hasMore;
  final bool isLoadingMore;
  final FeedFilter filter;

  const FeedLoaded({
    required this.posts,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.filter = const FeedFilter(),
  });

  FeedLoaded copyWith({
    List<PostModel>? posts,
    bool? hasMore,
    bool? isLoadingMore,
    FeedFilter? filter,
  }) =>
      FeedLoaded(
        posts: posts ?? this.posts,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        filter: filter ?? this.filter,
      );

  @override
  List<Object?> get props => [posts, hasMore, isLoadingMore, filter];
}

class FeedError extends FeedState {
  final String message;
  const FeedError(this.message);
  @override
  List<Object?> get props => [message];
}

class PublishPostResult extends Equatable {
  final bool savedLocally;
  final bool syncedRemotely;
  final String message;

  const PublishPostResult({
    required this.savedLocally,
    required this.syncedRemotely,
    required this.message,
  });

  @override
  List<Object?> get props => [savedLocally, syncedRemotely, message];
}

/// Active filter criteria for the feed.
class FeedFilter extends Equatable {
  final String? faculty;
  final String? category;
  final String? type; // 'project' | 'opportunity' | null = all
  final String? recency;
  final bool groupsOnly;
  final bool followingOnly;
  final String? searchedUserId;
  final String? searchedUserName;

  const FeedFilter({
    this.faculty,
    this.category,
    this.type,
    this.recency,
    this.groupsOnly = false,
    this.followingOnly = false,
    this.searchedUserId,
    this.searchedUserName,
  });

  bool get isActive =>
      faculty != null ||
      category != null ||
      type != null ||
      recency != null ||
      groupsOnly ||
      followingOnly ||
      searchedUserId != null;

  FeedFilter copyWith({
    String? faculty,
    String? category,
    String? type,
    String? recency,
    bool? groupsOnly,
    bool? followingOnly,
    String? searchedUserId,
    String? searchedUserName,
    bool clearFaculty = false,
    bool clearCategory = false,
    bool clearType = false,
    bool clearRecency = false,
    bool clearGroupsOnly = false,
    bool clearFollowingOnly = false,
    bool clearSearchedUser = false,
  }) =>
      FeedFilter(
        faculty: clearFaculty ? null : faculty ?? this.faculty,
        category: clearCategory ? null : category ?? this.category,
        type: clearType ? null : type ?? this.type,
        recency: clearRecency ? null : recency ?? this.recency,
        groupsOnly: clearGroupsOnly ? false : groupsOnly ?? this.groupsOnly,
        followingOnly:
            clearFollowingOnly ? false : followingOnly ?? this.followingOnly,
        searchedUserId:
            clearSearchedUser ? null : searchedUserId ?? this.searchedUserId,
        searchedUserName: clearSearchedUser
            ? null
            : searchedUserName ?? this.searchedUserName,
      );

  @override
  List<Object?> get props => [
        faculty,
        category,
        type,
        recency,
        groupsOnly,
        followingOnly,
        searchedUserId,
        searchedUserName,
      ];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class FeedCubit extends Cubit<FeedState> {
  final PostDao _postDao;
  final UserDao _userDao;
  final ActivityLogDao _activityLogDao;
  final RecommenderService _recommenderService;
  final RecommendationLogDao? _recLogDao;
  final SyncQueueDao _syncQueue;
  final SyncService? _syncService;
  final String? _currentUserId;
  final AuthCubit? _authCubit;
  final FirestoreService? _firestore;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<int>? _feedRealtimeSub;
  Timer? _feedRefreshDebounce;
  String? _lastObservedAuthUserId;
  DateTime? _lastSuccessfulLoadAt;
  static const _pageSize = 40;
  static const _targetAuthorGroups = 12;
  static const _maxPrefetchPages = 6;

  FeedCubit({
    PostDao? postDao,
    UserDao? userDao,
    ActivityLogDao? activityLogDao,
    RecommenderService? recommenderService,
    RecommendationLogDao? recLogDao,
    SyncQueueDao? syncQueue,
    SyncService? syncService,
    FirestoreService? firestore,
    String? currentUserId,
    AuthCubit? authCubit,
  })  : _postDao = postDao ?? PostDao(),
        _userDao = userDao ?? UserDao(),
        _activityLogDao = activityLogDao ?? ActivityLogDao(),
        _recommenderService = recommenderService ?? RecommenderService(),
        _recLogDao = recLogDao,
        _syncQueue = syncQueue ?? SyncQueueDao(),
        _syncService = syncService,
        _firestore = firestore,
        _currentUserId = currentUserId,
        _authCubit = authCubit,
        super(const FeedInitial());

  void _ensureAuthListener() {
    if (_authSub != null) {
      return;
    }

    _lastObservedAuthUserId = _activeUserId;
    _authSub = _authCubit?.stream.listen((_) {
      final nextUserId = _activeUserId;
      if (nextUserId == _lastObservedAuthUserId) {
        return;
      }

      _lastObservedAuthUserId = nextUserId;
      // Always reset to "All" when auth identity changes so the new session
      // starts from an unfiltered feed. Users can then apply filters in UI.
      unawaited(loadFeed(filter: const FeedFilter(), forceSync: true));
    });
  }

  String? get _activeUserId => _authCubit?.currentUser?.id ?? _currentUserId;

  bool get _canViewPendingModeration {
    final user = _authCubit?.currentUser;
    if (user == null) return false;
    return user.role == UserRole.admin || user.role == UserRole.superAdmin;
  }

  void _emitIfOpen(FeedState nextState) {
    if (!isClosed) {
      emit(nextState);
    }
  }

  void _traceAction(
    String action,
    String step, {
    String? userId,
    Map<String, Object?> details = const {},
  }) {
    debugPrint(
      '=========== user=${userId ?? _activeUserId ?? 'guest'} action=$action step=$step ===========',
    );
    if (details.isNotEmpty) {
      debugPrint('[FeedCubit][$action][$step] $details');
    }
  }

  // ── Load first page ────────────────────────────────────────────────────────

  Future<void> ensureLoaded(
      {Duration staleAfter = const Duration(minutes: 2)}) async {
    _ensureAuthListener();

    final current = state;
    if (current is FeedInitial || current is FeedError) {
      await loadFeed();
      return;
    }

    if (current is! FeedLoaded) return;

    final loadedAt = _lastSuccessfulLoadAt;
    if (loadedAt == null) {
      _lastSuccessfulLoadAt = DateTime.now();
      unawaited(_syncFeedInBackground(filter: current.filter));
      return;
    }

    final age = DateTime.now().difference(loadedAt);
    if (age >= staleAfter) {
      unawaited(_syncFeedInBackground(filter: current.filter));
    }
  }

  Future<void> loadFeed({
    FeedFilter? filter,
    bool forceSync = false,
  }) async {
    _ensureAuthListener();
    final shouldForceSync = forceSync ||
        (state is FeedInitial && (_activeUserId?.isNotEmpty ?? false));
    _emitIfOpen(const FeedLoading());
    try {
      final requestedFilter = filter ?? const FeedFilter();
      final startTime = DateTime.now();
      debugPrint(
        '[FeedCubit] loadFeed starting '
        'filter=${requestedFilter.type ?? 'all'} '
        'user=${_activeUserId ?? 'guest'} '
        'at=${startTime.millisecondsSinceEpoch}',
      );
      final f = requestedFilter;

      if (shouldForceSync) {
        await _syncService?.syncRemoteToLocal(postLimit: _pageSize * 2);
        if (isClosed) return;
        final syncEndTime = DateTime.now();
        debugPrint(
          '[FeedCubit] loadFeed sync finished '
          'filter=${requestedFilter.type ?? 'all'} '
          'user=${_activeUserId ?? 'guest'} '
          'syncDuration=${syncEndTime.difference(startTime).inMilliseconds}ms',
        );
      }

      final batch = await _loadGroupedBatch(
        filter: f,
        existingAuthorIds: const <String>{},
      );
      final queryEndTime = DateTime.now();
      debugPrint(
        '[FeedCubit] loadFeed query finished '
        'posts=${batch.posts.length} '
        'totalDuration=${queryEndTime.difference(startTime).inMilliseconds}ms',
      );
      _emitIfOpen(FeedLoaded(
        posts: batch.posts,
        hasMore: batch.hasMore,
        filter: f,
      ));
      _lastSuccessfulLoadAt = DateTime.now();
      _startFeedRealtimeWatcher();

      if (!shouldForceSync) {
        unawaited(_syncFeedInBackground(filter: f));
      }
    } catch (e) {
      debugPrint('Feed load error: $e');
      _emitIfOpen(const FeedError(
        'Could not load your feed right now. Please try again.',
      ));
    }
  }

  Future<void> _syncFeedInBackground({required FeedFilter filter}) async {
    try {
      await _syncService?.syncRemoteToLocal(postLimit: _pageSize * 2);
      if (isClosed) return;

      final current = state;
      if (current is FeedLoaded && current.filter != filter) {
        return;
      }

      final refreshedBatch = await _loadGroupedBatch(
        filter: filter,
        existingAuthorIds: const <String>{},
      );

      final latest = state;
      if (latest is FeedLoaded && latest.filter == filter) {
        _emitIfOpen(latest.copyWith(
          posts: refreshedBatch.posts,
          hasMore: refreshedBatch.hasMore,
        ));
        _lastSuccessfulLoadAt = DateTime.now();
      }
    } catch (e) {
      debugPrint('[FeedCubit] background sync failed: $e');
    }
  }

  // ── Load next page ─────────────────────────────────────────────────────────

  Future<void> loadMore() async {
    final current = state;
    if (current is! FeedLoaded) return;
    if (!current.hasMore || current.isLoadingMore) return;

    _emitIfOpen(current.copyWith(isLoadingMore: true));

    try {
      final batch = await _loadGroupedBatch(
        filter: current.filter,
        afterCursor: current.posts.isNotEmpty
            ? current.posts.last.createdAt.millisecondsSinceEpoch
            : null,
        existingAuthorIds: current.posts.map((post) => post.authorId).toSet(),
      );

      _emitIfOpen(current.copyWith(
        posts: [...current.posts, ...batch.posts],
        hasMore: batch.hasMore,
        isLoadingMore: false,
      ));
    } catch (e) {
      _emitIfOpen(current.copyWith(isLoadingMore: false));
    }
  }

  Future<_FeedBatchResult> _loadGroupedBatch({
    required FeedFilter filter,
    required Set<String> existingAuthorIds,
    int? afterCursor,
  }) async {
    final collectedPosts = <PostModel>[];
    final seenPostIds = <String>{};
    final seenAuthorIds = <String>{...existingAuthorIds};

    var cursor = afterCursor;
    var hasMore = true;
    final currentUserId = _activeUserId;

    var enforceFollowingOnly = filter.followingOnly;
    Set<String> followedAuthorIds = const <String>{};
    if (enforceFollowingOnly) {
      if (currentUserId == null || currentUserId.isEmpty) {
        debugPrint(
          '[FeedCubit] followingOnly requested for guest; falling back to unfiltered feed.',
        );
        enforceFollowingOnly = false;
      } else {
        followedAuthorIds = await _postDao.getFollowedUserIds(currentUserId);
        if (followedAuthorIds.isEmpty) {
          return const _FeedBatchResult(posts: <PostModel>[], hasMore: false);
        }
      }
    }

    for (var page = 0; page < _maxPrefetchPages; page++) {
      final pagePosts = await _postDao.getFeedPage(
        pageSize: _pageSize,
        afterCursor: cursor,
        filterFaculty: filter.faculty,
        filterCategory: filter.category,
        filterType: filter.type,
        groupsOnly: filter.groupsOnly,
        currentUserId: _activeUserId,
        includePendingForAdmin: _canViewPendingModeration,
      );

      if (pagePosts.isEmpty) {
        hasMore = false;
        break;
      }

      var scopedPagePosts = pagePosts;
      if (enforceFollowingOnly) {
        scopedPagePosts = scopedPagePosts
            .where((post) => followedAuthorIds.contains(post.authorId))
            .toList(growable: false);
      }
      if (filter.searchedUserId != null && filter.searchedUserId!.isNotEmpty) {
        scopedPagePosts = scopedPagePosts
            .where((post) => post.authorId == filter.searchedUserId)
            .toList(growable: false);
      }
      scopedPagePosts = scopedPagePosts
          .where((post) => !_isExpiredAdvert(post))
          .toList(growable: false);

      for (final post in scopedPagePosts) {
        if (seenPostIds.add(post.id)) {
          collectedPosts.add(post);
          seenAuthorIds.add(post.authorId);
        }
      }

      if (pagePosts.length < _pageSize) {
        hasMore = false;
        break;
      }

      cursor = pagePosts.last.createdAt.millisecondsSinceEpoch;

      if (seenAuthorIds.length >=
          existingAuthorIds.length + _targetAuthorGroups) {
        break;
      }
    }

    final rankedPosts = await _rankPosts(
      posts: collectedPosts,
      useHybrid: afterCursor == null,
    );

    var finalPosts = rankedPosts.isEmpty && collectedPosts.isNotEmpty
        ? collectedPosts
        : rankedPosts;

    if (filter.faculty != null && filter.faculty!.trim().isNotEmpty) {
      finalPosts = [...finalPosts]..shuffle(Random());
    }

    debugPrint(
      '[FeedCubit] ✅ batch ready — '
      'raw=${collectedPosts.length} ranked=${rankedPosts.length} '
      'serving=${finalPosts.length} '
      'filter=${filter.type ?? 'all'} user=${_activeUserId ?? 'guest'}',
    );

    return _FeedBatchResult(posts: finalPosts, hasMore: hasMore);
  }

  Future<List<PostModel>> _rankPosts({
    required List<PostModel> posts,
    required bool useHybrid,
  }) async {
    final log = StringBuffer();
    log.writeln('');
    log.writeln('══════════════════════════════════════════════════════');
    log.writeln('  📊 RECOMMENDATION ENGINE');
    log.writeln('══════════════════════════════════════════════════════');
    log.writeln('  Candidates : ${posts.length}');

    // ── Fallback helper ─────────────────────────────────────────────────────
    List<PostModel> dateSorted() =>
        ([...posts]..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

    if (posts.isEmpty) {
      log.writeln('  ⚠  Nothing to rank — list is empty');
      log.writeln('══════════════════════════════════════════════════════');
      debugPrint(log.toString());
      return posts;
    }

    // ── User context ─────────────────────────────────────────────────────────
    final currentUserId = _activeUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      log.writeln('  User       : guest (unauthenticated)');
      log.writeln('  Strategy   : date-descending (no profile available)');
      final sorted = dateSorted();
      log.writeln('  ✓ Serving  : ${sorted.length} posts (newest → oldest)');
      log.writeln('══════════════════════════════════════════════════════');
      debugPrint(log.toString());
      return sorted;
    }

    final uidTail = currentUserId.length > 8
        ? '…${currentUserId.substring(currentUserId.length - 8)}'
        : currentUserId;
    log.writeln('  User       : $uidTail');

    final user = await _userDao.getUserById(currentUserId);
    if (user == null || user.profile == null) {
      log.writeln(
          '  Profile    : ⚠  not found in local DB (sync may still be running)');
      log.writeln('  Strategy   : date-descending fallback');
      final sorted = dateSorted();
      log.writeln('  ✓ Serving  : ${sorted.length} posts (newest → oldest)');
      log.writeln('══════════════════════════════════════════════════════');
      debugPrint(log.toString());
      return sorted;
    }

    // ── Profile summary ───────────────────────────────────────────────────────
    final profile = user.profile!;
    final skills = profile.skills;
    final skillPreview = skills.isEmpty
        ? 'none'
        : '${skills.take(3).join(', ')}${skills.length > 3 ? ' (+${skills.length - 3} more)' : ''}';
    log.writeln('  Role       : ${user.role.name}');
    log.writeln('  Faculty    : ${profile.faculty ?? 'unknown'}');
    log.writeln('  Program    : ${profile.programName ?? 'unknown'}');
    log.writeln('  Skills     : $skillPreview');

    // ── Activity signals ──────────────────────────────────────────────────────
    final recentlyViewedCategories =
        await _activityLogDao.getRecentCategorySignals(currentUserId);
    final recentSearchTerms =
        await _activityLogDao.getRecentSearchTerms(currentUserId);
    final postRatingSignals =
        await _activityLogDao.getPostRatingSignalsForPosts(
      posts.map((post) => post.id).toList(),
    );
    log.writeln(
        '  Viewed cats: ${recentlyViewedCategories.isEmpty ? 'none yet' : recentlyViewedCategories.take(4).join(', ')}');
    log.writeln(
        '  Searches   : ${recentSearchTerms.isEmpty ? 'none yet' : recentSearchTerms.take(4).join(', ')}');
    log.writeln(
        '  Ratings    : lecturer=${postRatingSignals.lecturerRatings.length}, student=${postRatingSignals.studentRatings.length}');
    log.writeln(
        '  Mode       : ${useHybrid ? 'hybrid (local + Gemini rerank)' : 'local scoring only'}');
    log.writeln('──────────────────────────────────────────────────────');

    // ── Run ranker ────────────────────────────────────────────────────────────
    final ranked = useHybrid
        ? await _recommenderService.rankHybrid(
            user: user,
            candidates: posts,
            recentlyViewedCategories: recentlyViewedCategories,
            recentSearchTerms: recentSearchTerms,
            lecturerRatingsByPost: postRatingSignals.lecturerRatings,
            studentRatingsByPost: postRatingSignals.studentRatings,
          )
        : _recommenderService.rankLocally(
            user: user,
            candidates: posts,
            recentlyViewedCategories: recentlyViewedCategories,
            recentSearchTerms: recentSearchTerms,
            lecturerRatingsByPost: postRatingSignals.lecturerRatings,
            studentRatingsByPost: postRatingSignals.studentRatings,
          );

    // ── Log ranked results ────────────────────────────────────────────────────
    const maxLogRows = 5;
    if (ranked.isNotEmpty) {
      final logCount = ranked.length.clamp(0, maxLogRows);
      log.writeln('  Ranked ${ranked.length} post(s) — top $logCount shown:');
      for (var i = 0; i < logCount; i++) {
        final r = ranked[i];
        final scoreStr = r.score.toStringAsFixed(3);
        final title = r.post.title.length > 32
            ? '${r.post.title.substring(0, 29)}…'
            : r.post.title;
        final reasons = r.reasons.isEmpty ? 'baseline' : r.reasons.join(', ');
        log.writeln('    #${i + 1}  [$scoreStr]  "$title"');
        log.writeln('           signals: $reasons');
      }
      if (ranked.length > maxLogRows) {
        log.writeln(
            '    … ${ranked.length - maxLogRows} more post(s) below threshold');
      }
    } else {
      log.writeln(
          '  ⚠  Ranker returned 0 results (unexpected) — applying date fallback');
    }

    log.writeln('──────────────────────────────────────────────────────');

    // ── Guarantee non-empty result ────────────────────────────────────────────
    if (ranked.isEmpty) {
      final sorted = dateSorted();
      log.writeln('  FALLBACK   : date-descending (${sorted.length} posts)');
      log.writeln('══════════════════════════════════════════════════════');
      debugPrint(log.toString());
      return sorted;
    }

    final rankedPosts = ranked.map((entry) => entry.post).toList();
    final fairnessAdjusted = _injectCrossFacultyVideoFairness(
      posts: rankedPosts,
      homeFaculty: profile.faculty,
    );

    final movedSlots = _countMovedSlots(rankedPosts, fairnessAdjusted);
    if (movedSlots > 0) {
      await _activityLogDao.logAction(
        userId: currentUserId,
        action: 'feed_fairness_injected',
        entityType: DatabaseSchema.tablePosts,
        metadata: {
          'strategy': 'cross_faculty_video_3_to_1',
          'movedSlots': movedSlots,
          'candidateCount': rankedPosts.length,
        },
      );
    }

    log.writeln(
        '  ✓ Serving  : ${fairnessAdjusted.length} posts (ranked order)');
    log.writeln('══════════════════════════════════════════════════════');
    debugPrint(log.toString());

    // Log top 25 scored posts to recommendation_logs (SQLite + Firestore)
    if (_recLogDao != null && ranked.isNotEmpty) {
      final algoLabel = useHybrid ? 'hybrid' : 'local';
      final entries = ranked
          .take(25)
          .map((r) => RecommendationLogEntry(
                userId: currentUserId,
                itemId: r.post.id,
                itemType: 'post',
                algorithm: algoLabel,
                score: r.score,
                reasons: r.reasons,
              ))
          .toList();
      _recLogDao.insertBatch(entries).catchError(
            (e) => debugPrint('[FeedCubit] rec log failed: $e'),
          );
    }

    return fairnessAdjusted;
  }

  List<PostModel> _injectCrossFacultyVideoFairness({
    required List<PostModel> posts,
    required String? homeFaculty,
  }) {
    final normalizedHomeFaculty = homeFaculty?.trim().toLowerCase();
    if (normalizedHomeFaculty == null || normalizedHomeFaculty.isEmpty) {
      return posts;
    }

    final videoIndexes = <int>[];
    final videos = <PostModel>[];
    for (var i = 0; i < posts.length; i++) {
      final post = posts[i];
      if (_isVideoPost(post)) {
        videoIndexes.add(i);
        videos.add(post);
      }
    }

    if (videos.length < 4) return posts;

    final sameFacultyVideos = <PostModel>[];
    final otherFacultyVideos = <PostModel>[];
    for (final video in videos) {
      final postFaculty = video.faculty?.trim().toLowerCase();
      if (postFaculty?.isNotEmpty == true &&
          postFaculty != normalizedHomeFaculty) {
        otherFacultyVideos.add(video);
      } else {
        sameFacultyVideos.add(video);
      }
    }

    if (otherFacultyVideos.isEmpty || sameFacultyVideos.length < 3) {
      return posts;
    }

    otherFacultyVideos.shuffle(Random());
    final reorderedVideos = <PostModel>[];
    var sameCounter = 0;

    while (sameFacultyVideos.isNotEmpty || otherFacultyVideos.isNotEmpty) {
      if (sameCounter >= 3 && otherFacultyVideos.isNotEmpty) {
        reorderedVideos.add(otherFacultyVideos.removeAt(0));
        sameCounter = 0;
        continue;
      }

      if (sameFacultyVideos.isNotEmpty) {
        reorderedVideos.add(sameFacultyVideos.removeAt(0));
        sameCounter++;
      } else if (otherFacultyVideos.isNotEmpty) {
        reorderedVideos.add(otherFacultyVideos.removeAt(0));
        sameCounter = 0;
      }
    }

    final rebuilt = List<PostModel>.from(posts);
    for (var i = 0;
        i < videoIndexes.length && i < reorderedVideos.length;
        i++) {
      rebuilt[videoIndexes[i]] = reorderedVideos[i];
    }
    return rebuilt;
  }

  bool _isVideoPost(PostModel post) {
    if (post.youtubeUrl != null && post.youtubeUrl!.trim().isNotEmpty) {
      return true;
    }
    for (final url in post.mediaUrls) {
      if (isVideoMediaPath(url)) return true;
      final lower = url.toLowerCase();
      if (RegExp(r'\.(mp4|mov|m4v|3gp|webm|mkv)(\?|$)').hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  int _countMovedSlots(List<PostModel> original, List<PostModel> adjusted) {
    if (original.length != adjusted.length) return 0;
    var moved = 0;
    for (var i = 0; i < original.length; i++) {
      if (original[i].id != adjusted[i].id) moved++;
    }
    return moved;
  }

  bool _isExpiredAdvert(PostModel post) {
    if (post.type != 'advert') return false;
    final deadline = post.opportunityDeadline;
    if (deadline == null) return false;
    return deadline.isBefore(DateTime.now());
  }

  Future<void> ratePost({
    required PostModel post,
    required int stars,
  }) async {
    final current = state;
    if (current is! FeedLoaded) return;
    final currentUserId = _activeUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      debugPrint('[FeedCubit] Ignoring rating because user is guest.');
      return;
    }

    final safeStars = stars.clamp(1, 5);
    final role = _authCubit?.currentUser?.role.name ?? 'student';

    // Find the post and optimistically update rating state
    final index = current.posts.indexWhere((p) => p.id == post.id);
    if (index == -1) return;

    final original = current.posts[index];
    final optimistic = original.copyWith(
      isRatedByMe: true,
      myRatingStars: safeStars,
    );

    final updatedPosts = List<PostModel>.from(current.posts)
      ..[index] = optimistic;
    _emitIfOpen(current.copyWith(posts: updatedPosts));

    try {
      await _activityLogDao.logAction(
        userId: currentUserId,
        action: 'rate_post',
        entityType: DatabaseSchema.tablePosts,
        entityId: post.id,
        metadata: {
          'stars': safeStars,
          'rater_role': role,
          'post_title': post.title,
          'author_id': post.authorId,
        },
      );

      await _syncQueue.enqueue(
        operation: 'create',
        entity: 'post_ratings',
        entityId:
            '${currentUserId}_${post.id}_${DateTime.now().millisecondsSinceEpoch}',
        payload: {
          'post_id': post.id,
          'user_id': currentUserId,
          'stars': safeStars,
          'rater_role': role,
          'author_id': post.authorId,
          'post_title': post.title,
          'rater_name': _authCubit?.currentUser?.displayName ??
              _authCubit?.currentUser?.email ??
              'Someone',
          'rated_at': DateTime.now().toIso8601String(),
        },
      );

      await _postDao.updatePostActionState(
        postId: post.id,
        isRatedByMe: true,
        myRatingStars: safeStars,
      );

      unawaited(_syncService?.processPendingSync());
      debugPrint(
        '[FeedCubit] Rating logged post=${post.id} stars=$safeStars role=$role',
      );
    } catch (e) {
      debugPrint('[FeedCubit] ratePost failed: $e');
      // Rollback on error
      final rollback = List<PostModel>.from(current.posts)..[index] = original;
      _emitIfOpen(current.copyWith(posts: rollback));
    }
  }

  /// Increments comment count and emits updated post state
  Future<void> addCommentToPost(String postId) async {
    final current = state;
    if (current is! FeedLoaded) return;

    final index = current.posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final original = current.posts[index];
    final optimistic = original.copyWith(
      commentCount: original.commentCount + 1,
    );

    final updatedPosts = List<PostModel>.from(current.posts)
      ..[index] = optimistic;
    _emitIfOpen(current.copyWith(posts: updatedPosts));

    debugPrint(
        '[FeedCubit] Comment added to post=$postId new count=${optimistic.commentCount}');
  }

  Future<void> recordPostView(String postId) async {
    final current = state;
    if (current is! FeedLoaded) return;

    final currentUserId = _activeUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    final index = current.posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final original = current.posts[index];
    if (original.isViewedByMe) {
      _traceAction(
        'view',
        'already_viewed',
        userId: currentUserId,
        details: {
          'postId': postId,
        },
      );
      return;
    }

    _traceAction(
      'view',
      'ui_open',
      userId: currentUserId,
      details: {
        'postId': postId,
        'authorId': original.authorId,
      },
    );

    final optimistic = original.copyWith(
      isViewedByMe: true,
      viewCount: original.viewCount + 1,
    );
    final updatedPosts = List<PostModel>.from(current.posts)
      ..[index] = optimistic;
    _emitIfOpen(current.copyWith(posts: updatedPosts));
    _traceAction(
      'view',
      'render_optimistic',
      userId: currentUserId,
      details: {
        'postId': postId,
        'viewCount': optimistic.viewCount,
      },
    );

    try {
      final isNewView = await _postDao.recordUniqueView(
        postId: postId,
        userId: currentUserId,
      );

      if (!isNewView) {
        final correctedPosts = List<PostModel>.from(current.posts)
          ..[index] = original.copyWith(isViewedByMe: true);
        _emitIfOpen(current.copyWith(posts: correctedPosts));
        _traceAction(
          'view',
          'already_persisted',
          userId: currentUserId,
          details: {
            'postId': postId,
          },
        );
        return;
      }

      await _postDao.incrementViewCount(postId);
      _traceAction(
        'view',
        'local_persisted',
        userId: currentUserId,
        details: {
          'postId': postId,
          'viewCount': optimistic.viewCount,
        },
      );

      if (original.type == 'advert') {
        await _activityLogDao.logAction(
          userId: currentUserId,
          action: 'view_advert',
          entityType: DatabaseSchema.tablePosts,
          entityId: original.id,
          metadata: {
            'post_title': original.title,
            'target_faculty': original.faculty,
            'deadline': original.opportunityDeadline?.toIso8601String(),
          },
        );
      }

      await _syncQueue.enqueue(
        operation: 'create',
        entity: 'post_views',
        entityId: '${currentUserId}_${original.id}',
        payload: {
          'viewer_id': currentUserId,
          'viewer_name': _authCubit?.currentUser?.displayName ??
              _authCubit?.currentUser?.email ??
              'Someone',
          'author_id': original.authorId,
          'post_id': original.id,
          'post_title': original.title,
        },
      );
      _traceAction(
        'view',
        'remote_queued',
        userId: currentUserId,
        details: {
          'postId': postId,
          'authorId': original.authorId,
        },
      );

      unawaited(_syncService?.processPendingSync());
    } catch (e) {
      _traceAction(
        'view',
        'failed',
        userId: currentUserId,
        details: {
          'postId': postId,
          'error': e.toString(),
        },
      );
      final rollback = List<PostModel>.from(current.posts)..[index] = original;
      _emitIfOpen(current.copyWith(posts: rollback));
    }
  }

  /// Sets collaboration request state and emits updated post
  Future<void> requestCollaborationWithPost(String postId,
      {String? message}) async {
    final current = state;
    if (current is! FeedLoaded) return;
    final currentUserId = _activeUserId;
    if (currentUserId == null || currentUserId.isEmpty) return;

    final index = current.posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final original = current.posts[index];
    _traceAction(
      'collaborate',
      'ui_tap',
      userId: currentUserId,
      details: {
        'postId': postId,
        'authorId': original.authorId,
      },
    );
    final optimistic = original.copyWith(
      hasCollaborationRequest: true,
    );

    final updatedPosts = List<PostModel>.from(current.posts)
      ..[index] = optimistic;
    _emitIfOpen(current.copyWith(posts: updatedPosts));
    _traceAction(
      'collaborate',
      'render_optimistic',
      userId: currentUserId,
      details: {
        'postId': postId,
        'hasCollaborationRequest': optimistic.hasCollaborationRequest,
      },
    );

    try {
      await _postDao.persistCollaborationRequest(
        senderId: currentUserId,
        receiverId: original.authorId,
        postId: postId,
        message: message,
      );
      _traceAction(
        'collaborate',
        'local_persisted',
        userId: currentUserId,
        details: {
          'postId': postId,
          'receiverId': original.authorId,
        },
      );
      await _postDao.updatePostActionState(
        postId: postId,
        hasCollaborationRequest: true,
      );
      _traceAction(
        'collaborate',
        'render_state_saved',
        userId: currentUserId,
        details: {
          'postId': postId,
          'hasCollaborationRequest': true,
        },
      );
    } catch (e) {
      _traceAction(
        'collaborate',
        'failed',
        userId: currentUserId,
        details: {
          'postId': postId,
          'error': e.toString(),
        },
      );
      final rollback = List<PostModel>.from(current.posts)..[index] = original;
      _emitIfOpen(current.copyWith(posts: rollback));
    }
  }

  /// Sets follow state when user follows post author
  Future<void> followAuthor(String postId) async {
    final current = state;
    if (current is! FeedLoaded) return;
    final currentUserId = _activeUserId;
    if (currentUserId == null || currentUserId.isEmpty) return;

    final index = current.posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final original = current.posts[index];
    _traceAction(
      'follow',
      'ui_tap',
      userId: currentUserId,
      details: {
        'postId': postId,
        'authorId': original.authorId,
      },
    );
    final optimistic = original.copyWith(
      isFollowingAuthor: true,
    );

    final updatedPosts = List<PostModel>.from(current.posts)
      ..[index] = optimistic;
    _emitIfOpen(current.copyWith(posts: updatedPosts));
    _traceAction(
      'follow',
      'render_optimistic',
      userId: currentUserId,
      details: {
        'postId': postId,
        'authorId': original.authorId,
        'isFollowingAuthor': optimistic.isFollowingAuthor,
      },
    );

    try {
      await _postDao.persistFollowRelationship(
        followerId: currentUserId,
        followeeId: original.authorId,
      );
      _traceAction(
        'follow',
        'local_persisted',
        userId: currentUserId,
        details: {
          'postId': postId,
          'authorId': original.authorId,
        },
      );

      await _activityLogDao.logAction(
        userId: currentUserId,
        action: 'follow_user',
        entityType: 'users',
        entityId: original.authorId,
        metadata: {
          'author_name': original.authorName,
          'post_title': original.title,
        },
      );
      _traceAction(
        'follow',
        'activity_logged',
        userId: currentUserId,
        details: {
          'postId': postId,
          'authorId': original.authorId,
        },
      );

      await _syncQueue.enqueue(
        operation: 'create',
        entity: 'follows',
        entityId: '${currentUserId}_${original.authorId}',
        payload: {
          'follower_id': currentUserId,
          'followed_id': original.authorId,
          'follower_name': _authCubit?.currentUser?.displayName ??
              _authCubit?.currentUser?.email ??
              'Someone',
          'followed_at': DateTime.now().toIso8601String(),
        },
      );

      // Push follow immediately so receiver notifications are created
      // without waiting for a later connectivity event.
      unawaited(_syncService?.processPendingSync());
      _traceAction(
        'follow',
        'remote_queued',
        userId: currentUserId,
        details: {
          'postId': postId,
          'authorId': original.authorId,
        },
      );

      await _postDao.updatePostActionState(
        postId: postId,
        isFollowingAuthor: true,
      );
      _traceAction(
        'follow',
        'render_state_saved',
        userId: currentUserId,
        details: {
          'postId': postId,
          'authorId': original.authorId,
          'isFollowingAuthor': true,
        },
      );
    } catch (e) {
      _traceAction(
        'follow',
        'failed',
        userId: currentUserId,
        details: {
          'postId': postId,
          'authorId': original.authorId,
          'error': e.toString(),
        },
      );
      final rollback = List<PostModel>.from(current.posts)..[index] = original;
      _emitIfOpen(current.copyWith(posts: rollback));
    }
  }

  // ── Apply filters ──────────────────────────────────────────────────────────

  Future<void> applyFilter(FeedFilter filter) async {
    final userId = _activeUserId;
    if (userId != null && userId.isNotEmpty) {
      final previous = state is FeedLoaded
          ? (state as FeedLoaded).filter
          : const FeedFilter();
      await _activityLogDao.logAction(
        userId: userId,
        action: 'feed_filter_applied',
        entityType: DatabaseSchema.tablePosts,
        entityId: filter.searchedUserId,
        metadata: {
          'from': {
            'faculty': previous.faculty,
            'type': previous.type,
            'groupsOnly': previous.groupsOnly,
            'followingOnly': previous.followingOnly,
            'searchedUserId': previous.searchedUserId,
          },
          'to': {
            'faculty': filter.faculty,
            'type': filter.type,
            'groupsOnly': filter.groupsOnly,
            'followingOnly': filter.followingOnly,
            'searchedUserId': filter.searchedUserId,
            'searchedUserName': filter.searchedUserName,
          },
        },
      );
    }
    await loadFeed(filter: filter);
  }

  Future<void> clearFilters() async {
    await loadFeed(filter: const FeedFilter());
  }

  Future<void> refreshPostFromLocal(String postId) async {
    final current = state;
    if (current is! FeedLoaded) return;

    final index = current.posts.indexWhere((post) => post.id == postId);
    if (index == -1) return;

    try {
      final latest =
          await _postDao.getPostById(postId, currentUserId: _activeUserId);
      if (latest == null) return;

      final updated = List<PostModel>.from(current.posts)..[index] = latest;
      _emitIfOpen(current.copyWith(posts: updated));
    } catch (e) {
      debugPrint(
          '[FeedCubit] refreshPostFromLocal failed for post=$postId: $e');
    }
  }

  // ── Optimistic Like ────────────────────────────────────────────────────────

  Future<void> likePost(String postId) async {
    final current = state;
    if (current is! FeedLoaded) return;
    final currentUserId = _activeUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      debugPrint(
          '[FeedCubit] Ignoring like for post=$postId because no authenticated user is available.');
      return;
    }

    // 1. Find the target post and optimistically toggle
    final index = current.posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final original = current.posts[index];
    final wasLiked = original.isLikedByMe;
    final optimistic = original.copyWith(
      isLikedByMe: !wasLiked,
      likeCount: wasLiked
          ? (original.likeCount - 1).clamp(0, 999999)
          : original.likeCount + 1,
    );

    final updatedPosts = List<PostModel>.from(current.posts)
      ..[index] = optimistic;

    // 2. Emit immediately → user sees feedback in <16ms
    _emitIfOpen(current.copyWith(posts: updatedPosts));

    try {
      debugPrint(
        '[FeedCubit] Toggling like locally for post=$postId user=$currentUserId wasLiked=$wasLiked',
      );
      // 3. Persist locally
      final newCount = await _postDao.toggleLike(
        postId: postId,
        userId: currentUserId,
      );
      await _activityLogDao.logAction(
        userId: currentUserId,
        action: wasLiked ? 'unlike_post' : 'like_post',
        entityType: 'posts',
        entityId: postId,
        metadata: {
          'post_title': original.title,
          'author_id': original.authorId,
        },
      );

      // 4. Enqueue for Firestore sync
      final actionAtIso = DateTime.now().toIso8601String();
      await _syncQueue.enqueue(
        operation: wasLiked ? 'delete' : 'create',
        entity: 'likes',
        entityId: '${currentUserId}_$postId',
        payload: {
          'post_id': postId,
          'user_id': currentUserId,
          'is_liking': !wasLiked,
          'liked_at': actionAtIso,
          'like_count': newCount,
          'author_id': original.authorId,
          'post_title': original.title,
          'actor_name': _authCubit?.currentUser?.displayName ??
              _authCubit?.currentUser?.email ??
              'Someone',
        },
      );
      if (!wasLiked && original.isDislikedByMe) {
        await _syncQueue.enqueue(
          operation: 'delete',
          entity: 'dislikes',
          entityId: '${currentUserId}_$postId',
          payload: {
            'post_id': postId,
            'user_id': currentUserId,
            'is_disliking': false,
          },
        );
      }
      debugPrint(
        '[FeedCubit] Like queued for post=$postId user=$currentUserId isLiking=${!wasLiked} localCount=$newCount',
      );
      unawaited(_syncService?.processPendingSync());

      // 5. Update with DB-confirmed count
      final confirmed = current.posts.toList()
        ..[index] = optimistic.copyWith(likeCount: newCount);
      if (state is FeedLoaded) {
        _emitIfOpen((state as FeedLoaded).copyWith(posts: confirmed));
      }
    } catch (_) {
      debugPrint(
          '[FeedCubit] Like toggle failed for post=$postId user=$_currentUserId. Rolling back optimistic UI.');
      // 6. Rollback on failure
      if (state is FeedLoaded) {
        final rolled = (state as FeedLoaded).posts.toList()..[index] = original;
        _emitIfOpen((state as FeedLoaded).copyWith(posts: rolled));
      }
    }
  }

  Future<void> toggleSavePost(String postId) async {
    final current = state;
    if (current is! FeedLoaded) return;
    final currentUserId = _activeUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      debugPrint(
        '[FeedCubit] Ignoring save for post=$postId because no authenticated user is available.',
      );
      return;
    }

    final index = current.posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final original = current.posts[index];
    final wasSaved = original.isSavedByMe;
    final optimistic = original.copyWith(isSavedByMe: !wasSaved);

    final updatedPosts = List<PostModel>.from(current.posts)
      ..[index] = optimistic;
    _emitIfOpen(current.copyWith(posts: updatedPosts));

    try {
      await _postDao.updatePostActionState(
        postId: postId,
        isSavedByMe: !wasSaved,
      );
      await _activityLogDao.logAction(
        userId: currentUserId,
        action: wasSaved ? 'unsave_post' : 'save_post',
        entityType: 'posts',
        entityId: postId,
        metadata: {
          'post_title': original.title,
          'author_id': original.authorId
        },
      );
    } catch (e) {
      debugPrint('[FeedCubit] Save toggle failed for post=$postId: $e');
      if (state is FeedLoaded) {
        final rolled = (state as FeedLoaded).posts.toList()..[index] = original;
        _emitIfOpen((state as FeedLoaded).copyWith(posts: rolled));
      }
    }
  }

  // ── Optimistic Dislike ─────────────────────────────────────────────────────

  Future<void> dislikePost(String postId) async {
    final current = state;
    if (current is! FeedLoaded) return;
    final currentUserId = _activeUserId;
    if (currentUserId == null || currentUserId.isEmpty) return;

    final index = current.posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final original = current.posts[index];
    final wasDisliked = original.isDislikedByMe;
    final optimistic = original.copyWith(
      isDislikedByMe: !wasDisliked,
      dislikeCount: wasDisliked
          ? (original.dislikeCount - 1).clamp(0, 999999)
          : original.dislikeCount + 1,
    );

    final updatedPosts = List<PostModel>.from(current.posts)
      ..[index] = optimistic;
    _emitIfOpen(current.copyWith(posts: updatedPosts));

    try {
      final newCount = await _postDao.toggleDislike(
        postId: postId,
        userId: currentUserId,
      );
      await _activityLogDao.logAction(
        userId: currentUserId,
        action: wasDisliked ? 'undislike_post' : 'dislike_post',
        entityType: 'posts',
        entityId: postId,
        metadata: {
          'post_title': original.title,
          'author_id': original.authorId
        },
      );
      await _syncQueue.enqueue(
        operation: wasDisliked ? 'delete' : 'create',
        entity: 'dislikes',
        entityId: '${currentUserId}_$postId',
        payload: {
          'post_id': postId,
          'user_id': currentUserId,
          'is_disliking': !wasDisliked,
          'dislike_count': newCount,
          'author_id': original.authorId,
        },
      );
      if (!wasDisliked && original.isLikedByMe) {
        await _syncQueue.enqueue(
          operation: 'delete',
          entity: 'likes',
          entityId: '${currentUserId}_$postId',
          payload: {
            'post_id': postId,
            'user_id': currentUserId,
            'is_liking': false,
          },
        );
      }
      unawaited(_syncService?.processPendingSync());
      final confirmed = current.posts.toList()
        ..[index] = optimistic.copyWith(dislikeCount: newCount);
      if (state is FeedLoaded) {
        _emitIfOpen((state as FeedLoaded).copyWith(posts: confirmed));
      }
    } catch (_) {
      if (state is FeedLoaded) {
        final rolled = (state as FeedLoaded).posts.toList()..[index] = original;
        _emitIfOpen((state as FeedLoaded).copyWith(posts: rolled));
      }
    }
  }

  // ── Publish new post ───────────────────────────────────────────────────────

  bool _hasPendingLocalMedia(PostModel post) {
    return post.mediaUrls.any(isLocalMediaPath);
  }

  Future<PublishPostResult> publishPost(PostModel post) async {
    try {
      await _postDao.insertPost(post);
      await _syncQueue.enqueue(
        operation: 'create',
        entity: 'posts',
        entityId: post.id,
        payload: post.toMap(),
      );
      // Prepend to current feed for instant visibility
      if (state is FeedLoaded) {
        final current = state as FeedLoaded;
        _emitIfOpen(current.copyWith(posts: [post, ...current.posts]));
      } else {
        await loadFeed();
      }

      final syncResult = await _syncService?.processPendingSync();
      if (syncResult != null &&
          syncResult.failed == 0 &&
          syncResult.remaining == 0) {
        return const PublishPostResult(
          savedLocally: true,
          syncedRemotely: true,
          message: 'Post published successfully and synced to Firebase.',
        );
      }

      if (syncResult != null && syncResult.failed > 0) {
        return PublishPostResult(
          savedLocally: true,
          syncedRemotely: false,
          message: _hasPendingLocalMedia(post)
              ? 'Post saved locally. Media upload or remote sync is still pending and will retry automatically.'
              : 'Post saved locally, but Firebase sync is waiting for connection. It will retry automatically.',
        );
      }

      return PublishPostResult(
        savedLocally: true,
        syncedRemotely: false,
        message: _hasPendingLocalMedia(post)
            ? 'Post saved locally. Media upload is still pending and will continue automatically.'
            : 'Post saved locally. Firebase sync is still pending.',
      );
    } catch (e) {
      debugPrint('Publish post error: $e');
      _emitIfOpen(const FeedError(
        'Could not publish your post right now. Please try again.',
      ));
      return const PublishPostResult(
        savedLocally: false,
        syncedRemotely: false,
        message: 'Could not publish your post right now. Please try again.',
      );
    }
  }

  // ── Refresh ────────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    _ensureAuthListener();
    final currentFilter =
        state is FeedLoaded ? (state as FeedLoaded).filter : const FeedFilter();
    await loadFeed(filter: currentFilter, forceSync: true);
  }

  void _startFeedRealtimeWatcher() {
    if (_feedRealtimeSub != null || _firestore == null) return;
    _feedRealtimeSub = _firestore.watchRecentPostActivityTicks().listen((_) {
      _feedRefreshDebounce?.cancel();
      _feedRefreshDebounce = Timer(const Duration(milliseconds: 800), () {
        final current = state;
        if (current is FeedLoaded) {
          unawaited(_syncFeedInBackground(filter: current.filter));
        }
      });
    });
  }

  void _stopFeedRealtimeWatcher() {
    _feedRefreshDebounce?.cancel();
    _feedRefreshDebounce = null;
    _feedRealtimeSub?.cancel();
    _feedRealtimeSub = null;
  }

  @override
  Future<void> close() async {
    _stopFeedRealtimeWatcher();
    await _authSub?.cancel();
    _authSub = null;
    return super.close();
  }
}

class _FeedBatchResult {
  final List<PostModel> posts;
  final bool hasMore;

  const _FeedBatchResult({
    required this.posts,
    required this.hasMore,
  });
}
