// lib/features/notifications/bloc/notification_cubit.dart
//
// MUST StarTrack — Notification Cubit (Phase 4)
//
// States:
//   NotificationInitial    — idle
//   NotificationsLoading   — loading
//   NotificationsLoaded    — list + badge count + active filter tab
//   NotificationError      — error
//
// Key methods:
//   loadNotifications([type])  — loads all or filtered by tab
//   markRead(id)               — single read
//   markAllRead()              — clears badge
//   respondToCollab(id, bool)  — accept / decline collaboration request
//   deleteNotification(id)     — remove single
//
// Badge integration:
//   unreadCount is exposed in NotificationsLoaded.
//   MainShell subscribes to this cubit and shows the count on the
//   notifications tab icon (Phase 5: drive from FCM on app resume).

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';

import '../../../data/local/dao/notification_dao.dart';
import '../../auth/bloc/auth_cubit.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class NotificationState extends Equatable {
  const NotificationState();
  @override
  List<Object?> get props => [];
}

class NotificationInitial extends NotificationState {
  const NotificationInitial();
}

class NotificationsLoading extends NotificationState {
  const NotificationsLoading();
}

class NotificationsLoaded extends NotificationState {
  final List<NotificationModel> notifications;
  final int unreadCount;
  final String? activeFilter; // null = all

  const NotificationsLoaded({
    required this.notifications,
    required this.unreadCount,
    this.activeFilter,
  });

  NotificationsLoaded copyWith({
    List<NotificationModel>? notifications,
    int? unreadCount,
    String? activeFilter,
  }) => NotificationsLoaded(
    notifications: notifications ?? this.notifications,
    unreadCount: unreadCount ?? this.unreadCount,
    activeFilter: activeFilter ?? this.activeFilter,
  );

  @override
  List<Object?> get props => [notifications, unreadCount, activeFilter];
}

class NotificationError extends NotificationState {
  final String message;
  const NotificationError(this.message);

  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class NotificationCubit extends Cubit<NotificationState> {
  final NotificationDao _dao;
  final AuthCubit _authCubit;
  late final StreamSubscription _authSub;
  late final StreamSubscription _daoSub;

  String? get _currentUserId => _authCubit.currentUser?.id;

  NotificationCubit({required NotificationDao dao, required AuthCubit authCubit})
      : _dao = dao,
        _authCubit = authCubit,
        super(const NotificationInitial()) {
    _authSub = _authCubit.stream.listen((state) {
      if (state is AuthAuthenticated) {
        unawaited(loadNotifications());
      } else if (state is AuthUnauthenticated) {
        emit(const NotificationsLoaded(notifications: [], unreadCount: 0));
      }
    });
    _daoSub = _dao.changes.listen((_) {
      if (_currentUserId != null && !isClosed) {
        unawaited(loadNotifications(
          type: state is NotificationsLoaded
              ? (state as NotificationsLoaded).activeFilter
              : null,
        ));
      }
    });
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> loadNotifications({String? type}) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      emit(const NotificationsLoaded(notifications: [], unreadCount: 0));
      return;
    }
    emit(const NotificationsLoading());

    try {
      final results = await Future.wait([
        _dao.getNotifications(userId: uid, type: type),
        _dao.getUnreadCount(uid),
      ]);

      emit(NotificationsLoaded(
        notifications: results[0] as List<NotificationModel>,
        unreadCount: results[1] as int,
        activeFilter: type,
      ));
    } catch (e) {
      emit(NotificationError('Failed to load notifications: $e'));
    }
  }

  // ── Mark single as read ───────────────────────────────────────────────────

  Future<void> markRead(String notificationId) async {
    final current = state;
    if (current is! NotificationsLoaded) return;

    // Optimistic update
    final updated = current.notifications.map((n) =>
      n.id == notificationId
          ? NotificationModel(
              id: n.id, userId: n.userId, type: n.type,
              senderId: n.senderId, senderName: n.senderName,
              senderPhotoUrl: n.senderPhotoUrl, body: n.body,
              detail: n.detail, entityId: n.entityId,
              createdAt: n.createdAt, isRead: true, extra: n.extra)
          : n,
    ).toList();

    final newUnread = (current.unreadCount - 1).clamp(0, 9999);
    emit(current.copyWith(notifications: updated, unreadCount: newUnread));

    await _dao.markAsRead(notificationId);
  }

  // ── Mark all read ─────────────────────────────────────────────────────────

  Future<void> markAllRead() async {
    final current = state;
    if (current is! NotificationsLoaded) return;

    final updated = current.notifications.map((n) => NotificationModel(
      id: n.id, userId: n.userId, type: n.type,
      senderId: n.senderId, senderName: n.senderName,
      senderPhotoUrl: n.senderPhotoUrl, body: n.body,
      detail: n.detail, entityId: n.entityId,
      createdAt: n.createdAt, isRead: true, extra: n.extra,
    )).toList();

    emit(current.copyWith(notifications: updated, unreadCount: 0));
    final uid = _currentUserId;
    if (uid != null && uid.isNotEmpty) {
      await _dao.markAllRead(uid);
    }
  }

  // ── Respond to collaboration request ─────────────────────────────────────

  /// Accepts or declines a collaboration request in-place.
  Future<void> respondToCollab({
    required String notificationId,
    required bool accepted,
  }) async {
    await _dao.respondToCollabRequest(
      notificationId: notificationId,
      accepted: accepted,
    );

    // Reload to reflect updated extra_json
    final current = state;
    if (current is NotificationsLoaded) {
      await loadNotifications(type: current.activeFilter);
    }
  }

  // ── Delete notification ───────────────────────────────────────────────────

  Future<void> deleteNotification(String notificationId) async {
    final current = state;
    if (current is! NotificationsLoaded) return;

    final wasUnread = current.notifications
        .any((n) => n.id == notificationId && !n.isRead);

    final updated = current.notifications
        .where((n) => n.id != notificationId)
        .toList();

    emit(current.copyWith(
      notifications: updated,
      unreadCount: wasUnread
          ? (current.unreadCount - 1).clamp(0, 9999)
          : current.unreadCount,
    ));

    await _dao.deleteNotification(notificationId);
  }

  // ── Unread badge count only (for nav shell) ───────────────────────────────

  Future<int> fetchBadgeCount() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return 0;
    return _dao.getUnreadCount(uid);
  }

  @override
  Future<void> close() async {
    await _authSub.cancel();
    await _daoSub.cancel();
    return super.close();
  }
}
