class SkillPatternCluster {
  const SkillPatternCluster({
    required this.id,
    required this.label,
    required this.skills,
    this.keywords = const <String>[],
    this.summary,
  });

  final String id;
  final String label;
  final List<String> skills;
  final List<String> keywords;
  final String? summary;

  factory SkillPatternCluster.fromMap(Map<String, dynamic> map) {
    List<String> toStringList(dynamic raw) {
      if (raw is! List) return const <String>[];
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }

    final id = (map['id'] ?? map['clusterId'] ?? '').toString().trim();
    final label = (map['label'] ?? map['name'] ?? id).toString().trim();

    return SkillPatternCluster(
      id: id.isEmpty ? 'cluster_unknown' : id,
      label: label.isEmpty ? 'Unlabeled cluster' : label,
      skills: toStringList(map['skills']),
      keywords: toStringList(map['keywords']),
      summary: (map['summary'] ?? map['description'])?.toString().trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'skills': skills,
      'keywords': keywords,
      'summary': summary,
    };
  }
}

class SkillPatternCorrelation {
  const SkillPatternCorrelation({
    required this.fromClusterId,
    required this.toClusterId,
    required this.weight,
    this.reason,
  });

  final String fromClusterId;
  final String toClusterId;
  final double weight;
  final String? reason;

  factory SkillPatternCorrelation.fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic raw) {
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw?.toString() ?? '');
      if (parsed == null) return 0.0;
      return parsed;
    }

    final from = (map['from'] ?? map['fromClusterId'] ?? '')
        .toString()
        .trim();
    final to = (map['to'] ?? map['toClusterId'] ?? '').toString().trim();

    return SkillPatternCorrelation(
      fromClusterId: from,
      toClusterId: to,
      weight: toDouble(map['weight']).clamp(0.0, 1.0).toDouble(),
      reason: map['reason']?.toString().trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'from': fromClusterId,
      'to': toClusterId,
      'weight': weight,
      'reason': reason,
    };
  }
}

class SkillPatternResult {
  const SkillPatternResult({
    required this.clusters,
    required this.correlations,
    required this.normalizedSkills,
    required this.source,
    this.mode,
    this.rawPayload = const <String, dynamic>{},
  });

  final List<SkillPatternCluster> clusters;
  final List<SkillPatternCorrelation> correlations;
  final List<String> normalizedSkills;
  final String source;
  final String? mode;
  final Map<String, dynamic> rawPayload;

  bool get hasClusters => clusters.isNotEmpty;

  factory SkillPatternResult.empty({
    String source = 'empty',
    String? mode,
  }) {
    return SkillPatternResult(
      clusters: const <SkillPatternCluster>[],
      correlations: const <SkillPatternCorrelation>[],
      normalizedSkills: const <String>[],
      source: source,
      mode: mode,
    );
  }

  factory SkillPatternResult.fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>> toMapList(dynamic raw) {
      if (raw is! List) return const <Map<String, dynamic>>[];
      return raw
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false);
    }

    List<String> toStringList(dynamic raw) {
      if (raw is! List) return const <String>[];
      return raw
          .map((item) => item.toString().trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }

    final clusters = toMapList(map['clusters'])
        .map(SkillPatternCluster.fromMap)
        .toList(growable: false);

    final correlations = toMapList(map['correlations'])
        .map(SkillPatternCorrelation.fromMap)
        .where((corr) =>
            corr.fromClusterId.isNotEmpty && corr.toClusterId.isNotEmpty)
        .toList(growable: false);

    return SkillPatternResult(
      clusters: clusters,
      correlations: correlations,
      normalizedSkills: toStringList(map['normalizedSkills'] ?? map['skills']),
      source: (map['source'] ?? 'unknown').toString(),
      mode: map['mode']?.toString(),
      rawPayload: map,
    );
  }
}