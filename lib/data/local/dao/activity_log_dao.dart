import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database_helper.dart';
import '../schema/database_schema.dart';

class PostRatingSignals {
  final Map<String, double> lecturerRatings;
  final Map<String, double> studentRatings;

  const PostRatingSignals({
    this.lecturerRatings = const {},
    this.studentRatings = const {},
  });
}

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

  Future<PostRatingSignals> getPostRatingSignalsForPosts(
    List<String> postIds,
  ) async {
    if (postIds.isEmpty) return const PostRatingSignals();

    final cleanedIds = postIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (cleanedIds.isEmpty) return const PostRatingSignals();

    final db = await _db.database;
    final placeholders = List.filled(cleanedIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT a.user_id, a.entity_id, a.metadata, a.created_at, u.role
      FROM ${DatabaseSchema.tableActivityLogs} a
      INNER JOIN ${DatabaseSchema.tableUsers} u ON u.id = a.user_id
      WHERE a.action = 'rate_post'
        AND a.entity_type = ?
        AND a.entity_id IN ($placeholders)
      ORDER BY a.created_at DESC
      ''',
      [DatabaseSchema.tablePosts, ...cleanedIds],
    );

    final lecturerSum = <String, double>{};
    final lecturerCount = <String, int>{};
    final studentSum = <String, double>{};
    final studentCount = <String, int>{};
    final seenUserPost = <String>{};

    for (final row in rows) {
      final userId = row['user_id']?.toString().trim();
      final postId = row['entity_id']?.toString().trim();
      if (userId == null || userId.isEmpty || postId == null || postId.isEmpty) {
        continue;
      }

      final userPostKey = '$userId::$postId';
      if (!seenUserPost.add(userPostKey)) continue;

      final metadataRaw = row['metadata']?.toString();
      if (metadataRaw == null || metadataRaw.trim().isEmpty) continue;

      final metadata = _tryDecodeMap(metadataRaw);
      if (metadata == null) continue;

      final stars = _parseStars(metadata['stars']);
      if (stars == null) continue;

      final normalized = (stars / 5.0).clamp(0.0, 1.0);
      final role = row['role']?.toString().trim().toLowerCase() ?? '';

      if (role == 'lecturer') {
        lecturerSum[postId] = (lecturerSum[postId] ?? 0) + normalized;
        lecturerCount[postId] = (lecturerCount[postId] ?? 0) + 1;
      } else {
        studentSum[postId] = (studentSum[postId] ?? 0) + normalized;
        studentCount[postId] = (studentCount[postId] ?? 0) + 1;
      }
    }

    final lecturerRatings = <String, double>{};
    for (final entry in lecturerSum.entries) {
      final count = lecturerCount[entry.key] ?? 0;
      if (count > 0) {
        lecturerRatings[entry.key] = (entry.value / count).clamp(0.0, 1.0);
      }
    }

    final studentRatings = <String, double>{};
    for (final entry in studentSum.entries) {
      final count = studentCount[entry.key] ?? 0;
      if (count > 0) {
        studentRatings[entry.key] = (entry.value / count).clamp(0.0, 1.0);
      }
    }

    return PostRatingSignals(
      lecturerRatings: lecturerRatings,
      studentRatings: studentRatings,
    );
  }

  Future<int?> getMyLatestPostRating({
    required String userId,
    required String postId,
  }) async {
    final safeUserId = userId.trim();
    final safePostId = postId.trim();
    if (safeUserId.isEmpty || safePostId.isEmpty) return null;

    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableActivityLogs,
      columns: ['metadata'],
      where: 'user_id = ? AND action = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: [
        safeUserId,
        'rate_post',
        DatabaseSchema.tablePosts,
        safePostId,
      ],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final metadataRaw = rows.first['metadata']?.toString();
    if (metadataRaw == null || metadataRaw.trim().isEmpty) return null;

    final metadata = _tryDecodeMap(metadataRaw);
    if (metadata == null) return null;
    return _parseStars(metadata['stars']);
  }

  Map<String, dynamic>? _tryDecodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  int? _parseStars(dynamic value) {
    if (value is int) return value.clamp(1, 5);
    if (value is double) return value.round().clamp(1, 5);
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed.clamp(1, 5);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getReportedPostSummaries({
    int limit = 50,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableActivityLogs,
      columns: ['user_id', 'entity_id', 'metadata', 'created_at'],
      where: 'action = ? AND entity_type = ? AND entity_id IS NOT NULL',
      whereArgs: ['report_post', DatabaseSchema.tablePosts],
      orderBy: 'created_at DESC',
      limit: 500,
    );

    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final postId = row['entity_id']?.toString().trim();
      if (postId == null || postId.isEmpty) {
        continue;
      }

      final userId = row['user_id']?.toString() ?? '';
      final createdAtRaw = row['created_at']?.toString();
      final createdAt = DateTime.tryParse(createdAtRaw ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final metadata = _tryDecodeMap(row['metadata']?.toString() ?? '{}') ?? const <String, dynamic>{};
      final reason = (metadata['reason']?.toString().trim().isNotEmpty == true)
          ? metadata['reason'].toString().trim()
          : 'Other';

      final current = grouped.putIfAbsent(
        postId,
        () => {
          'postId': postId,
          'reportsCount': 0,
          'latestReportedAt': createdAt,
          'latestReporterId': userId,
          'topReason': reason,
          '_reasons': <String, int>{},
        },
      );

      current['reportsCount'] = (current['reportsCount'] as int) + 1;
      if (createdAt.isAfter(current['latestReportedAt'] as DateTime)) {
        current['latestReportedAt'] = createdAt;
        current['latestReporterId'] = userId;
      }

      final reasons = current['_reasons'] as Map<String, int>;
      reasons[reason] = (reasons[reason] ?? 0) + 1;
      current['topReason'] = reasons.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }

    if (grouped.isEmpty) {
      return const [];
    }

    final ids = grouped.keys.toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final posts = await db.rawQuery(
      '''
      SELECT p.id, p.title, p.author_id, p.moderation_status, p.is_archived,
             u.display_name AS author_name
      FROM ${DatabaseSchema.tablePosts} p
      LEFT JOIN ${DatabaseSchema.tableUsers} u ON u.id = p.author_id
      WHERE p.id IN ($placeholders)
      ''',
      ids,
    );

    final postById = <String, Map<String, Object?>>{
      for (final post in posts) (post['id']?.toString() ?? ''): post,
    };

    final summaries = grouped.values.map((summary) {
      final post = postById[summary['postId'] as String];
      final topReason = summary['topReason'] as String? ?? 'Other';
      final reportsCount = summary['reportsCount'] as int? ?? 0;
      final risk = reportsCount >= 5
          ? 'high'
          : reportsCount >= 3
              ? 'medium'
              : 'low';
      return {
        'postId': summary['postId'],
        'postTitle': post?['title']?.toString() ?? 'Untitled post',
        'authorId': post?['author_id']?.toString() ?? '',
        'authorName': post?['author_name']?.toString() ?? 'Unknown',
        'reportsCount': reportsCount,
        'latestReporterId': summary['latestReporterId']?.toString() ?? '',
        'latestReportedAt': (summary['latestReportedAt'] as DateTime).toIso8601String(),
        'topReason': topReason,
        'risk': risk,
        'isArchived': (post?['is_archived'] as int? ?? 0) == 1,
        'moderationStatus': post?['moderation_status']?.toString() ?? 'approved',
      };
    }).toList();

    summaries.sort((a, b) {
      final left = DateTime.tryParse(a['latestReportedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = DateTime.tryParse(b['latestReportedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });

    return summaries.take(limit).toList();
  }

  Future<int> getActionCountForDays({
    required String action,
    int days = 7,
  }) async {
    final db = await _db.database;
    final cutoff = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM ${DatabaseSchema.tableActivityLogs}
      WHERE action = ?
        AND created_at >= ?
      ''',
      [action, cutoff],
    );
    return rows.first['count'] as int? ?? 0;
  }

  Future<int> getActiveUserCountSince({int days = 7}) async {
    final db = await _db.database;
    final cutoff = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT user_id) AS count
      FROM ${DatabaseSchema.tableActivityLogs}
      WHERE created_at >= ?
      ''',
      [cutoff],
    );
    return rows.first['count'] as int? ?? 0;
  }

  Future<List<Map<String, dynamic>>> getRecentLogs({
    int limit = 100,
    String? action,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableActivityLogs,
      columns: [
        'id',
        'user_id',
        'action',
        'entity_type',
        'entity_id',
        'metadata',
        'created_at',
      ],
      where: action == null ? null : 'action = ?',
      whereArgs: action == null ? null : [action],
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return rows.map((row) {
      final metadataRaw = row['metadata']?.toString() ?? '{}';
      final metadata = _tryDecodeMap(metadataRaw) ?? const <String, dynamic>{};
      return {
        'id': row['id']?.toString() ?? '',
        'userId': row['user_id']?.toString() ?? '',
        'action': row['action']?.toString() ?? '',
        'entityType': row['entity_type']?.toString() ?? '',
        'entityId': row['entity_id']?.toString() ?? '',
        'metadata': metadata,
        'createdAt': row['created_at']?.toString() ?? '',
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getTopActions({
    int days = 7,
    int limit = 10,
  }) async {
    final db = await _db.database;
    final cutoff = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT action, COUNT(*) AS total
      FROM ${DatabaseSchema.tableActivityLogs}
      WHERE created_at >= ?
      GROUP BY action
      ORDER BY total DESC
      LIMIT ?
      ''',
      [cutoff, limit],
    );

    return rows
        .map(
          (row) => {
            'action': row['action']?.toString() ?? '',
            'total': row['total'] as int? ?? 0,
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> getDailyActionSeries({
    int days = 14,
  }) async {
    final db = await _db.database;
    final cutoff = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT SUBSTR(created_at, 1, 10) AS day,
             COUNT(*) AS total_actions,
             COUNT(DISTINCT user_id) AS active_users
      FROM ${DatabaseSchema.tableActivityLogs}
      WHERE created_at >= ?
      GROUP BY day
      ORDER BY day ASC
      ''',
      [cutoff],
    );

    return rows
        .map(
          (row) => {
            'day': row['day']?.toString() ?? '',
            'totalActions': row['total_actions'] as int? ?? 0,
            'activeUsers': row['active_users'] as int? ?? 0,
          },
        )
        .toList();
  }
}