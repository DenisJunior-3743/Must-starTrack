import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/activity_log_dao.dart';

class ActivityLogsScreen extends StatefulWidget {
  const ActivityLogsScreen({super.key});

  @override
  State<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends State<ActivityLogsScreen> {
  final _dao = sl<ActivityLogDao>();
  bool _loading = true;
  List<Map<String, dynamic>> _recentLogs = const [];
  List<Map<String, dynamic>> _topActions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final recent = await _dao.getRecentLogs(limit: 80);
      final top = await _dao.getTopActions(days: 7, limit: 8);
      if (!mounted) return;
      setState(() {
        _recentLogs = recent;
        _topActions = top;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _timeLabel(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Logs'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  Text(
                    'Most Frequent Actions (7 days)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _topActions
                        .map(
                          (row) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryTint10,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${row['action']} (${row['total']})',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Audit Timeline',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_recentLogs.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No activity logs yet.'),
                      ),
                    ),
                  ..._recentLogs.map((row) {
                    final metadata = row['metadata'] as Map<String, dynamic>? ??
                        const <String, dynamic>{};
                    final reason = metadata['reason']?.toString();
                    final note = metadata['note']?.toString();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          row['action']?.toString() ?? 'unknown_action',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          'user: ${row['userId'] ?? '-'}\n'
                          'entity: ${row['entityType'] ?? '-'} / ${row['entityId'] ?? '-'}\n'
                          'time: ${_timeLabel(row['createdAt']?.toString() ?? '')}'
                          '${reason == null ? '' : '\nreason: $reason'}'
                          '${(note == null || note.isEmpty) ? '' : '\nnote: $note'}',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12),
                        ),
                        isThreeLine: true,
                        leading: const Icon(
                          Icons.history_rounded,
                          color: AppColors.primary,
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
