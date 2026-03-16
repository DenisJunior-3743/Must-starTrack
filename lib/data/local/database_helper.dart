// lib/data/local/database_helper.dart
//
// MUST StarTrack — SQLite Database Helper (Singleton)
//
// Manages the lifecycle of the local SQLite database:
//   - Opens / creates the database on first launch
//   - Runs all CREATE TABLE and index statements
//   - Provides the shared Database instance to all DAOs
//   - Handles future migration via onUpgrade
//
// Design: Singleton pattern ensures only one database connection
// exists app-wide, preventing "database locked" race conditions.
//
// Offline-first principle: This is always the first read target.
// The app reads from here, writes here, then syncs to Firestore.

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'schema/database_schema.dart';

class DatabaseHelper {
  // ── Singleton ─────────────────────────────────────────────────────────────
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();
  factory DatabaseHelper() => instance;

  Database? _database;

  /// Returns the open database, initialising it on first access.
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, DatabaseSchema.databaseName);

    debugPrint('📦 StarTrack DB → $path');

    return openDatabase(
      path,
      version: DatabaseSchema.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      // Enable foreign key enforcement — SQLite disables this by default.
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // WAL mode improves concurrent read performance (feeds, etc).
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
    );
  }

  /// Called once when the database file does not yet exist.
  Future<void> _onCreate(Database db, int version) async {
    debugPrint('🏗️  Creating StarTrack DB (v$version)...');

    // Wrap everything in a transaction so either all tables are
    // created or none are — no partial schema states.
    await db.transaction((txn) async {
      for (final sql in DatabaseSchema.allCreateStatements) {
        await txn.execute(sql);
      }
      for (final idx in DatabaseSchema.indexes) {
        await txn.execute(idx);
      }
    });

    debugPrint('✅ StarTrack DB created with '
        '${DatabaseSchema.allCreateStatements.length} tables '
        'and ${DatabaseSchema.indexes.length} indexes.');
  }

  /// Called when databaseVersion is bumped.
  /// Future migrations go here — do NOT touch onCreate for existing tables.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('🔄 Upgrading DB from v$oldVersion → v$newVersion');
    // Example migration pattern for future phases:
    // if (oldVersion < 2) { await db.execute('ALTER TABLE posts ADD COLUMN ...'); }
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  /// Closes the database connection.
  /// Call this only on app exit — never between operations.
  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
      debugPrint('📦 StarTrack DB closed.');
    }
  }

  /// Clears all data from all tables — used in tests and dev reset.
  /// In production this is only called from the "Delete my data" feature.
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      // Disable FK checks during bulk delete to avoid cascade ordering issues.
      await txn.rawQuery('PRAGMA foreign_keys = OFF');
      for (final table in [
        DatabaseSchema.tableActivityLogs,
        DatabaseSchema.tableAchievements,
        DatabaseSchema.tableDraftPosts,
        DatabaseSchema.tableSearchHistory,
        DatabaseSchema.tableDeviceTokens,
        DatabaseSchema.tableEndorsements,
        DatabaseSchema.tableTasks,
        DatabaseSchema.tableProjectMilestones,
        DatabaseSchema.tableModerationQueue,
        DatabaseSchema.tableSyncQueue,
        DatabaseSchema.tableOpportunities,
        DatabaseSchema.tableNotifications,
        DatabaseSchema.tableMessages,
        DatabaseSchema.tableMessageThreads,
        DatabaseSchema.tableCollabRequests,
        DatabaseSchema.tableFollows,
        DatabaseSchema.tableDislikes,
        DatabaseSchema.tableLikes,
        DatabaseSchema.tableComments,
        DatabaseSchema.tablePosts,
        DatabaseSchema.tableProfiles,
        DatabaseSchema.tableUsers,
      ]) {
        await txn.delete(table);
      }
      await txn.rawQuery('PRAGMA foreign_keys = ON');
    });
    debugPrint('🗑️  All local data cleared.');
  }

  // ── Helpers for DAOs ──────────────────────────────────────────────────────

  /// Convenience: fetch a single row by primary key.
  Future<Map<String, dynamic>?> fetchById(
    String table,
    String id,
  ) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Convenience: soft-delete by updating a flag column.
  Future<void> softDelete(
    String table,
    String id, {
    String flagColumn = 'is_deleted',
  }) async {
    final db = await database;
    await db.update(
      table,
      {flagColumn: 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
