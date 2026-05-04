import 'package:equatable/equatable.dart';

import '../../core/constants/app_enums.dart';

class PostModel extends Equatable {
  final String id;
  final String authorId;
  final String? authorName;
  final String? authorPhotoUrl;
  final String? authorRole;

  final String? groupId;
  final String? groupName;
  final String? groupAvatarUrl;

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
    return faculty!
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();
  }

  final List<String> skillsUsed;

  final List<String> mediaUrls;
  final String? youtubeUrl;
  final List<Map<String, String>> externalLinks;
  final Map<String, String> ownershipAnswers;
  final Map<String, String> contentValidationAnswers;

  final PostVisibility visibility;
  final ModerationStatus moderationStatus;
  final int trustScore;
  final String? aiReviewStatus;
  final String? aiDecision;
  final double? aiConfidence;
  final Map<String, int> aiScores;
  final List<String> aiFindings;
  final List<String> aiEvidence;
  final String? aiFinalTake;
  final Map<String, dynamic> aiMediaAnalysis;
  final DateTime? aiReviewedAt;

  final int likeCount;
  final int dislikeCount;
  final int commentCount;
  final int shareCount;
  final int viewCount;

  final bool isArchived;
  final bool isLikedByMe;
  final bool isDislikedByMe;
  final bool isSavedByMe;

  // ── User action state tracking ───────────────────────────────────────────
  final bool isRatedByMe;
  final int myRatingStars;
  final bool isFollowingAuthor;
  final bool hasCollaborationRequest;
  final bool isViewedByMe;

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
    this.groupId,
    this.groupName,
    this.groupAvatarUrl,
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
    this.ownershipAnswers = const {},
    this.contentValidationAnswers = const {},
    this.visibility = PostVisibility.public,
    this.moderationStatus = ModerationStatus.approved,
    this.trustScore = 100,
    this.aiReviewStatus,
    this.aiDecision,
    this.aiConfidence,
    this.aiScores = const {},
    this.aiFindings = const [],
    this.aiEvidence = const [],
    this.aiFinalTake,
    this.aiMediaAnalysis = const {},
    this.aiReviewedAt,
    this.likeCount = 0,
    this.dislikeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.viewCount = 0,
    this.isArchived = false,
    this.isLikedByMe = false,
    this.isDislikedByMe = false,
    this.isSavedByMe = false,
    this.isRatedByMe = false,
    this.myRatingStars = 0,
    this.isFollowingAuthor = false,
    this.hasCollaborationRequest = false,
    this.isViewedByMe = false,
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
            .map((e) =>
                e.map((k, val) => MapEntry(k.toString(), val.toString())))
            .toList();
      }
      return const [];
    }

    Map<String, String> toStringMap(dynamic v) {
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val.toString()));
      }
      return const {};
    }

    Map<String, int> toScoreMap(dynamic v) {
      if (v is Map) {
        return v.map((k, val) {
          final parsed = toInt(val);
          return MapEntry(k.toString(), parsed.clamp(0, 100));
        });
      }
      return const {};
    }

    Map<String, dynamic> toDynamicMap(dynamic v) {
      if (v is Map<String, dynamic>) return Map<String, dynamic>.from(v);
      if (v is Map) {
        return v.map((key, value) => MapEntry(key.toString(), value));
      }
      return const {};
    }

    double? toNullableDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value.trim());
      return null;
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
      authorPhotoUrl:
          toNullableString(j['authorPhotoUrl'] ?? j['author_photo_url']),
      authorRole: toNullableString(j['authorRole'] ?? j['author_role']),
      groupId: toNullableString(j['groupId'] ?? j['group_id']),
      groupName: toNullableString(j['groupName'] ?? j['group_name']),
      groupAvatarUrl:
          toNullableString(j['groupAvatarUrl'] ?? j['group_avatar_url']),
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
      ownershipAnswers:
          toStringMap(j['ownershipAnswers'] ?? j['ownership_answers']),
      contentValidationAnswers: toStringMap(
          j['contentValidationAnswers'] ?? j['content_validation_answers']),
      visibility: PostVisibility.values.firstWhere(
        (v) => v.name == (j['visibility']?.toString() ?? 'public'),
        orElse: () => PostVisibility.public,
      ),
      moderationStatus: ModerationStatus.values.firstWhere(
        (v) =>
            v.name ==
            (j['moderationStatus']?.toString() ??
                j['moderation_status']?.toString() ??
                'approved'),
        orElse: () => ModerationStatus.approved,
      ),
      trustScore: toInt(j['trustScore'] ?? j['trust_score'], fallback: 100),
      aiReviewStatus:
          toNullableString(j['aiReviewStatus'] ?? j['ai_review_status']),
      aiDecision: toNullableString(j['aiDecision'] ?? j['ai_decision']),
      aiConfidence: toNullableDouble(j['aiConfidence'] ?? j['ai_confidence']),
      aiScores: toScoreMap(j['aiScores'] ?? j['ai_scores']),
      aiFindings: toStringList(j['aiFindings'] ?? j['ai_findings']),
      aiEvidence: toStringList(j['aiEvidence'] ?? j['ai_evidence']),
      aiFinalTake: toNullableString(j['aiFinalTake'] ?? j['ai_final_take']),
      aiMediaAnalysis:
          toDynamicMap(j['aiMediaAnalysis'] ?? j['ai_media_analysis']),
      aiReviewedAt: j['aiReviewedAt'] != null
          ? DateTime.tryParse(j['aiReviewedAt'].toString())
          : j['ai_reviewed_at'] != null
              ? DateTime.tryParse(j['ai_reviewed_at'].toString())
              : null,
      likeCount: toInt(j['likeCount'] ?? j['like_count']),
      dislikeCount: toInt(j['dislikeCount'] ?? j['dislike_count']),
      commentCount: toInt(j['commentCount'] ?? j['comment_count']),
      shareCount: toInt(j['shareCount'] ?? j['share_count']),
      viewCount: toInt(j['viewCount'] ?? j['view_count']),
      isArchived: toBool(j['isArchived'] ?? j['is_archived']),
      isLikedByMe: toBool(j['isLikedByMe'] ?? j['is_liked_by_me']),
      isDislikedByMe: toBool(j['isDislikedByMe'] ?? j['is_disliked_by_me']),
      isSavedByMe: toBool(j['isSavedByMe'] ?? j['is_saved_by_me']),
      isRatedByMe: toBool(j['isRatedByMe'] ?? j['is_rated_by_me']),
      myRatingStars: toInt(j['myRatingStars'] ?? j['my_rating_stars']),
      isFollowingAuthor:
          toBool(j['isFollowingAuthor'] ?? j['is_following_author']),
      hasCollaborationRequest: toBool(
          j['hasCollaborationRequest'] ?? j['has_collaboration_request']),
      isViewedByMe: toBool(j['isViewedByMe'] ?? j['is_viewed_by_me']),
      areaOfExpertise:
          toNullableString(j['areaOfExpertise'] ?? j['area_of_expertise']),
      maxParticipants:
          toNullableInt(j['maxParticipants'] ?? j['max_participants']),
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
        'groupId': groupId,
        'groupName': groupName,
        'groupAvatarUrl': groupAvatarUrl,
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
        'ownershipAnswers': ownershipAnswers,
        'contentValidationAnswers': contentValidationAnswers,
        'visibility': visibility.name,
        'moderationStatus': moderationStatus.name,
        'trustScore': trustScore,
        'aiReviewStatus': aiReviewStatus,
        'aiDecision': aiDecision,
        'aiConfidence': aiConfidence,
        'aiScores': aiScores,
        'aiFindings': aiFindings,
        'aiEvidence': aiEvidence,
        'aiFinalTake': aiFinalTake,
        'aiMediaAnalysis': aiMediaAnalysis,
        'aiReviewedAt': aiReviewedAt?.toIso8601String(),
        'likeCount': likeCount,
        'dislikeCount': dislikeCount,
        'commentCount': commentCount,
        'shareCount': shareCount,
        'viewCount': viewCount,
        'isArchived': isArchived,
        'isLikedByMe': isLikedByMe,
        'isDislikedByMe': isDislikedByMe,
        'isSavedByMe': isSavedByMe,
        'isRatedByMe': isRatedByMe,
        'myRatingStars': myRatingStars,
        'isFollowingAuthor': isFollowingAuthor,
        'hasCollaborationRequest': hasCollaborationRequest,
        'isViewedByMe': isViewedByMe,
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
        'group_id': groupId,
        'group_name': groupName,
        'group_avatar_url': groupAvatarUrl,
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
        'ownership_answers': ownershipAnswers,
        'content_validation_answers': contentValidationAnswers,
        'visibility': visibility.name,
        'moderation_status': moderationStatus.name,
        'trust_score': trustScore,
        'ai_review_status': aiReviewStatus,
        'ai_decision': aiDecision,
        'ai_confidence': aiConfidence,
        'ai_scores': aiScores,
        'ai_findings': aiFindings,
        'ai_evidence': aiEvidence,
        'ai_final_take': aiFinalTake,
        'ai_media_analysis': aiMediaAnalysis,
        'ai_reviewed_at': aiReviewedAt?.toIso8601String(),
        'like_count': likeCount,
        'dislike_count': dislikeCount,
        'comment_count': commentCount,
        'share_count': shareCount,
        'view_count': viewCount,
        'is_archived': isArchived,
        'is_liked_by_me': isLikedByMe,
        'is_disliked_by_me': isDislikedByMe,
        'is_saved_by_me': isSavedByMe,
        'is_rated_by_me': isRatedByMe,
        'my_rating_stars': myRatingStars,
        'is_following_author': isFollowingAuthor,
        'has_collaboration_request': hasCollaborationRequest,
        'is_viewed_by_me': isViewedByMe,
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
    String? groupId,
    String? groupName,
    String? groupAvatarUrl,
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
    Map<String, String>? ownershipAnswers,
    Map<String, String>? contentValidationAnswers,
    PostVisibility? visibility,
    ModerationStatus? moderationStatus,
    int? trustScore,
    String? aiReviewStatus,
    String? aiDecision,
    double? aiConfidence,
    Map<String, int>? aiScores,
    List<String>? aiFindings,
    List<String>? aiEvidence,
    String? aiFinalTake,
    Map<String, dynamic>? aiMediaAnalysis,
    DateTime? aiReviewedAt,
    int? likeCount,
    int? dislikeCount,
    int? commentCount,
    int? shareCount,
    int? viewCount,
    bool? isArchived,
    bool? isLikedByMe,
    bool? isDislikedByMe,
    bool? isSavedByMe,
    bool? isRatedByMe,
    int? myRatingStars,
    bool? isFollowingAuthor,
    bool? hasCollaborationRequest,
    bool? isViewedByMe,
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
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      groupAvatarUrl: groupAvatarUrl ?? this.groupAvatarUrl,
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
      ownershipAnswers: ownershipAnswers ?? this.ownershipAnswers,
      contentValidationAnswers:
          contentValidationAnswers ?? this.contentValidationAnswers,
      visibility: visibility ?? this.visibility,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      trustScore: trustScore ?? this.trustScore,
      aiReviewStatus: aiReviewStatus ?? this.aiReviewStatus,
      aiDecision: aiDecision ?? this.aiDecision,
      aiConfidence: aiConfidence ?? this.aiConfidence,
      aiScores: aiScores ?? this.aiScores,
      aiFindings: aiFindings ?? this.aiFindings,
      aiEvidence: aiEvidence ?? this.aiEvidence,
      aiFinalTake: aiFinalTake ?? this.aiFinalTake,
      aiMediaAnalysis: aiMediaAnalysis ?? this.aiMediaAnalysis,
      aiReviewedAt: aiReviewedAt ?? this.aiReviewedAt,
      likeCount: likeCount ?? this.likeCount,
      dislikeCount: dislikeCount ?? this.dislikeCount,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
      viewCount: viewCount ?? this.viewCount,
      isArchived: isArchived ?? this.isArchived,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      isDislikedByMe: isDislikedByMe ?? this.isDislikedByMe,
      isSavedByMe: isSavedByMe ?? this.isSavedByMe,
      isRatedByMe: isRatedByMe ?? this.isRatedByMe,
      myRatingStars: myRatingStars ?? this.myRatingStars,
      isFollowingAuthor: isFollowingAuthor ?? this.isFollowingAuthor,
      hasCollaborationRequest:
          hasCollaborationRequest ?? this.hasCollaborationRequest,
      isViewedByMe: isViewedByMe ?? this.isViewedByMe,
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
        groupId,
        groupName,
        title,
        category,
        moderationStatus,
        trustScore,
        aiReviewStatus,
        aiDecision,
        aiConfidence,
        aiScores,
        ownershipAnswers,
        contentValidationAnswers,
        aiFindings,
        aiEvidence,
        aiFinalTake,
        aiMediaAnalysis,
        aiReviewedAt,
        likeCount,
        dislikeCount,
        commentCount,
        shareCount,
        viewCount,
        isLikedByMe,
        isDislikedByMe,
        isRatedByMe,
        myRatingStars,
        isFollowingAuthor,
        hasCollaborationRequest,
        isViewedByMe,
        isArchived,
        updatedAt,
      ];
}
