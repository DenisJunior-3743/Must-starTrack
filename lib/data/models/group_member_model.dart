import 'package:equatable/equatable.dart';

class GroupMemberModel extends Equatable {
  final String id;
  final String groupId;
  final String? groupName;
  final String userId;
  final String? userName;
  final String? userPhotoUrl;
  final String role;
  final String status;
  final String? invitedBy;
  final String? invitedByName;
  final DateTime? joinedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GroupMemberModel({
    required this.id,
    required this.groupId,
    this.groupName,
    required this.userId,
    this.userName,
    this.userPhotoUrl,
    this.role = 'member',
    this.status = 'pending',
    this.invitedBy,
    this.invitedByName,
    this.joinedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => status == 'active';
  bool get canManage => isActive && (role == 'owner' || role == 'admin');

  factory GroupMemberModel.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic value) {
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic value) {
      if (value == null) return null;
      if (value is String) return DateTime.tryParse(value);
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      return null;
    }

    String? parseNullableString(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return GroupMemberModel(
      id: map['id'] as String,
      groupId: (map['group_id'] ?? map['groupId'] ?? '') as String,
      groupName: parseNullableString(map['group_name'] ?? map['groupName']),
      userId: (map['user_id'] ?? map['userId'] ?? '') as String,
      userName: parseNullableString(map['user_name'] ?? map['userName']),
      userPhotoUrl:
          parseNullableString(map['user_photo_url'] ?? map['userPhotoUrl']),
      role: (map['role'] as String? ?? 'member').trim(),
      status: (map['status'] as String? ?? 'pending').trim(),
      invitedBy: parseNullableString(map['invited_by'] ?? map['invitedBy']),
      invitedByName:
          parseNullableString(map['invited_by_name'] ?? map['invitedByName']),
      joinedAt: parseNullableDate(map['joined_at'] ?? map['joinedAt']),
      createdAt: parseDate(map['created_at'] ?? map['createdAt']),
      updatedAt: parseDate(map['updated_at'] ?? map['updatedAt']),
    );
  }

  factory GroupMemberModel.fromJson(Map<String, dynamic> json) =>
      GroupMemberModel.fromMap(json);

  Map<String, dynamic> toMap() => {
        'id': id,
        'group_id': groupId,
        'user_id': userId,
        'user_name': userName,
        'user_photo_url': userPhotoUrl,
        'role': role,
        'status': status,
        'invited_by': invitedBy,
        'invited_by_name': invitedByName,
        'joined_at': joinedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'sync_status': 0,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'group_id': groupId,
        'group_name': groupName,
        'user_id': userId,
        'user_name': userName,
        'user_photo_url': userPhotoUrl,
        'role': role,
        'status': status,
        'invited_by': invitedBy,
        'invited_by_name': invitedByName,
        'joined_at': joinedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  GroupMemberModel copyWith({
    String? id,
    String? groupId,
    String? groupName,
    String? userId,
    String? userName,
    String? userPhotoUrl,
    String? role,
    String? status,
    String? invitedBy,
    String? invitedByName,
    DateTime? joinedAt,
    bool clearJoinedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GroupMemberModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhotoUrl: userPhotoUrl ?? this.userPhotoUrl,
      role: role ?? this.role,
      status: status ?? this.status,
      invitedBy: invitedBy ?? this.invitedBy,
      invitedByName: invitedByName ?? this.invitedByName,
      joinedAt: clearJoinedAt ? null : joinedAt ?? this.joinedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        groupId,
        groupName,
        userId,
        userName,
        userPhotoUrl,
        role,
        status,
        invitedBy,
        invitedByName,
        joinedAt,
        createdAt,
        updatedAt,
      ];
}
