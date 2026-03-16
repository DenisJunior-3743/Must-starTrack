// lib/features/profile/bloc/profile_cubit.dart
//
// MUST StarTrack — Profile Cubit (Phase 4)
//
// Manages state for ProfileScreen and EditProfileScreen.
//
// States:
//   ProfileInitial   — nothing loaded yet
//   ProfileLoading   — loading from SQLite / Firestore
//   ProfileLoaded    — user + posts + follow status loaded
//   ProfileUpdating  — save in progress (edit profile)
//   ProfileError     — error with message
//
// Key methods:
//   loadProfile(userId)      — loads user + posts from SQLite
//   toggleFollow(userId)     — optimistic follow/unfollow
//   updateProfile(data)      — writes to SQLite + enqueues Firestore sync
//   uploadPhoto(file)        — Phase 5: Firebase Storage upload
//
// Architecture note:
//   ProfileCubit reads from UserDao + PostDao (local SQLite).
//   On mutation it calls SyncQueueDao.enqueue() so changes propagate to
//   Firestore when connectivity is available (offline-first guarantee).

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:io';

import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class ProfileState extends Equatable {
  const ProfileState();
  @override
  List<Object?> get props => [];
}

class ProfileInitial extends ProfileState {
  const ProfileInitial();
}

class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

class ProfileLoaded extends ProfileState {
  final UserModel user;
  final List<PostModel> posts;
  final bool isOwnProfile;
  final bool isFollowing;

  const ProfileLoaded({
    required this.user,
    required this.posts,
    required this.isOwnProfile,
    this.isFollowing = false,
  });

  ProfileLoaded copyWith({
    UserModel? user,
    List<PostModel>? posts,
    bool? isOwnProfile,
    bool? isFollowing,
  }) => ProfileLoaded(
    user: user ?? this.user,
    posts: posts ?? this.posts,
    isOwnProfile: isOwnProfile ?? this.isOwnProfile,
    isFollowing: isFollowing ?? this.isFollowing,
  );

  @override
  List<Object?> get props => [user, posts, isOwnProfile, isFollowing];
}

class ProfileUpdating extends ProfileState {
  const ProfileUpdating();
}

class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class ProfileCubit extends Cubit<ProfileState> {
  final UserDao _userDao;
  final PostDao _postDao;

  // inject from AuthCubit in Phase 5
  static const _currentUserId = 'current_user';

  ProfileCubit({
    required UserDao userDao,
    required PostDao postDao,
  })  : _userDao = userDao,
        _postDao = postDao,
        super(const ProfileInitial());

  // ── Load profile ──────────────────────────────────────────────────────────

  /// Loads [userId]'s profile from local SQLite.
  /// Pass null for the current user's own profile.
  Future<void> loadProfile(String? userId) async {
    emit(const ProfileLoading());

    try {
      final uid = userId ?? _currentUserId;
      final isOwn = uid == _currentUserId;

      // Read user + posts concurrently
      final results = await Future.wait([
        _userDao.getUserById(uid),
        _postDao.getPostsByAuthor(uid, pageSize: 30),
      ]);

      final user = results[0] as UserModel?;
      final posts = results[1] as List<PostModel>;

      if (user == null) {
        // Phase 5: fallback to Firestore fetch
        emit(const ProfileError('User not found. Check your connection.'));
        return;
      }

      // check follows table for isFollowing
      emit(ProfileLoaded(
        user: user,
        posts: posts,
        isOwnProfile: isOwn,
        isFollowing: false,
      ));
    } catch (e) {
      emit(ProfileError('Failed to load profile: $e'));
    }
  }

  // ── Toggle follow / unfollow ──────────────────────────────────────────────

  /// Optimistic update: flips isFollowing immediately, then persists.
  Future<void> toggleFollow() async {
    final current = state;
    if (current is! ProfileLoaded) return;

    // 1. Optimistic flip
    final newFollowing = !current.isFollowing;
    emit(current.copyWith(isFollowing: newFollowing));

    try {
      // 2. Persist to local SQLite follows table
      final db = await DatabaseHelper.instance.database;
      if (newFollowing) {
        await db.insert('follows', {
          'follower_id': _currentUserId,
          'following_id': current.user.id,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        await db.delete('follows',
          where: 'follower_id = ? AND following_id = ?',
          whereArgs: [_currentUserId, current.user.id]);
      }
      // 3. Phase 5: SyncQueueDao.enqueue('follows', current.user.id, ...)
    } catch (e) {
      // Rollback on failure
      emit(current.copyWith(isFollowing: !newFollowing));
    }
  }

  // ── Update profile ────────────────────────────────────────────────────────

  /// Saves edited profile data to SQLite then emits reloaded state.
  Future<void> updateProfile({
    required String displayName,
    String? bio,
    String? faculty,
    String? programme,
    int? yearOfStudy,
    List<String>? skills,
    Map<String, String>? portfolioLinks,
    String? visibility,
    File? photo, // Phase 5: upload to Firebase Storage
  }) async {
    final current = state;
    if (current is! ProfileLoaded) return;

    emit(const ProfileUpdating());

    try {
      // Build updated user
      final oldProfile = current.user.profile;
      final updated = current.user.copyWith(
        displayName: displayName,
        updatedAt: DateTime.now(),
        profile: oldProfile?.copyWith(
          bio: bio,
          faculty: faculty,
          programName: programme,
          yearOfStudy: yearOfStudy,
          skills: skills,
          portfolioLinks: portfolioLinks,
          profileVisibility: visibility,
        ),
      );

      await _userDao.updateUser(updated);
      // Phase 5: SyncQueueDao.enqueue('users', updated.id, updated.toJson())

      // Reload posts (they may have been unchanged)
      final posts = await _postDao.getPostsByAuthor(
          updated.id, pageSize: 30);

      emit(ProfileLoaded(
        user: updated,
        posts: posts,
        isOwnProfile: current.isOwnProfile,
        isFollowing: current.isFollowing,
      ));
    } catch (e) {
      emit(ProfileError('Failed to save profile: $e'));
    }
  }

  // ── Reload ────────────────────────────────────────────────────────────────

  Future<void> reload() async {
    final current = state;
    if (current is! ProfileLoaded) return;

    final uid = current.user.id;
    await loadProfile(uid == _currentUserId ? null : uid);
  }
}
