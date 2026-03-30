import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/recommendation_log_dao.dart';
import '../../../data/local/dao/user_dao.dart';

class SystemReportsScreen extends StatefulWidget {
  const SystemReportsScreen({super.key});

  @override
  State<SystemReportsScreen> createState() => _SystemReportsScreenState();
}

class _SystemReportsScreenState extends State<SystemReportsScreen> {
  final _postDao = sl<PostDao>();
  final _userDao = sl<UserDao>();
  final _activityDao = sl<ActivityLogDao>();
  final _recDao = sl<RecommendationLogDao>();

  bool _loading = true;
  Map<String, int> _postStats = const {};
  int _totalUsers = 0;
  int _newReports7d = 0;
  int _activeUsers7d = 0;
  int _recommendationLogs = 0;
  List<AlgorithmStats> _algorithms = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final postStats = await _postDao.getPostStats();
      final totalUsers = await _userDao.getUserCount();
      final reports7 = await _activityDao.getActionCountForDays(
        action: 'report_post',
        days: 7,
      );
      final active7 = await _activityDao.getActiveUserCountSince(days: 7);
      final recTotal = await _recDao.getTotalCount();
      final algo = await _recDao.getAlgorithmSummary();

      if (!mounted) return;
      setState(() {
        _postStats = postStats;
        _totalUsers = totalUsers;
        _newReports7d = reports7;
        _activeUsers7d = active7;
        _recommendationLogs = recTotal;
        _algorithms = algo;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _copySummary() async {
    final lines = <String>[
      'MUST StarTrack System Report',
      'Total users: $_totalUsers',
      'Total posts: ${_postStats['total'] ?? 0}',
      'Projects: ${_postStats['projects'] ?? 0}',
      'Opportunities: ${_postStats['opportunities'] ?? 0}',
      'Pending moderation: ${_postStats['pendingModeration'] ?? 0}',
      'Archived posts: ${_postStats['archived'] ?? 0}',
      'Reports (last 7 days): $_newReports7d',
      'Active users (last 7 days): $_activeUsers7d',
      'Recommendation logs: $_recommendationLogs',
    ];
    for (final stat in _algorithms) {
      lines.add(
        'Algorithm ${stat.algorithm}: total=${stat.total}, interaction=${stat.interactionRateLabel}',
      );
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied to clipboard')),
    );
  }

  Widget _metricCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Copy summary',
            onPressed: _loading ? null : _copySummary,
            icon: const Icon(Icons.copy_all_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                _metricCard('Total Users', '$_totalUsers', Icons.group_rounded),
                const SizedBox(height: 8),
                _metricCard('Total Posts', '${_postStats['total'] ?? 0}', Icons.article_rounded),
                const SizedBox(height: 8),
                _metricCard('Pending Moderation', '${_postStats['pendingModeration'] ?? 0}', Icons.pending_actions_rounded),
                const SizedBox(height: 8),
                _metricCard('Reports (7d)', '$_newReports7d', Icons.flag_rounded),
                const SizedBox(height: 8),
                _metricCard('Active Users (7d)', '$_activeUsers7d', Icons.insights_rounded),
                const SizedBox(height: 8),
                _metricCard('Recommendation Logs', '$_recommendationLogs', Icons.auto_awesome_rounded),
                const SizedBox(height: 14),
                Text(
                  'Recommendation Algorithms',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                if (_algorithms.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('No recommendation logs available yet.'),
                    ),
                  ),
                ..._algorithms.map(
                  (stat) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.tune_rounded, color: AppColors.primary),
                      title: Text(
                        stat.algorithm,
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Total: ${stat.total} · Interaction: ${stat.interactionRateLabel}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
