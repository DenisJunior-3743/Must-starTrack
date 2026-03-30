import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/sync_service.dart';

class SuspicionScoreScreen extends StatefulWidget {
  final String? postId;

  const SuspicionScoreScreen({super.key, this.postId});

  @override
  State<SuspicionScoreScreen> createState() => _SuspicionScoreScreenState();
}

class _SuspicionScoreScreenState extends State<SuspicionScoreScreen> {
  final _activityDao = sl<ActivityLogDao>();
  final _postDao = sl<PostDao>();
  final _userDao = sl<UserDao>();
  final _syncQueueDao = sl<SyncQueueDao>();
  final _syncService = sl<SyncService>();

  bool _loading = true;
  Map<String, dynamic>? _flag;
  PostModel? _post;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _activityDao.getReportedPostSummaries(limit: 120);
      Map<String, dynamic>? selected;
      if (widget.postId != null && widget.postId!.trim().isNotEmpty) {
        for (final row in rows) {
          if (row['postId'] == widget.postId) {
            selected = row;
            break;
          }
        }
      }
      selected ??= rows.isNotEmpty ? rows.first : null;
      final post = selected == null
          ? null
          : await _postDao.getPostById(selected['postId']?.toString() ?? '');
      if (!mounted) return;
      setState(() {
        _flag = selected;
        _post = post;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int _overallScore(Map<String, dynamic> row) {
    final reports = row['reportsCount'] as int? ?? 0;
    return (reports * 20).clamp(5, 95);
  }

  Map<String, int> _categoryScores(Map<String, dynamic> row) {
    final reason = (row['topReason']?.toString().toLowerCase() ?? '');
    final reports = row['reportsCount'] as int? ?? 0;
    final base = (reports * 14).clamp(5, 90);

    final map = <String, int>{
      'Inappropriate Media': reason.contains('inappropriate') ? base : (base ~/ 3),
      'External Link Safety': reason.contains('link') || reason.contains('fake') ? base : (base ~/ 3),
      'Hate Speech': reason.contains('hate') ? base : (base ~/ 4),
      'Spam / Bot Signals': reason.contains('spam') ? base : (base ~/ 3),
    };
    return map;
  }

  Future<void> _approve() async {
    final post = _post;
    if (post == null) return;
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
    await _load();
  }

  Future<void> _deletePost() async {
    final post = _post;
    if (post == null) return;
    await _postDao.archivePost(post.id);
    final updated = await _postDao.getPostById(post.id);
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
    await _load();
  }

  Future<void> _banAuthor() async {
    final post = _post;
    if (post == null || post.authorId.isEmpty) return;
    await _userDao.banUser(post.authorId);
    await _activityDao.logAction(
      userId: post.authorId,
      action: 'admin_banned_user',
      entityType: 'users',
      entityId: post.authorId,
      metadata: {
        'source': 'suspicion_score_screen',
        'post_id': post.id,
      },
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final row = _flag;
    if (row == null || _post == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Suspicion Detail')),
        body: const Center(child: Text('No flagged post available.')),
      );
    }

    final score = _overallScore(row);
    final categories = _categoryScores(row);
    final risk = row['risk']?.toString() ?? 'low';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suspicion Score Detail'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _post!.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Reported ${row['reportsCount']} times · risk: $risk',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 70,
                        height: 70,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: score / 100,
                              strokeWidth: 8,
                              color: score >= 70
                                  ? AppColors.danger
                                  : score >= 40
                                      ? AppColors.warning
                                      : AppColors.mustGreen,
                            ),
                            Center(
                              child: Text(
                                '$score',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Automated suspicion score from report density and reason profile. Review category bars below before taking action.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...categories.entries.map((entry) {
            final value = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '$value%',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: value / 100,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(999),
                      color: value >= 70
                          ? AppColors.danger
                          : value >= 40
                              ? AppColors.warning
                              : AppColors.mustGreen,
                      backgroundColor: AppColors.borderLight,
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _approve,
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.mustGreen),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _deletePost,
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Delete'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _banAuthor,
                  icon: const Icon(Icons.gavel_rounded),
                  label: const Text('Ban'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
