import 'package:equatable/equatable.dart';

import '../../core/constants/app_enums.dart';

class PostModel extends Equatable {
  final String id;
  final String authorId;
  final String? authorName;
  final String? authorPhotoUrl;
  final String? authorRole;

  final String type;
  final String title;
  final String? description;
  final String? category;
  final List<String> tags;
  final String? faculty;
  final String? program;

  /// Splits the comma-joined faculty string into a list.
  /// For projects this is a single entry; for opportunities it may have many.
  List<String> get faculties {
    if (faculty == null || faculty!.trim().isEmpty) return const [];
    return faculty!.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty).toList();
  }
  final List<String> skillsUsed;

  final List<String> mediaUrls;
  final String? youtubeUrl;
  final List<Map<String, String>> externalLinks;

  final PostVisibility visibility;
  final ModerationStatus moderationStatus;
  final int trustScore;

  final int likeCount;
  final int dislikeCount;
  final int commentCount;
  final int shareCount;
  final int viewCount;

  final bool isArchived;
  final bool isLikedByMe;
  final bool isDislikedByMe;
  final bool isSavedByMe;

  // ── Opportunity-specific fields ──────────────────────────────────────────
  final String? areaOfExpertise;
  final int? maxParticipants;
  final int joinCount;
  final bool isJoinedByMe;
  final DateTime? opportunityDeadline;

  final DateTime createdAt;
  final DateTime updatedAt;

  const PostModel({
    required this.id,
    required this.authorId,
    this.authorName,
    this.authorPhotoUrl,
    this.authorRole,
    this.type = 'project',
    required this.title,
    this.description,
    this.category,
    this.tags = const [],
    this.faculty,
    this.program,
    this.skillsUsed = const [],
    this.mediaUrls = const [],
    this.youtubeUrl,
    this.externalLinks = const [],
    this.visibility = PostVisibility.public,
    this.moderationStatus = ModerationStatus.approved,
    this.trustScore = 100,
    this.likeCount = 0,
    this.dislikeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.viewCount = 0,
    this.isArchived = false,
    this.isLikedByMe = false,
    this.isDislikedByMe = false,
    this.isSavedByMe = false,
    this.areaOfExpertise,
    this.maxParticipants,
    this.joinCount = 0,
    this.isJoinedByMe = false,
    this.opportunityDeadline,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PostModel.fromJson(Map<String, dynamic> j) {
    String? toNullableString(dynamic value) {
      if (value == null) return null;
      if (value is String) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      return value.toString();
    }

    String toRequiredString(dynamic value, {String fallback = ''}) {
      return toNullableString(value) ?? fallback;
    }

    int? toNullableInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    int toInt(dynamic value, {int fallback = 0}) {
      return toNullableInt(value) ?? fallback;
    }

    bool toBool(dynamic value, {bool fallback = false}) {
      if (value == null) return fallback;
      if (value is bool) return value;
      if (value is int) return value == 1;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == '1' || normalized == 'true') return true;
        if (normalized == '0' || normalized == 'false') return false;
      }
      return fallback;
    }

    List<String> toStringList(dynamic v) {
      if (v is List) {
        return v.map((e) => e.toString()).toList();
      }
      return const [];
    }

    List<Map<String, String>> toLinkList(dynamic v) {
      if (v is List) {
        return v
            .whereType<Map>()
            .map((e) => e.map((k, val) => MapEntry(k.toString(), val.toString())))
            .toList();
      }
      return const [];
    }

    final createdRaw = j['createdAt'] ?? j['created_at'];
    final updatedRaw = j['updatedAt'] ?? j['updated_at'];

    DateTime parseTime(dynamic v) {
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.now();
    }

    return PostModel(
      id: toRequiredString(j['id']),
      authorId: toRequiredString(j['authorId'] ?? j['author_id']),
      authorName: toNullableString(j['authorName'] ?? j['author_name']),
      authorPhotoUrl: toNullableString(j['authorPhotoUrl'] ?? j['author_photo_url']),
      authorRole: toNullableString(j['authorRole'] ?? j['author_role']),
      type: toRequiredString(j['type'], fallback: 'project'),
      title: toRequiredString(j['title']),
      description: toNullableString(j['description']),
      category: toNullableString(j['category']),
      tags: toStringList(j['tags']),
      faculty: toNullableString(j['faculty']),
      program: toNullableString(j['program']),
      skillsUsed: toStringList(j['skillsUsed'] ?? j['skills_used']),
      mediaUrls: toStringList(j['mediaUrls'] ?? j['media_urls']),
      youtubeUrl: toNullableString(j['youtubeUrl'] ?? j['youtube_url']),
      externalLinks: toLinkList(j['externalLinks'] ?? j['external_links']),
      visibility: PostVisibility.values.firstWhere(
        (v) => v.name == (j['visibility']?.toString() ?? 'public'),
        orElse: () => PostVisibility.public,
      ),
      moderationStatus: ModerationStatus.values.firstWhere(
        (v) => v.name == (j['moderationStatus']?.toString() ?? j['moderation_status']?.toString() ?? 'approved'),
        orElse: () => ModerationStatus.approved,
      ),
        trustScore: toInt(j['trustScore'] ?? j['trust_score'], fallback: 100),
        likeCount: toInt(j['likeCount'] ?? j['like_count']),
        dislikeCount: toInt(j['dislikeCount'] ?? j['dislike_count']),
        commentCount: toInt(j['commentCount'] ?? j['comment_count']),
        shareCount: toInt(j['shareCount'] ?? j['share_count']),
        viewCount: toInt(j['viewCount'] ?? j['view_count']),
        isArchived: toBool(j['isArchived'] ?? j['is_archived']),
        isLikedByMe: toBool(j['isLikedByMe'] ?? j['is_liked_by_me']),
        isDislikedByMe: toBool(j['isDislikedByMe'] ?? j['is_disliked_by_me']),
        isSavedByMe: toBool(j['isSavedByMe'] ?? j['is_saved_by_me']),
        areaOfExpertise: toNullableString(j['areaOfExpertise'] ?? j['area_of_expertise']),
        maxParticipants: toNullableInt(j['maxParticipants'] ?? j['max_participants']),
        joinCount: toInt(j['joinCount'] ?? j['join_count']),
        isJoinedByMe: toBool(j['isJoinedByMe'] ?? j['is_joined_by_me']),
      opportunityDeadline: j['opportunityDeadline'] != null
          ? DateTime.tryParse(j['opportunityDeadline'].toString())
          : j['opportunity_deadline'] != null
              ? DateTime.tryParse(j['opportunity_deadline'].toString())
              : null,
      createdAt: parseTime(createdRaw),
      updatedAt: parseTime(updatedRaw),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'authorRole': authorRole,
        'type': type,
        'title': title,
        'description': description,
        'category': category,
        'tags': tags,
        'faculty': faculty,
        // faculties is an array for Firestore array-contains queries.
        // For projects it holds one entry; for opportunities it may hold many.
        'faculties': faculties,
        'program': program,
        'skillsUsed': skillsUsed,
        'mediaUrls': mediaUrls,
        'youtubeUrl': youtubeUrl,
        'externalLinks': externalLinks,
        'visibility': visibility.name,
        'moderationStatus': moderationStatus.name,
        'trustScore': trustScore,
        'likeCount': likeCount,
        'dislikeCount': dislikeCount,
        'commentCount': commentCount,
        'shareCount': shareCount,
        'viewCount': viewCount,
        'isArchived': isArchived,
        'isLikedByMe': isLikedByMe,
        'isDislikedByMe': isDislikedByMe,
        'isSavedByMe': isSavedByMe,
        'areaOfExpertise': areaOfExpertise,
        'maxParticipants': maxParticipants,
        'joinCount': joinCount,
        'isJoinedByMe': isJoinedByMe,
        'opportunityDeadline': opportunityDeadline?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'author_id': authorId,
        'author_name': authorName,
        'author_photo_url': authorPhotoUrl,
        'author_role': authorRole,
        'type': type,
        'title': title,
        'description': description,
        'category': category,
        'tags': tags,
        'faculty': faculty,
        'program': program,
        'skills_used': skillsUsed,
        'media_urls': mediaUrls,
        'youtube_url': youtubeUrl,
        'external_links': externalLinks,
        'visibility': visibility.name,
        'moderation_status': moderationStatus.name,
        'trust_score': trustScore,
        'like_count': likeCount,
        'dislike_count': dislikeCount,
        'comment_count': commentCount,
        'share_count': shareCount,
        'view_count': viewCount,
        'is_archived': isArchived,
        'is_liked_by_me': isLikedByMe,
        'is_disliked_by_me': isDislikedByMe,
        'is_saved_by_me': isSavedByMe,
        'area_of_expertise': areaOfExpertise,
        'max_participants': maxParticipants,
        'join_count': joinCount,
        'is_joined_by_me': isJoinedByMe,
        'opportunity_deadline': opportunityDeadline?.toIso8601String(),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  PostModel copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? authorPhotoUrl,
    String? authorRole,
    String? type,
    String? title,
    String? description,
    String? category,
    List<String>? tags,
    String? faculty,
    String? program,
    List<String>? skillsUsed,
    List<String>? mediaUrls,
    String? youtubeUrl,
    List<Map<String, String>>? externalLinks,
    PostVisibility? visibility,
    ModerationStatus? moderationStatus,
    int? trustScore,
    int? likeCount,
    int? dislikeCount,
    int? commentCount,
    int? shareCount,
    int? viewCount,
    bool? isArchived,
    bool? isLikedByMe,
    bool? isDislikedByMe,
    bool? isSavedByMe,
    String? areaOfExpertise,
    int? maxParticipants,
    int? joinCount,
    bool? isJoinedByMe,
    DateTime? opportunityDeadline,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PostModel(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
      authorRole: authorRole ?? this.authorRole,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      faculty: faculty ?? this.faculty,
      program: program ?? this.program,
      skillsUsed: skillsUsed ?? this.skillsUsed,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      externalLinks: externalLinks ?? this.externalLinks,
      visibility: visibility ?? this.visibility,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      trustScore: trustScore ?? this.trustScore,
      likeCount: likeCount ?? this.likeCount,
      dislikeCount: dislikeCount ?? this.dislikeCount,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
      viewCount: viewCount ?? this.viewCount,
      isArchived: isArchived ?? this.isArchived,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      isDislikedByMe: isDislikedByMe ?? this.isDislikedByMe,
      isSavedByMe: isSavedByMe ?? this.isSavedByMe,
      areaOfExpertise: areaOfExpertise ?? this.areaOfExpertise,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      joinCount: joinCount ?? this.joinCount,
      isJoinedByMe: isJoinedByMe ?? this.isJoinedByMe,
      opportunityDeadline: opportunityDeadline ?? this.opportunityDeadline,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        authorId,
        title,
        category,
        likeCount,
        commentCount,
        isArchived,
        updatedAt,
      ];
}