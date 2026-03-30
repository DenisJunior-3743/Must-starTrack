// lib/data/local/dao/faculty_dao.dart
//
// MUST StarTrack — Faculty Data Access Object
//
// CRUD operations for the faculties table.
// All operations are local-first; SyncService handles remote sync.

import 'package:sqflite/sqflite.dart';

import '../../models/faculty_model.dart';
import '../database_helper.dart';
import '../schema/database_schema.dart';

class FacultyDao {
  final DatabaseHelper _dbHelper;

  FacultyDao(this._dbHelper);

  /// Get all active faculties, sorted by name.
  Future<List<FacultyModel>> getAllFaculties({bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    final where = activeOnly ? 'is_active = 1' : null;
    final result = await db.query(
      DatabaseSchema.tableFaculties,
      where: where,
      orderBy: 'name ASC',
    );
    return result.map(FacultyModel.fromMap).toList();
  }

  /// Get a single faculty by ID.
  Future<FacultyModel?> getFacultyById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      DatabaseSchema.tableFaculties,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return FacultyModel.fromMap(result.first);
  }

  /// Get faculty by code (unique).
  Future<FacultyModel?> getFacultyByCode(String code) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      DatabaseSchema.tableFaculties,
      where: 'code = ?',
      whereArgs: [code],
    );
    if (result.isEmpty) return null;
    return FacultyModel.fromMap(result.first);
  }

  /// Create a new faculty.
  Future<String> createFaculty(FacultyModel faculty) async {
    final db = await _dbHelper.database;
    await db.insert(
      DatabaseSchema.tableFaculties,
      faculty.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return faculty.id;
  }

  /// Update an existing faculty.
  Future<void> updateFaculty(FacultyModel faculty) async {
    final db = await _dbHelper.database;
    await db.update(
      DatabaseSchema.tableFaculties,
      faculty.toMap(),
      where: 'id = ?',
      whereArgs: [faculty.id],
    );
  }

  /// Soft-delete a faculty by setting is_active = 0.
  /// Archived faculties are hidden from dropdown but data is preserved.
  Future<void> archiveFaculty(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      DatabaseSchema.tableFaculties,
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hard-delete a faculty from the database.
  /// Only use during testing; in production, archive instead.
  Future<void> deleteFaculty(String id) async {
    final db = await _dbHelper.database;
    await db.delete(
      DatabaseSchema.tableFaculties,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Search faculties by name or code (case-insensitive).
  Future<List<FacultyModel>> searchFaculties(
    String query, {
    bool activeOnly = true,
  }) async {
    final db = await _dbHelper.database;
    final searchPattern = '%$query%';
    
    String where = '(name LIKE ? OR code LIKE ?)';
    List<dynamic> whereArgs = [searchPattern, searchPattern];
    
    if (activeOnly) {
      where += ' AND is_active = 1';
      whereArgs = [searchPattern, searchPattern];
    }
    
    final result = await db.query(
      DatabaseSchema.tableFaculties,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );
    return result.map(FacultyModel.fromMap).toList();
  }

  /// Get count of all faculties.
  Future<int> getFacultyCount({bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    final where = activeOnly ? 'is_active = 1' : null;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseSchema.tableFaculties} ${where != null ? 'WHERE $where' : ''}',
    );
    final count = (result.first['count'] as int?) ?? 0;
    return count;
  }

  /// Update sync status for a faculty.
  /// Used by SyncService to mark synced records.
  Future<void> updateSyncStatus(String id, int status) async {
    final db = await _dbHelper.database;
    await db.update(
      DatabaseSchema.tableFaculties,
      {
        'sync_status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get all pending (not synced) faculties.
  Future<List<FacultyModel>> getPendingFaculties() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      DatabaseSchema.tableFaculties,
      where: 'sync_status = ?',
      whereArgs: [0],
    );
    return result.map(FacultyModel.fromMap).toList();
  }
}
