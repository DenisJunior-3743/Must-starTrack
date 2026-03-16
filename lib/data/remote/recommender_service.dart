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

class RecommenderService {
  RecommenderService({GeminiService? geminiService})
      : _geminiService = geminiService;

  final GeminiService? _geminiService;

  List<RecommendedPost> rankLocally({
    required UserModel user,
    required List<PostModel> candidates,
    Set<String> recentlyViewedCategories = const {},
  }) {
    final userSkills = user.profile?.skills.map((e) => e.toLowerCase()).toSet() ?? const <String>{};
    final userFaculty = user.profile?.faculty?.toLowerCase();
    final userProgram = user.profile?.programName?.toLowerCase();

    final scored = candidates.map((post) {
      double score = 0;
      final reasons = <String>[];

      final postSkills = post.skillsUsed.map((e) => e.toLowerCase()).toSet();
      final skillOverlap = userSkills.intersection(postSkills).length;
      if (skillOverlap > 0) {
        score += 0.45 * (skillOverlap.clamp(1, 5) / 5.0);
        reasons.add('skill_match');
      }

      final postFaculty = post.faculty?.toLowerCase();
      if (userFaculty != null && postFaculty == userFaculty) {
        score += 0.18;
        reasons.add('faculty_match');
      }

      final postProgram = post.program?.toLowerCase();
      if (userProgram != null && postProgram == userProgram) {
        score += 0.12;
        reasons.add('program_match');
      }

      final recencyHours = DateTime.now().difference(post.createdAt).inHours;
      final recencyScore = (1.0 - (recencyHours / (24 * 14))).clamp(0.0, 1.0);
      score += 0.15 * recencyScore;

      final engagement = (post.likeCount + post.commentCount * 2 + post.shareCount * 3).toDouble();
      final engagementScore = (engagement / 200.0).clamp(0.0, 1.0);
      score += 0.10 * engagementScore;

      if (post.category != null && recentlyViewedCategories.contains(post.category!.toLowerCase())) {
        score += 0.08;
        reasons.add('collaborative_signal');
      }

      return RecommendedPost(post: post, score: score.clamp(0.0, 1.0), reasons: reasons);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  Future<List<RecommendedPost>> rankHybrid({
    required UserModel user,
    required List<PostModel> candidates,
    Set<String> recentlyViewedCategories = const {},
  }) async {
    final localRanked = rankLocally(
      user: user,
      candidates: candidates,
      recentlyViewedCategories: recentlyViewedCategories,
    );

    final gemini = _geminiService;
    if (gemini == null || !gemini.isConfigured || localRanked.isEmpty) {
      return localRanked;
    }

    final top = localRanked.take(25).toList();
    final geminiResponse = await gemini.rankPosts(
      userProfile: {
        'role': user.role.name,
        'faculty': user.profile?.faculty,
        'program': user.profile?.programName,
        'skills': user.profile?.skills ?? const <String>[],
      },
      posts: top
          .map((e) => {
                'id': e.post.id,
                'title': e.post.title,
                'category': e.post.category,
                'skills': e.post.skillsUsed,
                'faculty': e.post.faculty,
                'program': e.post.program,
              })
          .toList(),
    );

    final ranking = (geminiResponse?['ranking'] as List?) ?? const [];
    if (ranking.isEmpty) return localRanked;

    final geminiScoreById = <String, double>{};
    for (final row in ranking) {
      if (row is Map<String, dynamic>) {
        final id = row['postId']?.toString();
        final score = (row['score'] as num?)?.toDouble();
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
  }
}