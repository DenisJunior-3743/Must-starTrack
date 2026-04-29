import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database_helper.dart';
import '../schema/database_schema.dart';

class CommentRecord {
  final String id;
  final String postId;
  final String authorId;
  final String content;
  final DateTime createdAt;
  final String? authorName;
  final String? authorPhotoUrl;
  final String? parentCommentId;

  const CommentRecord({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.authorName,
    this.authorPhotoUrl,
    this.parentCommentId,
  });
}

class CommentDao {
  final DatabaseHelper _db;
  final _uuid = const Uuid();

  CommentDao({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  Future<List<CommentRecord>> getCommentsForPost(String postId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        c.id,
        c.post_id,
        c.author_id,
        c.content,
        c.created_at,
        c.parent_comment_id,
        u.display_name AS author_name,
        u.photo_url AS author_photo_url
      FROM ${DatabaseSchema.tableComments} c
      LEFT JOIN ${DatabaseSchema.tableUsers} u ON u.id = c.author_id
      WHERE c.post_id = ? AND c.is_deleted = 0
      ORDER BY c.created_at DESC
    ''', [postId]);

    return rows.map((row) {
      final createdAtRaw = row['created_at'] as String?;
      return CommentRecord(
        id: row['id'] as String,
        postId: row['post_id'] as String,
        authorId: row['author_id'] as String,
        content: row['content'] as String? ?? '',
        createdAt: DateTime.tryParse(createdAtRaw ?? '') ?? DateTime.now(),
        authorName: row['author_name'] as String?,
        authorPhotoUrl: row['author_photo_url'] as String?,
        parentCommentId: row['parent_comment_id'] as String?,
      );
    }).toList();
  }

  Future<Map<String, List<String>>> getRecentCommentSnippetsForPosts(
    List<String> postIds, {
    int perPostLimit = 4,
    int maxChars = 220,
  }) async {
    final cleanedPostIds = postIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (cleanedPostIds.isEmpty) return const {};

    final db = await _db.database;
    final placeholders = List.filled(cleanedPostIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT c.post_id, c.content, c.created_at
      FROM ${DatabaseSchema.tableComments} c
      WHERE c.post_id IN ($placeholders)
        AND c.is_deleted = 0
      ORDER BY c.created_at DESC
      ''',
      cleanedPostIds,
    );

    final result = <String, List<String>>{};
    for (final row in rows) {
      final postId = row['post_id']?.toString();
      final content = row['content']?.toString().trim() ?? '';
      if (postId == null || postId.isEmpty || content.isEmpty) continue;

      final bucket = result.putIfAbsent(postId, () => <String>[]);
      if (bucket.length >= perPostLimit) continue;
      final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
      bucket.add(
        normalized.length > maxChars
            ? normalized.substring(0, maxChars)
            : normalized,
      );
    }

    return result;
  }

  Future<void> addLocalComment({
    required String postId,
    required String authorId,
    required String content,
    String? commentId,
    String? parentCommentId,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final id = commentId ?? _uuid.v4();

    await db.transaction((txn) async {
      await txn.insert(
        DatabaseSchema.tableComments,
        {
          'id': id,
          'post_id': postId,
          'author_id': authorId,
          'content': content,
          'parent_comment_id': parentCommentId,
          'created_at': now,
          'updated_at': now,
          'sync_status': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.rawUpdate('''
        UPDATE ${DatabaseSchema.tablePosts}
        SET comment_count = comment_count + 1, sync_status = 0
        WHERE id = ?
      ''', [postId]);
    });
  }

  Future<void> upsertRemoteComment({
    required String commentId,
    required String postId,
    required String authorId,
    required String content,
    required DateTime createdAt,
    String? parentCommentId,
  }) async {
    final db = await _db.database;
    final existing = await db.query(
      DatabaseSchema.tableComments,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [commentId],
      limit: 1,
    );

    await db.insert(
      DatabaseSchema.tableComments,
      {
        'id': commentId,
        'post_id': postId,
        'author_id': authorId,
        'content': content,
        'parent_comment_id': parentCommentId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': createdAt.toIso8601String(),
        'sync_status': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (existing.isEmpty) {
      await db.rawUpdate('''
        UPDATE ${DatabaseSchema.tablePosts}
        SET comment_count = comment_count + 1
        WHERE id = ?
      ''', [postId]);
    }
  }
}
