import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/dao/course_dao.dart';
import '../../../data/local/dao/faculty_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/schema/database_schema.dart';
import '../../../data/remote/sync_service.dart';

class SyncConsistencyScreen extends StatefulWidget {
  const SyncConsistencyScreen({super.key});

  @override
  State<SyncConsistencyScreen> createState() => _SyncConsistencyScreenState();
}

class _SyncConsistencyScreenState extends State<SyncConsistencyScreen> {
  final _syncService = sl<SyncService>();
  final _syncQueueDao = sl<SyncQueueDao>();
  final _facultyDao = sl<FacultyDao>();
  final _courseDao = sl<CourseDao>();

  bool _loading = true;
  bool _syncingNow = false;
  bool _enforcingNow = false;
  bool _strictMode = true;
  bool _autoEnforceAttempted = false;

  int _pending = 0;
  int _deadLetters = 0;

  Map<String, int> _localCounts = {};
  Map<String, int> _remoteCounts = {};
  Map<String, String> _remoteErrors = {};
  List<String> _analysisNotes = const [];
  int _criticalIssues = 0;
  int _warningIssues = 0;

  static const List<Map<String, String>> _pairings = [
    {'label': 'Users', 'local': 'users', 'remote': 'users'},
    {'label': 'Posts', 'local': 'posts', 'remote': 'posts'},
    {'label': 'Comments', 'local': 'comments', 'remote': 'comments'},
    {'label': 'Follows', 'local': 'follows', 'remote': 'follows'},
    {'label': 'Notifications', 'local': 'notifications', 'remote': 'notifications'},
    {'label': 'Collab Requests', 'local': 'collab_requests', 'remote': 'collab_requests'},
    {'label': 'Post Joins', 'local': 'post_joins', 'remote': 'post_joins'},
    {'label': 'Moderation Queue', 'local': 'moderation_queue', 'remote': 'moderation_queue'},
    {'label': 'Faculties', 'local': 'faculties', 'remote': 'faculties'},
    {'label': 'Courses', 'local': 'courses', 'remote': 'courses'},
    {'label': 'Groups', 'local': 'groups', 'remote': 'groups'},
    {'label': 'Group Members', 'local': 'group_members', 'remote': 'group_members'},
    {'label': 'Recommendation Logs', 'local': 'recommendation_logs', 'remote': 'recommendation_logs'},
    {'label': 'App Feedback', 'local': 'activity_logs', 'remote': 'app_feedback'},
  ];

  static const Set<String> _cacheScopedEntities = {
    'users',
    'posts',
    'comments',
    'follows',
    'notifications',
    'collab_requests',
    'post_joins',
    'groups',
    'group_members',
  };

  static const Set<String> _bestEffortEntities = {
    'recommendation_logs',
    'app_feedback',
  };

  bool _isPermissionDeniedError(String? error) {
    final value = (error ?? '').toLowerCase();
    return value.contains('permission-denied') ||
        value.contains('permission_denied') ||
        value.contains('missing or insufficient permissions');
  }

  String _compactRemoteError(String raw) {
    if (_isPermissionDeniedError(raw)) {
      return 'permission-denied';
    }
    final trimmed = raw.trim();
    if (trimmed.length <= 120) return trimmed;
    return '${trimmed.substring(0, 117)}...';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final localCounts = <String, int>{};
      for (final pair in _pairings) {
        final table = pair['local']!;
        final rows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM $table');
        final value = rows.isNotEmpty ? rows.first['cnt'] : 0;
        localCounts[table] = value is int ? value : int.tryParse('$value') ?? 0;
      }

      final remoteCounts = <String, int>{};
      final remoteErrors = <String, String>{};
      for (final pair in _pairings) {
        final collection = pair['remote']!;
        try {
          final agg = await FirebaseFirestore.instance
              .collection(collection)
              .count()
              .get();
          remoteCounts[collection] = agg.count ?? 0;
        } on FirebaseException catch (e) {
          // Fallback for environments where aggregate count may fail.
          try {
            remoteCounts[collection] = await _countRemoteByPaging(collection);
          } catch (_) {
            final message = (e.message ?? '').trim();
            final detail = message.isEmpty ? e.code : '${e.code}: $message';
            remoteErrors[collection] = _compactRemoteError(detail);
          }
        } catch (e) {
          // Fallback for non-Firebase exceptions too.
          try {
            remoteCounts[collection] = await _countRemoteByPaging(collection);
          } catch (_) {
            remoteErrors[collection] =
                _compactRemoteError('${e.runtimeType}: $e');
          }
        }
      }

      final pending = await _syncQueueDao.getPendingCount();
      final deadLetters = await _syncQueueDao.getDeadLetterCount();
      final analysis = _analyzeConsistency(
        localCounts: localCounts,
        remoteCounts: remoteCounts,
        remoteErrors: remoteErrors,
        pending: pending,
        deadLetters: deadLetters,
      );

      _logConsistencySnapshot(
        localCounts: localCounts,
        remoteCounts: remoteCounts,
        remoteErrors: remoteErrors,
        pending: pending,
        deadLetters: deadLetters,
        analysisNotes: analysis.notes,
        critical: analysis.critical,
        warnings: analysis.warnings,
      );

      if (!mounted) return;
      setState(() {
        _localCounts = localCounts;
        _remoteCounts = remoteCounts;
        _remoteErrors = remoteErrors;
        _pending = pending;
        _deadLetters = deadLetters;
        _analysisNotes = analysis.notes;
        _criticalIssues = analysis.critical;
        _warningIssues = analysis.warnings;
      });

      final facultiesLocal = localCounts['faculties'] ?? 0;
      final facultiesRemote = remoteCounts['faculties'] ?? 0;
      final coursesLocal = localCounts['courses'] ?? 0;
      final coursesRemote = remoteCounts['courses'] ?? 0;
      final hasMasterDrift = facultiesLocal > facultiesRemote || coursesLocal > coursesRemote;
      if (!_autoEnforceAttempted && hasMasterDrift && pending == 0 && deadLetters == 0) {
        _autoEnforceAttempted = true;
        await _enforceConsistency(silent: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runSyncNow() async {
    if (_syncingNow) return;
    setState(() => _syncingNow = true);
    try {
      await _syncService.processPendingSync();
      await _syncService.syncRemoteToLocal();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync cycle completed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncingNow = false);
    }
  }

  Future<void> _enforceConsistency({bool silent = false}) async {
    if (_enforcingNow) return;
    setState(() => _enforcingNow = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final existingRows = await db.query(
        DatabaseSchema.tableSyncQueue,
        columns: ['entity', 'entity_id'],
        where: 'retry_count < max_retries AND entity IN (?, ?)',
        whereArgs: ['faculties', 'courses'],
      );
      final existingKeys = existingRows
          .map((row) => '${row['entity']}::${row['entity_id']}')
          .toSet();

      final faculties = await _facultyDao.getAllFaculties(activeOnly: true);
      final courses = await _courseDao.getAllCourses(activeOnly: true);

      var enqueued = 0;
      for (final faculty in faculties) {
        final key = 'faculties::${faculty.id}';
        if (existingKeys.contains(key)) continue;
        await _syncQueueDao.enqueue(
          operation: 'update',
          entity: 'faculties',
          entityId: faculty.id,
          payload: {'id': faculty.id},
        );
        enqueued++;
      }

      for (final course in courses) {
        final key = 'courses::${course.id}';
        if (existingKeys.contains(key)) continue;
        await _syncQueueDao.enqueue(
          operation: 'update',
          entity: 'courses',
          entityId: course.id,
          payload: {'id': course.id},
        );
        enqueued++;
      }

      await _syncService.processPendingSync();
      await _syncService.syncRemoteToLocal();
      await _load();

      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enqueued == 0
                ? 'Consistency check complete: no new master-data jobs needed.'
                : 'Enforced consistency: queued $enqueued master-data sync job(s).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to enforce consistency: $e')),
      );
    } finally {
      if (mounted) setState(() => _enforcingNow = false);
    }
  }

  Color _deltaColor(int local, int remote) {
    if (local == remote) return AppColors.success;
    if (local > remote) return AppColors.warning;
    return AppColors.primary;
  }

  bool _isHydrationDriven(String key) {
    return key == 'notifications' ||
        key == 'comments' ||
        key == 'post_joins' ||
        key == 'collab_requests';
  }

  Future<int> _countRemoteByPaging(String collection) async {
    var total = 0;
    DocumentSnapshot<Map<String, dynamic>>? lastDoc;

    while (true) {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection(collection)
          .orderBy(FieldPath.documentId)
          .limit(400);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snap = await query.get();
      total += snap.docs.length;
      if (snap.docs.isEmpty || snap.docs.length < 400) {
        break;
      }
      lastDoc = snap.docs.last;
    }

    return total;
  }

  _ConsistencyAnalysis _analyzeConsistency({
    required Map<String, int> localCounts,
    required Map<String, int> remoteCounts,
    required Map<String, String> remoteErrors,
    required int pending,
    required int deadLetters,
  }) {
    final notes = <String>[];
    var critical = 0;
    var warnings = 0;

    if (deadLetters > 0) {
      critical++;
      notes.add('Dead letters exist ($deadLetters). Some queued writes are failing and need inspection.');
    }
    if (pending > 0) {
      warnings++;
      notes.add('Queue has $pending pending job(s). Local can be ahead until next successful push cycle.');
    }

    for (final pair in _pairings) {
      final localKey = pair['local']!;
      final remoteKey = pair['remote']!;
      final label = pair['label']!;
      final local = localCounts[localKey] ?? 0;
      final remote = remoteCounts[remoteKey] ?? 0;
      final error = remoteErrors[remoteKey];

      if (error != null) {
        if (_isPermissionDeniedError(error)) {
          warnings++;
          notes.add(
            '$label remote count is access-restricted by Firestore rules for this account (permission-denied).',
          );
        } else {
          critical++;
          notes.add('$label remote query failed: $error');
        }
        continue;
      }

      if (_cacheScopedEntities.contains(localKey)) {
        if (local != remote) {
          notes.add(
            '$label differs (local=$local, remote=$remote). This is cache-scoped and not required to match global remote totals.',
          );
        }
        continue;
      }

      if (_bestEffortEntities.contains(localKey)) {
        if (local != remote) {
          warnings++;
          notes.add(
            '$label differs (local=$local, remote=$remote). This path is best-effort and can lag without queue backlog.',
          );
        }
        continue;
      }

      if (local == remote) continue;

      final diff = (local - remote).abs();
      if (local > remote) {
        if (pending > 0) {
          warnings++;
          notes.add('$label local is ahead by $diff (expected while pending queue drains).');
        } else {
          warnings++;
          notes.add('$label local is ahead by $diff with no queue backlog; validate write path for this entity.');
        }
      } else {
        if (_isHydrationDriven(localKey)) {
          warnings++;
          notes.add('$label remote is ahead by $diff (usually resolves after remote-to-local hydration).');
        } else {
          warnings++;
          notes.add('$label remote is ahead by $diff; validate local hydration/upsert path.');
        }
      }
    }

    if (notes.isEmpty) {
      notes.add('All monitored entities are currently consistent.');
    }

    return _ConsistencyAnalysis(
      notes: notes,
      critical: critical,
      warnings: warnings,
    );
  }

  void _logConsistencySnapshot({
    required Map<String, int> localCounts,
    required Map<String, int> remoteCounts,
    required Map<String, String> remoteErrors,
    required int pending,
    required int deadLetters,
    required List<String> analysisNotes,
    required int critical,
    required int warnings,
  }) {
    debugPrint(
      '[SyncConsistency] snapshot pending=$pending deadLetters=$deadLetters '
      'critical=$critical warnings=$warnings',
    );

    for (final pair in _pairings) {
      final label = pair['label']!;
      final localKey = pair['local']!;
      final remoteKey = pair['remote']!;
      final local = localCounts[localKey] ?? 0;
      final remote = remoteCounts[remoteKey] ?? 0;
      final error = remoteErrors[remoteKey];

      if (error != null) {
        debugPrint('[SyncConsistency] $label local=$local remoteError=$error');
      } else {
        final delta = local - remote;
        debugPrint('[SyncConsistency] $label local=$local remote=$remote delta=$delta');
      }
    }

    for (final note in analysisNotes) {
      debugPrint('[SyncConsistency][Insight] $note');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Consistency'),
        actions: [
          IconButton(
            icon: Icon(
              _strictMode ? Icons.filter_alt_rounded : Icons.filter_alt_off_rounded,
            ),
            tooltip: _strictMode ? 'Strict mode: actionable only' : 'Show all signals',
            onPressed: () {
              setState(() => _strictMode = !_strictMode);
            },
          ),
          IconButton(
            icon: const Icon(Icons.verified_rounded),
            tooltip: 'Enforce master-data consistency',
            onPressed: _loading || _enforcingNow ? null : _enforceConsistency,
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Run sync now',
            onPressed: _loading || _syncingNow ? null : _runSyncNow,
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
                    if (_strictMode)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTint10,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Strict mode ON: showing actionable issues only',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: _smallMetric(
                            label: 'Queue Pending',
                            value: '$_pending',
                            color: _pending > 0 ? AppColors.warning : AppColors.success,
                            icon: Icons.schedule_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _smallMetric(
                            label: 'Dead Letters',
                            value: '$_deadLetters',
                            color: _deadLetters > 0 ? AppColors.danger : AppColors.success,
                            icon: Icons.error_outline_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.insights_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Needs Attention',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                if (_criticalIssues > 0)
                                  _statusChip(
                                    label: 'Critical $_criticalIssues',
                                    color: AppColors.danger,
                                  ),
                                if (_warningIssues > 0) ...[
                                  const SizedBox(width: 6),
                                  _statusChip(
                                    label: 'Warnings $_warningIssues',
                                    color: AppColors.warning,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._analysisNotes
                                .where((n) => !_strictMode ||
                                    (!n.contains('cache-scoped') &&
                                        !n.contains('best-effort')))
                                .take(8)
                                .map(
                              (note) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '- $note',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: AppColors.textSecondaryLight,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Local vs Firestore Counts',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._pairings.where((pair) {
                      if (!_strictMode) return true;
                      final key = pair['local']!;
                      return !_cacheScopedEntities.contains(key) &&
                          !_bestEffortEntities.contains(key);
                    }).map((pair) {
                      final label = pair['label']!;
                      final localKey = pair['local']!;
                      final remoteKey = pair['remote']!;
                      final local = _localCounts[localKey] ?? 0;
                      final remote = _remoteCounts[remoteKey];
                      final err = _remoteErrors[remoteKey];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Local: $local',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color: AppColors.textSecondaryLight,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      err != null ? 'Remote: $err' : 'Remote: ${remote ?? 0}',
                                      textAlign: TextAlign.end,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color: err != null
                                            ? AppColors.warning
                                            : AppColors.textSecondaryLight,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (err == null)
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _deltaColor(local, remote ?? 0).withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        local == (remote ?? 0)
                                            ? 'Consistent'
                                            : local > (remote ?? 0)
                                                ? 'Local ahead by ${local - (remote ?? 0)}'
                                                : 'Remote ahead by ${(remote ?? 0) - local}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _deltaColor(local, remote ?? 0),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _loading || _syncingNow ? null : _runSyncNow,
                      icon: _syncingNow
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: Text(_syncingNow ? 'Syncing...' : 'Run Sync + Refresh Verification'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _loading || _enforcingNow ? null : _enforceConsistency,
                      icon: _enforcingNow
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_rounded),
                      label: Text(
                        _enforcingNow
                            ? 'Enforcing...'
                            : 'Enforce Master-Data Consistency (Faculties/Courses)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _smallMetric({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              color: AppColors.textSecondaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ConsistencyAnalysis {
  final List<String> notes;
  final int critical;
  final int warnings;

  const _ConsistencyAnalysis({
    required this.notes,
    required this.critical,
    required this.warnings,
  });
}
