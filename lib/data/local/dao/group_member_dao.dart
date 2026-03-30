import 'package:sqflite/sqflite.dart';

import '../../models/group_member_model.dart';
import '../database_helper.dart';
import '../schema/database_schema.dart';

class GroupMemberDao {
  final DatabaseHelper _db;

  GroupMemberDao({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  Future<void> upsertMember(GroupMemberModel member) async {
    final db = await _db.database;
    await db.insert(
      DatabaseSchema.tableGroupMembers,
      member.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertMembers(List<GroupMemberModel> members) async {
    if (members.isEmpty) return;
    final db = await _db.database;
    final batch = db.batch();
    for (final member in members) {
      batch.insert(
        DatabaseSchema.tableGroupMembers,
        member.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<GroupMemberModel?> getMembership({
    required String groupId,
    required String userId,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableGroupMembers,
      where: 'group_id = ? AND user_id = ?',
      whereArgs: [groupId, userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GroupMemberModel.fromMap(rows.first);
  }

  Future<GroupMemberModel?> getMemberById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableGroupMembers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GroupMemberModel.fromMap(rows.first);
  }

  Future<List<GroupMemberModel>> getMembersForGroup(String groupId) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableGroupMembers,
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: "CASE status WHEN 'active' THEN 0 ELSE 1 END, CASE role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END, updated_at DESC",
    );
    return rows.map(GroupMemberModel.fromMap).toList();
  }

  Future<List<GroupMemberModel>> getPendingInvitesForUser(String userId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT gm.*, g.name AS group_name
      FROM ${DatabaseSchema.tableGroupMembers} gm
      INNER JOIN ${DatabaseSchema.tableGroups} g ON g.id = gm.group_id
      WHERE gm.user_id = ?
        AND gm.status = 'pending'
        AND COALESCE(g.is_dissolved, 0) = 0
      ORDER BY gm.updated_at DESC
    ''', [userId]);
    return rows.map(GroupMemberModel.fromMap).toList();
  }

  Future<void> updateMembershipStatus({
    required String groupId,
    required String userId,
    required String status,
    DateTime? joinedAt,
  }) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tableGroupMembers,
      {
        'status': status,
        'joined_at': joinedAt?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 0,
      },
      where: 'group_id = ? AND user_id = ?',
      whereArgs: [groupId, userId],
    );
  }

  Future<void> updateRole({
    required String groupId,
    required String userId,
    required String role,
  }) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tableGroupMembers,
      {
        'role': role,
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 0,
      },
      where: 'group_id = ? AND user_id = ?',
      whereArgs: [groupId, userId],
    );
  }

  Future<int> countActiveMembers(String groupId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM ${DatabaseSchema.tableGroupMembers}
      WHERE group_id = ? AND status = 'active'
    ''', [groupId]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<bool> isActiveMember({
    required String groupId,
    required String userId,
  }) async {
    final membership = await getMembership(groupId: groupId, userId: userId);
    return membership?.isActive ?? false;
  }

  Future<bool> isGroupManager({
    required String groupId,
    required String userId,
  }) async {
    final membership = await getMembership(groupId: groupId, userId: userId);
    return membership?.canManage ?? false;
  }
}
