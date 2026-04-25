import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class OpenAiService {
  // Separate timeouts: LLM responses can take 10-30 s for moderate prompts.
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _sendTimeout = Duration(seconds: 15);
  static const Duration _receiveTimeout = Duration(seconds: 60);

  OpenAiService({
    required String apiKey,
    Dio? dio,
    String model = 'gpt-4o-mini',
  })  : _apiKey = apiKey.trim(),
        _model = model,
        _dio = dio ?? Dio();

  final Dio _dio;
  final String _apiKey;
  final String _model;

  static const String _proxyUrlFromEnv = String.fromEnvironment(
    'OPENAI_PROXY_URL',
    defaultValue: '',
  );

  static const String _skillPatternProxyUrlFromEnv = String.fromEnvironment(
    'OPENAI_SKILL_PATTERN_PROXY_URL',
    defaultValue: '',
  );

  static const String _defaultProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'star-track-4ba2b',
  );

  bool get isConfigured {
    if (kIsWeb) return _rerankProxyEndpoint.trim().isNotEmpty;
    return _apiKey.isNotEmpty;
  }

  Future<String?> generateJson(String prompt) async {
    if (!isConfigured) return null;

    final response = await _dio.post(
      'https://api.openai.com/v1/chat/completions',
      data: {
        'model': _model,
        'temperature': 0.2,
        'response_format': {'type': 'json_object'},
        'messages': [
          {
            'role': 'system',
            'content':
                'You are the MUST StarTrack intelligent assistant. '
                'You know the platform deeply and always respond with valid JSON only.',
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
      },
      options: Options(
        contentType: Headers.jsonContentType,
        connectTimeout: _connectTimeout,
        sendTimeout: _sendTimeout,
        receiveTimeout: _receiveTimeout,
        headers: {
          'Authorization': 'Bearer $_apiKey',
        },
      ),
    );

    final data = response.data;
    final choices = (data['choices'] as List?) ?? const [];
    if (choices.isEmpty) return null;

    final message = choices.first['message'] as Map?;
    final content = message?['content']?.toString();
    if (content == null || content.trim().isEmpty) return null;
    return content;
  }

  Future<Map<String, dynamic>?> rankPosts({
    required Map<String, dynamic> userProfile,
    required List<Map<String, dynamic>> posts,
  }) async {
    if (kIsWeb) {
      return _rankPostsViaProxy(userProfile: userProfile, posts: posts);
    }

    final prompt = '''
Return strict JSON with key "ranking" as array of objects {"postId": string, "score": number, "reason": string}.
Use higher score for stronger skill/program/faculty match and recent engagement relevance.
User: ${jsonEncode(userProfile)}
Posts: ${jsonEncode(posts)}
''';

    final raw = await generateJson(prompt);
    if (raw == null || raw.isEmpty) return null;

    final normalizedRaw = _stripCodeFences(raw).trim();
    try {
      final decoded = jsonDecode(normalizedRaw);
      if (decoded is Map<String, dynamic>) {
        if (decoded['ranking'] is List) return decoded;
        if (decoded['results'] is List) {
          return <String, dynamic>{'ranking': decoded['results']};
        }
      }
      if (decoded is List) {
        return <String, dynamic>{'ranking': decoded};
      }
    } catch (_) {
      // Fall through to loose extraction.
    }

    final extracted = _extractFirstJsonObject(normalizedRaw);
    if (extracted == null) return null;
    try {
      final decoded = jsonDecode(extracted);
      if (decoded is Map<String, dynamic>) {
        if (decoded['ranking'] is List) return decoded;
        if (decoded['results'] is List) {
          return <String, dynamic>{'ranking': decoded['results']};
        }
      }
      if (decoded is List) {
        return <String, dynamic>{'ranking': decoded};
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<Map<String, dynamic>?> clusterSkills({
    required List<String> skills,
    required String mode,
    int maxClusters = 6,
  }) async {
    if (skills.isEmpty) {
      return <String, dynamic>{
        'source': 'empty',
        'mode': mode,
        'clusters': const <Map<String, dynamic>>[],
        'correlations': const <Map<String, dynamic>>[],
        'normalizedSkills': const <String>[],
      };
    }

    if (kIsWeb) {
      return _clusterSkillsViaProxy(
        skills: skills,
        mode: mode,
        maxClusters: maxClusters,
      );
    }

    final prompt = '''
Return strict JSON with keys:
- "clusters": array of objects {"id": string, "label": string, "skills": string[], "keywords": string[], "summary": string}
- "correlations": array of objects {"from": string, "to": string, "weight": number, "reason": string}
- "normalizedSkills": string[]
- "source": "openai"
- "mode": string

Task:
Group semantically similar skills for recommendation systems.
Use stable, human-readable cluster labels.
Provide useful cross-cluster correlations between complementary skills.
Correlations must have weight between 0 and 1.

Mode: $mode
Max clusters: $maxClusters
Skills: ${jsonEncode(skills)}
''';

    final raw = await generateJson(prompt);
    if (raw == null || raw.isEmpty) return null;

    final normalizedRaw = _stripCodeFences(raw).trim();
    try {
      final decoded = jsonDecode(normalizedRaw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // fall through
    }

    final extracted = _extractFirstJsonObject(normalizedRaw);
    if (extracted == null) return null;
    try {
      final decoded = jsonDecode(extracted);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<Map<String, dynamic>?> _rankPostsViaProxy({
    required Map<String, dynamic> userProfile,
    required List<Map<String, dynamic>> posts,
  }) async {
    final endpoint = _rerankProxyEndpoint;

    try {
      final response = await _dio.post(
        endpoint,
        data: <String, dynamic>{
          'userProfile': userProfile,
          'posts': posts,
        },
        options: Options(
          contentType: Headers.jsonContentType,
          connectTimeout: _connectTimeout,
          sendTimeout: _sendTimeout,
          receiveTimeout: _receiveTimeout,
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _clusterSkillsViaProxy({
    required List<String> skills,
    required String mode,
    required int maxClusters,
  }) async {
    final endpoint = _skillPatternProxyEndpoint;

    try {
      final response = await _dio.post(
        endpoint,
        data: <String, dynamic>{
          'skills': skills,
          'mode': mode,
          'maxClusters': maxClusters,
        },
        options: Options(
          contentType: Headers.jsonContentType,
          connectTimeout: _connectTimeout,
          sendTimeout: _sendTimeout,
          receiveTimeout: _receiveTimeout,
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  String get _rerankProxyEndpoint {
    final fromEnv = _proxyUrlFromEnv.trim();
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'https://us-central1-$_defaultProjectId.cloudfunctions.net/openAiRerank';
  }

  String get _skillPatternProxyEndpoint {
    final fromEnv = _skillPatternProxyUrlFromEnv.trim();
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'https://us-central1-$_defaultProjectId.cloudfunctions.net/openAiSkillPatterns';
  }

  String _stripCodeFences(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    final withoutStart = trimmed.replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*\s*'), '');
    return withoutStart.replaceFirst(RegExp(r'\s*```$'), '').trim();
  }

  String? _extractFirstJsonObject(String input) {
    final start = input.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    for (var i = start; i < input.length; i++) {
      final ch = input[i];
      if (ch == '{') depth += 1;
      if (ch == '}') depth -= 1;
      if (depth == 0) {
        return input.substring(start, i + 1);
      }
    }
    return null;
  }
}
