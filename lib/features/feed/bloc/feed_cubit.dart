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
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/recommender_service.dart';
import '../../../data/remote/sync_service.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class FeedState extends Equatable {
  const FeedState();
  @override List<Object?> get props => [];
}

class FeedInitial extends FeedState { const FeedInitial(); }

class FeedLoading extends FeedState { const FeedLoading(); }

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
  }) => FeedLoaded(
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
  @override List<Object?> get props => [message];
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

  bool get isActive => faculty != null || category != null || type != null || recency != null;

  FeedFilter copyWith({
    String? faculty,
    String? category,
    String? type,
    String? recency,
    bool clearFaculty = false,
    bool clearCategory = false,
    bool clearType = false,
    bool clearRecency = false,
  }) => FeedFilter(
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
  final SyncQueueDao _syncQueue;
  final SyncService? _syncService;
  final String? _currentUserId;
  static const _pageSize = 40;
  static const _targetAuthorGroups = 12;
  static const _maxPrefetchPages = 6;

  FeedCubit({
    PostDao? postDao,
    UserDao? userDao,
    ActivityLogDao? activityLogDao,
    RecommenderService? recommenderService,
    SyncQueueDao? syncQueue,
    SyncService? syncService,
    String? currentUserId,
  })  : _postDao = postDao ?? PostDao(),
        _userDao = userDao ?? UserDao(),
        _activityLogDao = activityLogDao ?? ActivityLogDao(),
        _recommenderService = recommenderService ?? RecommenderService(),
        _syncQueue = syncQueue ?? SyncQueueDao(),
        _syncService = syncService,
        _currentUserId = currentUserId,
        super(const FeedInitial());

  void _emitIfOpen(FeedState nextState) {
    if (!isClosed) {
      emit(nextState);
    }
  }

  // ── Load first page ────────────────────────────────────────────────────────

  Future<void> loadFeed({FeedFilter? filter}) async {
    _emitIfOpen(const FeedLoading());
    try {
      await _syncService?.syncRemoteToLocal(postLimit: _pageSize * 3);
      if (isClosed) return;
      final f = filter ?? const FeedFilter();
      final batch = await _loadGroupedBatch(
        filter: f,
        existingAuthorIds: const <String>{},
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
        currentUserId: _currentUserId,
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

      if (seenAuthorIds.length >= existingAuthorIds.length + _targetAuthorGroups) {
        break;
      }
    }

    final rankedPosts = await _rankPosts(
      posts: collectedPosts,
      useHybrid: afterCursor == null,
    );

    return _FeedBatchResult(posts: rankedPosts, hasMore: hasMore);
  }

  Future<List<PostModel>> _rankPosts({
    required List<PostModel> posts,
    required bool useHybrid,
  }) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty || posts.isEmpty) {
      return posts;
    }

    final user = await _userDao.getUserById(currentUserId);
    if (user == null || user.profile == null) {
      return posts;
    }

    final recentlyViewedCategories =
        await _activityLogDao.getRecentCategorySignals(currentUserId);
    final recentSearchTerms =
        await _activityLogDao.getRecentSearchTerms(currentUserId);

    final ranked = useHybrid
        ? await _recommenderService.rankHybrid(
            user: user,
            candidates: posts,
            recentlyViewedCategories: recentlyViewedCategories,
            recentSearchTerms: recentSearchTerms,
          )
        : _recommenderService.rankLocally(
            user: user,
            candidates: posts,
            recentlyViewedCategories: recentlyViewedCategories,
            recentSearchTerms: recentSearchTerms,
          );

    return ranked.map((entry) => entry.post).toList();
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
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      debugPrint('[FeedCubit] Ignoring like for post=$postId because no authenticated user is available.');
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
        '[FeedCubit] Toggling like locally for post=$postId user=$_currentUserId wasLiked=$wasLiked',
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
        '[FeedCubit] Like queued for post=$postId user=$_currentUserId isLiking=${!wasLiked} localCount=$newCount',
      );
      unawaited(_syncService?.processPendingSync());

      // 5. Update with DB-confirmed count
      final confirmed = current.posts.toList()
        ..[index] = optimistic.copyWith(likeCount: newCount);
      if (state is FeedLoaded) {
        _emitIfOpen((state as FeedLoaded).copyWith(posts: confirmed));
      }
    } catch (_) {
      debugPrint('[FeedCubit] Like toggle failed for post=$postId user=$_currentUserId. Rolling back optimistic UI.');
      // 6. Rollback on failure
      if (state is FeedLoaded) {
        final rolled = (state as FeedLoaded).posts.toList()
          ..[index] = original;
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
      if (syncResult != null && syncResult.failed == 0 && syncResult.remaining == 0) {
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
    final currentFilter = state is FeedLoaded
        ? (state as FeedLoaded).filter
        : const FeedFilter();
    await loadFeed(filter: currentFilter);
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