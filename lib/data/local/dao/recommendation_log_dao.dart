// lib/data/local/dao/recommendation_log_dao.dart
//
// MUST StarTrack — Recommendation Log DAO
//
// Writes every recommendation decision to SQLite and fires a background
// push to Firestore so admins can monitor algorithm performance across
// all distributed APK installs.
//
// Design decisions:
//   • insertBatch() is the primary write path — accepts a flat list so
//     the caller (cubit) doesn't need to know about SQL.
//   • Queue + push dual-path: each row is enqueued for reliable sync, and
//     also pushed fire-and-forget for low-latency admin visibility.
//   • getAlgorithmSummary() powers the admin Recommendations tab with
//     per-algorithm totals and interaction rates.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database_helper.dart';
import 'sync_queue_dao.dart';
import '../schema/database_schema.dart';
import '../../remote/firestore_service.dart';

// ── Entry model (lightweight — not full Equatable model) ─────────────────────

class RecommendationLogEntry {
  final String userId; // viewer / ranked-for user
  final String itemId; // post id or applicant user id
  final String itemType; // 'post' | 'user'
  final String algorithm; // 'local' | 'hybrid' | 'applicant' | 'collaborator'
  final double score;
  final List<String> reasons;

  const RecommendationLogEntry({
    required this.userId,
    required this.itemId,
    required this.itemType,
    required this.algorithm,
    required this.score,
    this.reasons = const [],
  });
}

// ── Per-algorithm aggregate stats ─────────────────────────────────────────────

class AlgorithmStats {
  final String algorithm;
  final int total;
  final int interacted;

  const AlgorithmStats({
    required this.algorithm,
    required this.total,
    required this.interacted,
  });

  double get interactionRate => total == 0 ? 0.0 : interacted / total;
  String get interactionRateLabel =>
      '${(interactionRate * 100).toStringAsFixed(1)}%';
}

class UserLogVolume {
  final String userId;
  final int total;

  const UserLogVolume({
    required this.userId,
    required this.total,
  });
}

// ── DAO ───────────────────────────────────────────────────────────────────────

class RecommendationLogDao {
  final DatabaseHelper _db;
  final FirestoreService? _firestore;
  final SyncQueueDao? _syncQueue;
  final _uuid = const Uuid();

  RecommendationLogDao({
    DatabaseHelper? db,
    FirestoreService? firestoreService,
    SyncQueueDao? syncQueueDao,
  })  : _db = db ?? DatabaseHelper.instance,
        _firestore = firestoreService,
        _syncQueue = syncQueueDao;

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Records a batch of recommendation decisions.
  /// Writes to SQLite synchronously, then pushes to Firestore in background.
  Future<void> insertBatch(List<RecommendationLogEntry> entries) async {
    if (entries.isEmpty) return;
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    final rows = <Map<String, dynamic>>[];

    for (final e in entries) {
      final row = <String, dynamic>{
        'id': _uuid.v4(),
        'user_id': e.userId,
        'item_id': e.itemId,
        'item_type': e.itemType,
        'algorithm': e.algorithm,
        'score': e.score,
        'reasons': jsonEncode(e.reasons),
        'was_interacted': 0,
        'logged_at': now,
        'sync_status': 0,
      };
      batch.insert(
        DatabaseSchema.tableRecommendationLogs,
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      rows.add(row);
    }

    await batch.commit(noResult: true);

    // Reliable path: enqueue each log row so SyncService can push even after restarts.
    if (_syncQueue != null) {
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await _syncQueue.enqueue(
          operation: 'create',
          entity: 'recommendation_logs',
          entityId: id,
          payload: row,
        );
      }
    }

    // Fire-and-forget Firestore push — ignore failures (log is best-effort remote)
    _firestore?.pushRecommendationLogs(rows).catchError((e) {
      debugPrint('[RecLogDao] Firestore push failed (offline?): $e');
    });
  }

  /// Marks an item as interacted (user clicked / liked / applied).
  /// Called from activity log handlers when the user acts on a recommended item.
  Future<void> markInteracted({
    required String userId,
    required String itemId,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableRecommendationLogs,
      columns: ['id', 'user_id', 'item_id', 'item_type', 'algorithm', 'score'],
      where: 'user_id = ? AND item_id = ? AND was_interacted = 0',
      whereArgs: [userId, itemId],
    );
    await db.update(
      DatabaseSchema.tableRecommendationLogs,
      {'was_interacted': 1},
      where: 'user_id = ? AND item_id = ?',
      whereArgs: [userId, itemId],
    );

    if (_syncQueue != null) {
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await _syncQueue.enqueue(
          operation: 'update',
          entity: 'recommendation_logs',
          entityId: id,
          payload: {
            ...row,
            'id': id,
            'was_interacted': 1,
            'interacted_at': DateTime.now().toIso8601String(),
          },
        );
      }
    }
  }

  // ── Read: admin analytics ─────────────────────────────────────────────────

  /// Returns per-algorithm aggregates for the admin dashboard.
  Future<List<AlgorithmStats>> getAlgorithmSummary() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        algorithm,
        COUNT(*) AS total,
        SUM(was_interacted) AS interacted
      FROM ${DatabaseSchema.tableRecommendationLogs}
      GROUP BY algorithm
      ORDER BY total DESC
    ''');

    return rows.map((r) {
      return AlgorithmStats(
        algorithm: r['algorithm'] as String? ?? 'unknown',
        total: (r['total'] as int?) ?? 0,
        interacted: (r['interacted'] as int?) ?? 0,
      );
    }).toList();
  }

  /// Total recommendation log count; optionally filtered by algorithm.
  Future<int> getTotalCount({String? algorithm}) async {
    final db = await _db.database;
    final result = algorithm != null
        ? await db.rawQuery(
            'SELECT COUNT(*) FROM ${DatabaseSchema.tableRecommendationLogs} WHERE algorithm = ?',
            [algorithm],
          )
        : await db.rawQuery(
            'SELECT COUNT(*) FROM ${DatabaseSchema.tableRecommendationLogs}',
          );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Paged log rows for the admin table view.
  Future<List<Map<String, dynamic>>> getRecentLogs({
    int pageSize = 50,
    int offset = 0,
    String? algorithm,
    String? userId,
  }) async {
    final db = await _db.database;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (algorithm != null) {
      conditions.add('algorithm = ?');
      args.add(algorithm);
    }
    if (userId != null) {
      conditions.add('user_id = ?');
      args.add(userId);
    }

    return db.query(
      DatabaseSchema.tableRecommendationLogs,
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'logged_at DESC',
      limit: pageSize,
      offset: offset,
    );
  }

  /// Returns the unique user IDs that have received recommendations (for sampling).
  Future<List<String>> getDistinctUserIds({int limit = 100}) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT user_id
      FROM ${DatabaseSchema.tableRecommendationLogs}
      ORDER BY user_id
      LIMIT $limit
    ''');
    return rows.map((r) => r['user_id'] as String).toList();
  }

  /// Top users by recommendation log volume.
  Future<List<UserLogVolume>> getTopUsersByLogCount({int limit = 10}) async {
    final db = await _db.database;
    final safeLimit = limit <= 0 ? 10 : limit;
    final rows = await db.rawQuery('''
      SELECT
        user_id,
        COUNT(*) AS total
      FROM ${DatabaseSchema.tableRecommendationLogs}
      GROUP BY user_id
      ORDER BY total DESC, user_id ASC
      LIMIT $safeLimit
    ''');

    return rows
        .map(
          (r) => UserLogVolume(
            userId: r['user_id'] as String? ?? '',
            total: (r['total'] as int?) ?? 0,
          ),
        )
        .where((item) => item.userId.isNotEmpty)
        .toList();
  }

  /// Latest log row for a specific (userId, itemId) pair — used by tests.
  Future<Map<String, dynamic>?> getLastEntry({
    required String userId,
    required String itemId,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableRecommendationLogs,
      where: 'user_id = ? AND item_id = ?',
      whereArgs: [userId, itemId],
      orderBy: 'logged_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }
}
