import '../../../data/models/post_model.dart';
import '../../../data/remote/recommender_service.dart';

class RecommendationBenchmarkSnapshot {
  const RecommendationBenchmarkSnapshot({
    required this.localAverageTopN,
    required this.hybridAverageTopN,
    required this.liftPercent,
    required this.topNOverlapRatio,
    required this.comparedCount,
    required this.reasonDistribution,
    required this.algorithmLogCounts,
    required this.mediaValidation,
  });

  final double localAverageTopN;
  final double hybridAverageTopN;
  final double liftPercent;
  final double topNOverlapRatio;
  final int comparedCount;
  final Map<String, int> reasonDistribution;
  final Map<String, int> algorithmLogCounts;
  final MediaValidationBenchmark mediaValidation;
}

class MediaValidationBenchmark {
  const MediaValidationBenchmark({
    required this.mediaPosts,
    required this.imagePosts,
    required this.videoPosts,
    required this.audioPosts,
    required this.aiReviewedMediaPosts,
    required this.averageAiConfidence,
    required this.averageMediaScore,
    required this.needsHumanCount,
    required this.scoreDistribution,
  });

  final int mediaPosts;
  final int imagePosts;
  final int videoPosts;
  final int audioPosts;
  final int aiReviewedMediaPosts;
  final double averageAiConfidence;
  final double averageMediaScore;
  final int needsHumanCount;
  final Map<String, double> scoreDistribution;
}

RecommendationBenchmarkSnapshot buildRecommendationBenchmark({
  required List<RecommendedPost> localResults,
  required List<RecommendedPost> hybridResults,
  required List<Map<String, dynamic>> remoteLogs,
  List<PostModel> projectPosts = const <PostModel>[],
  int topN = 10,
}) {
  final safeTopN = topN <= 0 ? 10 : topN;

  final localTop = localResults.take(safeTopN).toList(growable: false);
  final hybridTop = hybridResults.take(safeTopN).toList(growable: false);

  final localAvg = _averageScore(localTop);
  final hybridAvg = _averageScore(hybridTop);

  final lift =
      localAvg <= 0 ? 0.0 : (((hybridAvg - localAvg) / localAvg) * 100.0);

  final localIds = localTop.map((item) => item.post.id).toSet();
  final hybridIds = hybridTop.map((item) => item.post.id).toSet();
  final overlap = localIds.isEmpty
      ? 0.0
      : (localIds.intersection(hybridIds).length / localIds.length);

  final reasons = <String, int>{};
  for (final item in hybridTop) {
    for (final reason in item.reasons) {
      final normalized = reason.trim();
      if (normalized.isEmpty) continue;
      reasons[normalized] = (reasons[normalized] ?? 0) + 1;
    }
  }

  final algorithmCounts = <String, int>{};
  for (final row in remoteLogs) {
    final rawAlgorithm = (row['algorithm'] ?? row['algo'] ?? '').toString();
    final algorithm = rawAlgorithm.trim();
    if (algorithm.isEmpty) continue;
    algorithmCounts[algorithm] = (algorithmCounts[algorithm] ?? 0) + 1;
  }

  return RecommendationBenchmarkSnapshot(
    localAverageTopN: localAvg,
    hybridAverageTopN: hybridAvg,
    liftPercent: lift,
    topNOverlapRatio: overlap,
    comparedCount:
        localTop.length < hybridTop.length ? localTop.length : hybridTop.length,
    reasonDistribution: reasons,
    algorithmLogCounts: algorithmCounts,
    mediaValidation: buildMediaValidationBenchmark(projectPosts),
  );
}

double _averageScore(List<RecommendedPost> rows) {
  if (rows.isEmpty) return 0.0;
  var sum = 0.0;
  for (final row in rows) {
    sum += row.score;
  }
  return sum / rows.length;
}

MediaValidationBenchmark buildMediaValidationBenchmark(List<PostModel> posts) {
  final mediaPosts = posts
      .where((post) => post.mediaUrls.isNotEmpty || post.youtubeUrl != null)
      .toList(growable: false);
  final reviewed = mediaPosts
      .where((post) => (post.aiReviewStatus ?? '').isNotEmpty)
      .toList(growable: false);

  final confidences = reviewed
      .map((post) => post.aiConfidence ?? 0)
      .where((value) => value > 0)
      .toList(growable: false);
  final mediaScores = reviewed
      .map(_mediaScoreForPost)
      .where((value) => value > 0)
      .toList(growable: false);

  return MediaValidationBenchmark(
    mediaPosts: mediaPosts.length,
    imagePosts: mediaPosts.where(_hasImageMedia).length,
    videoPosts: mediaPosts.where(_hasVideoMedia).length,
    audioPosts: mediaPosts.where(_hasAudioMedia).length,
    aiReviewedMediaPosts: reviewed.length,
    averageAiConfidence: _average(confidences),
    averageMediaScore: _average(mediaScores),
    needsHumanCount:
        reviewed.where((post) => post.aiDecision == 'needs_human').length,
    scoreDistribution: <String, double>{
      'visual': _averageScoreKey(reviewed, 'media_visual_alignment'),
      'audio': _averageScoreKey(reviewed, 'media_audio_relevance'),
      'description': _averageScoreKey(reviewed, 'media_description_match'),
      'ownership': _averageScoreKey(reviewed, 'ownership_evidence'),
      'content': _averageScoreKey(reviewed, 'content_quality'),
    },
  );
}

double _mediaScoreForPost(PostModel post) {
  final values = [
    post.aiScores['media_visual_alignment'],
    post.aiScores['media_audio_relevance'],
    post.aiScores['media_description_match'],
  ].whereType<int>().where((value) => value > 0).toList(growable: false);
  return _average(values.map((value) => value.toDouble()).toList());
}

double _averageScoreKey(List<PostModel> posts, String key) {
  return _average(posts
      .map((post) => (post.aiScores[key] ?? 0).toDouble())
      .where((value) => value > 0)
      .toList(growable: false));
}

double _average(List<double> values) {
  if (values.isEmpty) return 0.0;
  return values.reduce((a, b) => a + b) / values.length;
}

bool _hasImageMedia(PostModel post) => post.mediaUrls.any((url) {
      final lower = url.toLowerCase();
      return lower.contains('/image/upload/') ||
          RegExp(r'\.(png|jpe?g|webp|gif|bmp)(\?|$)').hasMatch(lower);
    });

bool _hasVideoMedia(PostModel post) =>
    post.youtubeUrl != null ||
    post.mediaUrls.any((url) {
      final lower = url.toLowerCase();
      return lower.contains('/video/upload/') ||
          RegExp(r'\.(mp4|mov|m4v|webm|mkv|3gp)(\?|$)').hasMatch(lower);
    });

bool _hasAudioMedia(PostModel post) => post.mediaUrls.any((url) {
      final lower = url.toLowerCase();
      return RegExp(r'\.(mp3|m4a|wav|aac|ogg|oga|flac|mpga|mpeg)(\?|$)')
          .hasMatch(lower);
    });
