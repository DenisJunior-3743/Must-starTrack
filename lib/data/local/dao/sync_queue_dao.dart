// lib/data/local/dao/sync_queue_dao.dart
//
// MUST StarTrack — Sync Queue DAO
//
// The sync_queue table is the heart of the offline-first architecture.
// Every write that needs to reach Firestore goes through here first.
//
// Flow:
//   1. User performs action (e.g., likes a post)
//   2. Local SQLite write succeeds → UI updates immediately
//   3. SyncQueueDao.enqueue() adds a row to sync_queue
//   4. SyncService (background) picks up rows in order
//   5. Firestore write succeeds → sync_status = 1 (done)
//   6. Failed writes increment retry_count → max_retries = 5
//   7. After 5 failures, sync_status = 2 (failed) → admin alert
//
// Retry strategy: exponential backoff
//   retry 1: 30 seconds
//   retry 2: 2 minutes
//   retry 3: 10 minutes
//   retry 4: 1 hour
//   retry 5: 6 hours

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database_helper.dart';
import '../schema/database_schema.dart';

/// One item waiting to be pushed to Firestore.
class SyncQueueItem {
  final String id;
  final String operation;   // 'create' | 'update' | 'delete'
  final String entity;      // table name e.g. 'posts'
  final String entityId;    // the row's primary key
  final Map<String, dynamic> payload;
  final int retryCount;
  final int maxRetries;
  final String? lastError;
  final DateTime createdAt;
  final DateTime? nextRetryAt;

  const SyncQueueItem({
    required this.id,
    required this.operation,
    required this.entity,
    required this.entityId,
    required this.payload,
    this.retryCount = 0,
    this.maxRetries = 5,
    this.lastError,
    required this.createdAt,
    this.nextRetryAt,
  });

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) => SyncQueueItem(
    id: map['id'] as String,
    operation: map['operation'] as String,
    entity: map['entity'] as String,
    entityId: map['entity_id'] as String,
    payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
    retryCount: map['retry_count'] as int? ?? 0,
    maxRetries: map['max_retries'] as int? ?? 5,
    lastError: map['last_error'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
    nextRetryAt: map['next_retry_at'] != null
        ? DateTime.tryParse(map['next_retry_at'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'operation': operation, 'entity': entity, 'entity_id': entityId,
    'payload': jsonEncode(payload), 'retry_count': retryCount,
    'max_retries': maxRetries, 'last_error': lastError,
    'created_at': createdAt.toIso8601String(),
    'next_retry_at': nextRetryAt?.toIso8601String(),
  };
}

typedef SyncJob = SyncQueueItem;

extension SyncJobX on SyncQueueItem {
  String get entityType => entity;
  Map<String, dynamic> get payloadJson => payload;
}

class SyncQueueDao {
  final DatabaseHelper _db;
  final _uuid = const Uuid();

  SyncQueueDao({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  /// Adds an operation to the sync queue.
  Future<void> enqueue({
    required String operation,
    required String entity,
    required String entityId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _db.database;
    final item = SyncQueueItem(
      id: _uuid.v4(),
      operation: operation,
      entity: entity,
      entityId: entityId,
      payload: payload,
      createdAt: DateTime.now(),
      nextRetryAt: DateTime.now(), // eligible immediately
    );
    await db.insert(
      DatabaseSchema.tableSyncQueue,
      item.toMap(),
    );
    debugPrint(
      '[SyncQueue] Enqueued operation=$operation entity=$entity entityId=$entityId '
      'retry=${item.retryCount} payloadKeys=${payload.keys.toList()}',
    );
  }

  Future<List<SyncQueueItem>> getReadyJobs({int limit = 50}) async {
    final items = await getPendingItems();
    if (items.length <= limit) return items;
    return items.take(limit).toList();
  }

  Future<void> deleteJob(String itemId) => markSynced(itemId);

  Future<void> incrementAttempt(String itemId, {String errorMessage = 'sync_failed'}) =>
      markFailed(itemId, errorMessage);

  Future<int> getDeadLetterCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseSchema.tableSyncQueue} WHERE retry_count >= max_retries',
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Returns all items that are eligible to retry right now.
  Future<List<SyncQueueItem>> getPendingItems() async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      DatabaseSchema.tableSyncQueue,
      where: 'retry_count < max_retries AND (next_retry_at IS NULL OR next_retry_at <= ?)',
      whereArgs: [now],
      orderBy: 'created_at ASC',
      limit: 50, // process in batches of 50
    );
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  /// Returns the total count of pending items (for the sync status indicator).
  Future<int> getPendingCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DatabaseSchema.tableSyncQueue} WHERE retry_count < max_retries',
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Deletes a successfully synced item from the queue.
  Future<void> markSynced(String itemId) async {
    final db = await _db.database;
    await db.delete(
      DatabaseSchema.tableSyncQueue,
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  /// Increments retry count with exponential backoff.
  Future<void> markFailed(String itemId, String errorMessage) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseSchema.tableSyncQueue,
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final retryCount = (rows.first['retry_count'] as int? ?? 0) + 1;
    final nextRetry = _calculateNextRetry(retryCount);

    await db.update(
      DatabaseSchema.tableSyncQueue,
      {
        'retry_count': retryCount,
        'last_error': errorMessage,
        'next_retry_at': nextRetry.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  /// Exponential backoff schedule.
  DateTime _calculateNextRetry(int retryCount) {
    final delays = [
      const Duration(seconds: 30),
      const Duration(minutes: 2),
      const Duration(minutes: 10),
      const Duration(hours: 1),
      const Duration(hours: 6),
    ];
    final delay = retryCount < delays.length
        ? delays[retryCount - 1]
        : delays.last;
    return DateTime.now().add(delay);
  }

  /// Clears all permanently failed items (retry_count >= max_retries).
  Future<void> clearFailed() async {
    final db = await _db.database;
    await db.rawDelete(
      'DELETE FROM ${DatabaseSchema.tableSyncQueue} WHERE retry_count >= max_retries',
    );
  }

  /// Clears the entire queue — used only during logout / account deletion.
  Future<void> clearAll() async {
    final db = await _db.database;
    await db.delete(DatabaseSchema.tableSyncQueue);
  }
}
