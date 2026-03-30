import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/user_dao.dart';

class UserBehaviorAnalyticsScreen extends StatefulWidget {
  const UserBehaviorAnalyticsScreen({super.key});

  @override
  State<UserBehaviorAnalyticsScreen> createState() =>
      _UserBehaviorAnalyticsScreenState();
}

class _UserBehaviorAnalyticsScreenState
    extends State<UserBehaviorAnalyticsScreen> {
  final _activityDao = sl<ActivityLogDao>();
  final _userDao = sl<UserDao>();

  bool _loading = true;
  List<Map<String, dynamic>> _cohortData = [];
  List<Map<String, dynamic>> _dailyActivity = [];
  List<Map<String, dynamic>> _topActions = [];
  int _dau = 0;
  int _mau = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dau = await _activityDao.getActiveUserCountSince(days: 1);
      final mau = await _activityDao.getActiveUserCountSince(days: 30);
      final total = await _userDao.getUserCount();
      final daily = await _activityDao.getDailyActionSeries(days: 30);
      final top = await _activityDao.getTopActions(days: 30, limit: 15);

      // Calculate retention cohorts
      final cohorts = <Map<String, dynamic>>[];
      for (int days = 1; days <= 30; days += 7) {
        final active = await _activityDao.getActiveUserCountSince(days: days);
        final ratio = total > 0 ? ((active / total) * 100).toStringAsFixed(1) : '0.0';
        cohorts.add({
          'period': 'Last $days days',
          'users': active,
          'percentage': ratio,
        });
      }

      if (!mounted) return;
      setState(() {
        _dau = dau;
        _mau = mau;
        _total = total;
        _dailyActivity = daily;
        _topActions = top;
        _cohortData = cohorts;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _stickiness() {
    if (_mau == 0) return '0%';
    return '${((_dau / _mau) * 100).toStringAsFixed(1)}%';
  }

  int _peakActivity() {
    if (_dailyActivity.isEmpty) return 0;
    return _dailyActivity
        .map((d) => d['totalActions'] as int? ?? 0)
        .reduce((max, val) => max > val ? max : val);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Behavior Analytics'),
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
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    20 + MediaQuery.of(context).padding.bottom,
                  ),
                children: [
                  // Key metrics
                  Row(
                    children: [
                      Expanded(
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
                              Text(
                                'Total Users',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                              Text(
                                '$_total',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
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
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderLight),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DAU',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                              Text(
                                '$_dau',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.success,
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
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderLight),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stickiness',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                              Text(
                                _stickiness(),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'User Retention (Cohorts)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._cohortData.map((cohort) {
                    final percentage = double.tryParse(
                            cohort['percentage']?.toString() ?? '0') ??
                        0;
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
                                Text(
                                  cohort['period']?.toString() ?? '',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${cohort['users']} (${cohort['percentage']}%)',
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
                                value: percentage / 100,
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
                  Text(
                    'Most Frequent Actions (30 Days)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _topActions
                        .take(10)
                        .map((action) {
                          final actionType =
                              action['action']?.toString() ?? 'unknown';
                          final count = action['total'] ?? 0;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryTint10,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$actionType ($count)',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          );
                        })
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Daily Activity (Last 30 Days)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: _dailyActivity
                            .take(14)
                            .map((day) {
                              final total = day['totalActions'] as int? ?? 0;
                              final active = day['activeUsers'] as int? ?? 0;
                              final peak = _peakActivity();
                              final percentage =
                                  peak > 0 ? total / peak : 0.0;

                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment
                                              .spaceBetween,
                                      children: [
                                        Text(
                                          day['date']?.toString() ??
                                              '',
                                          style: GoogleFonts
                                              .plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight:
                                                FontWeight.w600,
                                          ),
                                        ),
                                        Wrap(
                                          spacing: 8,
                                          children: [
                                            Text(
                                              'Actions: $total',
                                              style: GoogleFonts
                                                  .plusJakartaSans(
                                                fontSize: 10,
                                                color: AppColors
                                                    .textSecondaryLight,
                                              ),
                                            ),
                                            Text(
                                              'Users: $active',
                                              style: GoogleFonts
                                                  .plusJakartaSans(
                                                fontSize: 10,
                                                color: AppColors
                                                    .textSecondaryLight,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: percentage,
                                        minHeight: 4,
                                        backgroundColor:
                                            AppColors.surfaceLight,
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                                AppColors.primary),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            })
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),
              ),
            ),
    );
  }
}
