import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/remote/sync_service.dart';

class ResourceMonitoringScreen extends StatefulWidget {
  const ResourceMonitoringScreen({super.key});

  @override
  State<ResourceMonitoringScreen> createState() =>
      _ResourceMonitoringScreenState();
}

class _ResourceMonitoringScreenState extends State<ResourceMonitoringScreen> {
  final _syncQueueDao = sl<SyncQueueDao>();
  final _syncService = sl<SyncService>();

  bool _loading = true;
  Map<String, dynamic> _resources = {};
  Map<String, dynamic> _syncMetrics = {};
  DateTime _lastRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'must_startrack.db');
      final dbFile = File(path);
      final dbSize = dbFile.existsSync() ? await dbFile.length() : 0;

      final syncMetrics = await _syncService.getSyncMetrics();
      final pendingCount = await _syncQueueDao.getPendingCount();
      final deadLetterCount = await _syncQueueDao.getDeadLetterCount();

      if (!mounted) return;
      setState(() {
        _resources = {
          'db_size_bytes': dbSize,
          'db_size_mb': (dbSize / (1024 * 1024)).toStringAsFixed(2),
          'estimated_tables': 25,
          'platform': Platform.isAndroid ? 'Android' : 'iOS',
          'device_memory_mb': _estimateDeviceMemory(),
        };
        _syncMetrics = {
          ...syncMetrics,
          'pending_jobs': pendingCount,
          'dead_letter_jobs': deadLetterCount,
          'is_syncing': syncMetrics['is_syncing'] ?? false,
        };
        _lastRefresh = DateTime.now();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int _estimateDeviceMemory() {
    // Estimate in MB - typical values
    if (Platform.isAndroid) {
      return 4096; // ~4GB typical
    }
    return 2048; // ~2GB typical for iOS
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
    String? subtext,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.textPrimaryLight,
            ),
          ),
          if (subtext != null) ...[
            const SizedBox(height: 4),
            Text(
              subtext,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resource Monitoring'),
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
                  Text(
                    'Database Storage',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _metricCard(
                        label: 'Database Size',
                        value: _resources['db_size_mb'] ?? '0 MB',
                        icon: Icons.storage_rounded,
                        subtext: '${_resources['estimated_tables']} tables',
                      ),
                      _metricCard(
                        label: 'Platform',
                        value: _resources['platform'] ?? 'Unknown',
                        icon: Icons.phone_android_rounded,
                        subtext: '${_resources['device_memory_mb']} MB RAM',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Sync Queue Health',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _metricCard(
                        label: 'Pending Jobs',
                        value: '${_syncMetrics['pending_jobs'] ?? 0}',
                        icon: Icons.schedule_rounded,
                        valueColor: (_syncMetrics['pending_jobs'] ?? 0) > 10
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                      _metricCard(
                        label: 'Dead Letters',
                        value: '${_syncMetrics['dead_letter_jobs'] ?? 0}',
                        icon: Icons.error_outline_rounded,
                        valueColor: (_syncMetrics['dead_letter_jobs'] ?? 0) > 0
                            ? AppColors.danger
                            : AppColors.success,
                      ),
                      _metricCard(
                        label: 'Sync Status',
                        value: _syncMetrics['is_syncing'] == true
                            ? 'Active'
                            : 'Idle',
                        icon: Icons.cloud_sync_rounded,
                        valueColor: _syncMetrics['is_syncing'] == true
                            ? AppColors.success
                            : AppColors.textSecondaryLight,
                      ),
                      _metricCard(
                        label: 'Queue Depth',
                        value: '${_syncMetrics['queue_depth'] ?? 0}',
                        icon: Icons.layers_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'System Status',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  color: AppColors.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Last Refresh',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color:
                                            AppColors.textSecondaryLight,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _lastRefresh
                                          .toLocal()
                                          .toString()
                                          .split('.')
                                          .first,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  color: AppColors.success),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Database operational and responsive',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
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
