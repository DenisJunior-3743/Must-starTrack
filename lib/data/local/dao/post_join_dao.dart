// lib/data/local/dao/post_join_dao.dart
//
// MUST StarTrack — PostJoin DAO
//
// Manages the post_joins table: which users have applied/joined
// an opportunity post. Used by the lecturer module to view applicants.

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database_helper.dart';
import '../schema/database_schema.dart';
import '../../models/user_model.dart';
import '../../models/post_model.dart';
import '../../models/profile_model.dart';

class PostJoinDao {
  final DatabaseHelper _db;
  final _uuid = const Uuid();

  PostJoinDao({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  /// Join an opportunity post. Returns the generated join id.
  Future<String> joinPost(String userId, String postId) async {
    final db = await _db.database;
    final id = _uuid.v4();
    await db.insert(
      DatabaseSchema.tablePostJoins,
      {
        'id': id,
        'user_id': userId,
        'post_id': postId,
        'created_at': DateTime.now().toIso8601String(),
        'sync_status': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // Increment join_count on the post
    await db.rawUpdate('''
      UPDATE ${DatabaseSchema.tablePosts}
      SET join_count = join_count + 1,
          sync_status = 0
      WHERE id = ?
    ''', [postId]);

    return id;
  }

  /// Leave / withdraw from an opportunity post.
  Future<void> leavePost(String userId, String postId) async {
    final db = await _db.database;
    final deleted = await db.delete(
      DatabaseSchema.tablePostJoins,
      where: 'user_id = ? AND post_id = ?',
      whereArgs: [userId, postId],
    );

    if (deleted > 0) {
      await db.rawUpdate('''
        UPDATE ${DatabaseSchema.tablePosts}
        SET join_count = MAX(join_count - 1, 0),
            sync_status = 0
        WHERE id = ?
      ''', [postId]);
    }
  }

  /// Check whether a user has already joined a post.
  Future<bool> hasUserJoined(String userId, String postId) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tablePostJoins,
      where: 'user_id = ? AND post_id = ?',
      whereArgs: [userId, postId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Get the number of applicants for a post.
  Future<int> getApplicantCount(String postId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM ${DatabaseSchema.tablePostJoins} WHERE post_id = ?',
      [postId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns users who joined a specific opportunity post, with profile data.
  Future<List<UserModel>> getApplicantsForPost(String postId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT u.*, pj.created_at AS joined_at
      FROM ${DatabaseSchema.tablePostJoins} pj
      INNER JOIN ${DatabaseSchema.tableUsers} u ON u.id = pj.user_id
      WHERE pj.post_id = ?
      ORDER BY pj.created_at DESC
    ''', [postId]);

    final users = <UserModel>[];
    for (final row in rows) {
      ProfileModel? profile;
      final profileRows = await db.query(
        DatabaseSchema.tableProfiles,
        where: 'user_id = ?',
        whereArgs: [row['id'] as String],
        limit: 1,
      );
      if (profileRows.isNotEmpty) {
        profile = ProfileModel.fromMap(profileRows.first);
      }
      users.add(UserModel.fromMap(row, profile: profile));
    }
    return users;
  }

  /// Returns all post IDs a user has joined (for "My Applications" screen).
  Future<List<String>> getJoinedPostIds(String userId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT post_id FROM ${DatabaseSchema.tablePostJoins} WHERE user_id = ?',
      [userId],
    );
    return rows.map((r) => r['post_id'] as String).toList();
  }

  /// Returns full PostModel list for opportunities a user has joined.
  Future<List<PostModel>> getJoinedPosts(String userId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT p.*
      FROM ${DatabaseSchema.tablePostJoins} pj
      INNER JOIN ${DatabaseSchema.tablePosts} p ON p.id = pj.post_id
      WHERE pj.user_id = ?
      ORDER BY pj.created_at DESC
    ''', [userId]);
    return rows.map((r) => PostModel.fromJson(r)).toList();
  }

  /// Returns rows pending sync.
  Future<List<Map<String, dynamic>>> getPendingSync() async {
    final db = await _db.database;
    return db.query(
      DatabaseSchema.tablePostJoins,
      where: 'sync_status = 0',
    );
  }

  /// Marks a join row as synced.
  Future<void> markSynced(String id) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tablePostJoins,
      {'sync_status': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
