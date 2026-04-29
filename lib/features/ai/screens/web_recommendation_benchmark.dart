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
  });

  final double localAverageTopN;
  final double hybridAverageTopN;
  final double liftPercent;
  final double topNOverlapRatio;
  final int comparedCount;
  final Map<String, int> reasonDistribution;
  final Map<String, int> algorithmLogCounts;
}

RecommendationBenchmarkSnapshot buildRecommendationBenchmark({
  required List<RecommendedPost> localResults,
  required List<RecommendedPost> hybridResults,
  required List<Map<String, dynamic>> remoteLogs,
  int topN = 10,
}) {
  final safeTopN = topN <= 0 ? 10 : topN;

  final localTop = localResults.take(safeTopN).toList(growable: false);
  final hybridTop = hybridResults.take(safeTopN).toList(growable: false);

  final localAvg = _averageScore(localTop);
  final hybridAvg = _averageScore(hybridTop);

  final lift = localAvg <= 0
      ? 0.0
      : (((hybridAvg - localAvg) / localAvg) * 100.0);

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
    comparedCount: localTop.length < hybridTop.length
        ? localTop.length
        : hybridTop.length,
    reasonDistribution: reasons,
    algorithmLogCounts: algorithmCounts,
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
