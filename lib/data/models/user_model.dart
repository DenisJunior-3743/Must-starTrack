// lib/data/models/user_model.dart
import 'package:equatable/equatable.dart';
import '../../core/router/route_guards.dart';
import 'profile_model.dart';

class UserModel extends Equatable {
  final String id;
  final String? firebaseUid;
  final String email;
  final UserRole role;
  final String? displayName;
  final String? photoUrl;
  final bool isEmailVerified;
  final bool isSuspended;
  final bool isBanned;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ProfileModel? profile;

  const UserModel({
    required this.id,
    this.firebaseUid,
    required this.email,
    this.role = UserRole.student,
    this.displayName,
    this.photoUrl,
    this.isEmailVerified = false,
    this.isSuspended = false,
    this.isBanned = false,
    this.lastSeenAt,
    required this.createdAt,
    required this.updatedAt,
    this.profile,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, {ProfileModel? profile}) {
    return UserModel(
      id: map['id'] as String,
      firebaseUid: map['firebase_uid'] as String?,
      email: map['email'] as String,
      role: UserRole.fromString(map['role'] as String?),
      displayName: map['display_name'] as String?,
      photoUrl: map['photo_url'] as String?,
      isEmailVerified: (map['is_email_verified'] as int? ?? 0) == 1,
      isSuspended: (map['is_suspended'] as int? ?? 0) == 1,
      isBanned: (map['is_banned'] as int? ?? 0) == 1,
      lastSeenAt: map['last_seen_at'] != null ? DateTime.tryParse(map['last_seen_at'] as String) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      profile: profile,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'firebase_uid': firebaseUid, 'email': email,
    'role': role.name, 'display_name': displayName, 'photo_url': photoUrl,
    'is_email_verified': isEmailVerified ? 1 : 0,
    'is_suspended': isSuspended ? 1 : 0, 'is_banned': isBanned ? 1 : 0,
    'last_seen_at': lastSeenAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(), 'sync_status': 0,
  };

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
    id: j['id'] as String, firebaseUid: j['firebaseUid'] as String?,
    email: j['email'] as String, role: UserRole.fromString(j['role'] as String?),
    displayName: j['displayName'] as String?, photoUrl: j['photoUrl'] as String?,
    isEmailVerified: j['isEmailVerified'] as bool? ?? false,
    isSuspended: j['isSuspended'] as bool? ?? false,
    isBanned: j['isBanned'] as bool? ?? false,
    lastSeenAt: j['lastSeenAt'] != null ? DateTime.tryParse(j['lastSeenAt'] as String) : null,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'firebaseUid': firebaseUid, 'email': email, 'role': role.name,
    'displayName': displayName, 'photoUrl': photoUrl,
    'isEmailVerified': isEmailVerified, 'isSuspended': isSuspended,
    'isBanned': isBanned, 'lastSeenAt': lastSeenAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(), 'updatedAt': updatedAt.toIso8601String(),
  };

  String get firstName => displayName?.split(' ').first ?? '';
  bool get isActive => !isSuspended && !isBanned;
  bool get isStudent => role == UserRole.student;
  bool get isLecturer => role == UserRole.lecturer;
  bool get isAdminUser => role == UserRole.admin || role == UserRole.superAdmin;

  UserModel copyWith({String? id, String? firebaseUid, String? email, UserRole? role,
    String? displayName, String? photoUrl, bool? isEmailVerified, bool? isSuspended,
    bool? isBanned, DateTime? lastSeenAt, DateTime? createdAt, DateTime? updatedAt,
    ProfileModel? profile}) => UserModel(
    id: id ?? this.id, firebaseUid: firebaseUid ?? this.firebaseUid,
    email: email ?? this.email, role: role ?? this.role,
    displayName: displayName ?? this.displayName, photoUrl: photoUrl ?? this.photoUrl,
    isEmailVerified: isEmailVerified ?? this.isEmailVerified,
    isSuspended: isSuspended ?? this.isSuspended, isBanned: isBanned ?? this.isBanned,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt, createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt, profile: profile ?? this.profile,
  );

  @override
  List<Object?> get props => [id, email, role, displayName, isEmailVerified];
}
