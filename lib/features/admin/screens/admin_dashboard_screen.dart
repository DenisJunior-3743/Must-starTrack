import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/sync_service.dart';
import '../../../data/local/dao/recommendation_log_dao.dart';
import '../../../core/constants/app_enums.dart';
import '../bloc/course_management_cubit.dart';
import '../bloc/faculty_management_cubit.dart';
import 'course_management_screen.dart';
import 'faculty_management_screen.dart';

enum _Risk { high, medium, low }

enum _Violation { inappropriate, suspicious, spam, other }

String _titleCaseWords(String value) {
  final parts = value
      .split(RegExp(r'\s+'))
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';
  return parts
      .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

String _bestUserLabel({String? displayName, String? email, String? userId}) {
  final cleanDisplay = displayName?.trim() ?? '';
  if (cleanDisplay.isNotEmpty) return cleanDisplay;

  final emailLocal = (email ?? '').split('@').first.trim();
  if (emailLocal.isNotEmpty) {
    final normalized = emailLocal.replaceAll(RegExp(r'[_\-.]+'), ' ');
    final title = _titleCaseWords(normalized);
    if (title.isNotEmpty) return title;
    return emailLocal;
  }

  final rawId = userId?.trim() ?? '';
  if (rawId.isEmpty) return 'Unknown user';
  if (rawId.contains('-') || rawId.contains('_')) {
    final normalized = rawId.replaceAll(RegExp(r'[_\-.]+'), ' ');
    final title = _titleCaseWords(normalized);
    if (title.isNotEmpty) return title;
  }
  return rawId.length > 8 ? '${rawId.substring(0, 8)}…' : rawId;
}

class _FlaggedItem {
  final String postId;
  final String authorId;
  final String title;
  final String reportedBy;
  final int reportsCount;
  final _Risk risk;
  final _Violation violation;
  final bool isArchived;
  bool isSelected = false;

  _FlaggedItem({
    required this.postId,
    required this.authorId,
    required this.title,
    required this.reportedBy,
    required this.reportsCount,
    required this.risk,
    required this.violation,
    required this.isArchived,
  });
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _postDao = sl<PostDao>();
  final _activityLogDao = sl<ActivityLogDao>();
  final _userDao = sl<UserDao>();
  final _syncQueueDao = sl<SyncQueueDao>();
  final _syncService = sl<SyncService>();

  int _selectedTab = 0;
  bool _loading = true;
  int _pendingReviews = 0;
  int _flaggedPosts = 0;
  int _reportedUsers = 0;
  int _totalPosts = 0;
  int _totalUsers = 0;
  int _syncPending = 0;
  int _syncDeadLetters = 0;
  int _weeklyReports = 0;
  int _weeklyActiveUsers = 0;
  List<PostModel> _pendingQueue = const [];
  List<UserModel> _recentUsers = const [];
  final List<_FlaggedItem> _items = [];

  @override
  void initState() {
    super.initState();
    _reloadDashboard();
  }

  List<_FlaggedItem> get _selected => _items.where((i) => i.isSelected).toList();

  Future<void> _reloadDashboard() async {
    setState(() => _loading = true);
    try {
      final postStats = await _postDao.getPostStats();
      final pendingPosts = await _postDao.getPendingModerationPosts(limit: 80);
      final flaggedRows = await _activityLogDao.getReportedPostSummaries(limit: 80);
      final allUsers = await _userDao.getAllUsers(pageSize: 60);
      final syncPending = await _syncQueueDao.getPendingCount();
      final syncDeadLetters = await _syncQueueDao.getDeadLetterCount();
      final weeklyReports = await _activityLogDao.getActionCountForDays(action: 'report_post', days: 7);
      final weeklyActiveUsers = await _activityLogDao.getActiveUserCountSince(days: 7);

      final flaggedItems = flaggedRows.map((row) {
        final risk = switch (row['risk']) {
          'high' => _Risk.high,
          'medium' => _Risk.medium,
          _ => _Risk.low,
        };
        final reason = (row['topReason']?.toString().toLowerCase() ?? 'other');
        final violation = reason.contains('inappropriate')
            ? _Violation.inappropriate
            : reason.contains('suspicious') || reason.contains('fake')
                ? _Violation.suspicious
                : reason.contains('spam')
                    ? _Violation.spam
                    : _Violation.other;
        return _FlaggedItem(
          postId: row['postId']?.toString() ?? '',
          authorId: row['authorId']?.toString() ?? '',
          title: row['postTitle']?.toString() ?? 'Untitled post',
          reportedBy: row['latestReporterId']?.toString() ?? 'unknown',
          reportsCount: row['reportsCount'] as int? ?? 0,
          risk: risk,
          violation: violation,
          isArchived: row['isArchived'] as bool? ?? false,
        );
      }).where((item) => item.postId.isNotEmpty).toList();

      final reportedUsers = flaggedItems.map((item) => item.authorId).where((id) => id.isNotEmpty).toSet().length;

      if (!mounted) return;
      setState(() {
        _pendingQueue = pendingPosts;
        _items
          ..clear()
          ..addAll(flaggedItems);
        _pendingReviews = pendingPosts.length;
        _flaggedPosts = flaggedItems.length;
        _reportedUsers = reportedUsers;
        _totalPosts = postStats['total'] ?? 0;
        _totalUsers = allUsers.length;
        _recentUsers = allUsers.take(20).toList();
        _syncPending = syncPending;
        _syncDeadLetters = syncDeadLetters;
        _weeklyReports = weeklyReports;
        _weeklyActiveUsers = weeklyActiveUsers;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _toggleSelect(String id) {
    setState(() {
      final item = _items.firstWhere((i) => i.postId == id);
      item.isSelected = !item.isSelected;
    });
  }

  Future<void> _approveSelected() async {
    final count = _selected.length;
    if (count == 0) return;
    for (final item in _selected) {
      await _postDao.updateModerationStatus(
        postId: item.postId,
        status: ModerationStatus.approved,
      );
      final updated = await _postDao.getPostById(item.postId);
      if (updated != null) {
        await _syncQueueDao.enqueue(
          operation: 'update',
          entity: 'posts',
          entityId: updated.id,
          payload: updated.copyWith(
            moderationStatus: ModerationStatus.approved,
            updatedAt: DateTime.now(),
          ).toMap(),
        );
      }
    }
    await _syncService.processPendingSync();
    await _reloadDashboard();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Approved $count post${count == 1 ? '' : 's'}')),
    );
  }

  Future<void> _rejectSelected() async {
    final count = _selected.length;
    if (count == 0) return;
    for (final item in _selected) {
      await _postDao.updateModerationStatus(
        postId: item.postId,
        status: ModerationStatus.rejected,
      );
      final updated = await _postDao.getPostById(item.postId);
      if (updated != null) {
        await _syncQueueDao.enqueue(
          operation: 'update',
          entity: 'posts',
          entityId: updated.id,
          payload: updated.copyWith(
            moderationStatus: ModerationStatus.rejected,
            updatedAt: DateTime.now(),
          ).toMap(),
        );
      }
    }
    await _syncService.processPendingSync();
    await _reloadDashboard();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rejected $count post${count == 1 ? '' : 's'}')),
    );
  }

  Future<void> _approvePendingPost(PostModel post) async {
    await _postDao.updateModerationStatus(
      postId: post.id,
      status: ModerationStatus.approved,
    );
    final updated = await _postDao.getPostById(post.id);
    if (updated != null) {
      await _syncQueueDao.enqueue(
        operation: 'update',
        entity: 'posts',
        entityId: updated.id,
        payload: updated.copyWith(
          moderationStatus: ModerationStatus.approved,
          updatedAt: DateTime.now(),
        ).toMap(),
      );
    }
    await _syncService.processPendingSync();
    await _reloadDashboard();
  }

  Future<void> _rejectPendingPost(PostModel post) async {
    await _postDao.updateModerationStatus(
      postId: post.id,
      status: ModerationStatus.rejected,
    );
    final updated = await _postDao.getPostById(post.id);
    if (updated != null) {
      await _syncQueueDao.enqueue(
        operation: 'update',
        entity: 'posts',
        entityId: updated.id,
        payload: updated.copyWith(
          moderationStatus: ModerationStatus.rejected,
          updatedAt: DateTime.now(),
        ).toMap(),
      );
    }
    await _syncService.processPendingSync();
    await _reloadDashboard();
  }

  Future<void> _archiveFlaggedPost(_FlaggedItem item) async {
    await _postDao.archivePost(item.postId);
    final updated = await _postDao.getPostById(item.postId);
    if (updated != null) {
      await _syncQueueDao.enqueue(
        operation: 'update',
        entity: 'posts',
        entityId: updated.id,
        payload: updated.copyWith(
          isArchived: true,
          updatedAt: DateTime.now(),
        ).toMap(),
      );
    }
    await _syncService.processPendingSync();
    await _reloadDashboard();
  }

  Future<void> _suspendAuthor(_FlaggedItem item) async {
    if (item.authorId.isEmpty) return;
    await _userDao.suspendUser(item.authorId);
    await _activityLogDao.logAction(
      userId: item.authorId,
      action: 'admin_suspended_user',
      entityType: 'users',
      entityId: item.authorId,
      metadata: {'source': 'admin_dashboard_flags'},
    );
    await _reloadDashboard();
  }

  Future<void> _warnAuthor(_FlaggedItem item) async {
    if (item.authorId.isEmpty) return;
    await _activityLogDao.logAction(
      userId: item.authorId,
      action: 'admin_warning_issued',
      entityType: 'posts',
      entityId: item.postId,
      metadata: {
        'reason': item.violation.name,
        'risk': item.risk.name,
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Warning issued to ${item.authorId}')),
    );
  }

  void _openChatWithAuthor(PostModel post) {
    if (post.authorId.isEmpty) return;
    context.push(
      RouteNames.chatDetail.replaceFirst(':threadId', post.authorId),
      extra: {
        'peerName': post.authorName ?? 'Student',
        'peerPhotoUrl': post.authorPhotoUrl,
        'isPeerLecturer': false,
      },
    );
  }

  Widget _summaryCardsWrap(List<_SummaryCard> cards) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: cards
          .map((card) => SizedBox(width: 220, child: card))
          .toList(growable: false),
    );
  }

  void _setSelectedTab(int index) {
    setState(() => _selectedTab = index);
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildSidebar() {
    Widget navTile({
      required int tab,
      required IconData icon,
      required String title,
      int? count,
    }) {
      final selected = _selectedTab == tab;
      return ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
        leading: Icon(icon, size: 20, color: selected ? AppColors.primary : null),
        title: Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? AppColors.primary : null,
          ),
        ),
        trailing: count != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.14)
                      : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.primary : AppColors.textSecondaryLight,
                  ),
                ),
              )
            : null,
        selected: selected,
        selectedColor: AppColors.primary,
        onTap: () => _setSelectedTab(tab),
      );
    }

    return Material(
      color: Theme.of(context).cardColor,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 12),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Admin Console',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: const EdgeInsets.only(left: 8),
              leading: const Icon(Icons.gavel_rounded),
              title: Text(
                'Moderation',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              initiallyExpanded: _selectedTab == 0 || _selectedTab == 1,
              children: [
                navTile(
                  tab: 0,
                  icon: Icons.dashboard_outlined,
                  title: 'Overview',
                  count: _flaggedPosts,
                ),
                navTile(
                  tab: 1,
                  icon: Icons.playlist_add_check_outlined,
                  title: 'Review Queue',
                  count: _pendingReviews,
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: const EdgeInsets.only(left: 8),
              leading: const Icon(Icons.groups_rounded),
              title: Text(
                'Users & Academics',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              initiallyExpanded:
                  _selectedTab == 2 || _selectedTab == 3 || _selectedTab == 4,
              children: [
                navTile(
                  tab: 2,
                  icon: Icons.group_outlined,
                  title: 'Users',
                  count: _totalUsers,
                ),
                navTile(
                  tab: 3,
                  icon: Icons.school_outlined,
                  title: 'Faculties',
                ),
                navTile(
                  tab: 4,
                  icon: Icons.book_outlined,
                  title: 'Courses',
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: const EdgeInsets.only(left: 8),
              leading: const Icon(Icons.insights_rounded),
              title: Text(
                'Insights',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              initiallyExpanded: _selectedTab == 5 || _selectedTab == 6,
              children: [
                navTile(
                  tab: 5,
                  icon: Icons.auto_graph_outlined,
                  title: 'AI Recommendations',
                ),
                navTile(
                  tab: 6,
                  icon: Icons.history_outlined,
                  title: 'System Logs',
                  count: _syncPending,
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: const EdgeInsets.only(left: 8),
              leading: const Icon(Icons.tune_rounded),
              title: Text(
                'System',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              initiallyExpanded: _selectedTab == 7,
              children: [
                navTile(
                  tab: 7,
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_selectedTab == 1) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Pending Moderation Queue',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ),
          if (_pendingQueue.isEmpty)
            const ListTile(
              leading: Icon(Icons.check_circle_outline_rounded),
              title: Text('No pending posts. Great job!'),
            ),
          ..._pendingQueue.map((post) => ListTile(
                title: Text(post.title),
                subtitle: Text('By ${post.authorName ?? post.authorId}'),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    IconButton(
                      tooltip: 'Chat author',
                      onPressed: () => _openChatWithAuthor(post),
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                    ),
                    IconButton(
                      tooltip: 'Approve',
                      onPressed: () => _approvePendingPost(post),
                      icon: const Icon(Icons.check_circle_rounded, color: AppColors.success),
                    ),
                    IconButton(
                      tooltip: 'Reject',
                      onPressed: () => _rejectPendingPost(post),
                      icon: const Icon(Icons.cancel_rounded, color: AppColors.danger),
                    ),
                  ],
                ),
              )),
        ],
      );
    }

    if (_selectedTab == 2) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Users Management',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ),
          ..._recentUsers.map(
            (user) {
              final displayName = _bestUserLabel(
                displayName: user.displayName,
                email: user.email,
                userId: user.id,
              );
              final initials = displayName.isNotEmpty
                  ? displayName[0].toUpperCase()
                  : '?';

              return Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryTint10,
                    child: Text(
                      initials,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  title: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTint10,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                user.role.label,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            if (user.isSuspended)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Suspended',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                            if (user.isBanned)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Banned',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.danger,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'User actions',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (value) async {
                      switch (value) {
                        case 'suspend':
                          await _userDao.suspendUser(user.id);
                          break;
                        case 'ban':
                          await _userDao.banUser(user.id);
                          break;
                        case 'delete':
                          await _userDao.deleteUser(user.id);
                          break;
                      }
                      await _reloadDashboard();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem<String>(
                        value: 'suspend',
                        child: Text('Suspend'),
                      ),
                      PopupMenuItem<String>(
                        value: 'ban',
                        child: Text('Ban'),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    if (_selectedTab == 3) {
      return BlocProvider(
        create: (_) => FacultyManagementCubit(),
        child: const FacultyManagementScreen(embedded: true),
      );
    }

    if (_selectedTab == 4) {
      return BlocProvider(
        create: (_) => CourseManagementCubit(),
        child: const CourseManagementScreen(embedded: true),
      );
    }

    if (_selectedTab == 5) {
      return const _AdminRecommendationsTab();
    }

    if (_selectedTab == 6) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'System Monitoring',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 12),
          _summaryCardsWrap([
            _SummaryCard(
              icon: Icons.sync_rounded,
              iconColor: AppColors.primary,
              value: _syncPending.toString(),
              label: 'Sync Queue',
            ),
            _SummaryCard(
              icon: Icons.warning_amber_rounded,
              iconColor: AppColors.warning,
              value: _syncDeadLetters.toString(),
              label: 'Sync Failures',
            ),
            _SummaryCard(
              icon: Icons.query_stats_rounded,
              iconColor: AppColors.success,
              value: _weeklyActiveUsers.toString(),
              label: 'Active Users (7d)',
            ),
          ]),
          const SizedBox(height: 10),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Weekly Reports Filed'),
            trailing: Text('$_weeklyReports'),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Total Posts'),
            trailing: Text('$_totalPosts'),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Total Users'),
            trailing: Text('$_totalUsers'),
          ),
        ],
      );
    }

    if (_selectedTab == 7) {
      return ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('Reload dashboard data'),
            onTap: _reloadDashboard,
          ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.only(bottom: _selected.isNotEmpty ? 156 : 24),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Summary Overview',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 10),
              _summaryCardsWrap([
                _SummaryCard(
                  icon: Icons.pending_actions_rounded,
                  iconColor: AppColors.warning,
                  value: _pendingReviews.toString(),
                  label: 'Pending Reviews',
                ),
                _SummaryCard(
                  icon: Icons.flag_rounded,
                  iconColor: AppColors.danger,
                  value: _flaggedPosts.toString(),
                  label: 'Flagged Posts',
                ),
                _SummaryCard(
                  icon: Icons.person_off_rounded,
                  iconColor: AppColors.primary,
                  value: _reportedUsers.toString(),
                  label: 'Reported Users',
                ),
              ]),
              const SizedBox(height: 18),
              Text(
                'Flagged Content',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
        ..._items.map(
          (item) => _FlaggedCard(
            item: item,
            onSelect: () => _toggleSelect(item.postId),
            onReview: () => _archiveFlaggedPost(item),
            onWarn: () => _warnAuthor(item),
            onSuspend: () => _suspendAuthor(item),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSelected = _selected.isNotEmpty;
    final isWide = MediaQuery.of(context).size.width >= 980;

    return Scaffold(
      drawer: isWide
          ? null
          : Drawer(
              child: _buildSidebar(),
            ),
      appBar: AppBar(
        leading: isWide
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.shield_outlined, color: AppColors.primary),
              )
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        title: Text(
          'Moderation Dashboard',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reloadDashboard,
          ),
        ],
      ),
      body: Row(
        children: [
          if (isWide)
            SizedBox(
              width: 280,
              child: _buildSidebar(),
            ),
          Expanded(
            child: _buildTabBody(),
          ),
        ],
      ),
      bottomSheet: hasSelected && _selectedTab == 0
          ? SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 12),
              child: _BulkActionBar(
                count: _selected.length,
                onApprove: () => _approveSelected(),
                onReject: () => _rejectSelected(),
                onBan: () {},
                onDeselect: () {
                  setState(() {
                    for (final item in _items) {
                      item.isSelected = false;
                    }
                  });
                },
              ),
            )
          : null,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlaggedCard extends StatelessWidget {
  final _FlaggedItem item;
  final VoidCallback onSelect;
  final VoidCallback onReview;
  final VoidCallback onWarn;
  final VoidCallback onSuspend;

  const _FlaggedCard({
    required this.item,
    required this.onSelect,
    required this.onReview,
    required this.onWarn,
    required this.onSuspend,
  });

  @override
  Widget build(BuildContext context) {
    final (riskLabel, riskBg, riskFg) = switch (item.risk) {
      _Risk.high => ('High Risk', const Color(0xFFFEF3C7), const Color(0xFFB45309)),
      _Risk.medium => ('Medium', AppColors.surfaceLight, AppColors.textSecondaryLight),
      _Risk.low => ('Low', AppColors.surfaceLight, AppColors.textSecondaryLight),
    };

    final (violIcon, violLabel) = switch (item.violation) {
      _Violation.inappropriate => (Icons.warning_rounded, 'Inappropriate Content'),
      _Violation.suspicious => (Icons.error_outline_rounded, 'Suspicious Activity'),
      _Violation.spam => (Icons.block_rounded, 'Spam / Repeated Post'),
      _Violation.other => (Icons.help_outline_rounded, 'Other'),
    };

    return GestureDetector(
      onLongPress: onSelect,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: item.isSelected ? AppColors.primaryTint10 : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(
            color: item.isSelected ? AppColors.primary : AppColors.borderLight,
            width: item.isSelected ? 1.5 : 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Reported by: ${item.reportedBy}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.reportsCount} report${item.reportsCount == 1 ? '' : 's'}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: riskBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    riskLabel,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: riskFg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(violIcon, size: 16, color: AppColors.textSecondaryLight),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    violLabel,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                ),
                TextButton(onPressed: onReview, child: const Text('Hide')),
                TextButton(onPressed: onWarn, child: const Text('Warn')),
                TextButton(onPressed: onSuspend, child: const Text('Suspend')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkActionBar extends StatelessWidget {
  final int count;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onBan;
  final VoidCallback onDeselect;

  const _BulkActionBar({
    required this.count,
    required this.onApprove,
    required this.onReject,
    required this.onBan,
    required this.onDeselect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          TextButton(onPressed: onDeselect, child: const Text('Clear')),
          FilledButton(onPressed: onApprove, child: const Text('Approve')),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onReject,
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Reject'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onBan,
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Ban'),
          ),
        ],
      ),
    );
  }
}

// ── AI Recommendations tab ────────────────────────────────────────────────────

class _AdminRecommendationsTab extends StatefulWidget {
  const _AdminRecommendationsTab();

  @override
  State<_AdminRecommendationsTab> createState() =>
      _AdminRecommendationsTabState();
}

class _AdminRecommendationsTabState extends State<_AdminRecommendationsTab> {
  late Future<_RecSummary> _future;
  String? _filterAlgo;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RecSummary> _load() async {
    final dao = sl<RecommendationLogDao>();
    final userDao = sl<UserDao>();
    final stats = await dao.getAlgorithmSummary();
    final total = await dao.getTotalCount();
    final unique = await dao.getDistinctUserIds();
    final recent = await dao.getRecentLogs(pageSize: 50);
    final userNames = <String, String>{};

    for (final row in recent) {
      final userId = row['user_id'] as String?;
      if (userId == null || userId.isEmpty || userNames.containsKey(userId)) {
        continue;
      }
      final user = await userDao.getUserById(userId);
      final displayName = _bestUserLabel(
        displayName: user?.displayName,
        email: user?.email,
        userId: userId,
      );
      userNames[userId] = displayName;
    }

    return _RecSummary(
      stats: stats,
      total: total,
      uniqueUsers: unique.length,
      recent: recent,
      userNames: userNames,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RecSummary>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 300,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(snap.error.toString())),
          );
        }
        final data = snap.data!;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // ── Header metrics row ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Recommendation Analytics',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.auto_graph_rounded,
                      iconColor: AppColors.primary,
                      value: data.total.toString(),
                      label: 'Total Logged',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.people_alt_rounded,
                      iconColor: AppColors.success,
                      value: data.uniqueUsers.toString(),
                      label: 'Unique Users',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.touch_app_rounded,
                      iconColor: AppColors.warning,
                      value: data.stats.isEmpty
                          ? '–'
                          : '${(data.stats.map((s) => s.interactionRate).reduce((a, b) => a + b) / data.stats.length * 100).round()}%',
                      label: 'Avg Interaction',
                    ),
                  ),
                ],
              ),
            ),

            // ── Per-algorithm bars ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Algorithms',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ),
            ...data.stats.map((s) => _AlgoStatCard(stat: s)),

            // ── Filter & recent log table ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Recent Logs',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    tooltip: 'Refresh',
                    onPressed: () =>
                        setState(() => _future = _load()),
                  ),
                ],
              ),
            ),

            // Algorithm filter chips
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _RecentFilterChip(
                    label: 'All',
                    selected: _filterAlgo == null,
                    onTap: () => setState(() => _filterAlgo = null),
                  ),
                  for (final algo in ['local', 'hybrid', 'applicant', 'collaborator'])
                    _RecentFilterChip(
                      label: algo,
                      selected: _filterAlgo == algo,
                      onTap: () => setState(() => _filterAlgo = algo),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Table header
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(flex: 3, child: _TableHeader('User')),
                  Expanded(flex: 2, child: _TableHeader('Algorithm')),
                  Expanded(flex: 2, child: _TableHeader('Score')),
                  Expanded(flex: 1, child: _TableHeader('✓')),
                ],
              ),
            ),
            const Divider(height: 1),

            ...data.recent
                .where((r) {
                  if (_filterAlgo == null) return true;
                  return (r['algorithm'] as String?) == _filterAlgo;
                })
                .take(50)
                .map(
                  (r) => _RecentLogRow(
                    row: r,
                    userName: data.userNames[r['user_id'] as String? ?? ''],
                  ),
                ),

            const SizedBox(height: 32),
          ],
        );
      },
    );
  }
}

class _RecSummary {
  final List<AlgorithmStats> stats;
  final int total;
  final int uniqueUsers;
  final List<Map<String, dynamic>> recent;
  final Map<String, String> userNames;

  const _RecSummary({
    required this.stats,
    required this.total,
    required this.uniqueUsers,
    required this.recent,
    required this.userNames,
  });
}

class _AlgoStatCard extends StatelessWidget {
  final AlgorithmStats stat;

  const _AlgoStatCard({required this.stat});

  Color get _color => switch (stat.algorithm) {
        'hybrid' => AppColors.primary,
        'local' => AppColors.success,
        'applicant' => AppColors.roleLecturer,
        _ => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    final rate = stat.interactionRate;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  stat.algorithm,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _color,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${stat.total} shown · ${stat.interacted} clicked',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(rate * 100).toStringAsFixed(1)}%',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate,
              backgroundColor: _color.withValues(alpha: 0.12),
              color: _color,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RecentFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondaryLight,
      ),
    );
  }
}

class _RecentLogRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final String? userName;

  const _RecentLogRow({required this.row, this.userName});

  @override
  Widget build(BuildContext context) {
    final rawUserId = row['user_id'] as String? ?? '';
    final userLabel = _bestUserLabel(
      displayName: userName,
      userId: rawUserId,
    );
    final algo = row['algorithm'] as String? ?? '?';
    final score = (row['score'] as num?)?.toDouble() ?? 0.0;
    final interacted = (row['was_interacted'] as int? ?? 0) == 1;

    final algoColor = switch (algo) {
      'hybrid' => AppColors.primary,
      'local' => AppColors.success,
      'applicant' => AppColors.roleLecturer,
      _ => AppColors.warning,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              userLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppColors.textSecondaryLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: algoColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                algo,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: algoColor,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${(score * 100).round()}%',
              style: GoogleFonts.plusJakartaSans(fontSize: 11),
            ),
          ),
          Expanded(
            flex: 1,
            child: Icon(
              interacted
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 14,
              color: interacted ? AppColors.success : AppColors.borderLight,
            ),
          ),
        ],
      ),
    );
  }
}
