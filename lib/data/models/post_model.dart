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
  final bool isSavedByMe;

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
    this.isSavedByMe = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PostModel.fromJson(Map<String, dynamic> j) {
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
      id: (j['id'] ?? '') as String,
      authorId: (j['authorId'] ?? j['author_id'] ?? '') as String,
      authorName: (j['authorName'] ?? j['author_name']) as String?,
      authorPhotoUrl: (j['authorPhotoUrl'] ?? j['author_photo_url']) as String?,
      authorRole: (j['authorRole'] ?? j['author_role']) as String?,
      type: (j['type'] ?? 'project') as String,
      title: (j['title'] ?? '') as String,
      description: (j['description']) as String?,
      category: (j['category']) as String?,
      tags: toStringList(j['tags']),
      faculty: (j['faculty']) as String?,
      program: (j['program']) as String?,
      skillsUsed: toStringList(j['skillsUsed'] ?? j['skills_used']),
      mediaUrls: toStringList(j['mediaUrls'] ?? j['media_urls']),
      youtubeUrl: (j['youtubeUrl'] ?? j['youtube_url']) as String?,
      externalLinks: toLinkList(j['externalLinks'] ?? j['external_links']),
      visibility: PostVisibility.values.firstWhere(
        (v) => v.name == (j['visibility']?.toString() ?? 'public'),
        orElse: () => PostVisibility.public,
      ),
      moderationStatus: ModerationStatus.values.firstWhere(
        (v) => v.name == (j['moderationStatus']?.toString() ?? j['moderation_status']?.toString() ?? 'approved'),
        orElse: () => ModerationStatus.approved,
      ),
      trustScore: (j['trustScore'] ?? j['trust_score'] ?? 100) as int,
      likeCount: (j['likeCount'] ?? j['like_count'] ?? 0) as int,
      dislikeCount: (j['dislikeCount'] ?? j['dislike_count'] ?? 0) as int,
      commentCount: (j['commentCount'] ?? j['comment_count'] ?? 0) as int,
      shareCount: (j['shareCount'] ?? j['share_count'] ?? 0) as int,
      viewCount: (j['viewCount'] ?? j['view_count'] ?? 0) as int,
      isArchived: (j['isArchived'] ?? j['is_archived'] ?? false) is int
          ? (j['isArchived'] ?? j['is_archived']) == 1
          : (j['isArchived'] ?? j['is_archived'] ?? false) as bool,
      isLikedByMe: (j['isLikedByMe'] ?? j['is_liked_by_me'] ?? false) is int
          ? (j['isLikedByMe'] ?? j['is_liked_by_me']) == 1
          : (j['isLikedByMe'] ?? j['is_liked_by_me'] ?? false) as bool,
      isSavedByMe: (j['isSavedByMe'] ?? j['is_saved_by_me'] ?? false) is int
          ? (j['isSavedByMe'] ?? j['is_saved_by_me']) == 1
          : (j['isSavedByMe'] ?? j['is_saved_by_me'] ?? false) as bool,
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
        'isSavedByMe': isSavedByMe,
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
        'is_saved_by_me': isSavedByMe,
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
    bool? isSavedByMe,
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
      isSavedByMe: isSavedByMe ?? this.isSavedByMe,
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