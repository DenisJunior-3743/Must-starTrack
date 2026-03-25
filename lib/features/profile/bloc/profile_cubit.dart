// lib/features/profile/bloc/profile_cubit.dart
//
// MUST StarTrack â€” Profile Cubit (Phase 4)
//
// Manages state for ProfileScreen and EditProfileScreen.
//
// States:
//   ProfileInitial   â€” nothing loaded yet
//   ProfileLoading   â€” loading from SQLite / Firestore
//   ProfileLoaded    â€” user + posts + follow status loaded
//   ProfileUpdating  â€” save in progress (edit profile)
//   ProfileError     â€” error with message
//
// Key methods:
//   loadProfile(userId)      â€” loads user + posts from SQLite
//   toggleFollow(userId)     â€” optimistic follow/unfollow
//   updateProfile(data)      â€” writes to SQLite + Firestore; uploads photo to Cloudinary
//
// Architecture note:
//   ProfileCubit reads from UserDao + PostDao (local SQLite).
//   On mutation it writes directly to Firestore immediately (profile changes
//   are user-critical), and also persists locally so offline reads work.

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/schema/database_schema.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/profile_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/cloudinary_service.dart';
import '../../../data/remote/firestore_service.dart';
import '../../auth/bloc/auth_cubit.dart';

// â”€â”€ States â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
  final int followerCount;
  final int followingCount;
  final int collabCount;

  const ProfileLoaded({
    required this.user,
    required this.posts,
    required this.isOwnProfile,
    this.isFollowing = false,
    this.followerCount = 0,
    this.followingCount = 0,
    this.collabCount = 0,
  });

  ProfileLoaded copyWith({
    UserModel? user,
    List<PostModel>? posts,
    bool? isOwnProfile,
    bool? isFollowing,
    int? followerCount,
    int? followingCount,
    int? collabCount,
  }) => ProfileLoaded(
    user: user ?? this.user,
    posts: posts ?? this.posts,
    isOwnProfile: isOwnProfile ?? this.isOwnProfile,
    isFollowing: isFollowing ?? this.isFollowing,
    followerCount: followerCount ?? this.followerCount,
    followingCount: followingCount ?? this.followingCount,
    collabCount: collabCount ?? this.collabCount,
  );

  @override
  List<Object?> get props => [user, posts, isOwnProfile, isFollowing, followerCount, followingCount, collabCount];
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

// â”€â”€ Cubit â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class ProfileCubit extends Cubit<ProfileState> {
  final UserDao _userDao;
  final PostDao _postDao;
  final AuthCubit _authCubit;
  final SyncQueueDao _syncQueue;
  final CloudinaryService _cloudinary;
  final FirestoreService _firestore;

  String? get _currentUserId => _authCubit.currentUser?.id;

  ProfileCubit({
    required UserDao userDao,
    required PostDao postDao,
    required AuthCubit authCubit,
    required SyncQueueDao syncQueue,
    required CloudinaryService cloudinary,
    required FirestoreService firestore,
  })  : _userDao = userDao,
        _postDao = postDao,
        _authCubit = authCubit,
        _syncQueue = syncQueue,
        _cloudinary = cloudinary,
        _firestore = firestore,
        super(const ProfileInitial());

  // â”€â”€ Load profile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Loads [userId]'s profile from local SQLite.
  /// Pass null for the current user's own profile.
  Future<void> loadProfile(String? userId) async {
    emit(const ProfileLoading());

    try {
      final currentUid = _currentUserId;
      final uid = userId ?? currentUid;
      if (uid == null) {
        emit(const ProfileError('Not signed in.'));
        return;
      }
      final isOwn = uid == currentUid;

      // Read user + posts concurrently
      final results = await Future.wait([
        _userDao.getUserById(uid),
        _postDao.getPostsByAuthor(uid, pageSize: 30),
      ]);

      final user = results[0] as UserModel?;
      final posts = results[1] as List<PostModel>;

      if (user == null) {
        emit(const ProfileError('User not found. Check your connection.'));
        return;
      }

      // Query follow status + counts from DB
      final db = await DatabaseHelper.instance.database;
      bool isFollowing = false;
      if (!isOwn && currentUid != null) {
        final rows = await db.query(
          DatabaseSchema.tableFollows,
          where: 'follower_id = ? AND followee_id = ?',
          whereArgs: [currentUid, uid],
          limit: 1,
        );
        isFollowing = rows.isNotEmpty;
      }

      final followerRows = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ${DatabaseSchema.tableFollows} WHERE followee_id = ?',
        [uid],
      );
      final followingRows = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ${DatabaseSchema.tableFollows} WHERE follower_id = ?',
        [uid],
      );
      final collabRows = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ${DatabaseSchema.tableCollabRequests} WHERE (sender_id = ? OR receiver_id = ?) AND status = ?',
        [uid, uid, 'accepted'],
      );

      final followerCount = followerRows.first['cnt'] as int? ?? 0;
      final followingCount = followingRows.first['cnt'] as int? ?? 0;
      final collabCount = collabRows.first['cnt'] as int? ?? 0;

      emit(ProfileLoaded(
        user: user,
        posts: posts,
        isOwnProfile: isOwn,
        isFollowing: isFollowing,
        followerCount: followerCount,
        followingCount: followingCount,
        collabCount: collabCount,
      ));
    } catch (e) {
      emit(ProfileError('Failed to load profile: $e'));
    }
  }

  // â”€â”€ Toggle follow / unfollow â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Optimistic update: flips isFollowing immediately, then persists.
  Future<void> toggleFollow() async {
    final current = state;
    if (current is! ProfileLoaded) return;
    final uid = _currentUserId;
    if (uid == null) return;

    // 1. Optimistic flip
    final newFollowing = !current.isFollowing;
    final followerDelta = newFollowing ? 1 : -1;
    emit(current.copyWith(
      isFollowing: newFollowing,
      followerCount: (current.followerCount + followerDelta).clamp(0, 999999),
    ));

    try {
      // 2. Persist to local SQLite follows table
      final db = await DatabaseHelper.instance.database;
      if (newFollowing) {
        await db.insert(DatabaseSchema.tableFollows, {
          'id': const Uuid().v4(),
          'follower_id': uid,
          'followee_id': current.user.id,
          'created_at': DateTime.now().millisecondsSinceEpoch.toString(),
          'sync_status': 0,
        });
      } else {
        await db.delete(DatabaseSchema.tableFollows,
          where: 'follower_id = ? AND followee_id = ?',
          whereArgs: [uid, current.user.id]);
      }
    } catch (e) {
      // Rollback on failure
      emit(current.copyWith(
        isFollowing: !newFollowing,
        followerCount: current.followerCount,
      ));
    }
  }

  // â”€â”€ Update profile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Saves edited profile data to SQLite + Firestore.
  /// If [photo] is provided it is first uploaded to Cloudinary and the
  /// resulting URL replaces [photoUrl].
  Future<void> updateProfile({
    required String displayName,
    String? bio,
    String? faculty,
    String? programme,
    int? yearOfStudy,
    List<String>? skills,
    Map<String, String>? portfolioLinks,
    String? visibility,
    File? photo,
  }) async {
    final current = state;
    if (current is! ProfileLoaded) return;

    emit(const ProfileUpdating());

    try {
      String? resolvedPhotoUrl = current.user.photoUrl;

      // Upload new photo to Cloudinary if provided
      if (photo != null) {
        if (_cloudinary.isConfigured) {
          resolvedPhotoUrl = await _cloudinary.uploadFile(
            photo,
            folder: 'avatars',
          );
        } else {
          debugPrint('[ProfileCubit] Cloudinary not configured â€“ skipping photo upload.');
        }
      }

      // Build updated user + profile
      final oldProfile = current.user.profile;
      final now = DateTime.now();
      final nextProfile = (oldProfile ?? ProfileModel(
        id: current.user.id,
        userId: current.user.id,
        createdAt: now,
        updatedAt: now,
      )).copyWith(
        bio: bio,
        faculty: faculty,
        programName: programme,
        yearOfStudy: yearOfStudy,
        skills: skills,
        portfolioLinks: portfolioLinks,
        profileVisibility: visibility,
        updatedAt: now,
      );
      final updated = current.user.copyWith(
        displayName: displayName,
        photoUrl: resolvedPhotoUrl,
        updatedAt: now,
        profile: nextProfile,
      );

      // 1. Persist locally
      await _userDao.updateUser(updated);

      // 2. Push to Firestore immediately (profile changes are user-critical)
      try {
        await _firestore.setUser(updated);
      } catch (e) {
        debugPrint('[ProfileCubit] Firestore upsert failed, enqueueing for sync: $e');
        // Fallback: enqueue for later sync
        await _syncQueue.enqueue(
          operation: 'update',
          entity: DatabaseSchema.tableUsers,
          entityId: updated.id,
          payload: updated.toJson(),
        );
      }

      // 3. Update AuthCubit in-memory user so other screens see the new photo
      _authCubit.updateCurrentUser(updated);

      // Reload posts (unchanged but re-query to keep state consistent)
      final posts = await _postDao.getPostsByAuthor(updated.id, pageSize: 30);

      emit(ProfileLoaded(
        user: updated,
        posts: posts,
        isOwnProfile: current.isOwnProfile,
        isFollowing: current.isFollowing,
        followerCount: current.followerCount,
        followingCount: current.followingCount,
        collabCount: current.collabCount,
      ));
    } catch (e) {
      emit(ProfileError('Failed to save profile: $e'));
    }
  }

  // â”€â”€ Reload â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> reload() async {
    final current = state;
    if (current is! ProfileLoaded) return;

    final uid = current.user.id;
    await loadProfile(uid == _currentUserId ? null : uid);
  }
}
