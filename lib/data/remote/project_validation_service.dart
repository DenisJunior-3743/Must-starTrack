import 'dart:convert';

import '../../core/constants/app_enums.dart';
import '../../core/utils/media_path_utils.dart';
import '../models/post_model.dart';
import 'openai_service.dart';

class ProjectValidationService {
  ProjectValidationService({required OpenAiService openAiService})
      : _openAiService = openAiService;

  final OpenAiService _openAiService;

  Future<PostModel> reviewPendingPost(PostModel post) async {
    if (post.type.toLowerCase() != 'project' ||
        post.moderationStatus != ModerationStatus.pending) {
      return post;
    }

    if (!_openAiService.isConfigured) {
      return _manualFallback(
        post,
        'AI review is not configured on this platform. Human review required.',
      );
    }

    try {
      final payload = await _openAiService.validateProjectPost(
        post: _validationPayload(post),
      );
      if (payload == null) {
        return _manualFallback(post, 'AI review could not run.');
      }
      if (payload['error'] != null) {
        return _manualFallback(
          post,
          'AI review could not run: ${payload['error']}.',
        );
      }
      final result = _ProjectValidationResult.fromMap(payload);
      return post.copyWith(
        moderationStatus: ModerationStatus.pending,
        trustScore: result.trustScore,
        aiReviewStatus: 'completed',
        aiDecision: result.decision,
        aiConfidence: result.confidence,
        aiScores: result.scores,
        aiFindings: result.findings,
        aiEvidence: result.evidence,
        aiFinalTake: result.finalTake,
        aiMediaAnalysis: result.mediaAnalysis,
        aiReviewedAt: DateTime.now(),
      );
    } catch (_) {
      return _manualFallback(post, 'AI review failed. Human review required.');
    }
  }

  PostModel _manualFallback(PostModel post, String reason) {
    return post.copyWith(
      aiReviewStatus: 'failed',
      aiDecision: 'needs_human',
      aiConfidence: 0,
      aiScores: const {},
      aiFindings: [reason],
      aiEvidence: const [],
      aiFinalTake: 'Keep this post in manual review.',
      aiMediaAnalysis: const {},
      aiReviewedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> _validationPayload(PostModel post) {
    final remoteMediaUrls = post.mediaUrls
        .where((url) => !isLocalMediaPath(url))
        .where((url) =>
            url.trim().startsWith('http://') ||
            url.trim().startsWith('https://'))
        .toList(growable: false);
    final videoCount = post.mediaUrls.where(isVideoMediaPath).length;
    final imageCount = post.mediaUrls.length - videoCount;
    final localMediaCount = post.mediaUrls.length - remoteMediaUrls.length;

    return <String, dynamic>{
      'id': post.id,
      'type': post.type,
      'title': post.title,
      'description': post.description,
      'faculty': post.faculty,
      'program': post.program,
      'category': post.category,
      'skillsUsed': post.skillsUsed,
      'tags': post.tags,
      'youtubeUrl': post.youtubeUrl,
      'externalLinks': post.externalLinks,
      'ownershipAnswers': post.ownershipAnswers,
      'contentValidationAnswers': post.contentValidationAnswers,
      'mediaUrls': remoteMediaUrls,
      'mediaCount': post.mediaUrls.length,
      'remoteMediaCount': remoteMediaUrls.length,
      'localMediaCount': localMediaCount,
      'imageCount': imageCount,
      'videoCount': videoCount,
      'authorRole': post.authorRole,
      'groupId': post.groupId,
      'groupName': post.groupName,
    };
  }
}

class _ProjectValidationResult {
  const _ProjectValidationResult({
    required this.decision,
    required this.confidence,
    required this.scores,
    required this.findings,
    required this.evidence,
    required this.finalTake,
    required this.mediaAnalysis,
  });

  final String decision;
  final double confidence;
  final Map<String, int> scores;
  final List<String> findings;
  final List<String> evidence;
  final String finalTake;
  final Map<String, dynamic> mediaAnalysis;

  bool get shouldAutoApprove =>
      decision == 'approve' &&
      confidence >= 0.86 &&
      (scores['academic_relevance'] ?? 0) >= 75 &&
      (scores['safety'] ?? 0) >= 85 &&
      (scores['ownership_evidence'] ?? 0) >= 55;

  int get trustScore {
    if (scores.isEmpty) return (confidence * 100).round().clamp(0, 100);
    final values = scores.values.toList(growable: false);
    final average = values.reduce((a, b) => a + b) / values.length;
    return ((average * 0.65) + (confidence * 100 * 0.35)).round().clamp(0, 100);
  }

  factory _ProjectValidationResult.fromMap(Map<String, dynamic> map) {
    final decision = _normalizeDecision(map['decision']);
    final confidence = _toDouble(map['confidence']).clamp(0, 1).toDouble();
    final rawScores = map['scores'];
    final scores = <String, int>{};
    if (rawScores is Map) {
      for (final entry in rawScores.entries) {
        scores[entry.key.toString()] = _toInt(entry.value).clamp(0, 100);
      }
    }

    return _ProjectValidationResult(
      decision: decision,
      confidence: confidence,
      scores: scores,
      findings: _toStringList(map['findings'] ?? map['flags']),
      evidence: _toStringList(map['evidence'] ?? map['evidence_needed']),
      finalTake: (map['final_take'] ??
              map['finalTake'] ??
              map['admin_summary'] ??
              'Human review recommended.')
          .toString()
          .trim(),
      mediaAnalysis: _toDynamicMap(map['mediaAnalysis'] ?? map['media_analysis']),
    );
  }

  static String _normalizeDecision(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'approve' ||
        normalized == 'reject' ||
        normalized == 'needs_human') {
      return normalized;
    }
    return 'needs_human';
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    if (value is String && value.trim().startsWith('[')) {
      try {
        return _toStringList(jsonDecode(value));
      } catch (_) {}
    }
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? const [] : [text];
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static Map<String, dynamic> _toDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }
}
