import 'package:sqflite/sqflite.dart';

import '../../models/group_model.dart';
import '../database_helper.dart';
import '../schema/database_schema.dart';

class GroupDao {
  final DatabaseHelper _db;

  GroupDao({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  Future<void> upsertGroup(GroupModel group) async {
    final db = await _db.database;
    await db.insert(
      DatabaseSchema.tableGroups,
      group.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<GroupModel?> getGroupById(String id) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT g.*,
        (
          SELECT COUNT(*)
          FROM ${DatabaseSchema.tableGroupMembers} gm
          WHERE gm.group_id = g.id AND gm.status = 'active'
        ) AS member_count,
        (
          SELECT COUNT(*)
          FROM ${DatabaseSchema.tablePosts} p
          WHERE p.group_id = g.id AND COALESCE(p.is_archived, 0) = 0
        ) AS visible_post_count
      FROM ${DatabaseSchema.tableGroups} g
      WHERE g.id = ?
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    return GroupModel.fromMap(rows.first);
  }

  Future<List<GroupModel>> getGroupsForUser(
    String userId, {
    bool includeDissolved = false,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT g.*,
        (
          SELECT COUNT(*)
          FROM ${DatabaseSchema.tableGroupMembers} gm2
          WHERE gm2.group_id = g.id AND gm2.status = 'active'
        ) AS member_count,
        (
          SELECT COUNT(*)
          FROM ${DatabaseSchema.tablePosts} p
          WHERE p.group_id = g.id AND COALESCE(p.is_archived, 0) = 0
        ) AS visible_post_count
      FROM ${DatabaseSchema.tableGroups} g
      INNER JOIN ${DatabaseSchema.tableGroupMembers} gm ON gm.group_id = g.id
      WHERE gm.user_id = ?
        AND gm.status = 'active'
        ${includeDissolved ? '' : 'AND COALESCE(g.is_dissolved, 0) = 0'}
      ORDER BY g.updated_at DESC
    ''', [userId]);

    return rows.map(GroupModel.fromMap).toList();
  }

  Future<List<GroupModel>> getAllGroups({
    bool includeDissolved = false,
    int limit = 120,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT g.*,
        (
          SELECT COUNT(*)
          FROM ${DatabaseSchema.tableGroupMembers} gm
          WHERE gm.group_id = g.id AND gm.status = 'active'
        ) AS member_count,
        (
          SELECT COUNT(*)
          FROM ${DatabaseSchema.tablePosts} p
          WHERE p.group_id = g.id AND COALESCE(p.is_archived, 0) = 0
        ) AS visible_post_count
      FROM ${DatabaseSchema.tableGroups} g
      ${includeDissolved ? '' : 'WHERE COALESCE(g.is_dissolved, 0) = 0'}
      ORDER BY g.updated_at DESC
      LIMIT ?
    ''', [limit]);

    return rows.map(GroupModel.fromMap).toList();
  }

  Future<void> updateMemberCount(String groupId, int memberCount) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tableGroups,
      {
        'member_count': memberCount,
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 0,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );
  }

  Future<void> dissolveGroup(String groupId) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tableGroups,
      {
        'is_dissolved': 1,
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 0,
      },
      where: 'id = ?',
      whereArgs: [groupId],
    );
  }
}
