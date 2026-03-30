import '../models/post_model.dart';
import '../models/user_model.dart';
import 'gemini_service.dart';

class RecommendedPost {
  const RecommendedPost({
    required this.post,
    required this.score,
    required this.reasons,
  });

  final PostModel post;
  final double score;
  final List<String> reasons;
}

class RecommendedUser {
  const RecommendedUser({
    required this.user,
    required this.score,
    required this.reasons,
    this.matchedSkills = const [],
  });

  final UserModel user;
  final double score;
  final List<String> reasons;
  final List<String> matchedSkills;
}

class RecommenderService {
  RecommenderService({GeminiService? geminiService})
      : _geminiService = geminiService;

  final GeminiService? _geminiService;

  List<RecommendedPost> rankLocally({
    required UserModel user,
    required List<PostModel> candidates,
    Set<String> recentlyViewedCategories = const {},
    Set<String> recentSearchTerms = const {},
    Map<String, double> lecturerRatingsByPost = const {},
    Map<String, double> studentRatingsByPost = const {},
  }) {
    final userSkills =
        user.profile?.skills.map((e) => e.toLowerCase()).toSet() ??
        const <String>{};
    final userFaculty = user.profile?.faculty?.toLowerCase();
    final userProgram = user.profile?.programName?.toLowerCase();
    final normalizedSearchTerms = _normalizeTerms(recentSearchTerms);

    final scored = candidates.map((post) {
      double score = 0.05;
      final reasons = <String>[];

      final postSkills = post.skillsUsed.map((e) => e.toLowerCase()).toSet();
      final skillOverlap = userSkills.intersection(postSkills).length;
      if (skillOverlap > 0) {
        score += 0.38 * (skillOverlap.clamp(1, 5) / 5.0);
        reasons.add('skill_match');
      }

      final postFaculty = post.faculty?.toLowerCase();
      if (userFaculty != null && postFaculty == userFaculty) {
        score += 0.14;
        reasons.add('faculty_match');
      }

      final postProgram = post.program?.toLowerCase();
      if (userProgram != null && postProgram == userProgram) {
        score += 0.10;
        reasons.add('program_match');
      }

      if (normalizedSearchTerms.isNotEmpty &&
          _matchesPostSearchIntent(post, normalizedSearchTerms)) {
        score += 0.10;
        reasons.add('search_intent');
      }

      final recencyHours = DateTime.now().difference(post.createdAt).inHours;
      final recencyScore = (1.0 - (recencyHours / (24 * 14))).clamp(0.0, 1.0);
      score += 0.13 * recencyScore;

      final engagement =
          (post.likeCount + post.commentCount * 2 + post.shareCount * 3)
              .toDouble();
      final engagementScore = (engagement / 200.0).clamp(0.0, 1.0);
      score += 0.10 * engagementScore;

      if (post.category != null &&
          recentlyViewedCategories.contains(post.category!.toLowerCase())) {
        score += 0.08;
        reasons.add('collaborative_signal');
      }

      final opportunitySkillMatch =
          post.type == 'opportunity' && skillOverlap > 0;
      if (opportunitySkillMatch) {
        score += 0.07;
        reasons.add('opportunity_fit');
      }

      final lecturerRating = lecturerRatingsByPost[post.id];
      final studentRating = studentRatingsByPost[post.id];
      final ratingBlend = _blendRoleRatings(
        lecturerRating: lecturerRating,
        studentRating: studentRating,
      );
      if (ratingBlend != null) {
        score += 0.12 * ratingBlend;
        if (lecturerRating != null) reasons.add('lecturer_rating_signal');
        if (studentRating != null) reasons.add('student_rating_signal');
      }

      return RecommendedPost(
        post: post,
        score: score.clamp(0.0, 1.0),
        reasons: reasons,
      );
    }).toList();

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return b.post.createdAt.compareTo(a.post.createdAt);
    });
    return scored;
  }

  Future<List<RecommendedPost>> rankHybrid({
    required UserModel user,
    required List<PostModel> candidates,
    Set<String> recentlyViewedCategories = const {},
    Set<String> recentSearchTerms = const {},
    Map<String, double> lecturerRatingsByPost = const {},
    Map<String, double> studentRatingsByPost = const {},
  }) async {
    final localRanked = rankLocally(
      user: user,
      candidates: candidates,
      recentlyViewedCategories: recentlyViewedCategories,
      recentSearchTerms: recentSearchTerms,
      lecturerRatingsByPost: lecturerRatingsByPost,
      studentRatingsByPost: studentRatingsByPost,
    );

    final gemini = _geminiService;
    if (gemini == null || !gemini.isConfigured || localRanked.isEmpty) {
      return localRanked;
    }

    try {
      final top = localRanked.take(25).toList();
      final geminiResponse = await gemini.rankPosts(
        userProfile: {
          'role': user.role.name,
          'faculty': user.profile?.faculty,
          'program': user.profile?.programName,
          'skills': user.profile?.skills ?? const <String>[],
          'recentSearchTerms': recentSearchTerms.toList(),
          'recentCategories': recentlyViewedCategories.toList(),
        },
        posts: top
            .map((e) => {
                  'id': e.post.id,
                  'title': e.post.title,
                  'category': e.post.category,
                  'skills': e.post.skillsUsed,
                  'faculty': e.post.faculty,
                  'program': e.post.program,
                  'type': e.post.type,
                })
            .toList(),
      );

      final ranking = (geminiResponse?['ranking'] as List?) ?? const [];
      if (ranking.isEmpty) return localRanked;

      final geminiScoreById = <String, double>{};
      for (final row in ranking) {
        if (row is Map) {
          final data = Map<String, dynamic>.from(row);
          final id = data['postId']?.toString();
          final score = (data['score'] as num?)?.toDouble();
          if (id != null && score != null) {
            geminiScoreById[id] = score.clamp(0.0, 1.0);
          }
        }
      }

      final reranked = localRanked
          .map((item) {
            final aiScore = geminiScoreById[item.post.id];
            if (aiScore == null) return item;
            final blended = (item.score * 0.65) + (aiScore * 0.35);
            return RecommendedPost(
              post: item.post,
              score: blended,
              reasons: [...item.reasons, 'gemini_rerank'],
            );
          })
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      return reranked;
    } catch (_) {
      return localRanked;
    }
  }

  List<RecommendedUser> rankCollaborators({
    required UserModel currentUser,
    required List<UserModel> candidates,
    Set<String> excludedUserIds = const {},
    Set<String> recentSearchTerms = const {},
  }) {
    final currentSkills =
        currentUser.profile?.skills.map((e) => e.toLowerCase()).toSet() ??
        const <String>{};
    final currentFaculty = currentUser.profile?.faculty?.toLowerCase();
    final currentProgram = currentUser.profile?.programName?.toLowerCase();
    final normalizedSearchTerms = _normalizeTerms(recentSearchTerms);

    final ranked = candidates.where((candidate) {
      if (candidate.id == currentUser.id) return false;
      if (excludedUserIds.contains(candidate.id)) return false;
      if (!candidate.isStudent || !candidate.isActive) return false;
      return candidate.profile != null;
    }).map((candidate) {
      final candidateSkills =
          candidate.profile?.skills.map((e) => e.toLowerCase()).toSet() ??
          const <String>{};
      final sharedSkills = currentSkills.intersection(candidateSkills).toList();
      final complementarySkills =
          candidateSkills.difference(currentSkills).take(3).toList();

      double score = 0.05;
      final reasons = <String>[];

      if (sharedSkills.isNotEmpty) {
        score += 0.34 * (sharedSkills.length.clamp(1, 4) / 4.0);
        reasons.add('skill_match');
      }

      if (sharedSkills.isEmpty && complementarySkills.isNotEmpty) {
        score += 0.18;
        reasons.add('complementary_skills');
      }

      final candidateFaculty = candidate.profile?.faculty?.toLowerCase();
      if (currentFaculty != null && candidateFaculty == currentFaculty) {
        score += 0.12;
        reasons.add('faculty_match');
      }

      final candidateProgram = candidate.profile?.programName?.toLowerCase();
      if (currentProgram != null && candidateProgram == currentProgram) {
        score += 0.08;
        reasons.add('program_match');
      }

      score += 0.16 * _scoreProfileActivity(candidate);
      score += 0.08 * _scoreProfileCompleteness(candidate);

      if (normalizedSearchTerms.isNotEmpty &&
          _matchesUserSearchIntent(candidate, normalizedSearchTerms)) {
        score += 0.09;
        reasons.add('search_intent');
      }

      return RecommendedUser(
        user: candidate,
        score: score.clamp(0.0, 1.0),
        reasons: reasons,
        matchedSkills: sharedSkills.isNotEmpty ? sharedSkills : complementarySkills,
      );
    }).toList();

    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }

  List<RecommendedUser> rankStudentsForOpportunity({
    required PostModel opportunity,
    required List<UserModel> candidates,
  }) {
    final opportunitySkills = {
      ...opportunity.skillsUsed.map((skill) => skill.toLowerCase()),
      if (opportunity.areaOfExpertise != null &&
          opportunity.areaOfExpertise!.trim().isNotEmpty)
        opportunity.areaOfExpertise!.trim().toLowerCase(),
    };
    final opportunityFaculty = opportunity.faculty?.toLowerCase();
    final opportunityProgram = opportunity.program?.toLowerCase();

    final ranked = candidates.where((candidate) => candidate.profile != null).map((candidate) {
      final candidateSkills =
          candidate.profile?.skills.map((skill) => skill.toLowerCase()).toSet() ??
          const <String>{};
      final matchedSkills = opportunitySkills.intersection(candidateSkills).toList();

      double score = 0.08;
      final reasons = <String>[];

      if (matchedSkills.isNotEmpty) {
        score += 0.42 * (matchedSkills.length.clamp(1, 4) / 4.0);
        reasons.add('skill_match');
      }

      final candidateFaculty = candidate.profile?.faculty?.toLowerCase();
      if (opportunityFaculty != null && candidateFaculty == opportunityFaculty) {
        score += 0.10;
        reasons.add('faculty_match');
      }

      final candidateProgram = candidate.profile?.programName?.toLowerCase();
      if (opportunityProgram != null && candidateProgram == opportunityProgram) {
        score += 0.08;
        reasons.add('program_match');
      }

      score += 0.16 * _scoreProfileActivity(candidate);
      score += 0.10 * _scoreProfileCompleteness(candidate);

      if ((candidate.profile?.totalCollabs ?? 0) > 0) {
        score += 0.06;
        reasons.add('collaboration_ready');
      }

      return RecommendedUser(
        user: candidate,
        score: score.clamp(0.0, 1.0),
        reasons: reasons,
        matchedSkills: matchedSkills,
      );
    }).toList();

    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }

  Set<String> _normalizeTerms(Set<String> input) => input
      .map((term) => term.trim().toLowerCase())
      .where((term) => term.isNotEmpty)
      .toSet();

  bool _matchesPostSearchIntent(PostModel post, Set<String> searchTerms) {
    final haystack = [
      post.title,
      post.description ?? '',
      post.category ?? '',
      post.faculty ?? '',
      post.program ?? '',
      ...post.skillsUsed,
      ...post.tags,
    ].join(' ').toLowerCase();

    return searchTerms.any(haystack.contains);
  }

  bool _matchesUserSearchIntent(UserModel user, Set<String> searchTerms) {
    final haystack = [
      user.displayName ?? '',
      user.email,
      user.profile?.faculty ?? '',
      user.profile?.programName ?? '',
      ...?user.profile?.skills,
    ].join(' ').toLowerCase();

    return searchTerms.any(haystack.contains);
  }

  double _scoreProfileActivity(UserModel user) {
    final profile = user.profile;
    if (profile == null) return 0;

    final streak = (profile.activityStreak / 14).clamp(0.0, 1.0);
    final posts = (profile.totalPosts / 10).clamp(0.0, 1.0);
    final collabs = (profile.totalCollabs / 6).clamp(0.0, 1.0);
    return (0.45 * streak) + (0.30 * posts) + (0.25 * collabs);
  }

  double _scoreProfileCompleteness(UserModel user) {
    final profile = user.profile;
    if (profile == null) return 0;

    final completedFields = [
      profile.bio?.trim().isNotEmpty == true,
      profile.faculty?.trim().isNotEmpty == true,
      profile.programName?.trim().isNotEmpty == true,
      profile.skills.isNotEmpty,
    ].where((value) => value).length;

    return completedFields / 4.0;
  }

  double? _blendRoleRatings({
    required double? lecturerRating,
    required double? studentRating,
  }) {
    const lecturerWeight = 0.70;
    const studentWeight = 0.30;

    var totalWeight = 0.0;
    var weightedScore = 0.0;

    if (lecturerRating != null) {
      weightedScore += lecturerRating.clamp(0.0, 1.0) * lecturerWeight;
      totalWeight += lecturerWeight;
    }
    if (studentRating != null) {
      weightedScore += studentRating.clamp(0.0, 1.0) * studentWeight;
      totalWeight += studentWeight;
    }

    if (totalWeight <= 0) return null;
    return (weightedScore / totalWeight).clamp(0.0, 1.0);
  }
}