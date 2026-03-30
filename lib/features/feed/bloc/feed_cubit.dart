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
import '../../../data/models/post_model.dart';
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

  const FeedFilter({
    this.faculty,
    this.category,
    this.type,
    this.recency,
  });

  bool get isActive =>
      faculty != null || category != null || type != null || recency != null;

  FeedFilter copyWith({
    String? faculty,
    String? category,
    String? type,
    String? recency,
    bool clearFaculty = false,
    bool clearCategory = false,
    bool clearType = false,
    bool clearRecency = false,
  }) =>
      FeedFilter(
        faculty: clearFaculty ? null : faculty ?? this.faculty,
        category: clearCategory ? null : category ?? this.category,
        type: clearType ? null : type ?? this.type,
        recency: clearRecency ? null : recency ?? this.recency,
      );

  @override
  List<Object?> get props => [faculty, category, type, recency];
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
  StreamSubscription<AuthState>? _authSub;
  String? _lastObservedAuthUserId;
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
    String? currentUserId,
    AuthCubit? authCubit,
  })  : _postDao = postDao ?? PostDao(),
        _userDao = userDao ?? UserDao(),
        _activityLogDao = activityLogDao ?? ActivityLogDao(),
        _recommenderService = recommenderService ?? RecommenderService(),
        _recLogDao = recLogDao,
        _syncQueue = syncQueue ?? SyncQueueDao(),
        _syncService = syncService,
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
      unawaited(loadFeed(filter: const FeedFilter()));
    });
  }

  String? get _activeUserId => _authCubit?.currentUser?.id ?? _currentUserId;

  void _emitIfOpen(FeedState nextState) {
    if (!isClosed) {
      emit(nextState);
    }
  }

  // ── Load first page ────────────────────────────────────────────────────────

  Future<void> loadFeed({FeedFilter? filter}) async {
    _ensureAuthListener();
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
      await _syncService?.syncRemoteToLocal(postLimit: _pageSize * 3);
      if (isClosed) return;
      final syncEndTime = DateTime.now();
      debugPrint(
        '[FeedCubit] loadFeed sync finished '
        'filter=${requestedFilter.type ?? 'all'} '
        'user=${_activeUserId ?? 'guest'} '
        'syncDuration=${syncEndTime.difference(startTime).inMilliseconds}ms',
      );
      final f = requestedFilter;
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
    } catch (e) {
      debugPrint('Feed load error: $e');
      _emitIfOpen(const FeedError(
        'Could not load your feed right now. Please try again.',
      ));
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

    for (var page = 0; page < _maxPrefetchPages; page++) {
      final pagePosts = await _postDao.getFeedPage(
        pageSize: _pageSize,
        afterCursor: cursor,
        filterFaculty: filter.faculty,
        filterCategory: filter.category,
        filterType: filter.type,
        currentUserId: _activeUserId,
      );

      if (pagePosts.isEmpty) {
        hasMore = false;
        break;
      }

      for (final post in pagePosts) {
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

    final finalPosts = rankedPosts.isEmpty && collectedPosts.isNotEmpty
        ? collectedPosts
        : rankedPosts;

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
    final postRatingSignals = await _activityLogDao.getPostRatingSignalsForPosts(
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

    log.writeln('  ✓ Serving  : ${ranked.length} posts (ranked order)');
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

    return ranked.map((entry) => entry.post).toList();
  }

  Future<void> ratePost({
    required PostModel post,
    required int stars,
  }) async {
    final currentUserId = _activeUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      debugPrint('[FeedCubit] Ignoring rating because user is guest.');
      return;
    }

    final safeStars = stars.clamp(1, 5);
    final role = _authCubit?.currentUser?.role.name ?? 'student';

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
        entityId: '${currentUserId}_${post.id}_${DateTime.now().millisecondsSinceEpoch}',
        payload: {
          'post_id': post.id,
          'user_id': currentUserId,
          'stars': safeStars,
          'rater_role': role,
          'rated_at': DateTime.now().toIso8601String(),
        },
      );

      unawaited(_syncService?.processPendingSync());
      debugPrint(
        '[FeedCubit] Rating logged post=${post.id} stars=$safeStars role=$role',
      );
    } catch (e) {
      debugPrint('[FeedCubit] ratePost failed: $e');
    }
  }

  // ── Apply filters ──────────────────────────────────────────────────────────

  Future<void> applyFilter(FeedFilter filter) async {
    await loadFeed(filter: filter);
  }

  Future<void> clearFilters() async {
    await loadFeed(filter: const FeedFilter());
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
      await _syncQueue.enqueue(
        operation: wasLiked ? 'delete' : 'create',
        entity: 'likes',
        entityId: '${currentUserId}_$postId',
        payload: {
          'post_id': postId,
          'user_id': currentUserId,
          'is_liking': !wasLiked,
          'like_count': newCount,
          'author_id': original.authorId,
          'post_title': original.title,
        },
      );
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

    final updatedPosts = List<PostModel>.from(current.posts)..[index] = optimistic;
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
        metadata: {'post_title': original.title, 'author_id': original.authorId},
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
              ? 'Post saved offline. Media will upload and sync automatically when network is available.'
              : 'Post saved locally, but Firebase sync is waiting for connection. It will retry automatically.',
        );
      }

      return PublishPostResult(
        savedLocally: true,
        syncedRemotely: false,
        message: _hasPendingLocalMedia(post)
            ? 'Post saved locally. Media will upload automatically once you are back online.'
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
    await loadFeed(filter: currentFilter);
  }

  @override
  Future<void> close() async {
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
