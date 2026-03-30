import 'package:equatable/equatable.dart';

class GroupModel extends Equatable {
  final String id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String creatorId;
  final String? creatorName;
  final int memberCount;
  final int visiblePostCount;
  final bool isDissolved;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GroupModel({
    required this.id,
    required this.name,
    this.description,
    this.avatarUrl,
    required this.creatorId,
    this.creatorName,
    this.memberCount = 1,
    this.visiblePostCount = 0,
    this.isDissolved = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupModel.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic value) {
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      return DateTime.now();
    }

    int parseInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    bool parseBool(dynamic value, {bool fallback = false}) {
      if (value is bool) return value;
      if (value is int) return value == 1;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') return true;
        if (normalized == 'false' || normalized == '0') return false;
      }
      return fallback;
    }

    String? parseNullableString(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return GroupModel(
      id: map['id'] as String,
      name: (map['name'] as String? ?? '').trim(),
      description: parseNullableString(map['description']),
      avatarUrl: parseNullableString(map['avatar_url'] ?? map['avatarUrl']),
      creatorId: (map['creator_id'] ?? map['creatorId'] ?? '') as String,
      creatorName:
          parseNullableString(map['creator_name'] ?? map['creatorName']),
      memberCount: parseInt(map['member_count'] ?? map['memberCount'], fallback: 1),
      visiblePostCount:
          parseInt(map['visible_post_count'] ?? map['visiblePostCount']),
      isDissolved:
          parseBool(map['is_dissolved'] ?? map['isDissolved'], fallback: false),
      createdAt: parseDate(map['created_at'] ?? map['createdAt']),
      updatedAt: parseDate(map['updated_at'] ?? map['updatedAt']),
    );
  }

  factory GroupModel.fromJson(Map<String, dynamic> json) => GroupModel.fromMap(json);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'avatar_url': avatarUrl,
        'creator_id': creatorId,
        'creator_name': creatorName,
        'member_count': memberCount,
        'is_dissolved': isDissolved ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'sync_status': 0,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'avatar_url': avatarUrl,
        'creator_id': creatorId,
        'creator_name': creatorName,
        'member_count': memberCount,
        'visible_post_count': visiblePostCount,
        'is_dissolved': isDissolved,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  GroupModel copyWith({
    String? id,
    String? name,
    String? description,
    String? avatarUrl,
    String? creatorId,
    String? creatorName,
    int? memberCount,
    int? visiblePostCount,
    bool? isDissolved,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      creatorId: creatorId ?? this.creatorId,
      creatorName: creatorName ?? this.creatorName,
      memberCount: memberCount ?? this.memberCount,
      visiblePostCount: visiblePostCount ?? this.visiblePostCount,
      isDissolved: isDissolved ?? this.isDissolved,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        avatarUrl,
        creatorId,
        creatorName,
        memberCount,
        visiblePostCount,
        isDissolved,
        createdAt,
        updatedAt,
      ];
}
