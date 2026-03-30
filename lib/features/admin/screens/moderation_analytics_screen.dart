import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/user_dao.dart';

enum _PostTypeFilter { all, projects, opportunities }

class ModerationAnalyticsScreen extends StatefulWidget {
  const ModerationAnalyticsScreen({super.key});

  @override
  State<ModerationAnalyticsScreen> createState() =>
      _ModerationAnalyticsScreenState();
}

class _ModerationAnalyticsScreenState extends State<ModerationAnalyticsScreen> {
  final _activityDao = sl<ActivityLogDao>();
  final _postDao = sl<PostDao>();
  final _userDao = sl<UserDao>();

  bool _loading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _topReasons = [];
  List<Map<String, dynamic>> _userActions = [];
  Map<String, String> _userNames = {};
  Map<String, dynamic> _recommendationBreakdown = {};
  _PostTypeFilter _postTypeFilter = _PostTypeFilter.all;

  String _shortId(Object? raw, {int max = 12}) {
    final value = raw?.toString() ?? '';
    if (value.isEmpty) return '?';
    return value.length <= max ? value : value.substring(0, max);
  }

  String _bestUserLabel({required String id, String? displayName, String? email}) {
    final name = (displayName ?? '').trim();
    if (name.isNotEmpty) return name;

    final local = (email ?? '').split('@').first.trim();
    if (local.isNotEmpty) return local;

    return 'User ${_shortId(id, max: 8)}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final postStats = await _postDao.getPostStats();
      final reports7d = await _activityDao.getActionCountForDays(
        action: 'report_post',
        days: 7,
      );
      final reported = await _activityDao.getReportedPostSummaries(limit: 100);
      final recentMod = await _activityDao.getRecentLogs(limit: 200);

      // Filter by post type if needed
      List<Map<String, dynamic>> filteredReported = reported;
      if (_postTypeFilter == _PostTypeFilter.projects) {
        filteredReported = reported
            .where((r) => r['postType']?.toString() == 'project')
            .toList();
      } else if (_postTypeFilter == _PostTypeFilter.opportunities) {
        filteredReported = reported
            .where((r) => r['postType']?.toString() == 'opportunity')
            .toList();
      }

      // Calculate top reasons
      final reasonCounts = <String, int>{};
      for (final item in filteredReported) {
        final reason = item['topReason']?.toString() ?? 'other';
        reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;
      }
      final topReasons = reasonCounts.entries
          .map((e) => {'reason': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (b['count'] as int? ?? 0).compareTo(a['count'] as int? ?? 0));

      // Aggregate user actions - THIS SOLVES THE 60 COPIES PROBLEM
      final userActionMap = <String, Map<String, dynamic>>{};
      for (final action in recentMod) {
        final rawUserId = (action['userId'] ?? action['user_id'])?.toString() ?? '';
        final userId = rawUserId.trim().isEmpty ? '__system__' : rawUserId.trim();
        if (userActionMap.containsKey(userId)) {
          userActionMap[userId]!['count'] =
              (userActionMap[userId]!['count'] as int? ?? 0) + 1;
        } else {
          userActionMap[userId] = {
            'user_id': userId,
            'count': 1,
            'action': action['action'],
            'created_at': action['createdAt'] ?? action['created_at'],
          };
        }
      }
      final userActions = userActionMap.values.toList()
        ..sort((a, b) => (b['count'] as int? ?? 0)
            .compareTo(a['count'] as int? ?? 0));

      final topUserIds = userActions
          .map((e) => e['user_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty && id != '__system__')
          .take(30)
          .toSet()
          .toList();
      final userNameMap = <String, String>{};
      final users = await Future.wait(topUserIds.map(_userDao.getUserById));
      for (final user in users) {
        if (user == null) continue;
        userNameMap[user.id] = _bestUserLabel(
          id: user.id,
          displayName: user.displayName,
          email: user.email,
        );
      }

      // Get recommendation algorithm breakdown
      final allReports =
          await _activityDao.getRecentLogs(limit: 500);
      final recBreakdown = _analyzeRecommendationTypes(allReports);

      final pendingMod = postStats['pendingModeration'] ?? 0;
      final totalPosts = postStats['total'] ?? 0;
      final approved = (postStats['total'] ?? 0) - pendingMod;
      final rejected = postStats['archived'] ?? 0;

      if (!mounted) return;
      setState(() {
        _stats = {
          'total_reports_7d': reports7d,
          'pending_moderation': pendingMod,
          'total_posts': totalPosts,
          'flagged_posts': filteredReported.length,
          'approved_posts': approved,
          'rejected_posts': rejected,
          'approval_rate': totalPosts > 0
              ? ((approved / totalPosts) * 100).toStringAsFixed(1)
              : '0.0',
        };
        _topReasons = topReasons.take(8).toList();
        _userActions = userActions.take(50).toList();
        _userNames = userNameMap;
        _recommendationBreakdown = recBreakdown;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Analyzes recommendation types from activity logs
  /// Returns breakdown of: Skill Matching, Video Streaming, Opportunity Matching,
  /// Student Recruitment, Project Collaboration
  Map<String, dynamic> _analyzeRecommendationTypes(
      List<Map<String, dynamic>> logs) {
    final types = <String, int>{
      'Skill Matching': 0,
      'Video Streaming': 0,
      'Opportunity Matching': 0,
      'Student Recruitment': 0,
      'Project Collaboration': 0,
      'Other': 0,
    };

    for (final log in logs) {
      final action = log['action']?.toString().toLowerCase() ?? '';
      if (action.contains('stream') || action.contains('video')) {
        types['Video Streaming'] = (types['Video Streaming'] ?? 0) + 1;
      } else if (action.contains('skill') || action.contains('match')) {
        types['Skill Matching'] = (types['Skill Matching'] ?? 0) + 1;
      } else if (action.contains('opportunity') ||
          action.contains('apply')) {
        types['Opportunity Matching'] = (types['Opportunity Matching'] ?? 0) + 1;
      } else if (action.contains('student') ||
          action.contains('recruit')) {
        types['Student Recruitment'] = (types['Student Recruitment'] ?? 0) + 1;
      } else if (action.contains('project') ||
          action.contains('collab')) {
        types['Project Collaboration'] = (types['Project Collaboration'] ?? 0) + 1;
      } else {
        types['Other'] = (types['Other'] ?? 0) + 1;
      }
    }

    return types;
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    Color? color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color ?? AppColors.primary, size: 18),
                const SizedBox(width: 6),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color ?? AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: AppColors.textSecondaryLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderation Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  // Post type filter
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('All Posts'),
                          selected:
                              _postTypeFilter == _PostTypeFilter.all,
                          onSelected: (_) {
                            setState(() =>
                                _postTypeFilter = _PostTypeFilter.all);
                            _load();
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Projects Only'),
                          selected: _postTypeFilter ==
                              _PostTypeFilter.projects,
                          onSelected: (_) {
                            setState(() => _postTypeFilter =
                                _PostTypeFilter.projects);
                            _load();
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Opportunities Only'),
                          selected: _postTypeFilter ==
                              _PostTypeFilter.opportunities,
                          onSelected: (_) {
                            setState(() => _postTypeFilter =
                                _PostTypeFilter.opportunities);
                            _load();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Summary stats in rows
                  Row(
                    children: [
                      _statCard(
                        label: 'Reports (7d)',
                        value: '${_stats['total_reports_7d'] ?? 0}',
                        icon: Icons.flag_rounded,
                      ),
                      const SizedBox(width: 8),
                      _statCard(
                        label: 'Pending',
                        value: '${_stats['pending_moderation'] ?? 0}',
                        icon: Icons.pending_actions_rounded,
                        color: AppColors.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _statCard(
                        label: 'Flagged',
                        value: '${_stats['flagged_posts'] ?? 0}',
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      _statCard(
                        label: 'Approval Rate',
                        value: '${_stats['approval_rate'] ?? 0}%',
                        icon: Icons.check_circle_rounded,
                        color: AppColors.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Recommendation types breakdown
                  Text(
                    'Recommendation Types Breakdown',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._recommendationBreakdown.entries
                      .where((e) => (e.value as int? ?? 0) > 0)
                      .toList()
                      .asMap()
                      .entries
                      .map((entry) {
                    final type = entry.value.key;
                    final count = (entry.value.value as int?) ?? 0;
                    final maxCount = _recommendationBreakdown.values.fold<int>(
                      1,
                      (maxValue, value) {
                        final intValue = value is int ? value : 0;
                        return intValue > maxValue ? intValue : maxValue;
                      },
                    );
                    final percentage = maxCount > 0 ? count / maxCount : 0;

                    final colors = <String, Color>{
                      'Skill Matching': AppColors.primary,
                      'Video Streaming': const Color(0xFF6366F1),
                      'Opportunity Matching': const Color(0xFF8B5CF6),
                      'Student Recruitment': const Color(0xFFEC4899),
                      'Project Collaboration': const Color(0xFF14B8A6),
                    };

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    type,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$count events',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        colors[type] ?? AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percentage.toDouble(),
                                minHeight: 6,
                                backgroundColor: AppColors.surfaceLight,
                                valueColor: AlwaysStoppedAnimation(
                                    colors[type] ?? AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),

                  // Top report reasons
                  Text(
                    'Top Report Reasons',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_topReasons.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('No moderation data available.'),
                      ),
                    ),
                  ..._topReasons.map((item) {
                    final reason = item['reason'] as String? ?? 'unknown';
                    final count = item['count'] as int? ?? 0;
                    final maxCount =
                        _topReasons.first['count'] as int? ?? 1;
                    final percentage = maxCount > 0 ? count / maxCount : 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    reason,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$count reports',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percentage.toDouble(),
                                minHeight: 6,
                                backgroundColor: AppColors.surfaceLight,
                                valueColor: const AlwaysStoppedAnimation(
                                    AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),

                  // Aggregated user actions - DEDUPLICATES USERS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Top Active Users',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                      Text(
                        '${_userActions.length} unique users',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_userActions.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('No user activity yet.'),
                      ),
                    ),
                  ..._userActions.take(15).map((user) {
                    final rawId = user['user_id']?.toString() ?? '';
                    final displayName = rawId == '__system__'
                      ? 'System'
                      : (_userNames[rawId] ?? 'User ${_shortId(rawId, max: 8)}');
                    final count = user['count'] as int? ?? 0;
                    final maxCount = _userActions.isNotEmpty
                        ? (_userActions.first['count'] as int? ?? 1)
                        : 1;
                    final percentage =
                        maxCount > 0 ? count / maxCount : 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'User: $displayName',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryTint10,
                                    borderRadius:
                                        BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '$count action${count == 1 ? '' : 's'}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percentage.toDouble(),
                                minHeight: 5,
                                backgroundColor: AppColors.surfaceLight,
                                valueColor: const AlwaysStoppedAnimation(
                                    AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
