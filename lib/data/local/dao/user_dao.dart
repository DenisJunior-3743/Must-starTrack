// lib/data/local/dao/user_dao.dart
//
// MUST StarTrack — User & Profile DAO (Data Access Object)
//
// Provides typed read/write operations against the SQLite 'users'
// and 'profiles' tables. All methods are async and return models,
// never raw Maps (the model layer handles serialization).
//
// The DAO pattern keeps SQL out of the repository layer —
// repositories call DAOs, never the database directly.
// This makes testing straightforward: mock the DAO, not SQLite.
//
// Offline-first: every write also sets sync_status = 0 (pending sync).
// The SyncRepository picks these up and pushes to Firestore.

import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../schema/database_schema.dart';
import '../../models/user_model.dart';
import '../../models/profile_model.dart';

class UserDao {
  final DatabaseHelper _db;
  UserDao({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  // ── Users Table ───────────────────────────────────────────────────────────

  /// Insert a new user. Throws if email already exists (UNIQUE constraint).
  Future<void> insertUser(UserModel user) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final userMap = user.toMap();
      final updatedUsers = await txn.update(
        DatabaseSchema.tableUsers,
        userMap,
        where: 'id = ?',
        whereArgs: [user.id],
      );
      if (updatedUsers == 0) {
        await txn.insert(
          DatabaseSchema.tableUsers,
          userMap,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      final profile = user.profile;
      if (profile != null) {
        final profileMap = profile.toMap();
        final updatedProfiles = await txn.update(
          DatabaseSchema.tableProfiles,
          profileMap,
          where: 'user_id = ?',
          whereArgs: [profile.userId],
        );
        if (updatedProfiles == 0) {
          await txn.insert(
            DatabaseSchema.tableProfiles,
            profileMap,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }
    });
  }

  /// Fetch a user by their local UUID.
  Future<UserModel?> getUserById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableUsers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final profile = await getProfileByUserId(id);
    return UserModel.fromMap(rows.first, profile: profile);
  }

  /// Fetch a user by their Firebase UID (used after sign-in).
  Future<UserModel?> getUserByFirebaseUid(String uid) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableUsers,
      where: 'firebase_uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final profile = await getProfileByUserId(rows.first['id'] as String);
    return UserModel.fromMap(rows.first, profile: profile);
  }

  /// Fetch a user by email (used during login validation).
  Future<UserModel?> getUserByEmail(String email) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableUsers,
      where: 'LOWER(email) = LOWER(?)',
      whereArgs: [email],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final profile = await getProfileByUserId(rows.first['id'] as String);
    return UserModel.fromMap(rows.first, profile: profile);
  }

  /// Update a user record. Only updates changed fields.
  Future<void> updateUser(UserModel user) async {
    final db = await _db.database;
    final map = user.toMap()
      ..['updated_at'] = DateTime.now().toIso8601String()
      ..['sync_status'] = 0; // mark as needing sync
    await db.transaction((txn) async {
      await txn.update(
        DatabaseSchema.tableUsers,
        map,
        where: 'id = ?',
        whereArgs: [user.id],
      );

      final profile = user.profile;
      if (profile != null) {
        final profileMap = profile.toMap()
          ..['updated_at'] = DateTime.now().toIso8601String()
          ..['sync_status'] = 0;
        await txn.insert(
          DatabaseSchema.tableProfiles,
          profileMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Soft-deletes by marking the user as suspended.
  Future<void> suspendUser(String userId) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tableUsers,
      {
        'is_suspended': 1,
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 0,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Hard-deletes a user row. Cascades to profile and dependent rows.
  Future<void> deleteUser(String userId) async {
    final db = await _db.database;
    await db.delete(
      DatabaseSchema.tableUsers,
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Bans a user (sets is_banned = 1). Used by AdminCubit.
  Future<void> banUser(String userId) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tableUsers,
      {
        'is_banned': 1,
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 0,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Returns all users — used by admin dashboards.
  Future<List<UserModel>> getAllUsers({
    String? role,
    bool includeSuspended = true,
    int page = 0,
    int pageSize = 20,
  }) async {
    final db = await _db.database;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (role != null) {
      conditions.add('role = ?');
      args.add(role);
    }
    if (!includeSuspended) {
      conditions.add('is_suspended = 0');
    }

    final where = conditions.isNotEmpty ? conditions.join(' AND ') : null;

    final rows = await db.query(
      DatabaseSchema.tableUsers,
      where: where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: pageSize,
      offset: page * pageSize,
    );

    return Future.wait(rows.map((row) async {
      final profile = await getProfileByUserId(row['id'] as String);
      return UserModel.fromMap(row, profile: profile);
    }));
  }

  /// Returns count of all users (for admin stats).
  Future<int> getUserCount({String? role}) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseSchema.tableUsers}'
      '${role != null ? " WHERE role = '$role'" : ""}',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ── Profiles Table ────────────────────────────────────────────────────────

  /// Inserts a new profile record.
  Future<void> insertProfile(ProfileModel profile) async {
    final db = await _db.database;
    await db.insert(
      DatabaseSchema.tableProfiles,
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetches the profile for a given user ID.
  Future<ProfileModel?> getProfileByUserId(String userId) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableProfiles,
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    return rows.isEmpty ? null : ProfileModel.fromMap(rows.first);
  }

  /// Updates profile fields.
  Future<void> updateProfile(ProfileModel profile) async {
    final db = await _db.database;
    final map = profile.toMap()
      ..['updated_at'] = DateTime.now().toIso8601String()
      ..['sync_status'] = 0;
    await db.update(
      DatabaseSchema.tableProfiles,
      map,
      where: 'user_id = ?',
      whereArgs: [profile.userId],
    );
  }

  /// Searches users by display name or skills — used in discover + recruiter search.
  Future<List<UserModel>> searchUsers({
    required String query,
    String? faculty,
    String? course,
    String? skill,
    int page = 0,
    int pageSize = 20,
  }) async {
    final db = await _db.database;

    final where = <String>[
      '(u.display_name LIKE ? OR p.skills LIKE ?)',
      'u.is_banned = 0',
      "u.role = 'student'",
    ];
    final args = <Object?>['%$query%', '%$query%'];

    if (faculty != null && faculty.trim().isNotEmpty) {
      where.add('p.faculty = ?');
      args.add(faculty.trim());
    }
    if (course != null && course.trim().isNotEmpty) {
      where.add('p.program_name = ?');
      args.add(course.trim());
    }
    if (skill != null && skill.trim().isNotEmpty) {
      where.add('p.skills LIKE ?');
      args.add('%${skill.trim()}%');
    }

    final sql = '''
      SELECT u.*, p.skills, p.faculty, p.program_name, p.bio
      FROM ${DatabaseSchema.tableUsers} u
      LEFT JOIN ${DatabaseSchema.tableProfiles} p ON p.user_id = u.id
      WHERE ${where.join(' AND ')}
      ORDER BY p.activity_streak DESC
      LIMIT ? OFFSET ?
    ''';

    args.add(pageSize);
    args.add(page * pageSize);

    final rows = await db.rawQuery(sql, args);

    return Future.wait(rows.map((row) async {
      final profile = await getProfileByUserId(row['id'] as String);
      return UserModel.fromMap(row, profile: profile);
    }));
  }

  // ── Sync helpers ──────────────────────────────────────────────────────────

  /// Returns users that haven't been synced to Firestore yet.
  Future<List<UserModel>> getPendingSyncUsers() async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableUsers,
      where: 'sync_status = 0',
    );
    return rows.map((r) => UserModel.fromMap(r)).toList();
  }

  /// Marks a user as synced.
  Future<void> markSynced(String userId) async {
    final db = await _db.database;
    await db.update(
      DatabaseSchema.tableUsers,
      {'sync_status': 1},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }
}
