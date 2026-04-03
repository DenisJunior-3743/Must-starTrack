import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/group_dao.dart';
import '../../../data/local/dao/notification_dao.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/group_model.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/remote/sync_service.dart';
import '../../../data/local/dao/recommendation_log_dao.dart';
import '../../../core/constants/app_enums.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../bloc/course_management_cubit.dart';
import '../bloc/faculty_management_cubit.dart';
import 'course_management_screen.dart';
import 'faculty_management_screen.dart';
import 'resource_monitoring_screen.dart';
import 'sync_queue_details_screen.dart';
import 'user_behavior_analytics_detailed_screen.dart';
import 'moderation_analytics_screen.dart';
import 'sync_consistency_screen.dart';
import 'chatbot_analytics_screen.dart';

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

String _taskBucketFromRecRow(Map<String, dynamic> row) {
  final algorithm = (row['algorithm'] as String? ?? '').trim().toLowerCase();
  final itemType = (row['item_type'] as String? ?? '').trim().toLowerCase();

  if (algorithm == 'applicant') return 'opportunities';
  if (algorithm == 'collaborator') return 'streaming';
  if (itemType == 'user') return 'members';
  return 'projects';
}

String _taskBucketLabel(String bucket) {
  switch (bucket) {
    case 'opportunities':
      return 'Opportunities';
    case 'streaming':
      return 'Streaming';
    case 'members':
      return 'Members';
    case 'projects':
    default:
      return 'Projects';
  }
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
  final _firestoreService = sl<FirestoreService>();
  final _notifDao = sl<NotificationDao>();
  late final FacultyManagementCubit _facultyManagementCubit;
  late final CourseManagementCubit _courseManagementCubit;
  bool _isSidebarVisible = true;
  StreamSubscription<List<UserModel>>? _usersSub;
  StreamSubscription<void>? _notifCountSub;

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
  int _unreadNotifCount = 0;
  List<PostModel> _pendingQueue = const [];
  List<UserModel> _allUsers = const [];
  List<UserModel> _filteredUsers = const [];
  String _userSearchQuery = '';
  final List<_FlaggedItem> _items = [];

  @override
  void initState() {
    super.initState();
    _facultyManagementCubit = FacultyManagementCubit();
    _courseManagementCubit = CourseManagementCubit();
    _reloadDashboard();
    _subscribeToUsersStream();
    _subscribeToNotificationCount();
  }

  /// Listens to the notification DAO change stream and refreshes the unread
  /// badge count whenever a notification is inserted or marked read.
  void _subscribeToNotificationCount() {
    final uid = sl<AuthCubit>().currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    _unreadNotifCount = 0;
    // Initial load
    _notifDao.getUnreadCount(uid).then((count) {
      if (mounted) setState(() => _unreadNotifCount = count);
    });
    _notifCountSub = _notifDao.changes.listen((_) async {
      if (!mounted) return;
      final count = await _notifDao.getUnreadCount(uid);
      if (mounted) setState(() => _unreadNotifCount = count);
    });
  }

  /// Listens to the Firestore users collection so the admin user list updates
  /// the moment a new user registers or an existing profile changes — no
  /// manual refresh needed.
  void _subscribeToUsersStream() {
    _usersSub = _firestoreService.watchAllUsers(limit: 500).listen(
      (remoteUsers) async {
        debugPrint(
            '[AdminDashboard][UserSync] stream event: '
            'remoteUsers=${remoteUsers.length}');
        for (final user in remoteUsers) {
          debugPrint(
              '[AdminDashboard][UserSync]   stream uid=${user.id} '
              'email=${user.email} role=${user.role.name}');
        }

        // Upsert every user into local SQLite so FK dependencies are satisfied.
        var upserted = 0;
        var failed = 0;
        for (final user in remoteUsers) {
          try {
            await _userDao.insertUser(user);
            upserted++;
          } catch (error) {
            failed++;
            debugPrint(
                '[AdminDashboard][UserSync] ⚠ stream upsert failed '
                'uid=${user.id} email=${user.email}: $error');
          }
        }

        final localCount = await _userDao.getUserCount();
        debugPrint(
            '[AdminDashboard][UserSync] after stream upsert: '
            'remote=${remoteUsers.length} local=$localCount '
            'upserted=$upserted failed=$failed');
        if (localCount < remoteUsers.length) {
          debugPrint(
              '[AdminDashboard][UserSync] ⚠ CONSISTENCY GAP: '
              '${remoteUsers.length - localCount} user(s) missing from local DB.');
        }

        if (!mounted) return;
        setState(() {
          _allUsers = remoteUsers;
          _totalUsers = remoteUsers.length;
          _filterUsers(_userSearchQuery);
        });
      },
      onError: (Object error) {
        debugPrint('[AdminDashboard] users stream error: $error');
        Future<void>.microtask(() async {
          final localUsers = await _userDao.getAllUsers(pageSize: 500);
          final localCount = await _userDao.getUserCount();
          debugPrint(
              '[AdminDashboard][UserSync] stream fallback to local cache: '
              'getUserCount()=$localCount '
              'getAllUsers(pageSize:500).length=${localUsers.length}');
          if (!mounted) return;
          setState(() {
            _allUsers = localUsers;
            _totalUsers = localCount;
            _filterUsers(_userSearchQuery);
          });
        });
      },
    );
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _notifCountSub?.cancel();
    _facultyManagementCubit.close();
    _courseManagementCubit.close();
    super.dispose();
  }

  List<_FlaggedItem> get _selected => _items.where((i) => i.isSelected).toList();

  Future<void> _reloadDashboard() async {
    setState(() => _loading = true);
    try {
      // Ensure dashboard decisions use fresh remote data, not stale local cache.
      await _syncService.processPendingSync();
      await _syncService.syncRemoteToLocal(
        postLimit: 250,
        forceIncludePendingForAdmin: true,
      );

      // ── User-count diagnostics ───────────────────────────────────────
      final localCountAfterSync = await _userDao.getUserCount();
      final allUsers = await _userDao.getAllUsers(pageSize: 500);
      debugPrint(
          '[AdminDashboard][UserSync] _reloadDashboard: '
          'getUserCount()=$localCountAfterSync '
          'getAllUsers(pageSize:500).length=${allUsers.length}');
      if (localCountAfterSync != allUsers.length) {
        debugPrint(
            '[AdminDashboard][UserSync] ⚠ pageSize cap hit or query mismatch: '
            'count=$localCountAfterSync but list=${allUsers.length}');
      }
      for (final user in allUsers) {
        debugPrint(
            '[AdminDashboard][UserSync]   local uid=${user.id} '
            'email=${user.email} role=${user.role.name}');
      }

      final postStats = await _postDao.getPostStats();
      final pendingPosts = await _postDao.getPendingModerationPosts(limit: 250);
      final flaggedRows = await _activityLogDao.getReportedPostSummaries(limit: 80);
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
        _allUsers = allUsers;
        _filterUsers(_userSearchQuery);
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

  Future<void> _logoutAdmin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out admin?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await sl<AuthCubit>().logout();
    if (!mounted) return;
    context.go(RouteNames.login);
  }

  void _toggleSelect(String id) {
    setState(() {
      final item = _items.firstWhere((i) => i.postId == id);
      item.isSelected = !item.isSelected;
    });
  }

  void _filterUsers(String query) {
    setState(() {
      _userSearchQuery = query.toLowerCase();
      if (_userSearchQuery.isEmpty) {
        _filteredUsers = _allUsers;
      } else {
        _filteredUsers = _allUsers
            .where((user) {
              final displayName = _bestUserLabel(
                displayName: user.displayName,
                email: user.email,
                userId: user.id,
              ).toLowerCase();
              final email = user.email.toLowerCase();
              return displayName.contains(_userSearchQuery) ||
                  email.contains(_userSearchQuery) ||
                  user.id.toLowerCase().contains(_userSearchQuery);
            })
            .toList();
      }
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
    final isWide = MediaQuery.of(context).size.width >= 980;
    setState(() {
      _selectedTab = index;
      if (isWide) {
        _isSidebarVisible = false;
      }
    });
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
              initiallyExpanded:
                  _selectedTab == 5 ||
                  _selectedTab == 6 ||
                  _selectedTab == 13 ||
                  _selectedTab == 14 ||
                  _selectedTab == 15,
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
                navTile(
                  tab: 13,
                  icon: Icons.feedback_outlined,
                  title: 'App Feedback',
                ),
                navTile(
                  tab: 14,
                  icon: Icons.groups_rounded,
                  title: 'Groups',
                ),
                navTile(
                  tab: 15,
                  icon: Icons.query_stats_rounded,
                  title: 'Chatbot Accuracy',
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: const EdgeInsets.only(left: 8),
              leading: const Icon(Icons.monitor_heart_rounded),
              title: Text(
                'Monitoring',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              initiallyExpanded:
                  _selectedTab == 8 ||
                  _selectedTab == 9 ||
                  _selectedTab == 10 ||
                  _selectedTab == 11 ||
                  _selectedTab == 12,
              children: [
                navTile(
                  tab: 8,
                  icon: Icons.memory_rounded,
                  title: 'Resources',
                ),
                navTile(
                  tab: 9,
                  icon: Icons.cloud_sync_rounded,
                  title: 'Sync Queue',
                  count: _syncDeadLetters,
                ),
                navTile(
                  tab: 10,
                  icon: Icons.people_outline_rounded,
                  title: 'User Behavior',
                ),
                navTile(
                  tab: 11,
                  icon: Icons.assessment_rounded,
                  title: 'Moderation Stats',
                  count: _flaggedPosts,
                ),
                navTile(
                  tab: 12,
                  icon: Icons.verified_rounded,
                  title: 'Sync Consistency',
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
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 6),
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              ),
              leading: const Icon(
                Icons.logout_rounded,
                size: 20,
                color: AppColors.danger,
              ),
              title: Text(
                'Log Out',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
              onTap: _logoutAdmin,
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
                      tooltip: 'View content',
                      onPressed: () async {
                        final changed = await context.push<bool>(
                          RouteNames.adminPostReview
                              .replaceFirst(':postId', post.id),
                        );
                        if (changed == true) {
                          await _reloadDashboard();
                        }
                      },
                      icon: const Icon(Icons.visibility_rounded),
                    ),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Search bar
          TextField(
            onChanged: _filterUsers,
            decoration: InputDecoration(
              hintText: 'Search users by name, email, or ID...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _userSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => _filterUsers(''),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Users Management${_filteredUsers.length != _allUsers.length ? ' (${_filteredUsers.length} results)' : ' (${_allUsers.length} total)'}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 8),
          if (_filteredUsers.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _userSearchQuery.isNotEmpty
                      ? 'No users match your search'
                      : 'No users found',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                ),
              ),
            ),
          ..._filteredUsers.map(
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
                margin: const EdgeInsets.only(bottom: 10),
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
      return BlocProvider.value(
        value: _facultyManagementCubit,
        child: const FacultyManagementScreen(embedded: true),
      );
    }

    if (_selectedTab == 4) {
      return BlocProvider.value(
        value: _courseManagementCubit,
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

    if (_selectedTab == 13) {
      return const _AdminAppFeedbackTab();
    }

    if (_selectedTab == 14) {
      return const _AdminGroupsTab();
    }

    if (_selectedTab == 15) {
      return const ChatbotAnalyticsScreen();
    }

    if (_selectedTab == 8) {
      return const ResourceMonitoringScreen();
    }

    if (_selectedTab == 9) {
      return const SyncQueueDetailsScreen();
    }

    if (_selectedTab == 10) {
      return const UserBehaviorAnalyticsScreen();
    }

    if (_selectedTab == 11) {
      return const ModerationAnalyticsScreen();
    }

    if (_selectedTab == 12) {
      return const SyncConsistencyScreen();
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
            ? IconButton(
                tooltip: _isSidebarVisible ? 'Hide sidebar' : 'Show sidebar',
                icon: Icon(
                  _isSidebarVisible
                      ? Icons.menu_open_rounded
                      : Icons.menu_rounded,
                  color: AppColors.primary,
                ),
                onPressed: () {
                  setState(() => _isSidebarVisible = !_isSidebarVisible);
                },
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
          // ── Notification bell ───────────────────────────────────────────
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {
                  context.push(RouteNames.adminNotifications);
                },
              ),
              if (_unreadNotifCount > 0)
                Positioned(
                  top: 8,
                  right: 6,
                  child: IgnorePointer(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _unreadNotifCount > 99 ? '99+' : '$_unreadNotifCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reloadDashboard,
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logoutAdmin,
          ),
        ],
      ),
      body: Row(
        children: [
          if (isWide && _isSidebarVisible)
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

class _AdminAppFeedbackTab extends StatefulWidget {
  const _AdminAppFeedbackTab();

  @override
  State<_AdminAppFeedbackTab> createState() => _AdminAppFeedbackTabState();
}

class _AdminAppFeedbackTabState extends State<_AdminAppFeedbackTab> {
  late Future<_AdminFeedbackSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AdminFeedbackSummary> _load() async {
    final firestore = sl<FirestoreService>();
    final rows = await firestore.getRecentAppFeedback(limit: 120);

    final counts = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    final comments = <Map<String, dynamic>>[];
    double sum = 0;
    var total = 0;

    for (final row in rows) {
      final stars = (row['stars'] as num?)?.toInt() ?? 0;
      if (stars < 1 || stars > 5) continue;

      total += 1;
      sum += stars;
      counts[stars] = (counts[stars] ?? 0) + 1;

      final comment = row['comment']?.toString().trim() ?? '';
      if (comment.isNotEmpty) {
        comments.add(row);
      }
    }

    return _AdminFeedbackSummary(
      average: total == 0 ? 0 : sum / total,
      total: total,
      counts: counts,
      comments: comments.take(60).toList(growable: false),
    );
  }

  String _nameForRow(Map<String, dynamic> row) {
    final userName = row['user_name']?.toString().trim() ?? '';
    if (userName.isNotEmpty) return userName;
    final email = row['user_email']?.toString().trim() ?? '';
    final local = email.split('@').first.trim();
    if (local.isNotEmpty) return _titleCaseWords(local.replaceAll(RegExp(r'[_\-.]+'), ' '));
    final userId = row['user_id']?.toString().trim() ?? '';
    if (userId.isEmpty) return 'Member';
    return userId.length > 8 ? '${userId.substring(0, 8)}…' : userId;
  }

  String _ago(Map<String, dynamic> row) {
    final raw = row['created_at']?.toString() ?? '';
    final at = DateTime.tryParse(raw)?.toLocal();
    if (at == null) return 'recent';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${at.day}/${at.month}/${at.year}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminFeedbackSummary>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to load app feedback: ${snap.error}'),
            ),
          );
        }

        final data = snap.data ?? const _AdminFeedbackSummary.empty();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    icon: Icons.star_rounded,
                    iconColor: AppColors.warning,
                    value: data.average.toStringAsFixed(2),
                    label: 'Avg App Rating',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SummaryCard(
                    icon: Icons.rate_review_rounded,
                    iconColor: AppColors.primary,
                    value: data.total.toString(),
                    label: 'Total Responses',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                children: [
                  for (var star = 5; star >= 1; star--)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              '$star★',
                              style: GoogleFonts.plusJakartaSans(fontSize: 11),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: data.total == 0
                                    ? 0
                                    : (data.counts[star] ?? 0) / data.total,
                                minHeight: 7,
                                backgroundColor: AppColors.borderLight,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${data.counts[star] ?? 0}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Member Comments',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: () => setState(() => _future = _load()),
                ),
              ],
            ),
            if (data.comments.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No comments yet. Ratings are being collected.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                ),
              ),
            ...data.comments.map((row) {
              final stars = (row['stars'] as num?)?.toInt() ?? 0;
              final comment = row['comment']?.toString().trim() ?? '';
              final userRole = row['user_role']?.toString().trim() ?? 'member';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
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
                        Expanded(
                          child: Text(
                            _nameForRow(row),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _ago(row),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$stars★',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryTint10,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            userRole,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (comment.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        comment,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _AdminFeedbackSummary {
  final double average;
  final int total;
  final Map<int, int> counts;
  final List<Map<String, dynamic>> comments;

  const _AdminFeedbackSummary({
    required this.average,
    required this.total,
    required this.counts,
    required this.comments,
  });

  const _AdminFeedbackSummary.empty()
      : average = 0,
        total = 0,
        counts = const {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
        comments = const [];
}

class _AdminGroupsTab extends StatefulWidget {
  const _AdminGroupsTab();

  @override
  State<_AdminGroupsTab> createState() => _AdminGroupsTabState();
}

class _AdminGroupsTabState extends State<_AdminGroupsTab> {
  late Future<List<GroupModel>> _future;
  final _groupDao = sl<GroupDao>();
  final _postDao = sl<PostDao>();
  final _syncQueue = sl<SyncQueueDao>();
  final _syncService = sl<SyncService>();

  @override
  void initState() {
    super.initState();
    _future = _groupDao.getAllGroups(includeDissolved: true, limit: 240);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _groupDao.getAllGroups(includeDissolved: true, limit: 240);
    });
  }

  Future<void> _dissolve(GroupModel group) async {
    await _groupDao.dissolveGroup(group.id);
    await _syncQueue.enqueue(
      operation: 'dissolve',
      entity: 'groups',
      entityId: group.id,
      payload: {'group_id': group.id},
    );
    await _syncService.processPendingSync();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GroupModel>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Failed to load groups: ${snap.error}'));
        }

        final groups = snap.data ?? const <GroupModel>[];
        final active = groups.where((group) => !group.isDissolved).toList();
        final dissolved = groups.where((group) => group.isDissolved).toList();

        return FutureBuilder<List<PostModel>>(
          future: _postDao.getRecentGroupProjects(limit: 200),
          builder: (context, postsSnap) {
            final groupPosts = postsSnap.data ?? const <PostModel>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.groups_rounded,
                        iconColor: AppColors.primary,
                        value: active.length.toString(),
                        label: 'Active Groups',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.folder_copy_rounded,
                        iconColor: AppColors.success,
                        value: groupPosts.length.toString(),
                        label: 'Group Projects',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.archive_rounded,
                        iconColor: AppColors.warning,
                        value: dissolved.length.toString(),
                        label: 'Dissolved',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Groups Registry',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ],
                ),
                if (groups.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'No groups created yet.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      ),
                    ),
                  ),
                ...groups.map(
                  (group) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        group.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${group.memberCount} members • ${group.visiblePostCount} posts',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                      trailing: group.isDissolved
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Dissolved',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.warning,
                                ),
                              ),
                            )
                          : TextButton.icon(
                              onPressed: () => _dissolve(group),
                              icon: const Icon(Icons.block_rounded, size: 16),
                              label: const Text('Dissolve'),
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
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
  String? _filterTask;

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
    final recent = await dao.getRecentLogs(pageSize: 400);
    final topVolumes = await dao.getTopUsersByLogCount(limit: 8);
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

    for (final volume in topVolumes) {
      final userId = volume.userId;
      if (userNames.containsKey(userId)) continue;
      final user = await userDao.getUserById(userId);
      final displayName = _bestUserLabel(
        displayName: user?.displayName,
        email: user?.email,
        userId: userId,
      );
      userNames[userId] = displayName;
    }

    final taskBreakdown = _buildTaskBreakdown(recent);
    final memberComparisons = _buildMemberComparisons(recent);
    final reasonWeights = _buildReasonWeights(recent);
    final avgLogsPerUser =
      unique.isEmpty ? 0.0 : (total.toDouble() / unique.length);

    return _RecSummary(
      stats: stats,
      total: total,
      uniqueUsers: unique.length,
      recent: recent,
      userNames: userNames,
      topVolumes: topVolumes,
      taskBreakdown: taskBreakdown,
      memberComparisons: memberComparisons,
      reasonWeights: reasonWeights,
      avgLogsPerUser: avgLogsPerUser,
      projectedLogsFor100Members: (avgLogsPerUser * 100).round(),
    );
  }

  List<_TaskAlgorithmMetric> _buildTaskBreakdown(
    List<Map<String, dynamic>> rows,
  ) {
    final buckets = <String, _TaskAlgorithmAccumulator>{};
    for (final row in rows) {
      final task = _taskBucketFromRecRow(row);
      final algorithm = (row['algorithm'] as String? ?? 'unknown').trim();
      final key = '$task|$algorithm';
      final score = (row['score'] as num?)?.toDouble() ?? 0.0;
      final interacted = (row['was_interacted'] as int? ?? 0) == 1;

      final item = buckets.putIfAbsent(key, () {
        return _TaskAlgorithmAccumulator(task: task, algorithm: algorithm);
      });
      item.shown += 1;
      item.scoreTotal += score;
      if (interacted) item.interacted += 1;
    }

    final metrics = buckets.values
        .map(
          (item) => _TaskAlgorithmMetric(
            task: item.task,
            algorithm: item.algorithm,
            shown: item.shown,
            interacted: item.interacted,
            avgScore: item.shown == 0 ? 0 : item.scoreTotal / item.shown,
          ),
        )
        .toList();

    metrics.sort((a, b) {
      final taskCompare = a.task.compareTo(b.task);
      if (taskCompare != 0) return taskCompare;
      return b.shown.compareTo(a.shown);
    });
    return metrics;
  }

  List<_MemberTaskDecision> _buildMemberComparisons(
    List<Map<String, dynamic>> rows,
  ) {
    final local = <String, _AlgoAccumulator>{};
    final hybrid = <String, _AlgoAccumulator>{};

    for (final row in rows) {
      final algo = (row['algorithm'] as String? ?? '').trim().toLowerCase();
      if (algo != 'local' && algo != 'hybrid') continue;

      final userId = (row['user_id'] as String? ?? '').trim();
      if (userId.isEmpty) continue;
      final task = _taskBucketFromRecRow(row);
      final key = '$userId|$task';

      final score = (row['score'] as num?)?.toDouble() ?? 0.0;
      final interacted = (row['was_interacted'] as int? ?? 0) == 1;
      final target = algo == 'local' ? local : hybrid;

      final bucket = target.putIfAbsent(key, _AlgoAccumulator.new);
      bucket.count += 1;
      bucket.scoreTotal += score;
      if (interacted) bucket.interacted += 1;
    }

    final allKeys = <String>{...local.keys, ...hybrid.keys};
    final decisions = <_MemberTaskDecision>[];

    for (final key in allKeys) {
      final parts = key.split('|');
      if (parts.length != 2) continue;
      final userId = parts.first;
      final task = parts.last;

      final localItem = local[key] ?? _AlgoAccumulator();
      final hybridItem = hybrid[key] ?? _AlgoAccumulator();
      if (localItem.count == 0 && hybridItem.count == 0) continue;

      final localAvg = localItem.count == 0 ? 0.0 : localItem.scoreTotal / localItem.count;
      final hybridAvg =
          hybridItem.count == 0 ? 0.0 : hybridItem.scoreTotal / hybridItem.count;
      final chosen = _chooseAlgorithm(localItem, hybridItem, localAvg, hybridAvg);

      decisions.add(
        _MemberTaskDecision(
          userId: userId,
          task: task,
          localCount: localItem.count,
          hybridCount: hybridItem.count,
          localAvgScore: localAvg,
          hybridAvgScore: hybridAvg,
          selectedAlgorithm: chosen,
          scoreGap: (hybridAvg - localAvg).abs(),
        ),
      );
    }

    decisions.sort((a, b) {
      final usesCompare = b.totalLogs.compareTo(a.totalLogs);
      if (usesCompare != 0) return usesCompare;
      return b.scoreGap.compareTo(a.scoreGap);
    });
    return decisions;
  }

  String _chooseAlgorithm(
    _AlgoAccumulator local,
    _AlgoAccumulator hybrid,
    double localAvg,
    double hybridAvg,
  ) {
    if (hybrid.count == 0 && local.count > 0) return 'local';
    if (local.count == 0 && hybrid.count > 0) return 'hybrid';

    final localInteraction = local.count == 0 ? 0.0 : local.interacted / local.count;
    final hybridInteraction =
        hybrid.count == 0 ? 0.0 : hybrid.interacted / hybrid.count;
    final localComposite = localAvg + (localInteraction * 0.10);
    final hybridComposite = hybridAvg + (hybridInteraction * 0.10);
    return hybridComposite >= localComposite ? 'hybrid' : 'local';
  }

  List<_ReasonWeightMetric> _buildReasonWeights(
    List<Map<String, dynamic>> rows,
  ) {
    final acc = <String, _ReasonAccumulator>{};
    final totalsByTask = <String, int>{};

    for (final row in rows) {
      final algorithm = (row['algorithm'] as String? ?? '').trim().toLowerCase();
      if (algorithm != 'local' && algorithm != 'hybrid') continue;

      final task = _taskBucketFromRecRow(row);
      final score = (row['score'] as num?)?.toDouble() ?? 0.0;
      final interacted = (row['was_interacted'] as int? ?? 0) == 1;
      final reasons = _parseReasons(row['reasons']);
      if (reasons.isEmpty) continue;

      for (final reason in reasons) {
        final reasonKey = reason.trim();
        if (reasonKey.isEmpty) continue;
        final key = '$task|$reasonKey';
        final item = acc.putIfAbsent(
          key,
          () => _ReasonAccumulator(task: task, reason: reasonKey),
        );
        item.count += 1;
        item.scoreTotal += score;
        if (interacted) item.interacted += 1;
        totalsByTask[task] = (totalsByTask[task] ?? 0) + 1;
      }
    }

    final metrics = acc.values.map((item) {
      final taskTotal = totalsByTask[item.task] ?? 1;
      final frequencyShare = item.count / taskTotal;
      final avgScore = item.count == 0 ? 0.0 : item.scoreTotal / item.count;
      final interactionRate = item.count == 0 ? 0.0 : item.interacted / item.count;
      final weight = (frequencyShare * 0.60) + (avgScore * 0.30) + (interactionRate * 0.10);

      return _ReasonWeightMetric(
        task: item.task,
        reason: item.reason,
        count: item.count,
        avgScore: avgScore,
        interactionRate: interactionRate,
        weight: weight,
      );
    }).toList();

    metrics.sort((a, b) => b.weight.compareTo(a.weight));
    return metrics.take(12).toList();
  }

  List<String> _parseReasons(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Ignore malformed JSON and fall back to comma split.
    }
    return text
        .replaceAll('[', '')
        .replaceAll(']', '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
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

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Text(
                'Scale Watch',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.analytics_rounded,
                      iconColor: AppColors.primary,
                      value: data.avgLogsPerUser.toStringAsFixed(1),
                      label: 'Avg logs/member',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.groups_rounded,
                      iconColor: AppColors.roleLecturer,
                      value: data.projectedLogsFor100Members.toString(),
                      label: 'Projected @100 members',
                    ),
                  ),
                ],
              ),
            ),
            if (data.topVolumes.isNotEmpty)
              Container(
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
                    Text(
                      'High-volume members',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...data.topVolumes.take(5).map((item) {
                      final label = data.userNames[item.userId] ?? item.userId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(fontSize: 11),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${item.total} logs',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'AI vs Local by Member and Task',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _RecentFilterChip(
                    label: 'All tasks',
                    selected: _filterTask == null,
                    onTap: () => setState(() => _filterTask = null),
                  ),
                  for (final task in ['projects', 'opportunities', 'streaming', 'members'])
                    _RecentFilterChip(
                      label: _taskBucketLabel(task),
                      selected: _filterTask == task,
                      onTap: () => setState(() => _filterTask = task),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ...data.memberComparisons
                .where((item) => _filterTask == null || item.task == _filterTask)
                .take(30)
                .map(
                  (item) => _MemberAlgoComparisonCard(
                    item: item,
                    userName: data.userNames[item.userId],
                  ),
                ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Signal Weights (Transparent Formula)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'weight = 0.60 × frequencyShare + 0.30 × averageScore + 0.10 × interactionRate',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ),
            ...data.reasonWeights.map((item) => _ReasonWeightCard(item: item)),

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
                  Expanded(flex: 2, child: _TableHeader('Task')),
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
                .take(80)
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
  final List<UserLogVolume> topVolumes;
  final List<_TaskAlgorithmMetric> taskBreakdown;
  final List<_MemberTaskDecision> memberComparisons;
  final List<_ReasonWeightMetric> reasonWeights;
  final double? _avgLogsPerUser;
  final int? _projectedLogsFor100Members;

  double get avgLogsPerUser => _avgLogsPerUser ?? 0.0;
  int get projectedLogsFor100Members => _projectedLogsFor100Members ?? 0;

  const _RecSummary({
    required this.stats,
    required this.total,
    required this.uniqueUsers,
    required this.recent,
    required this.userNames,
    required this.topVolumes,
    required this.taskBreakdown,
    required this.memberComparisons,
    required this.reasonWeights,
    double? avgLogsPerUser,
    int? projectedLogsFor100Members,
  })  : _avgLogsPerUser = avgLogsPerUser,
        _projectedLogsFor100Members = projectedLogsFor100Members;
}

class _TaskAlgorithmMetric {
  final String task;
  final String algorithm;
  final int shown;
  final int interacted;
  final double avgScore;

  const _TaskAlgorithmMetric({
    required this.task,
    required this.algorithm,
    required this.shown,
    required this.interacted,
    required this.avgScore,
  });
}

class _TaskAlgorithmAccumulator {
  final String task;
  final String algorithm;
  int shown = 0;
  int interacted = 0;
  double scoreTotal = 0;

  _TaskAlgorithmAccumulator({
    required this.task,
    required this.algorithm,
  });
}

class _AlgoAccumulator {
  int count = 0;
  int interacted = 0;
  double scoreTotal = 0;
}

class _MemberTaskDecision {
  final String userId;
  final String task;
  final int localCount;
  final int hybridCount;
  final double localAvgScore;
  final double hybridAvgScore;
  final String selectedAlgorithm;
  final double scoreGap;

  const _MemberTaskDecision({
    required this.userId,
    required this.task,
    required this.localCount,
    required this.hybridCount,
    required this.localAvgScore,
    required this.hybridAvgScore,
    required this.selectedAlgorithm,
    required this.scoreGap,
  });

  int get totalLogs => localCount + hybridCount;
}

class _ReasonAccumulator {
  final String task;
  final String reason;
  int count = 0;
  int interacted = 0;
  double scoreTotal = 0;

  _ReasonAccumulator({required this.task, required this.reason});
}

class _ReasonWeightMetric {
  final String task;
  final String reason;
  final int count;
  final double avgScore;
  final double interactionRate;
  final double weight;

  const _ReasonWeightMetric({
    required this.task,
    required this.reason,
    required this.count,
    required this.avgScore,
    required this.interactionRate,
    required this.weight,
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

class _MemberAlgoComparisonCard extends StatelessWidget {
  final _MemberTaskDecision item;
  final String? userName;

  const _MemberAlgoComparisonCard({required this.item, this.userName});

  @override
  Widget build(BuildContext context) {
    final userLabel = _bestUserLabel(displayName: userName, userId: item.userId);
    final pickedColor = item.selectedAlgorithm == 'hybrid'
        ? AppColors.primary
        : AppColors.success;

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
              Expanded(
                child: Text(
                  userLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: pickedColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Pick: ${item.selectedAlgorithm}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: pickedColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Task: ${_taskBucketLabel(item.task)} · Logs: ${item.totalLogs}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Local ${item.localCount} · ${(item.localAvgScore * 100).toStringAsFixed(1)}%',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11),
                ),
              ),
              Expanded(
                child: Text(
                  'Hybrid ${item.hybridCount} · ${(item.hybridAvgScore * 100).toStringAsFixed(1)}%',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReasonWeightCard extends StatelessWidget {
  final _ReasonWeightMetric item;

  const _ReasonWeightCard({required this.item});

  @override
  Widget build(BuildContext context) {
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
              Expanded(
                child: Text(
                  item.reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                (item.weight * 100).toStringAsFixed(1),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_taskBucketLabel(item.task)} · freq ${item.count} · avg ${(item.avgScore * 100).toStringAsFixed(1)}% · interact ${(item.interactionRate * 100).toStringAsFixed(1)}%',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              color: AppColors.textSecondaryLight,
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
    final task = _taskBucketFromRecRow(row);
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
            child: Text(
              _taskBucketLabel(task),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: AppColors.textSecondaryLight,
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
