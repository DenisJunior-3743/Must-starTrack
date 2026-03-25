import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database_helper.dart';
import '../schema/database_schema.dart';

class ActivityLogDao {
  final DatabaseHelper _db;
  final _uuid = const Uuid();

  ActivityLogDao({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  Future<void> logAction({
    required String userId,
    required String action,
    String? entityType,
    String? entityId,
    Map<String, dynamic> metadata = const {},
  }) async {
    if (userId.trim().isEmpty) return;

    final db = await _db.database;
    await db.insert(
      DatabaseSchema.tableActivityLogs,
      {
        'id': _uuid.v4(),
        'user_id': userId,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'metadata': jsonEncode(metadata),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> logSearch({
    required String userId,
    required String query,
    String type = 'general',
  }) async {
    final trimmed = query.trim();
    if (userId.trim().isEmpty || trimmed.isEmpty) return;

    final db = await _db.database;
    await db.insert(
      DatabaseSchema.tableSearchHistory,
      {
        'id': _uuid.v4(),
        'user_id': userId,
        'query': trimmed,
        'type': type,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await logAction(
      userId: userId,
      action: 'search_$type',
      entityType: DatabaseSchema.tableSearchHistory,
      entityId: trimmed,
      metadata: {
        'query': trimmed,
        'type': type,
      },
    );
  }

  Future<Set<String>> getRecentCategorySignals(String userId, {int limit = 40}) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT LOWER(p.category) AS category
      FROM ${DatabaseSchema.tableActivityLogs} a
      INNER JOIN ${DatabaseSchema.tablePosts} p ON p.id = a.entity_id
      WHERE a.user_id = ?
        AND a.entity_type = ?
        AND a.action IN ('view_post', 'like_post', 'comment_post', 'share_post', 'join_opportunity')
        AND p.category IS NOT NULL
      ORDER BY a.created_at DESC
      LIMIT ?
    ''', [userId, DatabaseSchema.tablePosts, limit]);

    return rows
        .map((row) => row['category']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> getRecentSearchTerms(String userId, {int limit = 20}) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableSearchHistory,
      columns: ['query'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return rows
        .map((row) => (row['query'] as String? ?? '').trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
  }
}