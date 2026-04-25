import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/remote/recommender_service.dart';
import '../../auth/bloc/auth_cubit.dart';

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

  final _firestore = sl<FirestoreService>();
  final _userDao = sl<UserDao>();
  final _recommenderService = sl<RecommenderService>();

  bool _loading = true;
  String? _error;
  List<_RankedUser> _baseUsers = const [];

  _LeaderboardTimeRange _timeRange = _LeaderboardTimeRange.sprint;
  late String _selectedFaculty;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedFaculty = widget.initialFaculty.trim().isEmpty
        ? 'All Faculties'
        : widget.initialFaculty.trim();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      List<UserModel> remoteUsers;
      try {
        remoteUsers = await _firestore.getAllUsersFromRemote(limit: 5000);
      } catch (_) {
        remoteUsers = const <UserModel>[];
      }

      final localUsers = await _userDao.getAllUsers(
        role: 'student',
        includeSuspended: false,
        pageSize: 5000,
      );

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
      final users = usersById.values.toList(growable: false);

      final ranked = users
          .map((u) => _RankedUser(user: u, baseScore: _baseScoreFor(u)))
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _baseUsers = ranked;
        _selectedFaculty = _resolveInitialFaculty(ranked);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load leaderboard data: $e';
        _loading = false;
      });
    }
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

  double _baseScoreFor(UserModel user) {
    return _recommenderService.computeGlobalStudentScore(user);
  }

  double _timeBoost(DateTime updatedAt) {
    final days = DateTime.now().difference(updatedAt).inDays;
    switch (_timeRange) {
      case _LeaderboardTimeRange.sprint:
        if (days <= 30) return 1.0;
        if (days <= 90) return (1.0 - ((days - 30) / 120)).clamp(0.35, 1.0);
        return 0.35;
      case _LeaderboardTimeRange.term:
        if (days <= 120) return 1.0;
        if (days <= 240) {
          return (1.0 - ((days - 120) / 240)).clamp(0.55, 1.0);
        }
        return 0.55;
      case _LeaderboardTimeRange.allTime:
        return 1.0;
    }
  }

  int _pointsFor(_RankedUser row) {
    final boosted =
        (row.baseScore * 0.86) + (_timeBoost(row.user.updatedAt) * 0.14);
    return (boosted.clamp(0.0, 1.0) * 1000).round();
  }

  List<String> get _facultyOptions {
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
    return _baseUsers.where((row) {
      final faculty = (row.user.profile?.faculty ?? '').trim();
      final facultyOk =
          _selectedFaculty == 'All Faculties' || faculty == _selectedFaculty;
      final name = (row.user.displayName ?? row.user.email).toLowerCase();
      final searchOk = q.isEmpty || name.contains(q);
      return facultyOk && searchOk;
    }).map((row) {
      return _RankedResult(user: row.user, points: _pointsFor(row));
    }).toList()
      ..sort((a, b) => b.points.compareTo(a.points));
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
    final ranked = _ranked;
    final top3 = ranked.take(3).toList(growable: false);
    final rest = ranked.skip(3).toList(growable: false);

    final currentUserId = sl<AuthCubit>().currentUser?.id;
    _RankedResult? myRow;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      for (var i = 0; i < ranked.length; i++) {
        if (ranked[i].user.id == currentUserId) {
          myRow = ranked[i];
          break;
        }
      }
    }
    myRow ??= ranked.isNotEmpty ? ranked.first : null;
    final myRank = myRow == null ? 0 : ranked.indexOf(myRow) + 1;

    const myThreshold = 1000;
    final myProgress =
        myRow == null ? 0.0 : (myRow.points / myThreshold).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF040B22),
      appBar: AppBar(
        backgroundColor: const Color(0xFF040B22),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () {
            context.go(RouteNames.home);
          },
        ),
        title: Text(
          widget.title,
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF061845), Color(0xFF030D27)],
            ),
          ),
          child: _loading
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
                                color: Colors.white70,
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
                                color: Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.12)),
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
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    color: const Color(0xFF0D1A43),
                                    tooltip: 'Select faculty',
                                    icon: const Icon(
                                      Icons.filter_list_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    onSelected: (value) {
                                      setState(() => _selectedFaculty = value);
                                    },
                                    itemBuilder: (context) {
                                      return _facultyOptions
                                          .map(
                                            (f) => PopupMenuItem<String>(
                                              value: f,
                                              child: Text(
                                                f,
                                                style:
                                                    GoogleFonts.plusJakartaSans(
                                                  color: Colors.white,
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
                              color: Colors.white,
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
                            onChanged: (v) => setState(() => _searchQuery = v),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                                color: Colors.white),
                            decoration: InputDecoration(
                              hintText: widget.searchHint,
                              hintStyle: GoogleFonts.plusJakartaSans(
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                              prefixIcon: const Icon(Icons.search_rounded,
                                  color: Colors.white),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    AppDimensions.radiusFull),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
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
                                      color: Colors.white70,
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
                                      _TopPodium(top3: top3, onAction: _onCardAction),
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
    final labels = {
      _LeaderboardTimeRange.sprint: monthLabel,
      _LeaderboardTimeRange.term: semesterLabel,
      _LeaderboardTimeRange.allTime: allTimeLabel,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
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
                    color: Colors.white,
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
    final first = top3.isNotEmpty ? top3[0] : null;
    final second = top3.length > 1 ? top3[1] : null;
    final third = top3.length > 2 ? top3[2] : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
              child: _PodiumMember(
                  entry: second, rank: 2, height: 48, topOffset: 18,
                  onAction: onAction)),
          Expanded(
              child: _PodiumMember(
                  entry: first, rank: 1, height: 74, crowned: true,
                  onAction: onAction)),
          Expanded(
              child: _PodiumMember(
                  entry: third, rank: 3, height: 44, topOffset: 18,
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
            color: Colors.white,
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
            color: Colors.white70,
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
            color: const Color(0xFF0D1A43),
            tooltip: 'More',
            padding: EdgeInsets.zero,
            iconSize: 18,
            onSelected: (action) => onAction!(action, entry!.user),
            icon: const Icon(Icons.more_horiz_rounded,
                color: Colors.white54, size: 18),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _CardAction.viewPortfolio,
                child: Text('View Portfolio',
                    style: GoogleFonts.plusJakartaSans(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              PopupMenuItem(
                value: _CardAction.viewProfile,
                child: Text('View Profile',
                    style: GoogleFonts.plusJakartaSans(
                        color: Colors.white, fontWeight: FontWeight.w600)),
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
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: entries.asMap().entries.map((entry) {
          final index = entry.key;
          final rank = index + 4;
          final row = entry.value;
          final isMe = currentUserId != null && row.user.id == currentUserId;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: index == entries.length - 1
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '$rank',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
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
                                color: Colors.white,
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
                          color: Colors.white70,
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
                  color: const Color(0xFF0D1A43),
                  tooltip: 'More',
                  onSelected: (action) => onAction(action, row.user),
                  icon: const Icon(Icons.more_vert_rounded,
                      color: Colors.white54, size: 18),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _CardAction.viewPortfolio,
                      child: Text(
                        'View Portfolio',
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    PopupMenuItem(
                      value: _CardAction.viewProfile,
                      child: Text(
                        'View Profile',
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.white, fontWeight: FontWeight.w600),
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
                                color: Colors.white,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2452E8), Color(0xFF16379B)],
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
// Points guide card
// ─────────────────────────────────────────────────────────────────────────────

class _PointsGuideCard extends StatelessWidget {
  const _PointsGuideCard();

  @override
  Widget build(BuildContext context) {
    const rules = [
      (
        'Activity streak',
        '24% weight (cap: 30 days)',
        Icons.local_fire_department_rounded,
        Color(0xFFEF4444),
      ),
      (
        'Posts created',
        '22% weight (cap: 12 posts)',
        Icons.article_rounded,
        Color(0xFF10B981),
      ),
      (
        'Collaborations',
        '20% weight (cap: 8 collabs)',
        Icons.groups_rounded,
        Color(0xFF7C3AED),
      ),
      (
        'Followers',
        '14% weight (cap: 40 followers)',
        Icons.people_alt_rounded,
        Color(0xFF0EA5E9),
      ),
      (
        'Profile completeness',
        '12% weight (bio/program/faculty/skills)',
        Icons.badge_rounded,
        Color(0xFFF59E0B),
      ),
      (
        'Skills listed',
        '8% weight (cap: 8 skills)',
        Icons.psychology_rounded,
        Color(0xFF2563EB),
      ),
      (
        'Recency boost',
        '14% of total points by selected time filter',
        Icons.schedule_rounded,
        Color(0xFF22C55E),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How Points Are Earned',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: rules.map((rule) {
              final icon = rule.$3;
              final color = rule.$4;
              return Container(
                width: math.max(150, 160),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
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
                            rule.$1,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            rule.$2,
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF5B93FF),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(growable: false),
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

  const _RankedResult({required this.user, required this.points});

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
