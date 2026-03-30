import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/activity_log_dao.dart';

class UserActivityAnalyticsScreen extends StatefulWidget {
  const UserActivityAnalyticsScreen({super.key});

  @override
  State<UserActivityAnalyticsScreen> createState() => _UserActivityAnalyticsScreenState();
}

class _UserActivityAnalyticsScreenState extends State<UserActivityAnalyticsScreen> {
  final _activityDao = sl<ActivityLogDao>();
  bool _loading = true;
  int _active7 = 0;
  int _active30 = 0;
  List<Map<String, dynamic>> _daily = const [];
  List<Map<String, dynamic>> _topActions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final active7 = await _activityDao.getActiveUserCountSince(days: 7);
      final active30 = await _activityDao.getActiveUserCountSince(days: 30);
      final daily = await _activityDao.getDailyActionSeries(days: 14);
      final top = await _activityDao.getTopActions(days: 14, limit: 10);
      if (!mounted) return;
      setState(() {
        _active7 = active7;
        _active30 = active30;
        _daily = daily;
        _topActions = top;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final peakActions = _daily.isEmpty
        ? 1
        : _daily
            .map((d) => d['totalActions'] as int? ?? 0)
            .fold<int>(1, (a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Activity Analytics'),
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
                    Expanded(child: _metricCard('Active users (7d)', '$_active7', Icons.people_alt_rounded)),
                    const SizedBox(width: 8),
                    Expanded(child: _metricCard('Active users (30d)', '$_active30', Icons.timeline_rounded)),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Daily Activity (Last 14 Days)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                if (_daily.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('No activity data available yet.'),
                    ),
                  ),
                ..._daily.map((row) {
                  final total = row['totalActions'] as int? ?? 0;
                  final active = row['activeUsers'] as int? ?? 0;
                  final day = row['day']?.toString() ?? '-';
                  final ratio = peakActions == 0 ? 0.0 : total / peakActions;
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
                                  day,
                                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                '$total actions · $active users',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: ratio.clamp(0.0, 1.0),
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(999),
                            color: AppColors.primary,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 10),
                Text(
                  'Top Actions (14 days)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                ..._topActions.map(
                  (row) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.bolt_rounded, color: AppColors.primary),
                    title: Text(
                      row['action']?.toString() ?? '-',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                    ),
                    trailing: Text(
                      '${row['total'] ?? 0}',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
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
          const SizedBox(width: 8),
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
