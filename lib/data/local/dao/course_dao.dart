// lib/data/local/dao/course_dao.dart
//
// MUST StarTrack — Course Data Access Object
//
// CRUD operations for the courses table.
// All operations are local-first; SyncService handles remote sync.

import 'package:sqflite/sqflite.dart';

import '../../models/course_model.dart';
import '../database_helper.dart';
import '../schema/database_schema.dart';

class CourseDao {
  final DatabaseHelper _dbHelper;

  CourseDao(this._dbHelper);

  /// Get all active courses, sorted by name.
  Future<List<CourseModel>> getAllCourses({bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    final where = activeOnly ? 'is_active = 1' : null;
    final result = await db.query(
      DatabaseSchema.tableCourses,
      where: where,
      orderBy: 'name ASC',
    );
    return result.map(CourseModel.fromMap).toList();
  }

  /// Get courses for a specific faculty, sorted by name.
  Future<List<CourseModel>> getCoursesByFaculty(
    String facultyId, {
    bool activeOnly = true,
  }) async {
    final db = await _dbHelper.database;
    String where = 'faculty_id = ?';
    final whereArgs = <dynamic>[facultyId];
    
    if (activeOnly) {
      where += ' AND is_active = 1';
    }
    
    final result = await db.query(
      DatabaseSchema.tableCourses,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );
    return result.map(CourseModel.fromMap).toList();
  }

  /// Get a single course by ID.
  Future<CourseModel?> getCourseById(String id) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      DatabaseSchema.tableCourses,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return CourseModel.fromMap(result.first);
  }

  /// Get course by code (unique).
  Future<CourseModel?> getCourseByCode(String code) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      DatabaseSchema.tableCourses,
      where: 'code = ?',
      whereArgs: [code],
    );
    if (result.isEmpty) return null;
    return CourseModel.fromMap(result.first);
  }

  /// Create a new course.
  Future<String> createCourse(CourseModel course) async {
    final db = await _dbHelper.database;
    await db.insert(
      DatabaseSchema.tableCourses,
      course.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return course.id;
  }

  /// Update an existing course.
  Future<void> updateCourse(CourseModel course) async {
    final db = await _dbHelper.database;
    await db.update(
      DatabaseSchema.tableCourses,
      course.toMap(),
      where: 'id = ?',
      whereArgs: [course.id],
    );
  }

  /// Soft-delete a course by setting is_active = 0.
  /// Archived courses are hidden from dropdown but data is preserved.
  Future<void> archiveCourse(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      DatabaseSchema.tableCourses,
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hard-delete a course from the database.
  /// Only use during testing; in production, archive instead.
  Future<void> deleteCourse(String id) async {
    final db = await _dbHelper.database;
    await db.delete(
      DatabaseSchema.tableCourses,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Search courses by name or code (case-insensitive).
  /// Optionally filter by faculty_id.
  Future<List<CourseModel>> searchCourses(
    String query, {
    String? facultyId,
    bool activeOnly = true,
  }) async {
    final db = await _dbHelper.database;
    final searchPattern = '%$query%';
    
    String where = '(name LIKE ? OR code LIKE ?)';
    List<dynamic> whereArgs = [searchPattern, searchPattern];
    
    if (facultyId != null) {
      where += ' AND faculty_id = ?';
      whereArgs.add(facultyId);
    }
    
    if (activeOnly) {
      where += ' AND is_active = 1';
    }
    
    final result = await db.query(
      DatabaseSchema.tableCourses,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );
    return result.map(CourseModel.fromMap).toList();
  }

  /// Get count of courses for a faculty.
  Future<int> getCourseCountByFaculty(
    String facultyId, {
    bool activeOnly = true,
  }) async {
    final db = await _dbHelper.database;
    String where = 'faculty_id = ?';
    final whereArgs = <dynamic>[facultyId];
    
    if (activeOnly) {
      where += ' AND is_active = 1';
    }
    
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseSchema.tableCourses} WHERE $where',
      whereArgs,
    );
    final count = (result.first['count'] as int?) ?? 0;
    return count;
  }

  /// Get total course count.
  Future<int> getTotalCourseCount({bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    final where = activeOnly ? 'is_active = 1' : null;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseSchema.tableCourses} ${where != null ? 'WHERE $where' : ''}',
    );
    final count = (result.first['count'] as int?) ?? 0;
    return count;
  }

  /// Update sync status for a course.
  /// Used by SyncService to mark synced records.
  Future<void> updateSyncStatus(String id, int status) async {
    final db = await _dbHelper.database;
    await db.update(
      DatabaseSchema.tableCourses,
      {
        'sync_status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get all pending (not synced) courses.
  Future<List<CourseModel>> getPendingCourses() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      DatabaseSchema.tableCourses,
      where: 'sync_status = ?',
      whereArgs: [0],
    );
    return result.map(CourseModel.fromMap).toList();
  }

  /// Delete all courses for a faculty.
  /// Used when archiving a faculty.
  Future<void> deleteAllCoursesForFaculty(String facultyId) async {
    final db = await _dbHelper.database;
    await db.delete(
      DatabaseSchema.tableCourses,
      where: 'faculty_id = ?',
      whereArgs: [facultyId],
    );
  }
}
