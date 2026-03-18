// lib/data/local/dao/post_dao.dart
//
// MUST StarTrack — Post DAO (Data Access Object)
//
// Covers: posts, likes, comments, bookmarks.
// All writes set sync_status=0 so SyncService picks them up.
//
// Key design decisions:
//  • Optimistic UI — like/unlike modifies the local count immediately,
//    then enqueues a Firestore write. The user sees instant feedback
//    even on slow connections (HCI: Feedback principle).
//  • Cursor-based pagination — uses createdAt as cursor instead of OFFSET
//    because OFFSET degrades on large tables (O(n) scan). This keeps
//    feed scrolling snappy regardless of post count.
//  • Author denormalisation — author name/photo stored on the post row
//    to avoid a JOIN on every feed render. Refreshed when the author
//    updates their profile.

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database_helper.dart';
import '../schema/database_schema.dart';
import '../../models/post_model.dart';
import '../../../core/constants/app_enums.dart';

class PostDao {
  final DatabaseHelper _db;
  final _uuid = const Uuid();

  PostDao({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  // ── Create / Update ───────────────────────────────────────────────────────

  Future<void> insertPost(PostModel post) async {
    final db = await _db.database;
    final map = await _filterToExistingColumns(
      db,
      DatabaseSchema.tablePosts,
      _toDbMap(post),
    );
    await db.insert(
      DatabaseSchema.tablePosts,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updatePost(PostModel post) async {
    final db = await _db.database;
    final rawMap = _toDbMap(post)
      ..['updated_at'] = DateTime.now().millisecondsSinceEpoch
      ..['sync_status'] = 0;
    final map = await _filterToExistingColumns(
      db,
      DatabaseSchema.tablePosts,
      rawMap,
    );
    await db.update(
      DatabaseSchema.tablePosts,
      map,
      where: 'id = ?',
      whereArgs: [post.id],
    );
  }

  Future<void> archivePost(String postId) async {
    final db = await _db.database;
    final postColumns = await _tableColumns(db, DatabaseSchema.tablePosts);

    final update = <String, Object?>{
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'sync_status': 0,
    };

    if (postColumns.contains('is_archived')) {
      update['is_archived'] = 1;
    } else if (postColumns.contains('status')) {
      update['status'] = 'archived';
    }

    final safeUpdate = await _filterToExistingColumns(
      db,
      DatabaseSchema.tablePosts,
      update,
    );

    await db.update(
      DatabaseSchema.tablePosts,
      safeUpdate,
      where: 'id = ?',
      whereArgs: [postId],
    );
  }

  Future<void> deletePost(String postId) async {
    final db = await _db.database;
    await db.delete(
      DatabaseSchema.tablePosts,
      where: 'id = ?',
      whereArgs: [postId],
    );
  }

  // ── Read — Feed ───────────────────────────────────────────────────────────

  /// Returns approved, non-archived posts ordered by newest first.
  /// Uses cursor-based pagination for O(log n) performance.
  ///
  /// [afterCursor] = createdAt ms of the last item received.
  ///   Pass null for the first page.
  Future<List<PostModel>> getFeedPage({
    int pageSize = 20,
    int? afterCursor, // createdAt milliseconds
    String? filterFaculty,
    String? filterCategory,
    String? filterType, // 'project' | 'opportunity'
    String? currentUserId,
  }) async {
    final db = await _db.database;
    final postColumns = await _tableColumns(db, DatabaseSchema.tablePosts);
    final userColumns = await _tableColumns(db, DatabaseSchema.tableUsers);

    final conditions = <String>[];
    final args = <dynamic>[];

    if (postColumns.contains('is_archived')) {
      conditions.add('p.is_archived = 0');
    } else if (postColumns.contains('status')) {
      conditions.add("p.status != 'archived'");
    }

    if (postColumns.contains('moderation_status')) {
      conditions.add("p.moderation_status = 'approved'");
    } else if (postColumns.contains('status')) {
      conditions.add("p.status IN ('published', 'open')");
    }

    if (afterCursor != null) {
      conditions.add('p.created_at < ?');
      args.add(afterCursor);
    }
    if (filterFaculty != null) {
      conditions.add('p.faculty = ?');
      args.add(filterFaculty);
    }
    if (filterCategory != null) {
      conditions.add('p.category = ?');
      args.add(filterCategory);
    }
    if (filterType != null && postColumns.contains('type')) {
      conditions.add('p.type = ?');
      args.add(filterType);
    }

    args.addAll([pageSize]);

    // Left-join user interaction state so we get isLikedByMe in one query
    final likeJoin = currentUserId != null
        ? "LEFT JOIN ${DatabaseSchema.tableLikes} lk ON lk.post_id = p.id AND lk.user_id = '$currentUserId'"
        : '';

    final userNameColumn = userColumns.contains('display_name')
      ? 'display_name'
      : userColumns.contains('name')
        ? 'name'
        : null;
    final userPhotoColumn = userColumns.contains('photo_url')
      ? 'photo_url'
      : userColumns.contains('avatar_url')
        ? 'avatar_url'
        : null;

    final selectAuthorName = userNameColumn != null
      ? 'u.$userNameColumn AS author_name'
      : "'' AS author_name";
    final selectAuthorPhoto = userPhotoColumn != null
      ? 'u.$userPhotoColumn AS author_photo_url'
      : 'NULL AS author_photo_url';
    final selectAuthorRole = userColumns.contains('role')
      ? 'u.role AS author_role'
      : "'student' AS author_role";

    if (conditions.isEmpty) {
      conditions.add('1 = 1');
    }

    final sql = '''
      SELECT p.*,
         $selectAuthorName,
         $selectAuthorPhoto,
         $selectAuthorRole
             ${currentUserId != null ? ', CASE WHEN lk.id IS NOT NULL THEN 1 ELSE 0 END AS is_liked_by_me' : ''}
      FROM   ${DatabaseSchema.tablePosts} p
      JOIN   ${DatabaseSchema.tableUsers} u ON u.id = p.author_id
      $likeJoin
      WHERE  ${conditions.join(' AND ')}
      ORDER  BY p.created_at DESC
      LIMIT  ?
    ''';

    final rows = await db.rawQuery(sql, args);
    return rows.map(_fromDbRow).toList();
  }

  /// Returns posts by a specific author (for profile page).
  Future<List<PostModel>> getPostsByAuthor(
    String authorId, {
    int pageSize = 20,
    int? afterCursor,
  }) async {
    final db = await _db.database;
    final postColumns = await _tableColumns(db, DatabaseSchema.tablePosts);
    final rows = await db.rawQuery('''
      SELECT * FROM ${DatabaseSchema.tablePosts}
      WHERE  author_id = ?
        ${postColumns.contains('is_archived') ? 'AND is_archived = 0' : ''}
        ${!postColumns.contains('is_archived') && postColumns.contains('status') ? "AND status != 'archived'" : ''}
        ${afterCursor != null ? 'AND created_at < $afterCursor' : ''}
      ORDER  BY created_at DESC
      LIMIT  ?
    ''', [authorId, pageSize]);
    return rows.map(_fromDbRow).toList();
  }

  /// Full-text search across title, description, tags.
  Future<List<PostModel>> searchPosts({
    required String query,
    String? faculty,
    String? category,
    List<String>? skills,
    String? recency, // 'week' | 'month' | 'any'
    int pageSize = 20,
    int page = 0,
  }) async {
    final db = await _db.database;
    final postColumns = await _tableColumns(db, DatabaseSchema.tablePosts);
    final userColumns = await _tableColumns(db, DatabaseSchema.tableUsers);
    final pattern = '%$query%';

    int? afterMs;
    if (recency == 'week') {
      afterMs = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;
    } else if (recency == 'month') {
      afterMs = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
    }

    final conditions = [
      "(p.title LIKE ? OR p.description LIKE ? OR p.tags LIKE ?)",
    ];
    final args = <dynamic>[pattern, pattern, pattern];

    if (postColumns.contains('is_archived')) {
      conditions.add('p.is_archived = 0');
    } else if (postColumns.contains('status')) {
      conditions.add("p.status != 'archived'");
    }

    if (postColumns.contains('moderation_status')) {
      conditions.add("p.moderation_status = 'approved'");
    } else if (postColumns.contains('status')) {
      conditions.add("p.status IN ('published', 'open')");
    }

    if (faculty != null) { conditions.add('p.faculty = ?'); args.add(faculty); }
    if (category != null) { conditions.add('p.category = ?'); args.add(category); }
    if (afterMs != null) { conditions.add('p.created_at >= ?'); args.add(afterMs); }
    if (skills != null && skills.isNotEmpty) {
      for (final s in skills) {
        conditions.add('p.skills_used LIKE ?');
        args.add('%$s%');
      }
    }

    args.addAll([pageSize, page * pageSize]);

    final userNameColumn = userColumns.contains('display_name')
      ? 'display_name'
      : userColumns.contains('name')
        ? 'name'
        : null;
    final userPhotoColumn = userColumns.contains('photo_url')
      ? 'photo_url'
      : userColumns.contains('avatar_url')
        ? 'avatar_url'
        : null;

    final selectAuthorName = userNameColumn != null
      ? 'u.$userNameColumn AS author_name'
      : "'' AS author_name";
    final selectAuthorPhoto = userPhotoColumn != null
      ? 'u.$userPhotoColumn AS author_photo_url'
      : 'NULL AS author_photo_url';

    final rows = await db.rawQuery('''
      SELECT p.*, $selectAuthorName, $selectAuthorPhoto
      FROM   ${DatabaseSchema.tablePosts} p
      JOIN   ${DatabaseSchema.tableUsers} u ON u.id = p.author_id
      WHERE  ${conditions.join(' AND ')}
      ORDER  BY p.created_at DESC
      LIMIT  ? OFFSET ?
    ''', args);

    return rows.map(_fromDbRow).toList();
  }

  /// Fetch a single post by ID.
  Future<PostModel?> getPostById(String id, {String? currentUserId}) async {
    final db = await _db.database;
    final likeJoin = currentUserId != null
        ? "LEFT JOIN ${DatabaseSchema.tableLikes} lk ON lk.post_id = p.id AND lk.user_id = '$currentUserId'"
        : '';
    final rows = await db.rawQuery('''
      SELECT p.*,
             u.display_name AS author_name,
             u.photo_url    AS author_photo_url,
             u.role         AS author_role
             ${currentUserId != null ? ", CASE WHEN lk.id IS NOT NULL THEN 1 ELSE 0 END AS is_liked_by_me" : ""}
      FROM   ${DatabaseSchema.tablePosts} p
      JOIN   ${DatabaseSchema.tableUsers} u ON u.id = p.author_id
      $likeJoin
      WHERE  p.id = ?
    ''', [id]);
    return rows.isEmpty ? null : _fromDbRow(rows.first);
  }

  // ── Likes (Optimistic) ─────────────────────────────────────────────────────

  /// Toggle like state. Returns the new like count.
  /// Modifies the post row's like_count in the same transaction for consistency.
  Future<int> toggleLike({
    required String postId,
    required String userId,
  }) async {
    final db = await _db.database;

    return db.transaction((txn) async {
      final existing = await txn.query(
        DatabaseSchema.tableLikes,
        where: 'post_id = ? AND user_id = ?',
        whereArgs: [postId, userId],
        limit: 1,
      );

      int delta;
      if (existing.isNotEmpty) {
        // Unlike
        await txn.delete(
          DatabaseSchema.tableLikes,
          where: 'post_id = ? AND user_id = ?',
          whereArgs: [postId, userId],
        );
        delta = -1;
      } else {
        // Like (also remove dislike if present)
        await txn.delete(
          DatabaseSchema.tableDislikes,
          where: 'post_id = ? AND user_id = ?',
          whereArgs: [postId, userId],
        );
        await txn.insert(DatabaseSchema.tableLikes, {
          'id': _uuid.v4(),
          'post_id': postId,
          'user_id': userId,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'sync_status': 0,
        });
        delta = 1;
      }

      // Update denormalised count on post row
      await txn.rawUpdate('''
        UPDATE ${DatabaseSchema.tablePosts}
        SET like_count = MAX(0, like_count + ?), sync_status = 0
        WHERE id = ?
      ''', [delta, postId]);

      final result = await txn.rawQuery(
        'SELECT like_count FROM ${DatabaseSchema.tablePosts} WHERE id = ?',
        [postId],
      );
      return result.first['like_count'] as int? ?? 0;
    });
  }

  // ── View count ─────────────────────────────────────────────────────────────

  Future<void> incrementViewCount(String postId) async {
    final db = await _db.database;
    await db.rawUpdate('''
      UPDATE ${DatabaseSchema.tablePosts}
      SET view_count = view_count + 1
      WHERE id = ?
    ''', [postId]);
  }

  Future<bool> recordUniqueView({
    required String postId,
    required String userId,
  }) async {
    final db = await _db.database;
    final existing = await db.query(
      DatabaseSchema.tableActivityLogs,
      columns: ['id'],
      where: 'user_id = ? AND action = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: [userId, 'view_post', DatabaseSchema.tablePosts, postId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return false;
    }

    await db.insert(DatabaseSchema.tableActivityLogs, {
      'id': _uuid.v4(),
      'user_id': userId,
      'action': 'view_post',
      'entity_type': DatabaseSchema.tablePosts,
      'entity_id': postId,
      'metadata': '{}',
      'created_at': DateTime.now().toIso8601String(),
    });
    return true;
  }

  // ── Stats for admin ────────────────────────────────────────────────────────

  Future<Map<String, int>> getPostStats() async {
    final db = await _db.database;
    final postColumns = await _tableColumns(db, DatabaseSchema.tablePosts);
    final pendingExpr = postColumns.contains('moderation_status')
        ? "SUM(CASE WHEN moderation_status = 'pending' THEN 1 ELSE 0 END)"
        : '0';
    final archivedExpr = postColumns.contains('is_archived')
        ? 'SUM(CASE WHEN is_archived = 1 THEN 1 ELSE 0 END)'
        : postColumns.contains('status')
            ? "SUM(CASE WHEN status = 'archived' THEN 1 ELSE 0 END)"
            : '0';

    final result = await db.rawQuery('''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN type = 'project' THEN 1 ELSE 0 END) AS projects,
        SUM(CASE WHEN type = 'opportunity' THEN 1 ELSE 0 END) AS opportunities,
        $pendingExpr AS pending_mod,
        $archivedExpr AS archived
      FROM ${DatabaseSchema.tablePosts}
    ''');
    final row = result.first;
    return {
      'total': row['total'] as int? ?? 0,
      'projects': row['projects'] as int? ?? 0,
      'opportunities': row['opportunities'] as int? ?? 0,
      'pendingModeration': row['pending_mod'] as int? ?? 0,
      'archived': row['archived'] as int? ?? 0,
    };
  }

  // ── Serialisation helpers ──────────────────────────────────────────────────

  List<String> _imageMediaUrls(PostModel post) {
    return post.mediaUrls.where((url) => !_looksLikeVideoUrl(url)).toList();
  }

  List<String> _videoMediaUrls(PostModel post) {
    return post.mediaUrls.where(_looksLikeVideoUrl).toList();
  }

  bool _looksLikeVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/video/upload/') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv');
  }

  Map<String, dynamic> _toDbMap(PostModel p) => {
    'id': p.id,
    'author_id': p.authorId,
    'author_name': p.authorName,
    'author_photo_url': p.authorPhotoUrl,
    'type': p.type,
    'title': p.title,
    'description': p.description,
    'category': p.category,
    'tags': jsonEncode(p.tags),
    'faculty': p.faculty,
    'program': p.program,
    'skills_used': jsonEncode(p.skillsUsed),
    'images': jsonEncode(_imageMediaUrls(p)),
    'videos': jsonEncode(_videoMediaUrls(p)),
    'media_urls': jsonEncode(p.mediaUrls),
    'youtube_url': p.youtubeUrl,
    'youtube_link': p.youtubeUrl,
    'external_links': jsonEncode(p.externalLinks),
    'external_link': p.externalLinks.isNotEmpty
      ? p.externalLinks.first.values.firstOrNull
      : null,
    'visibility': p.visibility.name,
    'moderation_status': p.moderationStatus.name,
    'status': p.moderationStatus == ModerationStatus.approved ? 'published' : p.moderationStatus.name,
    'trust_score': p.trustScore,
    'suspicion_score': p.trustScore,
    'like_count': p.likeCount,
    'dislike_count': p.dislikeCount,
    'comment_count': p.commentCount,
    'share_count': p.shareCount,
    'view_count': p.viewCount,
    'is_archived': p.isArchived ? 1 : 0,
    'created_at': p.createdAt.millisecondsSinceEpoch,
    'updated_at': p.updatedAt.millisecondsSinceEpoch,
    'sync_status': 0,
  };

  PostModel _fromDbRow(Map<String, dynamic> row) {
    List<String> parseList(dynamic v) {
      if (v == null) return [];
      try { return List<String>.from(jsonDecode(v as String) as List); }
      catch (_) { return []; }
    }

    List<Map<String, String>> parseLinks(dynamic v) {
      if (v == null) return [];
      try {
        return (jsonDecode(v as String) as List)
            .map((e) => Map<String, String>.from(e as Map))
            .toList();
      } catch (_) { return []; }
    }

    int parseInt(dynamic v, {int fallback = 0}) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    DateTime parseDate(dynamic v) {
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) {
        final asInt = int.tryParse(v);
        if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
        final asDate = DateTime.tryParse(v);
        if (asDate != null) return asDate;
      }
      return DateTime.now();
    }

    String? pickString(List<String> keys) {
      for (final key in keys) {
        final value = row[key];
        if (value is String && value.isNotEmpty) return value;
      }
      return null;
    }

    final parsedMediaUrls = parseList(row['media_urls']);
    final parsedImages = parseList(row['images']);
    final parsedVideos = parseList(row['videos']);
    final combinedLegacyMedia = [...parsedImages, ...parsedVideos];

    final parsedExternalLinks = parseLinks(row['external_links']);
    final legacyExternalLink = pickString(['external_link']);

    return PostModel(
      id: row['id'] as String,
      authorId: row['author_id'] as String,
      authorName: pickString(['author_name', 'display_name', 'name']),
      authorPhotoUrl: pickString(['author_photo_url', 'photo_url', 'avatar_url']),
      authorRole: row['author_role'] as String?,
      type: row['type'] as String? ?? 'project',
      title: row['title'] as String,
      description: row['description'] as String?,
      category: row['category'] as String?,
      tags: parseList(row['tags']),
      faculty: row['faculty'] as String?,
      program: row['program'] as String?,
      skillsUsed: parseList(row['skills_used']),
      mediaUrls: parsedMediaUrls.isNotEmpty ? parsedMediaUrls : combinedLegacyMedia,
      youtubeUrl: pickString(['youtube_url', 'youtube_link']),
      externalLinks: parsedExternalLinks.isNotEmpty
          ? parsedExternalLinks
          : legacyExternalLink != null
              ? [
                  {'url': legacyExternalLink}
                ]
              : [],
      visibility: PostVisibility.values.firstWhere(
        (v) => v.name == row['visibility'],
        orElse: () => PostVisibility.public,
      ),
      moderationStatus: ModerationStatus.values.firstWhere(
        (v) => v.name == (row['moderation_status'] ?? row['status']),
        orElse: () => ModerationStatus.approved,
      ),
      trustScore: parseInt(row['trust_score'] ?? row['suspicion_score'], fallback: 100),
      likeCount: parseInt(row['like_count']),
      dislikeCount: parseInt(row['dislike_count']),
      commentCount: parseInt(row['comment_count']),
      shareCount: parseInt(row['share_count']),
      viewCount: parseInt(row['view_count']),
      isArchived: parseInt(row['is_archived']) == 1 || (row['status'] == 'archived'),
      isLikedByMe: parseInt(row['is_liked_by_me']) == 1,
      createdAt: parseDate(row['created_at']),
      updatedAt: parseDate(row['updated_at']),
    );
  }

  Future<Set<String>> _tableColumns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
  }

  Future<Map<String, dynamic>> _filterToExistingColumns(
    Database db,
    String table,
    Map<String, dynamic> values,
  ) async {
    final columns = await _tableColumns(db, table);
    return Map<String, dynamic>.fromEntries(
      values.entries.where((entry) => columns.contains(entry.key)),
    );
  }
}