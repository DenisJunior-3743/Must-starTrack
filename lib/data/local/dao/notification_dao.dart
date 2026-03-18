// lib/data/local/dao/notification_dao.dart
//
// MUST StarTrack — Notification DAO (Phase 4)
//
// Handles all SQLite operations for notifications:
//   • insertNotification     — write new notification
//   • getNotifications       — paginated, filterable by type
//   • markAsRead             — single notification
//   • markAllRead            — all notifications for user
//   • deleteNotification     — remove one
//   • clearOlderThan         — housekeeping (called weekly)
//   • getUnreadCount         — badge count
//
// Notification types (matches _NType enum in NotificationCenterScreen):
//   collaboration | message | opportunity | achievement | endorsement | system
//
// Schema table used:
//   notifications(id, user_id, type, sender_id, sender_name,
//                 sender_photo_url, body, detail, entity_id,
//                 created_at, is_read, extra_json)

import 'dart:convert';
import 'dart:async';
import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';

// ── Notification model ────────────────────────────────────────────────────────

class NotificationModel {
  final String id;
  final String userId;
  final String type; // collaboration|message|opportunity|achievement|endorsement|system
  final String? senderId;
  final String? senderName;
  final String? senderPhotoUrl;
  final String body;
  final String? detail;
  final String? entityId; // postId / userId / skillName depending on type
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic> extra; // extensible payload (skill name, streak count, etc.)

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    this.senderId,
    this.senderName,
    this.senderPhotoUrl,
    required this.body,
    this.detail,
    this.entityId,
    required this.createdAt,
    this.isRead = false,
    this.extra = const {},
  });

  factory NotificationModel.fromMap(Map<String, dynamic> m) {
    Map<String, dynamic> extra = {};
    try {
      if (m['extra_json'] != null) {
        extra = jsonDecode(m['extra_json'] as String) as Map<String, dynamic>;
      }
    } catch (_) {}

    return NotificationModel(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      type: m['type'] as String,
      senderId: m['sender_id'] as String?,
      senderName: m['sender_name'] as String?,
      senderPhotoUrl: m['sender_photo_url'] as String?,
      body: m['body'] as String,
      detail: m['detail'] as String?,
      entityId: m['entity_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      isRead: (m['is_read'] as int? ?? 0) == 1,
      extra: extra,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'type': type,
    'sender_id': senderId,
    'sender_name': senderName,
    'sender_photo_url': senderPhotoUrl,
    'body': body,
    'detail': detail,
    'entity_id': entityId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'is_read': isRead ? 1 : 0,
    'extra_json': extra.isEmpty ? null : jsonEncode(extra),
  };
}

// ── DAO ───────────────────────────────────────────────────────────────────────

class NotificationDao {
  final _db = DatabaseHelper.instance;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  void _notifyChanged() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  // ── Insert ───────────────────────────────────────────────────────────────

  /// Inserts [notification]. Uses REPLACE to handle FCM deduplication
  /// (same notification ID may arrive twice if network is flaky).
  Future<void> insertNotification(NotificationModel notification) async {
    final db = await _db.database;
    await db.insert(
      'notifications',
      notification.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyChanged();
  }

  // ── Paginated query ──────────────────────────────────────────────────────

  /// Fetches notifications for [userId].
  /// Pass [type] to filter by category tab (null = all).
  /// Cursor-based pagination using [before] timestamp.
  Future<List<NotificationModel>> getNotifications({
    required String userId,
    String? type,
    int pageSize = 40,
    DateTime? before,
  }) async {
    final db = await _db.database;

    final args = <dynamic>[userId];
    final filters = <String>['user_id = ?'];

    if (type != null) {
      filters.add('type = ?');
      args.add(type);
    }

    if (before != null) {
      filters.add('created_at < ?');
      args.add(before.millisecondsSinceEpoch);
    }

    final where = filters.join(' AND ');

    final rows = await db.rawQuery('''
      SELECT * FROM notifications
      WHERE $where
      ORDER BY created_at DESC
      LIMIT ?
    ''', [...args, pageSize]);

    return rows.map(NotificationModel.fromMap).toList();
  }

  // ── Mark single as read ──────────────────────────────────────────────────

  Future<void> markAsRead(String notificationId) async {
    final db = await _db.database;
    await db.update(
      'notifications',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [notificationId],
    );
    _notifyChanged();
  }

  // ── Mark all as read ─────────────────────────────────────────────────────

  Future<void> markAllRead(String userId) async {
    final db = await _db.database;
    await db.update(
      'notifications',
      {'is_read': 1},
      where: 'user_id = ? AND is_read = 0',
      whereArgs: [userId],
    );
    _notifyChanged();
  }

  // ── Respond to collaboration request ────────────────────────────────────

  /// Sets extra_json.accepted = true/false so the UI can show the resolved state.
  Future<void> respondToCollabRequest({
    required String notificationId,
    required bool accepted,
  }) async {
    final db = await _db.database;

    // Read current extra, update, write back
    final rows = await db.query(
      'notifications',
      columns: ['extra_json'],
      where: 'id = ?',
      whereArgs: [notificationId],
    );

    if (rows.isEmpty) return;

    Map<String, dynamic> extra = {};
    try {
      final raw = rows.first['extra_json'] as String?;
      if (raw != null) extra = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}

    extra['accepted'] = accepted;

    await db.update(
      'notifications',
      {'extra_json': jsonEncode(extra), 'is_read': 1},
      where: 'id = ?',
      whereArgs: [notificationId],
    );
    _notifyChanged();
  }

  // ── Delete one ───────────────────────────────────────────────────────────

  Future<void> deleteNotification(String notificationId) async {
    final db = await _db.database;
    await db.delete(
      'notifications',
      where: 'id = ?',
      whereArgs: [notificationId],
    );
    _notifyChanged();
  }

  // ── Housekeeping ─────────────────────────────────────────────────────────

  /// Removes read notifications older than [days] (default 30).
  /// Call from a background isolate weekly to prevent DB bloat.
  Future<int> clearOlderThan({required String userId, int days = 30}) async {
    final db = await _db.database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;

    final deleted = await db.delete(
      'notifications',
      where: 'user_id = ? AND is_read = 1 AND created_at < ?',
      whereArgs: [userId, cutoff],
    );
    if (deleted > 0) {
      _notifyChanged();
    }
    return deleted;
  }

  Future<void> dispose() async {
    await _changes.close();
  }

  // ── Unread count (nav badge) ─────────────────────────────────────────────

  Future<int> getUnreadCount(String userId) async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM notifications
      WHERE user_id = ? AND is_read = 0
    ''', [userId]);
    return result.first['cnt'] as int? ?? 0;
  }
}
