import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/remote/sync_service.dart';

class SyncQueueDetailsScreen extends StatefulWidget {
  const SyncQueueDetailsScreen({super.key});

  @override
  State<SyncQueueDetailsScreen> createState() =>
      _SyncQueueDetailsScreenState();
}

class _SyncQueueDetailsScreenState extends State<SyncQueueDetailsScreen> {
  final _syncQueueDao = sl<SyncQueueDao>();
  final _syncService = sl<SyncService>();

  bool _loading = true;
  List<Map<String, dynamic>> _pendingJobs = [];
  List<Map<String, dynamic>> _deadLetterJobs = [];
  int _totalPending = 0;
  int _totalDeadLetters = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pending = await _syncQueueDao.getReadyJobs(limit: 50);
      final allItems = await _syncQueueDao.getPendingItems();
      final totalPending = await _syncQueueDao.getPendingCount();
      final totalDeadLetters = await _syncQueueDao.getDeadLetterCount();

      if (!mounted) return;
      setState(() {
        _pendingJobs = pending.map((e) => e.toMap()).toList();
        _deadLetterJobs = allItems.map((e) => e.toMap()).toList();
        _totalPending = totalPending;
        _totalDeadLetters = totalDeadLetters;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _retryJob(String jobId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retry Job?'),
        content: const Text('This will attempt to resync this job.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retry')),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _syncQueueDao.markSynced(jobId);
      await _syncService.processPendingSync();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job retry initiated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to retry: $e')),
      );
    }
  }

  Future<void> _deleteJob(String jobId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Job?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _syncQueueDao.deleteJob(jobId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  Future<void> _clearAllDead() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Dead Letters?'),
        content: Text('This will delete $_totalDeadLetters failed job(s).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _syncQueueDao.clearFailed();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dead letters cleared')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear: $e')),
      );
    }
  }

  Widget _jobCard({
    required Map<String, dynamic> job,
    required bool isDead,
  }) {
    final operation = job['operation'] as String? ?? 'unknown';
    final entity = job['entity'] as String? ?? 'unknown';
    final createdAt = job['created_at'] as String? ?? '';
    final retries = job['retries'] as int? ?? 0;
    final error = job['error'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          isDead
              ? Icons.error_outline_rounded
              : Icons.pending_actions_rounded,
          color: isDead ? AppColors.danger : AppColors.warning,
        ),
        title: Text(
          '$operation $entity',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          createdAt,
          style: GoogleFonts.plusJakartaSans(fontSize: 10),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Job ID',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                          Text(
                            job['id']?.toString().substring(0, 12) ?? 'N/A',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Retries',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                          Text(
                            '$retries',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Error: $error',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    if (!isDead)
                      FilledButton.tonal(
                        onPressed: () =>
                            _retryJob(job['id']?.toString() ?? ''),
                        child: const Text('Retry'),
                      ),
                    FilledButton.tonal(
                      onPressed: () =>
                          _deleteJob(job['id']?.toString() ?? ''),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Queue Monitor'),
        actions: [
          if (_totalDeadLetters > 0)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Clear dead letters',
              onPressed: _clearAllDead,
            ),
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
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primaryTint10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pending',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                              Text(
                                '$_totalPending',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dead Letters',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                              Text(
                                '$_totalDeadLetters',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_pendingJobs.isEmpty && _totalPending == 0)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('✓ No pending jobs'),
                      ),
                    ),
                  if (_pendingJobs.isNotEmpty) ...[
                    Text(
                      'Pending Jobs (${_pendingJobs.length})',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._pendingJobs
                      .map((job) => _jobCard(job: job, isDead: false)),
                  ],
                  if (_deadLetterJobs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Dead Letter Jobs (${_deadLetterJobs.length})',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._deadLetterJobs
                      .map((job) => _jobCard(job: job, isDead: true)),
                  ],
                  if (_deadLetterJobs.isEmpty && _totalDeadLetters == 0)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('✓ No dead letters'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
