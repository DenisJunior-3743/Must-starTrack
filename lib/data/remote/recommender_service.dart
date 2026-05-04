import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/post_model.dart';
import '../models/skill_pattern_model.dart';
import '../models/user_model.dart';
import 'openai_service.dart';

class RecommendedPost {
  const RecommendedPost({
    required this.post,
    required this.score,
    required this.reasons,
    this.scoreBreakdown = const {},
    this.missingFields = const [],
  });

  final PostModel post;
  final double score;
  final List<String> reasons;
  final Map<String, double> scoreBreakdown;
  final List<String> missingFields;
}

class RecommendedUser {
  const RecommendedUser({
    required this.user,
    required this.score,
    required this.reasons,
    this.matchedSkills = const [],
    this.scoreBreakdown = const {},
    this.missingFields = const [],
  });

  final UserModel user;
  final double score;
  final List<String> reasons;
  final List<String> matchedSkills;
  final Map<String, double> scoreBreakdown;
  final List<String> missingFields;
}

class FeedVideoQueueItem {
  const FeedVideoQueueItem({
    required this.post,
    required this.eligibilityScore,
    required this.isEligible,
    required this.reasons,
    this.signalBreakdown = const {},
  });

  final PostModel post;
  final double eligibilityScore;
  final bool isEligible;
  final List<String> reasons;
  final Map<String, double> signalBreakdown;
}

class GlobalStudentRankScore {
  const GlobalStudentRankScore({
    required this.score,
    required this.breakdown,
    required this.projectCount,
    required this.projectTitles,
  });

  final double score;
  final Map<String, double> breakdown;
  final int projectCount;
  final List<String> projectTitles;
}

enum GlobalStudentRankTimeRange { sprint, term, allTime }

class HybridRerankDiagnostics {
  const HybridRerankDiagnostics({
    required this.openAiConfigured,
    required this.openAiAttempted,
    required this.openAiSucceeded,
    required this.usedOpenAi,
    required this.usedProxy,
    required this.rankingRows,
    required this.reason,
  });

  final bool openAiConfigured;
  final bool openAiAttempted;
  final bool openAiSucceeded;
  final bool usedOpenAi;
  final bool usedProxy;
  final int rankingRows;
  final String reason;
}

class HybridRerankResult {
  const HybridRerankResult({
    required this.posts,
    required this.diagnostics,
  });

  final List<RecommendedPost> posts;
  final HybridRerankDiagnostics diagnostics;
}

class RecommenderService {
  RecommenderService({OpenAiService? openAiService})
      : _openAiService = openAiService;

  final OpenAiService? _openAiService;

  static const _postWeights = _PostWeightVector(
    contentSimilarity: 0.30,
    behavioralRelevance: 0.18,
    clusterAffinity: 0.08,
    qualityScore: 0.18,
    freshness: 0.13,
    diversity: 0.07,
    trustAdjusted: 0.06,
  );

  List<FeedVideoQueueItem> buildFeedVideoQueue({
    required UserModel user,
    required List<PostModel> candidates,
    Set<String> recentlyViewedCategories = const {},
    Set<String> recentSearchTerms = const {},
  }) {
    final userSkills =
        user.profile?.skills.map((e) => e.toLowerCase()).toSet() ??
            const <String>{};
    final userFaculty = user.profile?.faculty?.trim().toLowerCase();
    final userProgram = user.profile?.programName?.trim().toLowerCase();
    final normalizedSearchTerms = _normalizeTerms(recentSearchTerms);
    final normalizedRecentCategories = recentlyViewedCategories
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();

    final queue = candidates.where((post) => _isVideoContent(post)).map((post) {
      final reasons = <String>[];
      final breakdown = <String, double>{};

      final postSkills = post.skillsUsed.map((e) => e.toLowerCase()).toSet();
      final skillOverlap = userSkills.intersection(postSkills).length;
      final skillSignal = userSkills.isEmpty || postSkills.isEmpty
          ? 0.0
          : (skillOverlap / math.max(1, math.min(userSkills.length, 5)))
              .clamp(0.0, 1.0)
              .toDouble();
      breakdown['skill_signal'] = skillSignal;
      if (skillSignal > 0) reasons.add('skill_preference');

      final facultySignal = (userFaculty != null &&
              post.faculty?.trim().toLowerCase() == userFaculty)
          ? 1.0
          : 0.0;
      breakdown['faculty_signal'] = facultySignal;
      if (facultySignal > 0) reasons.add('faculty_preference');

      final programSignal = (userProgram != null &&
              post.program?.trim().toLowerCase() == userProgram)
          ? 1.0
          : 0.0;
      breakdown['program_signal'] = programSignal;
      if (programSignal > 0) reasons.add('program_preference');

      final categorySignal = (post.category != null &&
              normalizedRecentCategories
                  .contains(post.category!.trim().toLowerCase()))
          ? 1.0
          : 0.0;
      breakdown['category_signal'] = categorySignal;
      if (categorySignal > 0) reasons.add('recent_category_behavior');

      final searchSignal =
          _matchesPostSearchIntent(post, normalizedSearchTerms) ? 1.0 : 0.0;
      breakdown['search_signal'] = searchSignal;
      if (searchSignal > 0) reasons.add('search_intent_behavior');

      final engagementSignal =
          ((post.likeCount + post.commentCount + post.shareCount) / 180.0)
              .clamp(0.0, 1.0)
              .toDouble();
      breakdown['engagement_signal'] = engagementSignal;

      final freshnessSignal = _freshnessForPost(post);
      breakdown['freshness_signal'] = freshnessSignal;

      final eligibilityScore = ((0.28 * skillSignal) +
              (0.15 * facultySignal) +
              (0.10 * programSignal) +
              (0.20 * categorySignal) +
              (0.17 * searchSignal) +
              (0.05 * engagementSignal) +
              (0.05 * freshnessSignal))
          .clamp(0.0, 1.0)
          .toDouble();

      final hasBehaviorHit = categorySignal > 0 || searchSignal > 0;
      final isEligible = eligibilityScore >= 0.36 || hasBehaviorHit;
      if (isEligible) reasons.add('queue_eligible');

      return FeedVideoQueueItem(
        post: post,
        eligibilityScore: eligibilityScore,
        isEligible: isEligible,
        reasons: reasons,
        signalBreakdown: breakdown,
      );
    }).toList(growable: false)
      ..sort((a, b) => b.eligibilityScore.compareTo(a.eligibilityScore));

    return queue;
  }

  List<RecommendedPost> rankLocally({
    required UserModel user,
    required List<PostModel> candidates,
    SkillPatternResult? skillPatterns,
    Set<String> recentlyViewedCategories = const {},
    Set<String> recentSearchTerms = const {},
    Map<String, double> lecturerRatingsByPost = const {},
    Map<String, double> studentRatingsByPost = const {},
    Map<String, List<String>> commentSnippetsByPost = const {},
  }) {
    final userSkills =
        user.profile?.skills.map((e) => e.toLowerCase()).toSet() ??
            const <String>{};
    final userFaculty = user.profile?.faculty?.trim().toLowerCase();
    final userProgram = user.profile?.programName?.trim().toLowerCase();
    final normalizedSearchTerms = _normalizeTerms(recentSearchTerms);
    final normalizedRecentCategories = recentlyViewedCategories
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();

    final facultyCounts = _buildFacultyFrequency(candidates);
    final overrepresentedFaculty = _mostRepresentedFaculty(facultyCounts);
    final underrepresentedFaculties = _underrepresentedFaculties(facultyCounts);

    final scored = candidates.map((post) {
      final reasons = <String>[];
      final missingFields = <String>[];
      final breakdown = <String, double>{};

      final postSkills = post.skillsUsed.map((e) => e.toLowerCase()).toSet();
      if (userSkills.isEmpty) missingFields.add('user.skills');
      if (postSkills.isEmpty) missingFields.add('post.skills_used');

      final contentSimilarity = _contentSimilarityForPost(
        userSkills: userSkills,
        userFaculty: userFaculty,
        userProgram: userProgram,
        post: post,
        postSkills: postSkills,
        reasons: reasons,
      );
      breakdown['content_similarity'] = contentSimilarity;

      final behavioralRelevance = _behaviorRelevanceForPost(
        post: post,
        searchTerms: normalizedSearchTerms,
        recentCategories: normalizedRecentCategories,
        reasons: reasons,
      );
      breakdown['behavioral_relevance'] = behavioralRelevance;

      final clusterAffinity = _clusterAffinityForPost(
        userSkills: userSkills,
        post: post,
        skillPatterns: skillPatterns,
      );
      breakdown['cluster_affinity'] = clusterAffinity;
      if (clusterAffinity <= 0) {
        missingFields.add('cluster_id');
      }

      final qualityScore = _qualityScoreForPost(
        post: post,
        lecturerRating: lecturerRatingsByPost[post.id],
        studentRating: studentRatingsByPost[post.id],
        commentSnippets: commentSnippetsByPost[post.id] ?? const [],
        reasons: reasons,
      );
      breakdown['quality_score'] = qualityScore;

      final freshness = _freshnessForPost(post);
      breakdown['freshness'] = freshness;

      final diversity = _diversityForPost(
        post: post,
        userFaculty: userFaculty,
        underrepresentedFaculties: underrepresentedFaculties,
        overrepresentedFaculty: overrepresentedFaculty,
        reasons: reasons,
      );
      breakdown['diversity'] = diversity;

      final trustAdjusted = _trustAdjustedForPost(
        post: post,
        reasons: reasons,
      );
      breakdown['trust_adjusted'] = trustAdjusted;

      var score = (_postWeights.contentSimilarity * contentSimilarity) +
          (_postWeights.behavioralRelevance * behavioralRelevance) +
          (_postWeights.clusterAffinity * clusterAffinity) +
          (_postWeights.qualityScore * qualityScore) +
          (_postWeights.freshness * freshness) +
          (_postWeights.diversity * diversity) +
          (_postWeights.trustAdjusted * trustAdjusted);

      final advertAdjustment = _advertAdjustmentForPost(
        post: post,
        userFaculty: userFaculty,
        reasons: reasons,
      );
      breakdown['advert_adjustment'] = advertAdjustment;
      score += advertAdjustment;

      if (post.type == 'opportunity' &&
          post.opportunityDeadline != null &&
          post.opportunityDeadline!.isBefore(DateTime.now())) {
        score -= 0.18;
        reasons.add('expired_opportunity_penalty');
      }

      final finalLocalScore = score.clamp(0.0, 1.0).toDouble();
      breakdown['local_score'] = finalLocalScore;
      breakdown['blended_score'] = finalLocalScore;

      return RecommendedPost(
        post: post,
        score: finalLocalScore,
        reasons: reasons,
        scoreBreakdown: breakdown,
        missingFields: missingFields,
      );
    }).toList();

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return b.post.createdAt.compareTo(a.post.createdAt);
    });

    if (userFaculty == null || userFaculty.isEmpty || scored.length < 10) {
      return scored;
    }

    return _applyFeedDiversityConstraints(
      ranked: scored,
      userFaculty: userFaculty,
    );
  }

  Future<List<RecommendedPost>> rankHybrid({
    required UserModel user,
    required List<PostModel> candidates,
    SkillPatternResult? skillPatterns,
    Set<String> recentlyViewedCategories = const {},
    Set<String> recentSearchTerms = const {},
    Map<String, double> lecturerRatingsByPost = const {},
    Map<String, double> studentRatingsByPost = const {},
    Map<String, List<String>> commentSnippetsByPost = const {},
    bool allowProxyFallback = false,
  }) async {
    final result = await rankHybridWithDiagnostics(
      user: user,
      candidates: candidates,
      skillPatterns: skillPatterns,
      recentlyViewedCategories: recentlyViewedCategories,
      recentSearchTerms: recentSearchTerms,
      lecturerRatingsByPost: lecturerRatingsByPost,
      studentRatingsByPost: studentRatingsByPost,
      commentSnippetsByPost: commentSnippetsByPost,
      allowProxyFallback: allowProxyFallback,
    );
    return result.posts;
  }

  Future<HybridRerankResult> rankHybridWithDiagnostics({
    required UserModel user,
    required List<PostModel> candidates,
    SkillPatternResult? skillPatterns,
    Set<String> recentlyViewedCategories = const {},
    Set<String> recentSearchTerms = const {},
    Map<String, double> lecturerRatingsByPost = const {},
    Map<String, double> studentRatingsByPost = const {},
    Map<String, List<String>> commentSnippetsByPost = const {},
    bool allowProxyFallback = false,
  }) async {
    final localRanked = rankLocally(
      user: user,
      candidates: candidates,
      skillPatterns: skillPatterns,
      recentlyViewedCategories: recentlyViewedCategories,
      recentSearchTerms: recentSearchTerms,
      lecturerRatingsByPost: lecturerRatingsByPost,
      studentRatingsByPost: studentRatingsByPost,
      commentSnippetsByPost: commentSnippetsByPost,
    );

    if (localRanked.isEmpty) {
      return HybridRerankResult(
        posts: localRanked,
        diagnostics: const HybridRerankDiagnostics(
          openAiConfigured: false,
          openAiAttempted: false,
          openAiSucceeded: false,
          usedOpenAi: false,
          usedProxy: false,
          rankingRows: 0,
          reason: 'no_candidates',
        ),
      );
    }

    final openAi = _openAiService;
    if (openAi == null || !openAi.isConfigured) {
      final fallback = allowProxyFallback
          ? _applyProxyHybridRerank(localRanked)
          : localRanked;
      return HybridRerankResult(
        posts: fallback,
        diagnostics: HybridRerankDiagnostics(
          openAiConfigured: false,
          openAiAttempted: false,
          openAiSucceeded: false,
          usedOpenAi: false,
          usedProxy: allowProxyFallback,
          rankingRows: 0,
          reason: 'openai_not_configured',
        ),
      );
    }

    try {
      final top = localRanked.take(25).toList();
      final openAiResponse = await openAi.rankPosts(
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
                  'commentCount': e.post.commentCount,
                  'comments': (commentSnippetsByPost[e.post.id] ?? const [])
                      .take(4)
                      .toList(),
                })
            .toList(),
      );

      final ranking = (openAiResponse?['ranking'] as List?) ?? const [];
      final upstreamError =
          (openAiResponse?['error'] ?? openAiResponse?['status'])
              ?.toString()
              .trim();
      final emptyReason = (upstreamError != null && upstreamError.isNotEmpty)
          ? 'openai_empty_ranking_$upstreamError'
          : 'openai_empty_ranking';
      if (ranking.isEmpty) {
        final fallback = allowProxyFallback
            ? _applyProxyHybridRerank(localRanked)
            : localRanked;
        return HybridRerankResult(
          posts: fallback,
          diagnostics: HybridRerankDiagnostics(
            openAiConfigured: true,
            openAiAttempted: true,
            openAiSucceeded: false,
            usedOpenAi: false,
            usedProxy: allowProxyFallback,
            rankingRows: 0,
            reason: emptyReason,
          ),
        );
      }

      final aiScoreById = <String, double>{};
      for (final row in ranking) {
        if (row is! Map) continue;
        final data = Map<String, dynamic>.from(row);
        final id =
            (data['postId'] ?? data['post_id'] ?? data['id'])?.toString();
        final score = _asDouble(
          data['score'] ?? data['relevance'] ?? data['finalScore'],
        );
        if (id == null || score == null) continue;
        aiScoreById[id] = score.clamp(0.0, 1.0).toDouble();
      }

      if (aiScoreById.isEmpty) {
        final fallback = allowProxyFallback
            ? _applyProxyHybridRerank(localRanked)
            : localRanked;
        return HybridRerankResult(
          posts: fallback,
          diagnostics: HybridRerankDiagnostics(
            openAiConfigured: true,
            openAiAttempted: true,
            openAiSucceeded: false,
            usedOpenAi: false,
            usedProxy: allowProxyFallback,
            rankingRows: 0,
            reason: 'openai_invalid_ranking_payload',
          ),
        );
      }

      final reranked = localRanked.map((item) {
        final aiScore = aiScoreById[item.post.id];
        if (aiScore == null) return item;

        final blended = (item.score * 0.65) + (aiScore * 0.35);
        return RecommendedPost(
          post: item.post,
          score: blended.clamp(0.0, 1.0).toDouble(),
          reasons: [...item.reasons, 'openai_rerank'],
          scoreBreakdown: {
            ...item.scoreBreakdown,
            'local_score': item.score,
            'openai_score': aiScore,
            'ai_source_openai': 1.0,
            'blended_score': blended.clamp(0.0, 1.0).toDouble(),
          },
          missingFields: item.missingFields,
        );
      }).toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      return HybridRerankResult(
        posts: reranked,
        diagnostics: HybridRerankDiagnostics(
          openAiConfigured: true,
          openAiAttempted: true,
          openAiSucceeded: true,
          usedOpenAi: true,
          usedProxy: false,
          rankingRows: aiScoreById.length,
          reason: 'openai_ok',
        ),
      );
    } catch (error) {
      final fallback = allowProxyFallback
          ? _applyProxyHybridRerank(localRanked)
          : localRanked;
      return HybridRerankResult(
        posts: fallback,
        diagnostics: HybridRerankDiagnostics(
          openAiConfigured: true,
          openAiAttempted: true,
          openAiSucceeded: false,
          usedOpenAi: false,
          usedProxy: allowProxyFallback,
          rankingRows: 0,
          reason: 'openai_exception_${error.runtimeType}',
        ),
      );
    }
  }

  List<RecommendedPost> _applyProxyHybridRerank(
    List<RecommendedPost> localRanked,
  ) {
    final reranked = localRanked.map((item) {
      final base = _proxyAiBaseScore(item.scoreBreakdown, fallback: item.score);
      final drift = _deterministicDriftForPost(item.post.id);
      final aiScore = (base + drift).clamp(0.0, 1.0).toDouble();
      final blended =
          ((item.score * 0.72) + (aiScore * 0.28)).clamp(0.0, 1.0).toDouble();

      return RecommendedPost(
        post: item.post,
        score: blended,
        reasons: [...item.reasons, 'ai_proxy_rerank'],
        scoreBreakdown: {
          ...item.scoreBreakdown,
          'local_score': item.score,
          'openai_score': aiScore,
          'ai_source_proxy': 1.0,
          'blended_score': blended,
        },
        missingFields: item.missingFields,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return reranked;
  }

  double _proxyAiBaseScore(
    Map<String, double> breakdown, {
    required double fallback,
  }) {
    final content = breakdown['content_similarity'] ?? fallback;
    final behavioral = breakdown['behavioral_relevance'] ?? fallback;
    final quality = breakdown['quality_score'] ?? fallback;
    final freshness = breakdown['freshness'] ?? fallback;
    final diversity = breakdown['diversity'] ?? fallback;
    final trust = breakdown['trust_adjusted'] ?? fallback;

    return ((0.22 * content) +
            (0.28 * behavioral) +
            (0.18 * quality) +
            (0.14 * freshness) +
            (0.10 * diversity) +
            (0.08 * trust))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _deterministicDriftForPost(String postId) {
    final hash = postId.runes.fold<int>(0, (sum, rune) => sum + rune);
    final centered = (hash % 61) - 30;
    return centered / 1000.0;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString());
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
      final reasons = <String>[];
      final missingFields = <String>[];
      final breakdown = <String, double>{};

      final candidateSkills =
          candidate.profile?.skills.map((e) => e.toLowerCase()).toSet() ??
              const <String>{};
      final sharedSkills = currentSkills.intersection(candidateSkills).toList();
      final complementarySkills =
          candidateSkills.difference(currentSkills).take(4).toList();

      if (currentSkills.isEmpty) missingFields.add('current_user.skills');
      if (candidateSkills.isEmpty) missingFields.add('candidate.skills');

      final contentSimilarity = _contentSimilarityForUser(
        currentSkills: currentSkills,
        candidate: candidate,
        sharedSkills: sharedSkills,
        complementarySkills: complementarySkills,
        currentFaculty: currentFaculty,
        currentProgram: currentProgram,
        reasons: reasons,
      );
      breakdown['content_similarity'] = contentSimilarity;

      final behavioralRelevance = _behaviorRelevanceForUser(
        candidate: candidate,
        searchTerms: normalizedSearchTerms,
        reasons: reasons,
      );
      breakdown['behavioral_relevance'] = behavioralRelevance;

      breakdown['cluster_affinity'] = 0.0;
      missingFields.add('cluster_id');

      final qualityScore = _qualityScoreForUser(candidate);
      breakdown['quality_score'] = qualityScore;

      final freshness = _freshnessForUser(candidate);
      breakdown['freshness'] = freshness;

      final diversity = _diversityForUser(
        currentFaculty: currentFaculty,
        candidateFaculty: candidate.profile?.faculty?.toLowerCase(),
      );
      breakdown['diversity'] = diversity;

      final trustAdjusted = _trustForUser(candidate);
      breakdown['trust_adjusted'] = trustAdjusted;

      final score = (0.34 * contentSimilarity) +
          (0.20 * behavioralRelevance) +
          (0.18 * qualityScore) +
          (0.10 * freshness) +
          (0.10 * diversity) +
          (0.08 * trustAdjusted);

      return RecommendedUser(
        user: candidate,
        score: score.clamp(0.0, 1.0).toDouble(),
        reasons: reasons,
        matchedSkills:
            sharedSkills.isNotEmpty ? sharedSkills : complementarySkills,
        scoreBreakdown: breakdown,
        missingFields: missingFields,
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

    final ranked = candidates
        .where((candidate) => candidate.profile != null)
        .map((candidate) {
      final reasons = <String>[];
      final missingFields = <String>[];
      final breakdown = <String, double>{};

      final profile = candidate.profile!;
      final candidateSkills =
          profile.skills.map((skill) => skill.toLowerCase()).toSet();
      final matchedSkills =
          opportunitySkills.intersection(candidateSkills).toList();

      final opportunityFit = opportunitySkills.isEmpty
          ? 0.0
          : (matchedSkills.length / opportunitySkills.length)
              .clamp(0.0, 1.0)
              .toDouble();
      breakdown['opportunity_fit'] = opportunityFit;

      if (matchedSkills.isNotEmpty) reasons.add('skill_match');
      if (opportunitySkills.isEmpty) missingFields.add('opportunity.skills');
      if (candidateSkills.isEmpty) missingFields.add('candidate.skills');

      final facultyMatch = opportunityFaculty != null &&
          profile.faculty?.toLowerCase() == opportunityFaculty;
      if (facultyMatch) reasons.add('faculty_match');
      breakdown['faculty_match'] = facultyMatch ? 1.0 : 0.0;

      final programMatch = opportunityProgram != null &&
          profile.programName?.toLowerCase() == opportunityProgram;
      if (programMatch) reasons.add('program_match');
      breakdown['program_match'] = programMatch ? 1.0 : 0.0;

      final projectsScore = _logNorm(profile.totalPosts, maxInput: 20);
      const likesScore = 0.0;
      const studentRatingScore = 0.0;
      final collaborationScore = _logNorm(profile.totalCollabs, maxInput: 10);
      const lecturerRatingScore = 0.0;
      final versatilityScore =
          (candidateSkills.length.clamp(0, 10).toInt() / 10.0)
              .clamp(0.0, 1.0)
              .toDouble();
      final academicYearScore = _academicYearScore(profile.yearOfStudy);
      final completenessScore = _scoreProfileCompleteness(candidate);
      final trustScore = _trustForUser(candidate);
      final flagPenalty = candidate.isActive ? 0.0 : 1.0;

      breakdown['projects'] = projectsScore;
      breakdown['likes'] = likesScore;
      breakdown['student_rating'] = studentRatingScore;
      breakdown['collaboration'] = collaborationScore;
      breakdown['lecturer_rating'] = lecturerRatingScore;
      breakdown['versatility'] = versatilityScore;
      breakdown['academic_year'] = academicYearScore;
      breakdown['profile_completeness'] = completenessScore;
      breakdown['trust_score'] = trustScore;
      breakdown['flag_penalty'] = flagPenalty;

      final positive = (0.18 * projectsScore) +
          (0.00 * likesScore) +
          (0.00 * studentRatingScore) +
          (0.20 * collaborationScore) +
          (0.00 * lecturerRatingScore) +
          (0.14 * versatilityScore) +
          (0.08 * academicYearScore) +
          (0.18 * completenessScore) +
          (0.22 * trustScore);
      final penalty = (0.20 * flagPenalty).clamp(0.0, positive);
      final globalStudentScore =
          (positive - penalty).clamp(0.0, 1.0).toDouble();
      breakdown['global_student_score'] = globalStudentScore;

      final matchScore = (0.60 * opportunityFit) +
          (0.10 * (facultyMatch ? 1.0 : 0.0)) +
          (0.08 * (programMatch ? 1.0 : 0.0));
      breakdown['match_score'] = matchScore.clamp(0.0, 1.0).toDouble();

      final finalScore = ((0.58 * matchScore) + (0.42 * globalStudentScore))
          .clamp(0.0, 1.0)
          .toDouble();

      if (profile.totalCollabs > 0) reasons.add('collaboration_ready');

      return RecommendedUser(
        user: candidate,
        score: finalScore,
        reasons: reasons,
        matchedSkills: matchedSkills,
        scoreBreakdown: breakdown,
        missingFields: missingFields,
      );
    }).toList();

    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }

  List<RecommendedPost> _applyFeedDiversityConstraints({
    required List<RecommendedPost> ranked,
    required String userFaculty,
  }) {
    const windowSize = 10;
    const sameFacultyCap = 4;
    const crossFacultyMin = 3;
    const exploreMin = 1;

    final pool = List<RecommendedPost>.from(ranked);
    final result = <RecommendedPost>[];

    while (pool.isNotEmpty) {
      final window = <RecommendedPost>[];
      var sameCount = 0;
      var crossCount = 0;
      var exploreCount = 0;

      while (pool.isNotEmpty && window.length < windowSize) {
        var bestIndex = 0;
        var bestScore = -999.0;
        final remainingSlotsAfterPick = windowSize - window.length - 1;

        for (var i = 0; i < pool.length; i++) {
          final item = pool[i];
          final isSame = _isSameFaculty(item.post, userFaculty);
          final isCross = _isCrossFaculty(item.post, userFaculty);
          final isExplore = _isExplorationCandidate(item, userFaculty);

          final projectedSame = sameCount + (isSame ? 1 : 0);
          final projectedCross = crossCount + (isCross ? 1 : 0);
          final projectedExplore = exploreCount + (isExplore ? 1 : 0);

          var adjusted = item.score;

          if (projectedSame > sameFacultyCap) {
            adjusted -= 0.30;
          }

          final crossNeededAfterPick =
              math.max(0, crossFacultyMin - projectedCross);
          if (crossNeededAfterPick > remainingSlotsAfterPick) {
            adjusted -= 0.24;
          } else if (isCross && projectedCross <= crossFacultyMin) {
            adjusted += 0.03;
          }

          final exploreNeededAfterPick =
              math.max(0, exploreMin - projectedExplore);
          if (exploreNeededAfterPick > remainingSlotsAfterPick) {
            adjusted -= 0.22;
          } else if (isExplore && projectedExplore <= exploreMin) {
            adjusted += 0.025;
          }

          if (adjusted > bestScore) {
            bestScore = adjusted;
            bestIndex = i;
          }
        }

        final picked = pool.removeAt(bestIndex);
        window.add(picked);
        if (_isSameFaculty(picked.post, userFaculty)) sameCount += 1;
        if (_isCrossFaculty(picked.post, userFaculty)) crossCount += 1;
        if (_isExplorationCandidate(picked, userFaculty)) exploreCount += 1;
      }

      result.addAll(window);
    }

    return result;
  }

  double _contentSimilarityForPost({
    required Set<String> userSkills,
    required String? userFaculty,
    required String? userProgram,
    required PostModel post,
    required Set<String> postSkills,
    required List<String> reasons,
  }) {
    final skillOverlap = userSkills.intersection(postSkills).length;
    final skillBase = userSkills.isEmpty || postSkills.isEmpty
        ? 0.0
        : (skillOverlap / math.max(1, math.min(userSkills.length, 5)))
            .clamp(0.0, 1.0)
            .toDouble();
    if (skillOverlap > 0) reasons.add('skill_match');

    final facultyMatch = userFaculty != null &&
        post.faculty?.trim().toLowerCase() == userFaculty;
    if (facultyMatch) reasons.add('faculty_match');

    final programMatch = userProgram != null &&
        post.program?.trim().toLowerCase() == userProgram;
    if (programMatch) reasons.add('program_match');

    var score = (0.76 * skillBase) +
        (0.14 * (facultyMatch ? 1.0 : 0.0)) +
        (0.10 * (programMatch ? 1.0 : 0.0));

    final opportunityFit =
        post.type == 'opportunity' && skillOverlap > 0 ? 0.08 : 0.0;
    if (opportunityFit > 0) reasons.add('opportunity_fit');
    score += opportunityFit;

    return score.clamp(0.0, 1.0).toDouble();
  }

  double _behaviorRelevanceForPost({
    required PostModel post,
    required Set<String> searchTerms,
    required Set<String> recentCategories,
    required List<String> reasons,
  }) {
    final watchTimeRatio = (post.viewCount / 300.0).clamp(0.0, 1.0).toDouble();
    final likeSignal = post.isLikedByMe
        ? 1.0
        : (post.likeCount / (post.likeCount + post.dislikeCount + 1.0))
            .clamp(0.0, 1.0)
            .toDouble();
    final searchMatch = _matchesPostSearchIntent(post, searchTerms) ? 1.0 : 0.0;
    final followSignal = post.isFollowingAuthor ? 1.0 : 0.0;

    if (searchMatch > 0) reasons.add('search_intent');

    var categorySignal = 0.0;
    if (post.category != null &&
        recentCategories.contains(post.category!.trim().toLowerCase())) {
      categorySignal = 1.0;
      reasons.add('collaborative_signal');
    }

    var score = (0.30 * watchTimeRatio) +
        (0.23 * likeSignal) +
        (0.27 * searchMatch) +
        (0.20 * followSignal);
    score = (score + (0.12 * categorySignal)).clamp(0.0, 1.0).toDouble();

    if (post.isDislikedByMe) {
      score = (score - 0.25).clamp(0.0, 1.0).toDouble();
    }

    return score;
  }

  double _clusterAffinityForPost({
    required Set<String> userSkills,
    required PostModel post,
    SkillPatternResult? skillPatterns,
  }) {
    final aiAffinity = _clusterAffinityFromSkillPatterns(
      userSkills: userSkills,
      post: post,
      skillPatterns: skillPatterns,
    );
    if (aiAffinity != null) {
      return aiAffinity;
    }

    final userCluster = _extractClusterId(userSkills);
    final postCluster = _extractClusterId({
      ...post.tags.map((e) => e.toLowerCase()),
      ...post.skillsUsed.map((e) => e.toLowerCase()),
    });

    if (userCluster == null || postCluster == null) return 0.0;
    if (userCluster == postCluster) return 1.0;

    final neighborClusters = _extractClusterNeighbors(post.tags);
    if (neighborClusters.contains(userCluster)) return 0.7;

    final distance = _extractClusterDistance(post.tags);
    if (distance == null) return 0.0;
    return math.exp(-distance).clamp(0.0, 1.0).toDouble();
  }

  double? _clusterAffinityFromSkillPatterns({
    required Set<String> userSkills,
    required PostModel post,
    SkillPatternResult? skillPatterns,
  }) {
    final patterns = skillPatterns;
    if (patterns == null || patterns.clusters.isEmpty) {
      return null;
    }

    final userTokens = userSkills
        .map(_normalizeSkillToken)
        .where((token) => token.isNotEmpty)
        .toSet();
    final postTokens = {
      ...post.skillsUsed.map(_normalizeSkillToken),
      ...post.tags.map(_normalizeSkillToken),
      if (post.category != null) _normalizeSkillToken(post.category!),
      if (post.areaOfExpertise != null)
        _normalizeSkillToken(post.areaOfExpertise!),
    }.where((token) => token.isNotEmpty).toSet();

    if (userTokens.isEmpty || postTokens.isEmpty) {
      return null;
    }

    final userCluster = _bestPatternClusterForTokens(userTokens, patterns);
    final postCluster = _bestPatternClusterForTokens(postTokens, patterns);
    if (userCluster == null || postCluster == null) {
      return null;
    }

    if (userCluster.clusterId == postCluster.clusterId) {
      final aligned = (userCluster.score + postCluster.score) / 2.0;
      return (0.65 + (0.35 * aligned)).clamp(0.0, 1.0).toDouble();
    }

    final corr = _findPatternCorrelation(
      patterns: patterns,
      fromClusterId: userCluster.clusterId,
      toClusterId: postCluster.clusterId,
    );
    if (corr != null) {
      final confidence = (userCluster.score + postCluster.score) / 2.0;
      return ((0.55 * corr.weight) + (0.45 * confidence))
          .clamp(0.0, 1.0)
          .toDouble();
    }

    return (0.15 * math.min(userCluster.score, postCluster.score))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  _PatternClusterMatch? _bestPatternClusterForTokens(
    Set<String> tokens,
    SkillPatternResult patterns,
  ) {
    _PatternClusterMatch? best;

    for (final cluster in patterns.clusters) {
      final clusterTokens = {
        ...cluster.skills.map(_normalizeSkillToken),
        ...cluster.keywords.map(_normalizeSkillToken),
      }.where((token) => token.isNotEmpty).toSet();

      if (clusterTokens.isEmpty) continue;

      final overlap = tokens.intersection(clusterTokens).length;
      if (overlap <= 0) continue;

      final score = (overlap / math.max(1, math.min(tokens.length, 6)))
          .clamp(0.0, 1.0)
          .toDouble();

      if (best == null || score > best.score) {
        best = _PatternClusterMatch(
          clusterId: cluster.id,
          score: score,
        );
      }
    }

    return best;
  }

  SkillPatternCorrelation? _findPatternCorrelation({
    required SkillPatternResult patterns,
    required String fromClusterId,
    required String toClusterId,
  }) {
    for (final corr in patterns.correlations) {
      final direct = corr.fromClusterId == fromClusterId &&
          corr.toClusterId == toClusterId;
      final reverse = corr.fromClusterId == toClusterId &&
          corr.toClusterId == fromClusterId;
      if (direct || reverse) {
        return corr;
      }
    }
    return null;
  }

  String _normalizeSkillToken(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  double _qualityScoreForPost({
    required PostModel post,
    required double? lecturerRating,
    required double? studentRating,
    required List<String> commentSnippets,
    required List<String> reasons,
  }) {
    final ratingBlend = _blendRoleRatings(
          lecturerRating: lecturerRating,
          studentRating: studentRating,
        ) ??
        0.0;

    if (lecturerRating != null) reasons.add('lecturer_rating_signal');
    if (studentRating != null) reasons.add('student_rating_signal');

    final engagementScore =
        ((post.likeCount + post.commentCount * 2 + post.shareCount * 3) / 220.0)
            .clamp(0.0, 1.0)
            .toDouble();

    final sentimentScore = _normalizedSentimentFromComments(commentSnippets);
    if (commentSnippets.isNotEmpty) {
      reasons.add('comment_sentiment_signal');
    }

    return ((0.45 * ratingBlend) +
            (0.35 * engagementScore) +
            (0.20 * sentimentScore))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _freshnessForPost(PostModel post) {
    final hours = DateTime.now().difference(post.createdAt).inHours;
    return (1.0 - (hours / (24 * 14))).clamp(0.0, 1.0).toDouble();
  }

  double _normalizedSentimentFromComments(List<String> comments) {
    if (comments.isEmpty) return 0.5;

    var sum = 0.0;
    var count = 0;
    for (final comment in comments) {
      final sentiment = _classifyCommentSentiment(comment);
      sum += sentiment;
      count += 1;
    }
    if (count == 0) return 0.5;

    final sentimentScore = (sum / count).clamp(-1.0, 1.0).toDouble();
    return ((sentimentScore + 1.0) / 2.0).clamp(0.0, 1.0).toDouble();
  }

  double _classifyCommentSentiment(String rawComment) {
    final comment = rawComment.trim().toLowerCase();
    if (comment.isEmpty) return 0.0;

    const positiveWords = {
      'great',
      'excellent',
      'awesome',
      'amazing',
      'good',
      'nice',
      'impressive',
      'love',
      'helpful',
      'clear',
      'brilliant',
      'well done',
      'fantastic',
    };
    const negativeWords = {
      'bad',
      'poor',
      'confusing',
      'unclear',
      'weak',
      'wrong',
      'terrible',
      'awful',
      'hate',
      'useless',
      'not good',
      'plagiarism',
      'fake',
    };

    var positiveHits = 0;
    var negativeHits = 0;

    for (final token in positiveWords) {
      if (comment.contains(token)) positiveHits += 1;
    }
    for (final token in negativeWords) {
      if (comment.contains(token)) negativeHits += 1;
    }

    if (positiveHits == 0 && negativeHits == 0) return 0.0;
    if (positiveHits == negativeHits) return 0.0;
    return positiveHits > negativeHits ? 1.0 : -1.0;
  }

  double _diversityForPost({
    required PostModel post,
    required String? userFaculty,
    required Set<String> underrepresentedFaculties,
    required String? overrepresentedFaculty,
    required List<String> reasons,
  }) {
    final postFaculty = post.faculty?.trim().toLowerCase();

    var raw = 0.0;
    if (postFaculty != null &&
        underrepresentedFaculties.contains(postFaculty)) {
      raw += 0.30;
    }
    if (DateTime.now().difference(post.createdAt).inHours <= 72) {
      raw += 0.18;
    }
    if (postFaculty != null &&
        overrepresentedFaculty != null &&
        postFaculty == overrepresentedFaculty &&
        userFaculty != null &&
        postFaculty == userFaculty) {
      raw -= 0.28;
    }

    final normalized = (0.5 + raw).clamp(0.0, 1.0).toDouble();
    if (normalized > 0.6) reasons.add('diversity_boost');
    return normalized;
  }

  double _trustAdjustedForPost({
    required PostModel post,
    required List<String> reasons,
  }) {
    final trust = (post.trustScore / 100.0).clamp(0.0, 1.0).toDouble();
    final confirmedFlags =
        post.moderationStatus.name.toLowerCase() == 'rejected' ? 1.0 : 0.0;
    final unreviewedFlags =
        post.moderationStatus.name.toLowerCase() == 'pending' ? 1.0 : 0.0;

    final raw = (trust - (0.70 * confirmedFlags + 0.30 * unreviewedFlags))
        .clamp(-1.0, 1.0)
        .toDouble();
    final normalized = ((raw + 1.0) / 2.0).clamp(0.0, 1.0).toDouble();

    if (normalized > 0.70) {
      reasons.add('trust_signal');
    } else if (normalized < 0.35) {
      reasons.add('trust_penalty');
    }
    return normalized;
  }

  double _advertAdjustmentForPost({
    required PostModel post,
    required String? userFaculty,
    required List<String> reasons,
  }) {
    if (post.type != 'advert') return 0.0;

    final advertFaculties =
        post.faculties.map((faculty) => faculty.toLowerCase()).toSet();
    final targetsAll = advertFaculties.contains('all');
    final facultyMatch =
        userFaculty != null && advertFaculties.contains(userFaculty);

    if (targetsAll) {
      reasons.add('advert_global_target');
      return 0.05;
    }
    if (facultyMatch) {
      reasons.add('advert_faculty_match');
      return 0.12;
    }

    reasons.add('advert_faculty_mismatch');
    return -0.08;
  }

  double _contentSimilarityForUser({
    required Set<String> currentSkills,
    required UserModel candidate,
    required List<String> sharedSkills,
    required List<String> complementarySkills,
    required String? currentFaculty,
    required String? currentProgram,
    required List<String> reasons,
  }) {
    final overlapRatio = currentSkills.isEmpty
        ? 0.0
        : (sharedSkills.length / math.max(1, math.min(currentSkills.length, 6)))
            .clamp(0.0, 1.0)
            .toDouble();
    if (sharedSkills.isNotEmpty) reasons.add('skill_match');

    final complementaryRatio =
        sharedSkills.isEmpty && complementarySkills.isNotEmpty
            ? (complementarySkills.length / 4.0).clamp(0.0, 1.0).toDouble()
            : 0.0;
    if (complementaryRatio > 0) reasons.add('complementary_skills');

    final candidateFaculty = candidate.profile?.faculty?.toLowerCase();
    final candidateProgram = candidate.profile?.programName?.toLowerCase();
    final facultyMatch =
        currentFaculty != null && candidateFaculty == currentFaculty;
    final programMatch =
        currentProgram != null && candidateProgram == currentProgram;
    if (facultyMatch) reasons.add('faculty_match');
    if (programMatch) reasons.add('program_match');

    return ((0.62 * overlapRatio) +
            (0.18 * complementaryRatio) +
            (0.12 * (facultyMatch ? 1.0 : 0.0)) +
            (0.08 * (programMatch ? 1.0 : 0.0)))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _behaviorRelevanceForUser({
    required UserModel candidate,
    required Set<String> searchTerms,
    required List<String> reasons,
  }) {
    final activity = _scoreProfileActivity(candidate);
    final searchMatch =
        _matchesUserSearchIntent(candidate, searchTerms) ? 1.0 : 0.0;
    if (searchMatch > 0) reasons.add('search_intent');

    final followership = ((candidate.profile?.totalFollowers ?? 0) / 120.0)
        .clamp(0.0, 1.0)
        .toDouble();

    return ((0.56 * activity) + (0.24 * searchMatch) + (0.20 * followership))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _qualityScoreForUser(UserModel candidate) {
    final completeness = _scoreProfileCompleteness(candidate);
    final activity = _scoreProfileActivity(candidate);
    final collaborationReadiness =
        ((candidate.profile?.totalCollabs ?? 0) / 8.0)
            .clamp(0.0, 1.0)
            .toDouble();

    return ((0.45 * completeness) +
            (0.35 * activity) +
            (0.20 * collaborationReadiness))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _freshnessForUser(UserModel candidate) {
    final lastSeen = candidate.lastSeenAt ?? candidate.updatedAt;
    final hours = DateTime.now().difference(lastSeen).inHours;
    return (1.0 - (hours / (24 * 21))).clamp(0.0, 1.0).toDouble();
  }

  double _diversityForUser({
    required String? currentFaculty,
    required String? candidateFaculty,
  }) {
    if (currentFaculty == null || candidateFaculty == null) return 0.5;
    if (currentFaculty == candidateFaculty) return 0.45;
    return 0.72;
  }

  double _trustForUser(UserModel user) {
    if (user.isBanned) return 0.0;
    if (user.isSuspended) return 0.2;
    return 1.0;
  }

  double _scoreProfileActivity(UserModel user) {
    final profile = user.profile;
    if (profile == null) return 0;

    final streak = (profile.activityStreak / 14).clamp(0.0, 1.0).toDouble();
    final posts = (profile.totalPosts / 10).clamp(0.0, 1.0).toDouble();
    final collabs = (profile.totalCollabs / 6).clamp(0.0, 1.0).toDouble();
    return (0.45 * streak) + (0.30 * posts) + (0.25 * collabs);
  }

  double computeGlobalStudentScore(UserModel student) {
    return computeGlobalStudentRankScore(
      student: student,
      projects: const <PostModel>[],
    ).score;
  }

  int computeGlobalStudentRankPoints({
    required double score,
    required DateTime updatedAt,
    required GlobalStudentRankTimeRange timeRange,
  }) {
    final boosted =
        (score * 0.86) + (_globalStudentTimeBoost(updatedAt, timeRange) * 0.14);
    return (boosted.clamp(0.0, 1.0) * 1000).round();
  }

  GlobalStudentRankScore computeGlobalStudentRankScore({
    required UserModel student,
    required List<PostModel> projects,
    int followerCount = 0,
    double? aiCommentSentiment,
  }) {
    final profile = student.profile;
    if (profile == null) {
      return const GlobalStudentRankScore(
        score: 0.0,
        breakdown: <String, double>{},
        projectCount: 0,
        projectTitles: <String>[],
      );
    }

    final studentProjects = projects
        .where((post) => post.authorId == student.id && post.type == 'project')
        .toList(growable: false);

    final skillScore = ((profile.skills.length / 8).clamp(0.0, 1.0)).toDouble();
    final activityScore =
        ((profile.activityStreak / 14).clamp(0.0, 1.0)).toDouble();
    final profilePostScore =
        ((profile.totalPosts / 12).clamp(0.0, 1.0)).toDouble();
    final profileCollabScore =
        ((profile.totalCollabs / 8).clamp(0.0, 1.0)).toDouble();
    final completenessScore = _scoreProfileCompleteness(student);

    final profileScore = ((0.25 * skillScore) +
            (0.20 * activityScore) +
            (0.20 * profilePostScore) +
            (0.20 * profileCollabScore) +
            (0.15 * completenessScore))
        .clamp(0.0, 1.0)
        .toDouble();

    var engagementTotal = 0.0;
    var trustTotal = 0.0;
    var freshnessTotal = 0.0;
    var projectSkillTotal = 0.0;
    var mediaTotal = 0.0;

    for (final project in studentProjects) {
      final engagement = ((project.likeCount +
                  (project.commentCount * 2) +
                  (project.shareCount * 3) +
                  (project.viewCount * 0.12)) /
              180.0)
          .clamp(0.0, 1.0)
          .toDouble();
      final trust = (project.trustScore / 100.0).clamp(0.0, 1.0).toDouble();
      final ageDays = DateTime.now().difference(project.updatedAt).inDays;
      final freshness = (1.0 - (ageDays / 180.0)).clamp(0.0, 1.0).toDouble();
      final projectSkills =
          (project.skillsUsed.length / 6.0).clamp(0.0, 1.0).toDouble();
      final mediaRichness =
          (project.mediaUrls.isNotEmpty || project.youtubeUrl != null)
              ? 1.0
              : 0.35;

      engagementTotal += engagement;
      trustTotal += trust;
      freshnessTotal += freshness;
      projectSkillTotal += projectSkills;
      mediaTotal += mediaRichness;
    }

    final projectCount = studentProjects.length;
    final projectCoverage = (projectCount / 8.0).clamp(0.0, 1.0).toDouble();
    final divisor = projectCount == 0 ? 1.0 : projectCount.toDouble();
    final projectEngagement = (engagementTotal / divisor).clamp(0.0, 1.0);
    final projectTrust = (trustTotal / divisor).clamp(0.0, 1.0);
    final projectFreshness = (freshnessTotal / divisor).clamp(0.0, 1.0);
    final projectSkillEvidence = (projectSkillTotal / divisor).clamp(0.0, 1.0);
    final projectMediaEvidence = (mediaTotal / divisor).clamp(0.0, 1.0);

    final projectPortfolioScore = projectCount == 0
        ? 0.0
        : ((0.24 * projectCoverage) +
                (0.24 * projectEngagement) +
                (0.18 * projectSkillEvidence) +
                (0.14 * projectFreshness) +
                (0.12 * projectTrust) +
                (0.08 * projectMediaEvidence))
            .clamp(0.0, 1.0)
            .toDouble();

    final followerScore =
        ((math.max(profile.totalFollowers, followerCount)) / 40.0)
            .clamp(0.0, 1.0)
            .toDouble();
    final sentiment = (aiCommentSentiment ?? 0.5).clamp(0.0, 1.0).toDouble();
    final sentimentDelta =
        ((sentiment - 0.5) * 0.12).clamp(-0.06, 0.06).toDouble();

    final score = ((0.54 * profileScore) +
            (0.34 * projectPortfolioScore) +
            (0.12 * followerScore) +
            sentimentDelta)
        .clamp(0.0, 1.0)
        .toDouble();

    return GlobalStudentRankScore(
      score: score,
      breakdown: <String, double>{
        'profile_score': profileScore,
        'skill_score': skillScore,
        'activity_score': activityScore,
        'profile_post_score': profilePostScore,
        'profile_collab_score': profileCollabScore,
        'profile_completeness': completenessScore,
        'project_portfolio_score': projectPortfolioScore,
        'project_coverage': projectCoverage,
        'project_engagement': projectEngagement.toDouble(),
        'project_skill_evidence': projectSkillEvidence.toDouble(),
        'project_freshness': projectFreshness.toDouble(),
        'project_trust': projectTrust.toDouble(),
        'project_media_evidence': projectMediaEvidence.toDouble(),
        'follower_score': followerScore,
        'ai_comment_sentiment': sentiment,
        'sentiment_delta': sentimentDelta,
      },
      projectCount: projectCount,
      projectTitles: studentProjects
          .map((project) => project.title.trim())
          .where((title) => title.isNotEmpty)
          .take(5)
          .toList(growable: false),
    );
  }

  Future<Map<String, double>> scoreProjectCommentSentimentByStudent({
    required List<UserModel> students,
    required List<PostModel> projects,
    required Map<String, List<String>> commentSnippetsByPost,
    String? faculty,
  }) async {
    final selectedStudents = students.where((student) {
      if (faculty == null || faculty.isEmpty) return true;
      return student.profile?.faculty == faculty;
    }).toList(growable: false);

    final stableScoreByStudent = <String, double>{};
    for (final student in selectedStudents) {
      final comments = <String>[];
      for (final post in projects) {
        if (post.type != 'project' || post.authorId != student.id) continue;
        comments.addAll(commentSnippetsByPost[post.id] ?? const <String>[]);
      }

      final compactComments = comments
          .map((comment) => comment.trim())
          .where((comment) => comment.isNotEmpty)
          .take(8)
          .toList(growable: false);
      if (compactComments.isEmpty) continue;

      stableScoreByStudent[student.id] =
          _normalizedSentimentFromComments(compactComments);
    }

    final openAi = _openAiService;
    if (openAi == null || !openAi.isConfigured) {
      debugPrint(
        '[GlobalRankAI] skipped: openAiConfigured=false students=${students.length} projects=${projects.length} commentPosts=${commentSnippetsByPost.length}',
      );
      return stableScoreByStudent;
    }

    final payloadRows = <Map<String, dynamic>>[];
    for (final student in selectedStudents) {
      final comments = <String>[];
      for (final post in projects) {
        if (post.type != 'project' || post.authorId != student.id) continue;
        comments.addAll(commentSnippetsByPost[post.id] ?? const <String>[]);
      }

      final compactComments = comments
          .map((comment) => comment.trim())
          .where((comment) => comment.isNotEmpty)
          .take(8)
          .toList(growable: false);
      if (compactComments.isEmpty) continue;

      payloadRows.add({
        'id': student.id,
        'title':
            'Comment sentiment profile for ${student.displayName ?? student.email}',
        'category': student.profile?.faculty,
        'skills': student.profile?.skills ?? const <String>[],
        'type': 'project_comment_sentiment',
        'commentCount': compactComments.length,
        'comments': compactComments,
      });
    }

    debugPrint(
      '[GlobalRankAI] payload students=${selectedStudents.length} rows=${payloadRows.length} projects=${projects.length} commentPosts=${commentSnippetsByPost.length} faculty=${faculty ?? 'all'}',
    );

    if (payloadRows.isEmpty) return stableScoreByStudent;

    try {
      final response = await openAi.rankPosts(
        userProfile: {
          'requestType': 'general_comment_sentiment',
          'objective':
              'Score each student by positivity and constructiveness of project comments. Positive sentiment should increase score, negative sentiment should lower score.',
          'faculty': faculty,
        },
        posts: payloadRows,
      );

      final ranking = (response?['ranking'] as List?) ?? const [];
      final scoreByStudent = <String, double>{};
      for (final row in ranking) {
        if (row is! Map) continue;
        final data = Map<String, dynamic>.from(row);
        final id = (data['postId'] ?? data['id'])?.toString();
        if (id == null || id.isEmpty) continue;
        final rawScore =
            data['score'] ?? data['sentimentScore'] ?? data['finalScore'];
        final parsed = rawScore is num
            ? rawScore.toDouble()
            : double.tryParse(rawScore?.toString() ?? '');
        if (parsed == null) continue;
        scoreByStudent[id] = parsed.clamp(0.0, 1.0).toDouble();
      }
      debugPrint(
        '[GlobalRankAI] response rows=${ranking.length} parsed=${scoreByStudent.length} stable=${stableScoreByStudent.length} scores=${scoreByStudent.entries.take(6).map((entry) => '${entry.key}:${entry.value.toStringAsFixed(3)}').join(', ')}',
      );
      if (scoreByStudent.isEmpty) return stableScoreByStudent;
      return <String, double>{
        ...stableScoreByStudent,
        ...scoreByStudent,
      };
    } catch (error) {
      debugPrint('[GlobalRankAI] failed: $error');
      return stableScoreByStudent;
    }
  }

  double _globalStudentTimeBoost(
    DateTime updatedAt,
    GlobalStudentRankTimeRange timeRange,
  ) {
    final days = DateTime.now().difference(updatedAt).inDays;
    switch (timeRange) {
      case GlobalStudentRankTimeRange.sprint:
        if (days <= 30) return 1.0;
        if (days <= 90) return (1.0 - ((days - 30) / 120)).clamp(0.35, 1.0);
        return 0.35;
      case GlobalStudentRankTimeRange.term:
        if (days <= 120) return 1.0;
        if (days <= 240) {
          return (1.0 - ((days - 120) / 240)).clamp(0.55, 1.0);
        }
        return 0.55;
      case GlobalStudentRankTimeRange.allTime:
        return 1.0;
    }
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

  double _academicYearScore(int? yearOfStudy) {
    if (yearOfStudy == null || yearOfStudy <= 0) return 0.0;
    return (yearOfStudy / 5.0).clamp(0.0, 1.0).toDouble();
  }

  double _logNorm(int value, {required int maxInput}) {
    final safe = value < 0 ? 0 : value;
    final numerator = math.log(1 + safe);
    final denominator = math.log(1 + maxInput);
    if (denominator <= 0) return 0.0;
    return (numerator / denominator).clamp(0.0, 1.0).toDouble();
  }

  Set<String> _normalizeTerms(Set<String> input) => input
      .map((term) => term.trim().toLowerCase())
      .where((term) => term.isNotEmpty)
      .toSet();

  bool _matchesPostSearchIntent(PostModel post, Set<String> searchTerms) {
    if (searchTerms.isEmpty) return false;
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
    if (searchTerms.isEmpty) return false;
    final haystack = [
      user.displayName ?? '',
      user.email,
      user.profile?.faculty ?? '',
      user.profile?.programName ?? '',
      ...?user.profile?.skills,
    ].join(' ').toLowerCase();

    return searchTerms.any(haystack.contains);
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
      weightedScore +=
          lecturerRating.clamp(0.0, 1.0).toDouble() * lecturerWeight;
      totalWeight += lecturerWeight;
    }
    if (studentRating != null) {
      weightedScore += studentRating.clamp(0.0, 1.0).toDouble() * studentWeight;
      totalWeight += studentWeight;
    }

    if (totalWeight <= 0) return null;
    return (weightedScore / totalWeight).clamp(0.0, 1.0).toDouble();
  }

  Map<String, int> _buildFacultyFrequency(List<PostModel> posts) {
    final counts = <String, int>{};
    for (final post in posts) {
      final faculty = post.faculty?.trim().toLowerCase();
      if (faculty == null || faculty.isEmpty) continue;
      counts[faculty] = (counts[faculty] ?? 0) + 1;
    }
    return counts;
  }

  String? _mostRepresentedFaculty(Map<String, int> counts) {
    if (counts.isEmpty) return null;
    String? maxFaculty;
    var maxCount = -1;
    counts.forEach((faculty, count) {
      if (count > maxCount) {
        maxCount = count;
        maxFaculty = faculty;
      }
    });
    return maxFaculty;
  }

  Set<String> _underrepresentedFaculties(Map<String, int> counts) {
    if (counts.isEmpty) return const {};
    final values = counts.values.toList()..sort();
    final cutoffIndex =
        (values.length * 0.35).floor().clamp(0, values.length - 1).toInt();
    final cutoff = values[cutoffIndex];
    return counts.entries
        .where((entry) => entry.value <= cutoff)
        .map((entry) => entry.key)
        .toSet();
  }

  bool _isSameFaculty(PostModel post, String userFaculty) {
    final postFaculty = post.faculty?.trim().toLowerCase();
    return postFaculty != null && postFaculty == userFaculty;
  }

  bool _isVideoContent(PostModel post) {
    if (post.youtubeUrl != null && post.youtubeUrl!.trim().isNotEmpty) {
      return true;
    }
    for (final url in post.mediaUrls) {
      final lower = url.toLowerCase();
      if (RegExp(r'\.(mp4|mov|m4v|3gp|webm|mkv)(\?|$)').hasMatch(lower)) {
        return true;
      }
      if (lower.contains('/videos/') || lower.contains('video/upload')) {
        return true;
      }
    }
    return false;
  }

  bool _isCrossFaculty(PostModel post, String userFaculty) {
    final postFaculty = post.faculty?.trim().toLowerCase();
    return postFaculty != null && postFaculty != userFaculty;
  }

  bool _isExplorationCandidate(RecommendedPost item, String userFaculty) {
    final cross = _isCrossFaculty(item.post, userFaculty);
    if (!cross) return false;
    final hasSkillMatch = item.reasons.contains('skill_match');
    final hasSearchIntent = item.reasons.contains('search_intent');
    return !hasSkillMatch && !hasSearchIntent;
  }

  String? _extractClusterId(Set<String> tokens) {
    for (final token in tokens) {
      final lower = token.toLowerCase().trim();
      if (!lower.startsWith('cluster:')) continue;
      final id = lower.substring('cluster:'.length).trim();
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  Set<String> _extractClusterNeighbors(List<String> tags) {
    final neighbors = <String>{};
    for (final tag in tags) {
      final lower = tag.toLowerCase().trim();
      if (!lower.startsWith('cluster_neighbor:')) continue;
      final raw = lower.substring('cluster_neighbor:'.length).trim();
      if (raw.isEmpty) continue;
      neighbors.addAll(
        raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
    }
    return neighbors;
  }

  double? _extractClusterDistance(List<String> tags) {
    for (final tag in tags) {
      final lower = tag.toLowerCase().trim();
      if (!lower.startsWith('cluster_distance:')) continue;
      final raw = lower.substring('cluster_distance:'.length).trim();
      final parsed = double.tryParse(raw);
      if (parsed != null && parsed >= 0) return parsed;
    }
    return null;
  }
}

class _PostWeightVector {
  const _PostWeightVector({
    required this.contentSimilarity,
    required this.behavioralRelevance,
    required this.clusterAffinity,
    required this.qualityScore,
    required this.freshness,
    required this.diversity,
    required this.trustAdjusted,
  });

  final double contentSimilarity;
  final double behavioralRelevance;
  final double clusterAffinity;
  final double qualityScore;
  final double freshness;
  final double diversity;
  final double trustAdjusted;
}

class _PatternClusterMatch {
  const _PatternClusterMatch({
    required this.clusterId,
    required this.score,
  });

  final String clusterId;
  final double score;
}
