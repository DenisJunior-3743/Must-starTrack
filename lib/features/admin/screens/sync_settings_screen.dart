import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/remote/sync_service.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _queueDao = sl<SyncQueueDao>();
  final _syncService = sl<SyncService>();

  bool _loading = true;
  int _pending = 0;
  int _deadLetters = 0;
  List<SyncQueueItem> _readyJobs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pending = await _queueDao.getPendingCount();
      final dead = await _queueDao.getDeadLetterCount();
      final jobs = await _queueDao.getReadyJobs(limit: 25);
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _deadLetters = dead;
        _readyJobs = jobs;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _processNow() async {
    final result = await _syncService.processPendingSync();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Processed ${result.processed}, failed ${result.failed}, remaining ${result.remaining}',
        ),
      ),
    );
    await _load();
  }

  Future<void> _clearDeadLetters() async {
    await _queueDao.clearFailed();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dead-letter items cleared')),
    );
    await _load();
  }

  void _restartListener() {
    _syncService.stopListening();
    _syncService.startListening();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync listener restarted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Status & Settings'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _metricCard(
                        label: 'Pending Queue',
                        value: '$_pending',
                        color: AppColors.primary,
                        icon: Icons.sync_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricCard(
                        label: 'Dead Letters',
                        value: '$_deadLetters',
                        color: AppColors.danger,
                        icon: Icons.error_outline_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _processNow,
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('Process Now'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _deadLetters == 0 ? null : _clearDeadLetters,
                      icon: const Icon(Icons.delete_sweep_rounded),
                      label: const Text('Clear Dead Letters'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _restartListener,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Restart Listener'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Ready Jobs',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                if (_readyJobs.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('No sync jobs are currently ready.'),
                    ),
                  ),
                ..._readyJobs.map(
                  (job) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.work_history_rounded, color: AppColors.primary),
                      title: Text(
                        '${job.operation.toUpperCase()} ${job.entity}',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'entityId: ${job.entityId}\nretry: ${job.retryCount}/${job.maxRetries}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _metricCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
