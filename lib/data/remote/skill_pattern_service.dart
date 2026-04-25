import '../models/post_model.dart';
import '../models/skill_pattern_model.dart';
import 'openai_service.dart';

class SkillPatternService {
  SkillPatternService({required OpenAiService openAiService})
      : _openAiService = openAiService;

  final OpenAiService _openAiService;

  Future<SkillPatternResult> buildFromContext({
    required List<String> userSkills,
    required List<PostModel> candidatePosts,
    required String mode,
    int maxClusters = 6,
  }) async {
    final inputSkills = <String>{
      ...userSkills,
      for (final post in candidatePosts) ...post.skillsUsed,
    }
        .map(_normalizeSkill)
        .where((skill) => skill.isNotEmpty)
        .toList(growable: false);

    if (inputSkills.length < 2) {
      return SkillPatternResult.empty(source: 'insufficient_skills', mode: mode);
    }

    final remote = await _openAiService.clusterSkills(
      skills: inputSkills,
      mode: mode,
      maxClusters: maxClusters,
    );

    if (remote != null) {
      final parsed = SkillPatternResult.fromMap(remote);
      if (parsed.hasClusters) {
        return parsed;
      }
    }

    return _buildHeuristicFallback(inputSkills, mode: mode, maxClusters: maxClusters);
  }

  SkillPatternResult _buildHeuristicFallback(
    List<String> skills, {
    required String mode,
    required int maxClusters,
  }) {
    final buckets = <String, List<String>>{};
    for (final skill in skills) {
      final bucket = _bucketForSkill(skill);
      buckets.putIfAbsent(bucket, () => <String>[]).add(skill);
    }

    final entries = buckets.entries.toList(growable: false)
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    final selected = entries.take(maxClusters).toList(growable: false);
    final clusters = <SkillPatternCluster>[];
    for (var i = 0; i < selected.length; i++) {
      final entry = selected[i];
      final uniqueSkills = entry.value.toSet().toList(growable: false);
      clusters.add(
        SkillPatternCluster(
          id: 'h_cluster_${i + 1}',
          label: _labelForBucket(entry.key),
          skills: uniqueSkills,
          keywords: _keywordsForBucket(entry.key),
          summary: 'Heuristic grouping fallback.',
        ),
      );
    }

    final correlations = <SkillPatternCorrelation>[];
    for (var i = 0; i < clusters.length; i++) {
      for (var j = i + 1; j < clusters.length; j++) {
        correlations.add(
          SkillPatternCorrelation(
            fromClusterId: clusters[i].id,
            toClusterId: clusters[j].id,
            weight: 0.35,
            reason: 'heuristic_neighbor',
          ),
        );
      }
    }

    return SkillPatternResult(
      clusters: clusters,
      correlations: correlations,
      normalizedSkills: skills,
      source: 'heuristic_fallback',
      mode: mode,
      rawPayload: <String, dynamic>{
        'source': 'heuristic_fallback',
        'mode': mode,
        'skills': skills,
      },
    );
  }

  String _normalizeSkill(String input) {
    final normalized = input.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    return normalized.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _bucketForSkill(String skill) {
    if (_containsAny(skill, const ['flutter', 'dart', 'android', 'ios', 'mobile'])) {
      return 'mobile';
    }
    if (_containsAny(skill, const ['react', 'vue', 'angular', 'html', 'css', 'javascript', 'typescript', 'frontend', 'ui'])) {
      return 'frontend';
    }
    if (_containsAny(skill, const ['node', 'express', 'spring', 'django', 'laravel', 'backend', 'api', 'server'])) {
      return 'backend';
    }
    if (_containsAny(skill, const ['sql', 'postgres', 'mysql', 'mongodb', 'firebase', 'redis', 'database'])) {
      return 'data';
    }
    if (_containsAny(skill, const ['ml', 'machine learning', 'ai', 'nlp', 'computer vision', 'deep learning', 'llm'])) {
      return 'ai';
    }
    if (_containsAny(skill, const ['devops', 'docker', 'kubernetes', 'azure', 'aws', 'gcp', 'ci/cd'])) {
      return 'cloud';
    }
    return 'general';
  }

  bool _containsAny(String value, List<String> probes) {
    for (final probe in probes) {
      if (value.contains(probe)) return true;
    }
    return false;
  }

  String _labelForBucket(String bucket) {
    switch (bucket) {
      case 'mobile':
        return 'Mobile development';
      case 'frontend':
        return 'Frontend and UX';
      case 'backend':
        return 'Backend and API';
      case 'data':
        return 'Data and storage';
      case 'ai':
        return 'AI and ML';
      case 'cloud':
        return 'Cloud and DevOps';
      default:
        return 'General skills';
    }
  }

  List<String> _keywordsForBucket(String bucket) {
    switch (bucket) {
      case 'mobile':
        return const <String>['flutter', 'android', 'ios'];
      case 'frontend':
        return const <String>['ui', 'web', 'javascript'];
      case 'backend':
        return const <String>['api', 'server', 'services'];
      case 'data':
        return const <String>['database', 'queries', 'storage'];
      case 'ai':
        return const <String>['ml', 'nlp', 'models'];
      case 'cloud':
        return const <String>['deployment', 'containers', 'infra'];
      default:
        return const <String>['skills'];
    }
  }
}