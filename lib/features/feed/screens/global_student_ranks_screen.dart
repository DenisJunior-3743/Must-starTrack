import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/comment_dao.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/remote/recommender_service.dart';
import '../../auth/bloc/auth_cubit.dart';

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 80, spreadRadius: 24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class GlobalStudentRanksScreen extends StatefulWidget {
  final String title;
  final String initialFaculty;
  final String searchHint;
  final String emptyStateText;
  final String monthTabLabel;
  final String semesterTabLabel;
  final String allTimeTabLabel;
  final bool showCurrentFacultyName;

  const GlobalStudentRanksScreen({
    super.key,
    this.title = 'Faculty Leaderboard',
    this.initialFaculty = 'All Faculties',
    this.searchHint = 'Search student',
    this.emptyStateText = 'No students found',
    this.monthTabLabel = 'This Month',
    this.semesterTabLabel = 'This Semester',
    this.allTimeTabLabel = 'All Time',
    this.showCurrentFacultyName = true,
  });

  @override
  State<GlobalStudentRanksScreen> createState() =>
      _GlobalStudentRanksScreenState();
}

enum _LeaderboardTimeRange { sprint, term, allTime }

class _GlobalStudentRanksScreenState extends State<GlobalStudentRanksScreen> {
  static const String _defaultFaculty = 'Faculty of Computing and Informatic';
  static const int _studentLoadLimit = 5000;
  static const int _projectSignalLimit = 800;
  static const int _localProjectSignalLimit = 320;
  static const int _commentSignalPostLimit = 160;
  static const Duration _signalLoadTimeout = Duration(seconds: 10);

  final _firestore = sl<FirestoreService>();
  final _userDao = sl<UserDao>();
  final _postDao = sl<PostDao>();
  final _commentDao = sl<CommentDao>();
  final _recommenderService = sl<RecommenderService>();

  bool _loading = true;
  bool _refreshingSignals = false;
  String? _error;
  List<_RankedUser> _baseUsers = const [];
  List<PostModel> _projectPosts = const [];
  Map<String, int> _followerCountsIndex = const <String, int>{};
  Map<String, double> _commentSentimentByStudent = const <String, double>{};

  _LeaderboardTimeRange _timeRange = _LeaderboardTimeRange.sprint;
  late String _selectedFaculty;
  String _searchQuery = '';

  List<String> _facultyNames = const <String>[];
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _selectedFaculty = widget.initialFaculty.trim().isEmpty
        ? 'All Faculties'
        : widget.initialFaculty.trim();
    _loadFacultiesAndUsers();
  }

  Future<void> _loadFacultiesAndUsers() async {
    await _loadUsers();
  }

  Future<void> _loadFacultyNames(int loadVersion) async {
    final facultyNames = await _safeLoad<List<String>>(
      'faculty names',
      () => _firestore.getActiveFacultyNames(),
      const <String>[],
    );
    if (!mounted || loadVersion != _loadVersion || facultyNames.isEmpty) {
      return;
    }
    setState(() {
      _facultyNames = facultyNames;
    });
  }

  Future<List<UserModel>> _loadLocalStudents() async {
    try {
      final users = await _userDao.getAllUsers(
        role: 'student',
        includeSuspended: false,
        pageSize: _studentLoadLimit,
      );
      return users.where(_isEligibleStudent).toList(growable: false);
    } catch (error) {
      debugPrint('[MobileGlobalRank] local students unavailable: $error');
      return const <UserModel>[];
    }
  }

  Future<List<PostModel>> _loadLocalProjectPosts({required int limit}) async {
    try {
      final posts = await _postDao.getFeedPage(
        pageSize: limit,
        filterType: 'project',
      );
      return _projectSignalPosts(posts);
    } catch (error) {
      debugPrint(
          '[MobileGlobalRank] local project signals unavailable: $error');
      return const <PostModel>[];
    }
  }

  Future<T> _safeLoad<T>(
    String label,
    Future<T> Function() loader,
    T fallback, {
    Duration timeout = _signalLoadTimeout,
  }) async {
    try {
      return await loader().timeout(timeout);
    } catch (error) {
      debugPrint('[MobileGlobalRank] $label unavailable: $error');
      return fallback;
    }
  }

  List<UserModel> _mergeEligibleStudents(
    List<UserModel> localUsers,
    List<UserModel> remoteUsers,
  ) {
    final usersById = <String, UserModel>{};
    for (final user in localUsers) {
      if (_isEligibleStudent(user)) {
        usersById[user.id] = user;
      }
    }
    for (final user in remoteUsers) {
      if (_isEligibleStudent(user)) {
        usersById[user.id] = user;
      }
    }
    return usersById.values.toList(growable: false);
  }

  List<PostModel> _projectSignalPosts(List<PostModel> posts) {
    final filtered = posts
        .where((post) => post.type == 'project' && !post.isArchived)
        .toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered.length > _projectSignalLimit
        ? filtered.take(_projectSignalLimit).toList(growable: false)
        : filtered;
  }

  List<PostModel> _mergeProjectSignals(
    List<PostModel> localPosts,
    List<PostModel> remotePosts,
  ) {
    final postsById = <String, PostModel>{};
    for (final post in _projectSignalPosts(localPosts)) {
      postsById[post.id] = post;
    }
    for (final post in _projectSignalPosts(remotePosts)) {
      postsById[post.id] = post;
    }
    return _projectSignalPosts(postsById.values.toList(growable: false));
  }

  List<_RankedUser> _rankStudents(
    List<UserModel> users, {
    required List<PostModel> projectPosts,
    required Map<String, int> followerCounts,
    required Map<String, double> commentSentimentByStudent,
  }) {
    final projectsByAuthor = <String, List<PostModel>>{};
    for (final project in projectPosts) {
      final authorId = project.authorId.trim();
      if (authorId.isEmpty) continue;
      projectsByAuthor.putIfAbsent(authorId, () => <PostModel>[]).add(project);
    }

    return users
        .map(
          (user) => _RankedUser(
            user: user,
            baseScore: _baseScoreFor(
              user,
              projectPosts: projectsByAuthor[user.id] ?? const <PostModel>[],
              followerCounts: followerCounts,
              commentSentimentByStudent: commentSentimentByStudent,
            ),
          ),
        )
        .toList(growable: false);
  }

  void _publishRanking({
    required int loadVersion,
    required List<_RankedUser> ranked,
    required List<PostModel> projectPosts,
    required Map<String, int> followerCounts,
    required Map<String, double> commentSentimentByStudent,
    required bool loading,
    required bool refreshingSignals,
  }) {
    if (!mounted || loadVersion != _loadVersion) return;
    setState(() {
      _projectPosts = projectPosts;
      _followerCountsIndex = followerCounts;
      _commentSentimentByStudent = commentSentimentByStudent;
      _baseUsers = ranked;
      _selectedFaculty = _resolveInitialFaculty(ranked);
      _loading = loading;
      _refreshingSignals = refreshingSignals;
      _error = null;
    });
  }

  void _finishSignalRefresh(int loadVersion) {
    if (!mounted || loadVersion != _loadVersion) return;
    setState(() {
      _loading = false;
      _refreshingSignals = false;
    });
  }

  Future<void> _loadUsers() async {
    final loadVersion = ++_loadVersion;
    final hadRows = _baseUsers.isNotEmpty;
    setState(() {
      _loading = !hadRows;
      _refreshingSignals = hadRows;
      _error = null;
    });

    unawaited(_loadFacultyNames(loadVersion));

    try {
      final localStudentsFuture = _loadLocalStudents();
      final localProjectsFuture =
          _loadLocalProjectPosts(limit: _localProjectSignalLimit);

      final localStudents = await localStudentsFuture;
      final localProjects = await localProjectsFuture;
      if (!mounted || loadVersion != _loadVersion) return;

      final showedLocal = localStudents.isNotEmpty;
      if (showedLocal) {
        final ranked = _rankStudents(
          localStudents,
          projectPosts: localProjects,
          followerCounts: _followerCountsIndex,
          commentSentimentByStudent: _commentSentimentByStudent,
        );
        debugPrint(
          '[MobileGlobalRank] fast local users=${localStudents.length} projects=${localProjects.length}',
        );
        _publishRanking(
          loadVersion: loadVersion,
          ranked: ranked,
          projectPosts: localProjects,
          followerCounts: _followerCountsIndex,
          commentSentimentByStudent: _commentSentimentByStudent,
          loading: false,
          refreshingSignals: true,
        );
      }

      await _loadRemoteRankingSignals(
        loadVersion,
        localStudents: localStudents,
        localProjects: localProjects,
        showBlockingLoader: !showedLocal && !hadRows,
      );
    } catch (e) {
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        if (_baseUsers.isEmpty) {
          _error = 'Could not load leaderboard data: $e';
        }
        _loading = false;
        _refreshingSignals = false;
      });
    }
  }

  Future<void> _loadRemoteRankingSignals(
    int loadVersion, {
    required List<UserModel> localStudents,
    required List<PostModel> localProjects,
    required bool showBlockingLoader,
  }) async {
    if (!mounted || loadVersion != _loadVersion) return;
    setState(() {
      _loading = showBlockingLoader;
      _refreshingSignals = !showBlockingLoader;
    });

    final cachedStudents =
        _baseUsers.map((row) => row.user).toList(growable: false);
    final remoteUsersFuture = _safeLoad<List<UserModel>>(
      'remote users',
      () => _firestore.getAllUsersFromRemote(limit: _studentLoadLimit),
      cachedStudents,
    );
    final remotePostsFuture = _safeLoad<List<PostModel>>(
      'remote project posts',
      () => _firestore.getRecentPosts(limit: _projectSignalLimit),
      _projectPosts,
    );
    final followerCountsFuture = _safeLoad<Map<String, int>>(
      'follower counts',
      () => _firestore.getFollowerCountIndex(limit: _studentLoadLimit),
      _followerCountsIndex,
    );

    final remoteUsers = await remoteUsersFuture;
    final remotePosts = await remotePostsFuture;
    final followerCounts = await followerCountsFuture;
    if (!mounted || loadVersion != _loadVersion) return;

    final users = _mergeEligibleStudents(localStudents, remoteUsers);
    final projectPosts = _mergeProjectSignals(localProjects, remotePosts);

    if (users.isEmpty) {
      setState(() {
        _error = 'No eligible student profiles found yet.';
        _loading = false;
        _refreshingSignals = false;
      });
      return;
    }

    final ranked = _rankStudents(
      users,
      projectPosts: projectPosts,
      followerCounts: followerCounts,
      commentSentimentByStudent: _commentSentimentByStudent,
    );

    debugPrint(
      '[MobileGlobalRank] remote baseline users=${users.length} projects=${projectPosts.length} followers=${followerCounts.length}',
    );
    _publishRanking(
      loadVersion: loadVersion,
      ranked: ranked,
      projectPosts: projectPosts,
      followerCounts: followerCounts,
      commentSentimentByStudent: _commentSentimentByStudent,
      loading: false,
      refreshingSignals: true,
    );

    unawaited(
      _hydrateCommentSignals(
        loadVersion,
        users: users,
        projectPosts: projectPosts,
        followerCounts: followerCounts,
      ),
    );
  }

  Future<void> _hydrateCommentSignals(
    int loadVersion, {
    required List<UserModel> users,
    required List<PostModel> projectPosts,
    required Map<String, int> followerCounts,
  }) async {
    final commentProjects = _commentSignalProjects(projectPosts);
    if (commentProjects.isEmpty) {
      _finishSignalRefresh(loadVersion);
      return;
    }

    final commentSnippets = await _safeLoad<Map<String, List<String>>>(
      'comment snippets',
      () => _loadProjectCommentSnippets(commentProjects),
      const <String, List<String>>{},
    );
    if (!mounted || loadVersion != _loadVersion) return;
    if (commentSnippets.isEmpty) {
      _finishSignalRefresh(loadVersion);
      return;
    }

    final commentSentiment = await _safeLoad<Map<String, double>>(
      'comment quality signals',
      () => _recommenderService.scoreProjectCommentSentimentByStudent(
        students: users,
        projects: commentProjects,
        commentSnippetsByPost: commentSnippets,
      ),
      const <String, double>{},
      timeout: _signalLoadTimeout,
    );
    if (!mounted || loadVersion != _loadVersion) return;

    if (commentSentiment.isEmpty) {
      _finishSignalRefresh(loadVersion);
      return;
    }

    final ranked = _rankStudents(
      users,
      projectPosts: projectPosts,
      followerCounts: followerCounts,
      commentSentimentByStudent: commentSentiment,
    );

    debugPrint(
      '[MobileGlobalRank] comment signals posts=${commentProjects.length} commentPosts=${commentSnippets.length} studentScores=${commentSentiment.length}',
    );
    _publishRanking(
      loadVersion: loadVersion,
      ranked: ranked,
      projectPosts: projectPosts,
      followerCounts: followerCounts,
      commentSentimentByStudent: commentSentiment,
      loading: false,
      refreshingSignals: false,
    );
  }

  List<PostModel> _commentSignalProjects(List<PostModel> projectPosts) {
    final withComments = projectPosts
        .where((post) => post.commentCount > 0)
        .take(_commentSignalPostLimit)
        .toList(growable: false);
    if (withComments.isNotEmpty) return withComments;
    return projectPosts.take(_commentSignalPostLimit).toList(growable: false);
  }

  bool _isEligibleStudent(UserModel user) {
    return user.isStudent && user.isActive && user.profile != null;
  }

  String _resolveInitialFaculty(List<_RankedUser> ranked) {
    final options = ranked
        .map((row) => (row.user.profile?.faculty ?? '').trim())
        .where((faculty) => faculty.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    if (_selectedFaculty.isNotEmpty &&
        (_selectedFaculty == 'All Faculties' ||
            options.contains(_selectedFaculty))) {
      return _selectedFaculty;
    }
    if (options.contains(_defaultFaculty)) {
      return _defaultFaculty;
    }
    if (options.isNotEmpty) {
      return options.first;
    }
    return 'All Faculties';
  }

  double _baseScoreFor(
    UserModel user, {
    List<PostModel>? projectPosts,
    Map<String, int>? followerCounts,
    Map<String, double>? commentSentimentByStudent,
  }) {
    return _recommenderService
        .computeGlobalStudentRankScore(
          student: user,
          projects: projectPosts ?? _projectPosts,
          followerCount: (followerCounts ?? _followerCountsIndex)[user.id] ?? 0,
          aiCommentSentiment: (commentSentimentByStudent ??
              _commentSentimentByStudent)[user.id],
        )
        .score;
  }

  Future<Map<String, List<String>>> _loadProjectCommentSnippets(
    List<PostModel> projectPosts,
  ) async {
    final postIds = projectPosts
        .map((post) => post.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (postIds.isEmpty) return const <String, List<String>>{};

    try {
      final remote = await _firestore.getRecentCommentSnippetsForPosts(
        postIds: postIds,
        perPost: 3,
      );
      if (remote.isNotEmpty) return remote;
    } catch (_) {
      debugPrint(
        '[MobileGlobalRank] remote comment snippets unavailable; falling back to local cache',
      );
    }

    try {
      final local = await _commentDao.getRecentCommentSnippetsForPosts(
        postIds,
        perPostLimit: 3,
      );
      debugPrint(
        '[MobileGlobalRank] local comment fallback postCount=${local.length}',
      );
      return local;
    } catch (error) {
      debugPrint('[MobileGlobalRank] local comment fallback failed: $error');
      return const <String, List<String>>{};
    }
  }

  GlobalStudentRankTimeRange get _sharedTimeRange {
    switch (_timeRange) {
      case _LeaderboardTimeRange.sprint:
        return GlobalStudentRankTimeRange.sprint;
      case _LeaderboardTimeRange.term:
        return GlobalStudentRankTimeRange.term;
      case _LeaderboardTimeRange.allTime:
        return GlobalStudentRankTimeRange.allTime;
    }
  }

  int _pointsFor(_RankedUser row) {
    return _recommenderService.computeGlobalStudentRankPoints(
      score: row.baseScore,
      updatedAt: row.user.updatedAt,
      timeRange: _sharedTimeRange,
    );
  }

  List<String> get _facultyOptions {
    if (_facultyNames.isNotEmpty) {
      return ['All Faculties', ..._facultyNames];
    }
    // fallback: infer from users if facultyNames not loaded
    final faculties = _baseUsers
        .map((u) => (u.user.profile?.faculty ?? '').trim())
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All Faculties', ...faculties];
  }

  List<_RankedResult> get _ranked {
    final q = _searchQuery.trim().toLowerCase();
    final rankedByFaculty = _rankedByFaculty;
    if (q.isEmpty) return rankedByFaculty;

    return rankedByFaculty.where((row) {
      final name = (row.user.displayName ?? row.user.email).toLowerCase();
      return name.contains(q);
    }).toList(growable: false);
  }

  List<_RankedResult> get _rankedByFaculty {
    final filtered = _baseUsers.where((row) {
      final faculty = (row.user.profile?.faculty ?? '').trim();
      final facultyOk =
          _selectedFaculty == 'All Faculties' || faculty == _selectedFaculty;
      return facultyOk;
    }).map((row) {
      return _RankedResult(user: row.user, points: _pointsFor(row), rank: 0);
    }).toList()
      ..sort((a, b) => b.points.compareTo(a.points));

    return List<_RankedResult>.generate(
      filtered.length,
      (index) => _RankedResult(
        user: filtered[index].user,
        points: filtered[index].points,
        rank: index + 1,
      ),
      growable: false,
    );
  }

  void _onCardAction(_CardAction action, UserModel user) {
    switch (action) {
      case _CardAction.viewPortfolio:
        context.push(
          RouteNames.authorPortfolio.replaceFirst(':userId', user.id),
        );
        break;
      case _CardAction.viewProfile:
        context.push(
          RouteNames.profile.replaceFirst(':userId', user.id),
        );
        break;
      case _CardAction.message:
        context.push(
          RouteNames.chatDetail.replaceFirst(':threadId', user.id),
          extra: {
            'peerName': (user.displayName ?? user.email).trim(),
            'peerPhotoUrl': user.photoUrl,
            'isPeerLecturer': false,
          },
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgTop = isDark ? const Color(0xFF061845) : const Color(0xFFF8FBFF);
    final bgBottom = isDark ? const Color(0xFF030D27) : const Color(0xFFECF3FF);
    final fgPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final fgSecondary = isDark ? Colors.white70 : const Color(0xFF64748B);
    final pillBg = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.82);
    final pillBorder =
        isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0);

    final rankedByFaculty = _rankedByFaculty;
    final ranked = _ranked;
    final top3 = ranked.take(3).toList(growable: false);
    final rest = ranked.skip(3).toList(growable: false);

    final currentUserId = sl<AuthCubit>().currentUser?.id;
    _RankedResult? myRow;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      for (var i = 0; i < rankedByFaculty.length; i++) {
        if (rankedByFaculty[i].user.id == currentUserId) {
          myRow = rankedByFaculty[i];
          break;
        }
      }
    }
    myRow ??= rankedByFaculty.isNotEmpty ? rankedByFaculty.first : null;
    final myRank = myRow?.rank ?? 0;

    const myThreshold = 1000;
    final myProgress =
        myRow == null ? 0.0 : (myRow.points / myThreshold).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: fgPrimary),
          onPressed: () {
            context.go(RouteNames.home);
          },
        ),
        title: Text(
          widget.title,
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: fgPrimary,
          ),
        ),
        iconTheme: IconThemeData(color: fgPrimary),
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [bgTop, bgBottom],
                  ),
                ),
              ),
            ),
            const Positioned(
              top: -64,
              right: -58,
              child: _GlowBlob(color: Color(0x332563EB)),
            ),
            const Positioned(
              bottom: 80,
              left: -86,
              child: _GlowBlob(color: Color(0x221152D4)),
            ),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  color: Colors.white54, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                  color: fgSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _loadUsers,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          const SizedBox(height: 8),
                          // Faculty pill selector
                          Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width - 32,
                              ),
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: pillBg,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: pillBorder),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _selectedFaculty,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.plusJakartaSans(
                                          color: fgPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      color: isDark
                                          ? const Color(0xFF0D1A43)
                                          : Colors.white,
                                      tooltip: 'Select faculty',
                                      icon: Icon(
                                        Icons.filter_list_rounded,
                                        color: fgPrimary,
                                        size: 18,
                                      ),
                                      onSelected: (value) {
                                        setState(
                                            () => _selectedFaculty = value);
                                      },
                                      itemBuilder: (context) {
                                        return _facultyOptions
                                            .map(
                                              (f) => PopupMenuItem<String>(
                                                value: f,
                                                child: Text(
                                                  f,
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                    color: fgPrimary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(growable: false);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (widget.showCurrentFacultyName) ...[
                            const SizedBox(height: 4),
                            Text(
                              _selectedFaculty,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                color: fgPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          // Time range tabs
                          _TimeRangeTabs(
                            value: _timeRange,
                            monthLabel: widget.monthTabLabel,
                            semesterLabel: widget.semesterTabLabel,
                            allTimeLabel: widget.allTimeTabLabel,
                            onChanged: (next) =>
                                setState(() => _timeRange = next),
                          ),
                          const SizedBox(height: 10),
                          // Search field
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TextField(
                              onChanged: (v) =>
                                  setState(() => _searchQuery = v),
                              textAlign: TextAlign.center,
                              style:
                                  GoogleFonts.plusJakartaSans(color: fgPrimary),
                              decoration: InputDecoration(
                                hintText: widget.searchHint,
                                hintStyle: GoogleFonts.plusJakartaSans(
                                  color: fgSecondary,
                                ),
                                prefixIcon: Icon(Icons.search_rounded,
                                    color: fgSecondary),
                                filled: true,
                                fillColor: pillBg,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusFull),
                                  borderSide: BorderSide(color: pillBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusFull),
                                  borderSide: BorderSide(color: pillBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusFull),
                                  borderSide: BorderSide(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _refreshingSignals
                                ? Padding(
                                    key: const ValueKey('rank-refreshing'),
                                    padding:
                                        const EdgeInsets.fromLTRB(24, 8, 24, 0),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        minHeight: 2,
                                        backgroundColor: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.08,
                                              )
                                            : const Color(0xFFE2E8F0),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          AppColors.primary.withValues(
                                            alpha: 0.85,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox(
                                    key: ValueKey('rank-idle'),
                                    height: 10,
                                  ),
                          ),
                          const SizedBox(height: 12),
                          // Main content list
                          Expanded(
                            child: ranked.isEmpty
                                ? Center(
                                    child: Text(
                                      widget.emptyStateText,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: fgSecondary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : RefreshIndicator(
                                    onRefresh: _loadUsers,
                                    child: ListView(
                                      padding: const EdgeInsets.fromLTRB(
                                          14, 0, 14, 16),
                                      children: [
                                        _TopPodium(
                                            top3: top3,
                                            onAction: _onCardAction),
                                        const SizedBox(height: 10),
                                        _RanksCard(
                                          entries: rest,
                                          currentUserId: currentUserId,
                                          onAction: _onCardAction,
                                        ),
                                        const SizedBox(height: 10),
                                        _MyRankCard(
                                          rank: myRank,
                                          title: currentUserId != null &&
                                                  myRow != null &&
                                                  myRow.user.id == currentUserId
                                              ? 'Your Rank'
                                              : 'Top Rank',
                                          displayName: myRow?.name ?? '—',
                                          photoUrl: myRow?.user.photoUrl,
                                          faculty: myRow?.facultyAcronym ?? '—',
                                          points: myRow?.points ?? 0,
                                          threshold: myThreshold,
                                          progress: myProgress,
                                        ),
                                        const SizedBox(height: 10),
                                        const _PointsGuideCard(),
                                      ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Time range tab bar
// ─────────────────────────────────────────────────────────────────────────────

class _TimeRangeTabs extends StatelessWidget {
  final _LeaderboardTimeRange value;
  final String monthLabel;
  final String semesterLabel;
  final String allTimeLabel;
  final ValueChanged<_LeaderboardTimeRange> onChanged;

  const _TimeRangeTabs({
    required this.value,
    required this.monthLabel,
    required this.semesterLabel,
    required this.allTimeLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shell = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.85);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final labels = {
      _LeaderboardTimeRange.sprint: monthLabel,
      _LeaderboardTimeRange.term: semesterLabel,
      _LeaderboardTimeRange.allTime: allTimeLabel,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: shell,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: labels.entries.map((entry) {
          final active = value == entry.key;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  entry.value,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : textColor,
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top-3 podium
// ─────────────────────────────────────────────────────────────────────────────

class _TopPodium extends StatelessWidget {
  final List<_RankedResult> top3;
  final void Function(_CardAction, UserModel)? onAction;

  const _TopPodium({required this.top3, this.onAction});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final first = top3.isNotEmpty ? top3[0] : null;
    final second = top3.length > 1 ? top3[1] : null;
    final third = top3.length > 2 ? top3[2] : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
              child: _PodiumMember(
                  entry: second,
              rank: second?.rank ?? 0,
                  height: 48,
                  topOffset: 18,
                  onAction: onAction)),
          Expanded(
              child: _PodiumMember(
                  entry: first,
              rank: first?.rank ?? 0,
                  height: 74,
              crowned: first?.rank == 1,
                  onAction: onAction)),
          Expanded(
              child: _PodiumMember(
                  entry: third,
              rank: third?.rank ?? 0,
                  height: 44,
                  topOffset: 18,
                  onAction: onAction)),
        ],
      ),
    );
  }
}

class _PodiumMember extends StatelessWidget {
  final _RankedResult? entry;
  final int rank;
  final double height;
  final bool crowned;
  final double topOffset;
  final void Function(_CardAction, UserModel)? onAction;

  const _PodiumMember({
    required this.entry,
    required this.rank,
    required this.height,
    this.crowned = false,
    this.topOffset = 0,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (entry == null) return const SizedBox(height: 120);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF64748B);

    final podiumColor = switch (rank) {
      1 => const Color(0xFFC08B22),
      2 => const Color(0xFF6A748B),
      _ => const Color(0xFF8C5A2A),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: topOffset),
        if (crowned)
          const Padding(
            padding: EdgeInsets.only(bottom: 2),
            child: Icon(Icons.workspace_premium_rounded,
                color: Color(0xFFFFD44D), size: 24),
          ),
        CircleAvatar(
          radius: crowned ? 30 : 24,
          backgroundColor: Colors.white,
          child: CircleAvatar(
            radius: crowned ? 27 : 21,
            backgroundImage: entry!.user.photoUrl != null &&
                    entry!.user.photoUrl!.trim().isNotEmpty
                ? NetworkImage(entry!.user.photoUrl!.trim())
                : null,
            backgroundColor: _avatarColor(entry!.user),
            child: (entry!.user.photoUrl != null &&
                    entry!.user.photoUrl!.trim().isNotEmpty)
                ? null
                : Text(
                    entry!.name.characters.first,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          entry!.name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            color: textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          entry!.facultyAcronym,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            color: textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${entry!.points} pts',
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF4A85FF),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (onAction != null)
          PopupMenuButton<_CardAction>(
            color: isDark ? const Color(0xFF0D1A43) : Colors.white,
            tooltip: 'More',
            padding: EdgeInsets.zero,
            iconSize: 18,
            onSelected: (action) => onAction!(action, entry!.user),
            icon:
                Icon(Icons.more_horiz_rounded, color: textSecondary, size: 18),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _CardAction.viewPortfolio,
                child: Text('View Portfolio',
                    style: GoogleFonts.plusJakartaSans(
                        color: textPrimary, fontWeight: FontWeight.w600)),
              ),
              PopupMenuItem(
                value: _CardAction.viewProfile,
                child: Text('View Profile',
                    style: GoogleFonts.plusJakartaSans(
                        color: textPrimary, fontWeight: FontWeight.w600)),
              ),
              PopupMenuItem(
                value: _CardAction.message,
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded,
                        size: 16, color: Color(0xFF4A85FF)),
                    const SizedBox(width: 8),
                    Text('Message',
                        style: GoogleFonts.plusJakartaSans(
                            color: textPrimary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        Container(
          width: 56,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: podiumColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Text(
            '$rank',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ranks 4+ list
// ─────────────────────────────────────────────────────────────────────────────

class _RanksCard extends StatelessWidget {
  final List<_RankedResult> entries;
  final String? currentUserId;
  final void Function(_CardAction, UserModel) onAction;

  const _RanksCard({
    required this.entries,
    required this.currentUserId,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF64748B);
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: entries.asMap().entries.map((entry) {
          final index = entry.key;
          final row = entry.value;
          final isMe = currentUserId != null && row.user.id == currentUserId;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: index == entries.length - 1
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '${row.rank}',
                    style: GoogleFonts.plusJakartaSans(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                CircleAvatar(
                  radius: 16,
                  backgroundImage: row.user.photoUrl != null &&
                          row.user.photoUrl!.trim().isNotEmpty
                      ? NetworkImage(row.user.photoUrl!.trim())
                      : null,
                  backgroundColor: _avatarColor(row.user),
                  child: (row.user.photoUrl != null &&
                          row.user.photoUrl!.trim().isNotEmpty)
                      ? null
                      : Text(
                          row.name.characters.first,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                color: textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (isMe)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'YOU',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        row.facultyAcronym,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${row.points} pts',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF4A85FF),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                PopupMenuButton<_CardAction>(
                  color: isDark ? const Color(0xFF0D1A43) : Colors.white,
                  tooltip: 'More',
                  onSelected: (action) => onAction(action, row.user),
                  icon: Icon(Icons.more_vert_rounded,
                      color: textSecondary, size: 18),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _CardAction.viewPortfolio,
                      child: Text(
                        'View Portfolio',
                        style: GoogleFonts.plusJakartaSans(
                            color: textPrimary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    PopupMenuItem(
                      value: _CardAction.viewProfile,
                      child: Text(
                        'View Profile',
                        style: GoogleFonts.plusJakartaSans(
                            color: textPrimary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    PopupMenuItem(
                      value: _CardAction.message,
                      child: Row(
                        children: [
                          const Icon(Icons.chat_bubble_outline_rounded,
                              size: 16, color: Color(0xFF4A85FF)),
                          const SizedBox(width: 8),
                          Text(
                            'Message',
                            style: GoogleFonts.plusJakartaSans(
                                color: textPrimary,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My rank card
// ─────────────────────────────────────────────────────────────────────────────

class _MyRankCard extends StatelessWidget {
  final int rank;
  final String title;
  final String displayName;
  final String? photoUrl;
  final String faculty;
  final int points;
  final int threshold;
  final double progress;

  const _MyRankCard({
    required this.rank,
    required this.title,
    required this.displayName,
    this.photoUrl,
    required this.faculty,
    required this.points,
    required this.threshold,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grad = isDark
        ? const [Color(0xFF2452E8), Color(0xFF16379B)]
        : const [Color(0xFF3B82F6), Color(0xFF2563EB)];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: grad,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                rank <= 0 ? '-' : '#$rank',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundImage: photoUrl != null && photoUrl!.trim().isNotEmpty
                    ? NetworkImage(photoUrl!.trim())
                    : null,
                backgroundColor: Colors.white24,
                child: photoUrl != null && photoUrl!.trim().isNotEmpty
                    ? null
                    : const Icon(Icons.person_rounded, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      faculty,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$points pts',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$points / $threshold pts threshold',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signals guide card
// ─────────────────────────────────────────────────────────────────────────────

class _PointsGuideCard extends StatelessWidget {
  const _PointsGuideCard();

  Widget _ruleTile(
    BuildContext context, {
    required bool isDark,
    required Color textPrimary,
    required String title,
    required String comment,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 176,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    color: textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  comment,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required String comment,
    required bool isDark,
    required Color textPrimary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            color: textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          comment,
          style: GoogleFonts.plusJakartaSans(
            color: isDark ? Colors.white70 : const Color(0xFF64748B),
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ranking Signals',
            style: GoogleFonts.plusJakartaSans(
              color: textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The leaderboard reads these signals together to estimate academic activity, project quality, and community impact.',
            style: GoogleFonts.plusJakartaSans(
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          _sectionHeader(
            title: 'Profile Signals',
            comment: 'Signals from the student profile and learning activity.',
            isDark: isDark,
            textPrimary: textPrimary,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Skills listed',
                comment: 'Clear skills help the system understand expertise.',
                icon: Icons.psychology_rounded,
                color: const Color(0xFF2563EB),
              ),
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Activity streak',
                comment: 'Consistent activity shows continued participation.',
                icon: Icons.local_fire_department_rounded,
                color: const Color(0xFFEF4444),
              ),
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Profile completeness',
                comment:
                    'Bio, faculty, program, year, and links improve trust.',
                icon: Icons.badge_rounded,
                color: const Color(0xFFF59E0B),
              ),
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Collaboration history',
                comment: 'Past collaborations show teamwork and reliability.',
                icon: Icons.groups_rounded,
                color: const Color(0xFF7C3AED),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionHeader(
            title: 'Project Signals',
            comment: 'Signals from projects the student has published.',
            isDark: isDark,
            textPrimary: textPrimary,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Projects created',
                comment: 'More academic project work gives stronger evidence.',
                icon: Icons.folder_copy_rounded,
                color: const Color(0xFF2563EB),
              ),
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Skill evidence',
                comment:
                    'Project skills show what the student can build or study.',
                icon: Icons.construction_rounded,
                color: const Color(0xFF10B981),
              ),
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Freshness',
                comment: 'Recently updated projects show current momentum.',
                icon: Icons.update_rounded,
                color: const Color(0xFF22C55E),
              ),
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Trust and validation',
                comment: 'Moderation and ownership checks support credibility.',
                icon: Icons.shield_rounded,
                color: const Color(0xFFF59E0B),
              ),
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Media evidence',
                comment: 'Images, videos, demos, and links strengthen proof.',
                icon: Icons.perm_media_rounded,
                color: const Color(0xFFEF4444),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionHeader(
            title: 'Community Signals',
            comment: 'Signals from how others respond to the student work.',
            isDark: isDark,
            textPrimary: textPrimary,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Followers',
                comment: 'Followers indicate community interest and trust.',
                icon: Icons.people_alt_rounded,
                color: const Color(0xFF0EA5E9),
              ),
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Reactions',
                comment: 'Likes, shares, views, and saves show reach.',
                icon: Icons.thumb_up_alt_rounded,
                color: const Color(0xFF2563EB),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionHeader(
            title: 'Comment Signals',
            comment:
                'Comments are treated as academic feedback, not just volume.',
            isDark: isDark,
            textPrimary: textPrimary,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Comment count',
                comment: 'More discussion suggests the project is noticed.',
                icon: Icons.mode_comment_rounded,
                color: const Color(0xFF0EA5E9),
              ),
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'Comment quality',
                comment: 'Constructive feedback is valued above empty chatter.',
                icon: Icons.rate_review_rounded,
                color: const Color(0xFF10B981),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionHeader(
            title: 'Time Context',
            comment:
                'The selected period decides whether recent or long-term impact is emphasized.',
            isDark: isDark,
            textPrimary: textPrimary,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'This month',
                comment: 'Highlights students currently active.',
                icon: Icons.bolt_rounded,
                color: const Color(0xFF22C55E),
              ),
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'This semester',
                comment: 'Balances current work with sustained progress.',
                icon: Icons.calendar_month_rounded,
                color: const Color(0xFF7C3AED),
              ),
              _ruleTile(
                context,
                isDark: isDark,
                textPrimary: textPrimary,
                title: 'All time',
                comment: 'Rewards consistent long-term contribution.',
                icon: Icons.history_rounded,
                color: const Color(0xFFF59E0B),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers / data models
// ─────────────────────────────────────────────────────────────────────────────

enum _CardAction { viewPortfolio, viewProfile, message }

class _RankedUser {
  final UserModel user;
  final double baseScore;

  const _RankedUser({required this.user, required this.baseScore});
}

class _RankedResult {
  final UserModel user;
  final int points;
  final int rank;

  const _RankedResult({
    required this.user,
    required this.points,
    required this.rank,
  });

  String get name {
    final d = (user.displayName ?? '').trim();
    return d.isNotEmpty ? d : user.email;
  }

  String get faculty {
    final f = (user.profile?.faculty ?? '').trim();
    return f.isEmpty ? 'Faculty not set' : f;
  }

  String get facultyAcronym => _facultyAcronym(faculty);
}

Color _avatarColor(UserModel user) {
  final seed =
      (user.displayName ?? user.email).runes.fold<int>(0, (a, b) => a + b);
  const palette = <Color>[
    Color(0xFF2A6CF0),
    Color(0xFF09A66D),
    Color(0xFF7C4DFF),
    Color(0xFFFFB300),
    Color(0xFFEC4899),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
  ];
  return palette[seed % palette.length];
}

String _facultyAcronym(String facultyName) {
  final normalized = facultyName.trim();
  if (normalized.isEmpty || normalized == 'Faculty not set') {
    return 'N/A';
  }

  const knownAcronyms = <String, String>{
    'Faculty of Computing and Informatics': 'FCI',
    'Faculty of Computing and Informatic': 'FCI',
    'Faculty of Science': 'FOS',
    'Faculty of Engineering': 'FENG',
    'Faculty of Education': 'FED',
    'Faculty of Social Sciences': 'FSS',
    'Faculty of Environmental Sciences': 'FES',
    'Faculty of Business and Management Sciences': 'FBMS',
    'Faculty of Agriculture': 'FOA',
    'Faculty of Law': 'LAW',
    'Faculty of Medicine': 'FOM',
  };

  final direct = knownAcronyms[normalized];
  if (direct != null) {
    return direct;
  }

  final words = normalized
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .where((word) => !{'of', 'and', '&', 'the'}.contains(word.toLowerCase()))
      .toList(growable: false);

  if (words.isEmpty) {
    return normalized.toUpperCase().characters.take(4).toString();
  }

  return words
      .map((word) => word.characters.first.toUpperCase())
      .join()
      .characters
      .take(5)
      .toString();
}
