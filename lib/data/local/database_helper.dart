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
      onOpen: _onOpen,
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
    if (oldVersion < 2) {
      // Notifications table was redesigned: drop old schema and recreate
      // with the columns the DAO actually uses (sender_id, sender_name,
      // sender_photo_url, detail, entity_id, extra_json).
      await db
          .execute('DROP TABLE IF EXISTS ${DatabaseSchema.tableNotifications}');
      await db.execute(DatabaseSchema.createNotifications);
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_notif_user ON ${DatabaseSchema.tableNotifications}(user_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_notif_read ON ${DatabaseSchema.tableNotifications}(is_read)');
    }
    if (oldVersion < 3) {
      await db.execute(DatabaseSchema.createConversations);
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_conversations_user ON ${DatabaseSchema.tableConversations}(user_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_conversations_time ON ${DatabaseSchema.tableConversations}(last_message_at DESC)');

      await _ensureColumn(
          db, DatabaseSchema.tableMessages, 'conversation_id', 'TEXT');
      await _ensureColumn(db, DatabaseSchema.tableMessages, 'message_type',
          "TEXT NOT NULL DEFAULT 'text'");
      await _ensureColumn(db, DatabaseSchema.tableMessages, 'file_url', 'TEXT');
      await _ensureColumn(
          db, DatabaseSchema.tableMessages, 'file_name', 'TEXT');
      await _ensureColumn(
          db, DatabaseSchema.tableMessages, 'file_size', 'TEXT');
      await _ensureColumn(
          db, DatabaseSchema.tableMessages, 'created_at', 'INTEGER');
      await _ensureColumn(db, DatabaseSchema.tableMessages, 'is_read',
          'INTEGER NOT NULL DEFAULT 0');
      await _ensureColumn(db, DatabaseSchema.tableMessages, 'is_deleted',
          'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 4) {
      // Opportunity-specific columns on posts
      await _ensureColumn(
          db, DatabaseSchema.tablePosts, 'area_of_expertise', 'TEXT');
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'max_participants',
          'INTEGER DEFAULT 0');
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'join_count',
          'INTEGER NOT NULL DEFAULT 0');
      await _ensureColumn(
          db, DatabaseSchema.tablePosts, 'opportunity_deadline', 'TEXT');
      // Post joins table for tracking opportunity participation
      await db.execute(DatabaseSchema.createPostJoins);
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_post_joins_user ON ${DatabaseSchema.tablePostJoins}(user_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_post_joins_post ON ${DatabaseSchema.tablePostJoins}(post_id)');
    }
    if (oldVersion < 5) {
      // External links support - multiple links with descriptions
      await _ensureColumn(
          db, DatabaseSchema.tablePosts, 'external_links', "TEXT DEFAULT '[]'");
    }
    if (oldVersion < 6) {
      // Bring legacy posts tables in sync with the current feed/sync model.
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'author_name', 'TEXT');
      await _ensureColumn(
          db, DatabaseSchema.tablePosts, 'author_photo_url', 'TEXT');
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'author_role', 'TEXT');
      await _ensureColumn(
          db, DatabaseSchema.tablePosts, 'media_urls', "TEXT DEFAULT '[]'");
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'youtube_url', 'TEXT');
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'moderation_status',
          "TEXT DEFAULT 'approved'");
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'trust_score',
          'INTEGER NOT NULL DEFAULT 100');
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'is_archived',
          'INTEGER NOT NULL DEFAULT 0');

      await db.execute('''
        UPDATE ${DatabaseSchema.tablePosts}
        SET moderation_status = COALESCE(moderation_status,
          CASE WHEN status = 'rejected' THEN 'rejected' ELSE 'approved' END)
      ''');
      await db.execute('''
        UPDATE ${DatabaseSchema.tablePosts}
        SET trust_score = COALESCE(trust_score, suspicion_score, 100)
      ''');
      await db.execute('''
        UPDATE ${DatabaseSchema.tablePosts}
        SET is_archived = CASE WHEN COALESCE(status, 'published') = 'archived' THEN 1 ELSE COALESCE(is_archived, 0) END
      ''');
    }
    if (oldVersion < 7) {
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'type',
          "TEXT NOT NULL DEFAULT 'project'");
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'is_archived',
          'INTEGER NOT NULL DEFAULT 0');
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'moderation_status',
          "TEXT DEFAULT 'approved'");
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'author_name', 'TEXT');
      await _ensureColumn(
          db, DatabaseSchema.tablePosts, 'author_photo_url', 'TEXT');
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'author_role', 'TEXT');
      await _ensureColumn(
          db, DatabaseSchema.tablePosts, 'media_urls', "TEXT DEFAULT '[]'");
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'youtube_url', 'TEXT');
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'trust_score',
          'INTEGER NOT NULL DEFAULT 100');
      await db.execute('''
        UPDATE ${DatabaseSchema.tablePosts}
        SET type = COALESCE(type, 'project')
        WHERE type IS NULL OR type = ''
      ''');
    }
    if (oldVersion < 8) {
      // Ensure all critical columns exist on posts table.
      // These were added to createPosts but existing v7 databases may not have them.
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'is_archived',
          'INTEGER NOT NULL DEFAULT 0');
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'moderation_status',
          "TEXT DEFAULT 'approved'");
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'trust_score',
          'INTEGER NOT NULL DEFAULT 100');
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'type',
          "TEXT NOT NULL DEFAULT 'project'");
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'author_name', 'TEXT');
      await _ensureColumn(
          db, DatabaseSchema.tablePosts, 'author_photo_url', 'TEXT');
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'author_role', 'TEXT');
      await _ensureColumn(
          db, DatabaseSchema.tablePosts, 'media_urls', "TEXT DEFAULT '[]'");
      await _ensureColumn(db, DatabaseSchema.tablePosts, 'youtube_url', 'TEXT');

      // Update any posts that have status='archived' to set is_archived=1
      await db.execute('''
        UPDATE ${DatabaseSchema.tablePosts}
        SET is_archived = 1
        WHERE COALESCE(status, '') = 'archived' AND COALESCE(is_archived, 0) = 0
      ''');

      final schemaCheck =
          await db.rawQuery('PRAGMA table_info(${DatabaseSchema.tablePosts})');
      final schemaColumns = <String>{
        for (final col in schemaCheck) col['name'] as String? ?? '',
      };
      debugPrint(
          '[DatabaseHelper] Posts table PRAGMA check: columns=${schemaColumns.toList()}');

      final requiredCols = [
        'id',
        'is_archived',
        'moderation_status',
        'trust_score',
        'created_at',
        'updated_at',
      ];
      final missing =
          requiredCols.where((col) => !schemaColumns.contains(col)).toList();
      if (missing.isNotEmpty) {
        debugPrint(
            '[DatabaseHelper] Posts table missing columns after v8 migration: $missing');
      }

      debugPrint(
          '✅ Database v8 migration complete: posts table columns verified');
    }
    if (oldVersion < 9) {
      await _ensureColumn(
          db, DatabaseSchema.tableMessages, 'reply_to_id', 'TEXT');
      await _ensureColumn(
          db, DatabaseSchema.tableMessages, 'reply_to_preview', 'TEXT');
      debugPrint(
          '✅ Database v9 migration complete: reply columns added to messages');
    }
    if (oldVersion < 10) {
      // Create faculties and courses tables for master data management
      await db.execute(DatabaseSchema.createFaculties);
      await db.execute(DatabaseSchema.createCourses);

      // Create indexes for performance
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_courses_faculty ON ${DatabaseSchema.tableCourses}(faculty_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_courses_active ON ${DatabaseSchema.tableCourses}(is_active)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_faculties_active ON ${DatabaseSchema.tableFaculties}(is_active)');

      debugPrint(
          '✅ Database v10 migration complete: faculties and courses tables created');
    }
    if (oldVersion < 11) {
      await db.execute(DatabaseSchema.createRecommendationLogs);
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_rec_logs_user ON ${DatabaseSchema.tableRecommendationLogs}(user_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_rec_logs_algo ON ${DatabaseSchema.tableRecommendationLogs}(algorithm)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_rec_logs_time ON ${DatabaseSchema.tableRecommendationLogs}(logged_at DESC)');
      debugPrint(
          '✅ Database v11 migration complete: recommendation_logs table created');
    }
    if (oldVersion < 12) {
      await _ensureGroupSchema(db);
      debugPrint(
          '✅ Database v12 migration complete: groups and group_members created');
    }
    if (oldVersion < 13) {
      await _ensureColumn(
        db,
        DatabaseSchema.tableCollabRequests,
        'receiver_viewed_at',
        'TEXT',
      );
      debugPrint(
          '✅ Database v13 migration complete: collaboration request viewed tracking added');
    }
  }

  Future<void> _onOpen(Database db) async {
    await _ensureCoreIndexes(db);
    await _ensureGroupSchema(db);
    await _ensurePostOfflineSaveSchema(db);
    await _ensureAiReviewSchema(db);
  }

  Future<void> _ensureAiReviewSchema(Database db) async {
    await _ensureColumn(
        db, DatabaseSchema.tablePosts, 'ai_review_status', 'TEXT');
    await _ensureColumn(db, DatabaseSchema.tablePosts, 'ai_decision', 'TEXT');
    await _ensureColumn(db, DatabaseSchema.tablePosts, 'ai_confidence', 'REAL');
    await _ensureColumn(
        db, DatabaseSchema.tablePosts, 'ai_scores', "TEXT DEFAULT '{}'");
    await _ensureColumn(db, DatabaseSchema.tablePosts, 'ownership_answers',
        "TEXT DEFAULT '{}'");
    await _ensureColumn(db, DatabaseSchema.tablePosts,
        'content_validation_answers', "TEXT DEFAULT '{}'");
    await _ensureColumn(
        db, DatabaseSchema.tablePosts, 'ai_findings', "TEXT DEFAULT '[]'");
    await _ensureColumn(
        db, DatabaseSchema.tablePosts, 'ai_evidence', "TEXT DEFAULT '[]'");
    await _ensureColumn(db, DatabaseSchema.tablePosts, 'ai_final_take', 'TEXT');
    await _ensureColumn(
        db, DatabaseSchema.tablePosts, 'ai_reviewed_at', 'TEXT');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_posts_ai_review ON ${DatabaseSchema.tablePosts}(ai_review_status)',
    );
  }

  Future<void> _ensurePostOfflineSaveSchema(Database db) async {
    await _ensureColumn(
      db,
      DatabaseSchema.tablePosts,
      'is_saved_by_me',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_posts_saved ON ${DatabaseSchema.tablePosts}(is_saved_by_me)',
    );
  }

  Future<void> _ensureCoreIndexes(Database db) async {
    for (final idx in DatabaseSchema.indexes) {
      try {
        await db.execute(idx);
      } catch (error) {
        debugPrint('[DatabaseHelper] Skipped index init: $error');
      }
    }
  }

  Future<void> _ensureGroupSchema(Database db) async {
    await db.execute(DatabaseSchema.createGroups);
    await db.execute(DatabaseSchema.createGroupMembers);
    await _ensureColumn(db, DatabaseSchema.tablePosts, 'group_id', 'TEXT');
    await _ensureColumn(db, DatabaseSchema.tablePosts, 'group_name', 'TEXT');
    await _ensureColumn(
      db,
      DatabaseSchema.tablePosts,
      'group_avatar_url',
      'TEXT',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_groups_creator ON ${DatabaseSchema.tableGroups}(creator_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_groups_dissolved ON ${DatabaseSchema.tableGroups}(is_dissolved)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_group_members_group ON ${DatabaseSchema.tableGroupMembers}(group_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_group_members_user ON ${DatabaseSchema.tableGroupMembers}(user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_group_members_status ON ${DatabaseSchema.tableGroupMembers}(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_posts_group ON ${DatabaseSchema.tablePosts}(group_id)',
    );
  }

  Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final hasColumn = rows.any((row) => row['name'] == column);
    if (!hasColumn) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
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
        DatabaseSchema.tableConversations,
        DatabaseSchema.tableMessageThreads,
        DatabaseSchema.tableCollabRequests,
        DatabaseSchema.tableFollows,
        DatabaseSchema.tableDislikes,
        DatabaseSchema.tableLikes,
        DatabaseSchema.tableComments,
        DatabaseSchema.tableGroupMembers,
        DatabaseSchema.tablePosts,
        DatabaseSchema.tableGroups,
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
