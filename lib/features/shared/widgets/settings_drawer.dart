// lib/features/shared/widgets/settings_drawer.dart
//
// MUST StarTrack — Settings Side Drawer
//
// Opened by the hamburger (☰) button that lives in each screen's app bar.
// Contains: theme mode selector, notification prefs link, about, logout.
//
// To open from any screen:
//   Scaffold.of(context).openEndDrawer();
// (The hosting screen must declare `endDrawer: const SettingsDrawer()`.)

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/remote/sync_service.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../auth/bloc/auth_cubit.dart';

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGuest = sl<AuthCubit>().currentUser == null;
    final isAdmin = sl<AuthCubit>().isAdmin;

    return Drawer(
      width: 300,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ── Branded header ────────────────────────────────────────────────
          _DrawerHeader(isDark: isDark),

          // ── Scrollable body ───────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Appearance section
                const _SectionLabel('Appearance'),
                const _ThemeModeSelector(),
                const SizedBox(height: 8),
                const Divider(indent: 16, endIndent: 16),
                const SizedBox(height: 8),

                // Account section
                const _SectionLabel('Account'),
                _DrawerTile(
                  icon: Icons.person_outline_rounded,
                  label: 'My Profile',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(RouteNames.myProfile);
                  },
                ),
                if (!isGuest)
                  _DrawerTile(
                    icon: Icons.folder_open_rounded,
                    label: 'My Projects',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(RouteNames.projects);
                    },
                  ),
                _DrawerTile(
                  icon: Icons.leaderboard_rounded,
                  label: 'View Ranks',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(RouteNames.globalRanks);
                  },
                ),
                _DrawerTile(
                  icon: Icons.notifications_outlined,
                  label: 'Notification Settings',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(RouteNames.notificationSettings);
                  },
                ),
                if (!isGuest)
                  _DrawerTile(
                    icon: Icons.delete_forever_rounded,
                    label: 'Delete Account',
                    color: AppColors.danger,
                    onTap: () => _handleDeleteAccount(context),
                  ),
                const SizedBox(height: 8),
                const Divider(indent: 16, endIndent: 16),
                const SizedBox(height: 8),

                // App section
                const _SectionLabel('About'),
                _DrawerTile(
                  icon: Icons.info_outline_rounded,
                  label: 'About MUST StarTrack',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(RouteNames.about);
                  },
                ),
                _DrawerTile(
                  icon: Icons.star_border_rounded,
                  label: 'Rate This App',
                  onTap: () {
                    Navigator.of(context).pop();
                    Future<void>.delayed(Duration.zero, () {
                      if (!context.mounted) return;
                      _showAppFeedbackSheet(context);
                    });
                  },
                ),
                _DrawerTile(
                  icon: Icons.support_agent_rounded,
                  label: 'App Assistant',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(RouteNames.chatbot);
                  },
                ),
                if (isAdmin)
                  _DrawerTile(
                    icon: Icons.query_stats_rounded,
                    label: 'Chatbot Accuracy',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(RouteNames.adminChatbotAnalytics);
                    },
                  ),
                const SizedBox(height: 8),
                const Divider(indent: 16, endIndent: 16),
                const SizedBox(height: 8),

                // Logout
                _DrawerTile(
                  icon: Icons.logout_rounded,
                  label: 'Log Out',
                  color: isGuest ? null : AppColors.danger,
                  enabled: !isGuest,
                  onTap: () => _handleLogout(context),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // ── Footer version ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              'MUST StarTrack v1.0',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAppFeedbackSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AppFeedbackSheet(),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    Navigator.of(context).pop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
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
    if (confirmed == true) {
      await sl<AuthCubit>().logout();
      if (!context.mounted) return;
      context.go(RouteNames.home);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Logged out successfully. You are now viewing in guest mode.',
            style: GoogleFonts.plusJakartaSans(),
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    Navigator.of(context).pop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.danger, size: 22),
            SizedBox(width: 8),
            Expanded(child: Text('Delete Account?')),
          ],
        ),
        content: const Text(
          'You will be signed out immediately and your account will be '
          'flagged for removal.\n\n'
          'Our admin team will process the request within 7 working days. '
          'Your academic data is retained for audit purposes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete & Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final user = sl<AuthCubit>().currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final requestId = '${user.id}_deletion_${now.microsecondsSinceEpoch}';
    try {
      await sl<FirestoreService>().flagAccountForDeletion(
        requestId: requestId,
        payload: {
          'id': requestId,
          'user_id': user.id,
          'display_name': user.displayName ?? '',
          'email': user.email,
          'role': user.role.name,
          'requested_at': now.toIso8601String(),
          'status': 'pending',
          'reviewed_by': null,
          'reviewed_at': null,
        },
      );
      await sl<ActivityLogDao>().logAction(
        userId: user.id,
        action: 'request_account_deletion',
        entityType: 'user',
        entityId: user.id,
        metadata: {'requested_at': now.toIso8601String()},
      );
      // Sign the user out and send them to guest / login
      await sl<AuthCubit>().logout();
      if (context.mounted) context.go(RouteNames.login);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send request: $e')),
        );
      }
    }
  }
}

class _AppFeedbackSheet extends StatefulWidget {
  const _AppFeedbackSheet();

  @override
  State<_AppFeedbackSheet> createState() => _AppFeedbackSheetState();
}

class _AppFeedbackSheetState extends State<_AppFeedbackSheet> {
  final _commentCtrl = TextEditingController();
  final _activityDao = sl<ActivityLogDao>();
  final _syncQueueDao = sl<SyncQueueDao>();
  final _syncService = sl<SyncService>();
  final _firestore = sl<FirestoreService>();
  final _userDao = sl<UserDao>();

  int _stars = 0;
  bool _submitting = false;
  late Future<_CommunityFeedbackData> _communityFuture;

  @override
  void initState() {
    super.initState();
    _communityFuture = _loadCommunity();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<_CommunityFeedbackData> _loadCommunity() async {
    final rows = await _firestore.getRecentAppFeedback(limit: 80);
    if (rows.isEmpty) {
      return const _CommunityFeedbackData.empty();
    }

    final items = <_CommunityFeedbackItem>[];
    final starsCount = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    double sum = 0;

    for (final row in rows) {
      final stars = (row['stars'] as num?)?.toInt() ?? 0;
      if (stars < 1 || stars > 5) {
        continue;
      }

      final userId = row['user_id']?.toString() ?? '';
      final userName = row['user_name']?.toString().trim() ?? '';
      final userEmail = row['user_email']?.toString().trim() ?? '';
      final comment = row['comment']?.toString().trim() ?? '';
      final createdAtRaw = row['created_at']?.toString() ?? '';
      final createdAt = DateTime.tryParse(createdAtRaw);

      sum += stars;
      starsCount[stars] = (starsCount[stars] ?? 0) + 1;

      items.add(
        _CommunityFeedbackItem(
          userId: userId,
          userName: userName,
          userEmail: userEmail,
          stars: stars,
          comment: comment,
          createdAt: createdAt,
        ),
      );
    }

    final total = items.length;
    if (total == 0) {
      return const _CommunityFeedbackData.empty();
    }

    return _CommunityFeedbackData(
      average: sum / total,
      total: total,
      starsCount: starsCount,
      items: items,
    );
  }

  Future<void> _submitFeedback() async {
    final user = sl<AuthCubit>().currentUser;
    final userId = user?.id ?? '';
    if (userId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to submit app feedback.')),
      );
      return;
    }
    if (_stars < 1 || _stars > 5) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final now = DateTime.now();
    final feedbackId = '${userId}_${now.microsecondsSinceEpoch}';

    final localUser = await _userDao.getUserById(userId);
    final displayName = localUser?.displayName?.trim() ?? '';
    final payload = <String, dynamic>{
      'id': feedbackId,
      'user_id': userId,
      'user_name': displayName,
      'user_email': localUser?.email ?? user?.email ?? '',
      'user_role': user?.role.name ?? 'student',
      'stars': _stars,
      'comment': _commentCtrl.text.trim(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    try {
      await _activityDao.logAction(
        userId: userId,
        action: 'rate_app',
        entityType: 'app_feedback',
        entityId: feedbackId,
        metadata: {
          'stars': _stars,
          'comment': _commentCtrl.text.trim(),
        },
      );

      await _syncQueueDao.enqueue(
        operation: 'create',
        entity: 'app_feedback',
        entityId: feedbackId,
        payload: payload,
      );

      await _firestore.setAppFeedback(feedbackId: feedbackId, payload: payload);
      await _syncService.processPendingSync();

      if (!mounted) return;
      setState(() {
        _commentCtrl.clear();
        _stars = 0;
        _communityFuture = _loadCommunity();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks! Your app feedback was shared.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit feedback: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _labelForUser(_CommunityFeedbackItem item) {
    final displayName = item.userName.trim();
    if (displayName.isNotEmpty) return displayName;

    final emailLocal = item.userEmail.split('@').first.trim();
    if (emailLocal.isNotEmpty) return emailLocal;

    final id = item.userId.trim();
    if (id.isEmpty) return 'Member';
    return id.length > 8 ? '${id.substring(0, 8)}…' : id;
  }

  String _dateLabel(DateTime? createdAt) {
    if (createdAt == null) return 'just now';
    final now = DateTime.now();
    final diff = now.difference(createdAt.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  Widget _buildSubmitTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        Text(
          'How is MUST StarTrack working for you?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your rating and comment help us improve recommendations, streaming, and collaboration features.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final filled = index < _stars;
            return IconButton(
              onPressed:
                  _submitting ? null : () => setState(() => _stars = index + 1),
              icon: Icon(
                filled ? Icons.star_rounded : Icons.star_border_rounded,
                size: 34,
                color: filled ? AppColors.warning : AppColors.borderLight,
              ),
            );
          }),
        ),
        Center(
          child: Text(
            _stars == 0
                ? 'Tap to rate from 1 to 5 stars'
                : '$_stars star${_stars == 1 ? '' : 's'} selected',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _commentCtrl,
          minLines: 3,
          maxLines: 5,
          maxLength: 320,
          decoration: InputDecoration(
            labelText: 'Comment (optional)',
            hintText: 'Tell us what works well and what we should improve.',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _submitting ? null : _submitFeedback,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded),
          label: Text(_submitting ? 'Submitting...' : 'Submit Feedback'),
        ),
      ],
    );
  }

  Widget _buildCommunityTab() {
    return FutureBuilder<_CommunityFeedbackData>(
      future: _communityFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not load feedback: ${snap.error}'),
            ),
          );
        }

        final data = snap.data ?? const _CommunityFeedbackData.empty();
        if (data.total == 0) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No community feedback yet. Be the first to rate the app.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.average.toStringAsFixed(2),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          'Average from ${data.total} ratings',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        for (var star = 5; star >= 1; star--)
                          _StarDistributionRow(
                            star: star,
                            count: data.starsCount[star] ?? 0,
                            total: data.total,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ...data.items.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
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
                            _labelForUser(item),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _dateLabel(item.createdAt),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: List.generate(5, (index) {
                        return Icon(
                          index < item.stars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 15,
                          color: AppColors.warning,
                        );
                      }),
                    ),
                    if (item.comment.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.comment,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.90,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'App Feedback',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.edit_note_rounded), text: 'Submit'),
                  Tab(icon: Icon(Icons.forum_rounded), text: 'Community'),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildSubmitTab(),
                    _buildCommunityTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityFeedbackData {
  final double average;
  final int total;
  final Map<int, int> starsCount;
  final List<_CommunityFeedbackItem> items;

  const _CommunityFeedbackData({
    required this.average,
    required this.total,
    required this.starsCount,
    required this.items,
  });

  const _CommunityFeedbackData.empty()
      : average = 0,
        total = 0,
        starsCount = const {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
        items = const [];
}

class _CommunityFeedbackItem {
  final String userId;
  final String userName;
  final String userEmail;
  final int stars;
  final String comment;
  final DateTime? createdAt;

  const _CommunityFeedbackItem({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.stars,
    required this.comment,
    required this.createdAt,
  });
}

class _StarDistributionRow extends StatelessWidget {
  final int star;
  final int count;
  final int total;

  const _StarDistributionRow({
    required this.star,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$star',
              style: GoogleFonts.plusJakartaSans(fontSize: 10),
            ),
          ),
          const Icon(Icons.star_rounded, size: 12, color: AppColors.warning),
          const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.borderLight,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 24,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerHeader extends StatelessWidget {
  final bool isDark;
  const _DrawerHeader({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [AppColors.mustGreenDark, const Color(0xFF124D2E)]
              : [AppColors.institutionalGreen, AppColors.mustGreen],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/must-logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              Text(
                'MUST StarTrack',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Mbarara University of Science\nand Technology',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.4,
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
// Theme mode selector — 3 pill buttons: Light / System / Dark
// ─────────────────────────────────────────────────────────────────────────────

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeMode>(
      builder: (context, mode) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.adaptive(
                context,
                light: AppColors.backgroundLight,
                dark: AppColors.surfaceDark2,
              ),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _ModeButton(
                  icon: Icons.light_mode_rounded,
                  label: 'Light',
                  active: mode == ThemeMode.light,
                  onTap: () =>
                      context.read<ThemeCubit>().setMode(ThemeMode.light),
                ),
                _ModeButton(
                  icon: Icons.settings_suggest_outlined,
                  label: 'System',
                  active: mode == ThemeMode.system,
                  onTap: () =>
                      context.read<ThemeCubit>().setMode(ThemeMode.system),
                ),
                _ModeButton(
                  icon: Icons.dark_mode_rounded,
                  label: 'Dark',
                  active: mode == ThemeMode.dark,
                  onTap: () =>
                      context.read<ThemeCubit>().setMode(ThemeMode.dark),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? Colors.white : AppColors.textSecondary(context),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color:
                      active ? Colors.white : AppColors.textSecondary(context),
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
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: AppColors.textSecondary(context),
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool enabled;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final tileColor = !enabled
        ? AppColors.textSecondary(context)
        : (color ?? AppColors.textPrimary(context));
    return ListTile(
      dense: true,
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: Icon(icon, size: 20, color: tileColor),
      title: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: tileColor,
        ),
      ),
      trailing: enabled
          ? Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textSecondary(context),
            )
          : null,
      onTap: enabled ? onTap : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      ),
    );
  }
}
