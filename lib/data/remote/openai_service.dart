import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class OpenAiService {
  // Separate timeouts: LLM responses can take 10-30 s for moderate prompts.
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _sendTimeout = Duration(seconds: 15);
  static const Duration _receiveTimeout = Duration(seconds: 60);
  static const Duration _projectValidationReceiveTimeout =
      Duration(seconds: 28);

  OpenAiService({
    required String apiKey,
    Dio? dio,
    String model = 'gpt-4o-mini',
    String diagnosticsTag = 'app',
  })  : _apiKey = apiKey.trim(),
        _model = model,
        _diagnosticsTag = diagnosticsTag,
        _dio = dio ?? Dio() {
    _logInitializationStatus();
  }

  final Dio _dio;
  final String _apiKey;
  final String _model;
  final String _diagnosticsTag;

  static const String _proxyUrlFromEnv = String.fromEnvironment(
    'OPENAI_PROXY_URL',
    defaultValue: '',
  );

  static const String _proxyBaseUrlFromEnv = String.fromEnvironment(
    'OPENAI_PROXY_BASE_URL',
    defaultValue: '',
  );

  static const String _skillPatternProxyUrlFromEnv = String.fromEnvironment(
    'OPENAI_SKILL_PATTERN_PROXY_URL',
    defaultValue: '',
  );

  static const String _projectValidationProxyUrlFromEnv =
      String.fromEnvironment(
    'OPENAI_PROJECT_VALIDATION_PROXY_URL',
    defaultValue: '',
  );

  static const String _chatbotProxyUrlFromEnv = String.fromEnvironment(
    'OPENAI_CHATBOT_PROXY_URL',
    defaultValue: '',
  );

  bool get isConfigured {
    return _apiKey.isNotEmpty ||
        _rerankProxyEndpoint.trim().isNotEmpty ||
        _chatbotProxyEndpoint.trim().isNotEmpty;
  }

  void _logInitializationStatus() {
    final hasApiKey = _apiKey.isNotEmpty;
    final hasProxy = _rerankProxyEndpoint.trim().isNotEmpty;
    final hasChatbotProxy = _chatbotProxyEndpoint.trim().isNotEmpty;
    final path = kIsWeb
        ? (hasChatbotProxy ? 'proxy_only_web' : 'missing_proxy_web')
        : (hasApiKey
            ? 'direct_openai_mobile_with_proxy_fallback'
            : 'proxy_only_mobile');
    debugPrint(
      '[OpenAIInit][$_diagnosticsTag] platform=${kIsWeb ? 'web' : 'mobile'} configured=$isConfigured hasApiKey=$hasApiKey hasProxy=$hasProxy hasChatbotProxy=$hasChatbotProxy keyChars=${_apiKey.length} model=$_model path=$path proxy=$_rerankProxyEndpoint chatbotProxy=$_chatbotProxyEndpoint',
    );
  }

  void _logRequest(String path) {
    const platform = kIsWeb ? 'web' : 'mobile';
    debugPrint(
      '[OpenAI][$_diagnosticsTag][REQUEST] platform=$platform path=$path '
      'keyChars=${_apiKey.length} proxy=$_rerankProxyEndpoint',
    );
  }

  Future<String?> generateJson(String prompt) async {
    if (kIsWeb || _apiKey.isEmpty) {
      _logRequest(kIsWeb ? 'chatbot_proxy_web' : 'chatbot_proxy_mobile');
      return _generateJsonViaProxy(prompt);
    }

    _logRequest('direct_openai');

    try {
      final response = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        data: {
          'model': _model,
          'temperature': 0.2,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content': 'You are the MUST StarTrack intelligent assistant. '
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
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      debugPrint(
        '[OpenAI][$_diagnosticsTag] direct_openai_failed '
        'status=${status ?? 'n/a'} type=${e.type} '
        'falling_back=true',
      );
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _generateJsonViaProxy(String prompt) async {
    final endpoint = _chatbotProxyEndpoint;
    if (endpoint.trim().isEmpty) return null;

    try {
      final response = await _dio.post(
        endpoint,
        data: <String, dynamic>{'prompt': prompt},
        options: Options(
          contentType: Headers.jsonContentType,
          connectTimeout: _connectTimeout,
          sendTimeout: _sendTimeout,
          receiveTimeout: _receiveTimeout,
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        final content = data['content'] ?? data['raw'] ?? data['json'];
        if (content is String && content.trim().isNotEmpty) {
          return content;
        }
        if (data['answer'] != null) {
          return jsonEncode(data);
        }
      }
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final content = map['content'] ?? map['raw'] ?? map['json'];
        if (content is String && content.trim().isNotEmpty) {
          return content;
        }
        if (map['answer'] != null) {
          return jsonEncode(map);
        }
      }
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      debugPrint(
        '[OpenAI][$_diagnosticsTag] chatbot_proxy_failed '
        'status=${status ?? 'n/a'} type=${e.type}',
      );
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> rankPosts({
    required Map<String, dynamic> userProfile,
    required List<Map<String, dynamic>> posts,
  }) async {
    if (kIsWeb || _apiKey.isEmpty) {
      _logRequest(kIsWeb ? 'proxy_web' : 'proxy_mobile');
      return _rankPostsViaProxy(userProfile: userProfile, posts: posts);
    }

    final prompt = '''
Return strict JSON with key "ranking" as array of objects {"postId": string, "score": number, "reason": string}.
Use higher score for stronger skill/program/faculty match and recent engagement relevance.
User: ${jsonEncode(userProfile)}
Posts: ${jsonEncode(posts)}
''';

    final raw = await generateJson(prompt);
    if (raw == null || raw.isEmpty) {
      return _rankPostsViaProxy(userProfile: userProfile, posts: posts);
    }

    final normalizedRaw = _stripCodeFences(raw).trim();
    Map<String, dynamic>? parsed;
    try {
      final decoded = jsonDecode(normalizedRaw);
      if (decoded is Map<String, dynamic>) {
        if (decoded['ranking'] is List) parsed = decoded;
        if (decoded['results'] is List) {
          parsed = <String, dynamic>{'ranking': decoded['results']};
        }
      }
      if (decoded is List) {
        parsed = <String, dynamic>{'ranking': decoded};
      }
    } catch (_) {
      // Fall through to loose extraction.
    }

    if (_hasRankingRows(parsed)) {
      return parsed;
    }

    final extracted = _extractFirstJsonObject(normalizedRaw);
    if (extracted == null) {
      return _rankPostsViaProxy(userProfile: userProfile, posts: posts);
    }
    try {
      final decoded = jsonDecode(extracted);
      if (decoded is Map<String, dynamic>) {
        if (decoded['ranking'] is List) {
          parsed = decoded;
        }
        if (decoded['results'] is List) {
          parsed = <String, dynamic>{'ranking': decoded['results']};
        }
      }
      if (decoded is List) {
        parsed = <String, dynamic>{'ranking': decoded};
      }
    } catch (_) {
      return _rankPostsViaProxy(userProfile: userProfile, posts: posts);
    }

    if (_hasRankingRows(parsed)) {
      return parsed;
    }

    // Keep behavior consistent with web by retrying through proxy when
    // direct mobile completion returns empty/invalid ranking payload.
    final proxy =
        await _rankPostsViaProxy(userProfile: userProfile, posts: posts);
    if (_hasRankingRows(proxy)) {
      return proxy;
    }

    return parsed ?? proxy;
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
Group semantically similar skills for recommendation systems, explicitly catering to skill distribution across university faculties and technical domains.
For example: group react, flutter, web_programming under Frontend/Mobile; python, tensorflow under AI/Data Science.
Use stable, human-readable cluster labels representing these broad domains.
Provide useful cross-cluster correlations between complementary skills.
Correlations must have weight between 0 and 1.

Mode: $mode
Max clusters: $maxClusters
Skills: ${jsonEncode(skills)}
''';

    final raw = await generateJson(prompt);
    if (raw == null || raw.isEmpty) {
      return _clusterSkillsViaProxy(
        skills: skills,
        mode: mode,
        maxClusters: maxClusters,
      );
    }

    final normalizedRaw = _stripCodeFences(raw).trim();
    Map<String, dynamic>? parsed;
    try {
      final decoded = jsonDecode(normalizedRaw);
      if (decoded is Map<String, dynamic>) parsed = decoded;
      if (decoded is Map) parsed = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // fall through
    }

    if (_hasSkillClusters(parsed)) {
      return parsed;
    }

    final extracted = _extractFirstJsonObject(normalizedRaw);
    if (extracted == null) {
      return _clusterSkillsViaProxy(
        skills: skills,
        mode: mode,
        maxClusters: maxClusters,
      );
    }
    try {
      final decoded = jsonDecode(extracted);
      if (decoded is Map<String, dynamic>) parsed = decoded;
      if (decoded is Map) parsed = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return _clusterSkillsViaProxy(
        skills: skills,
        mode: mode,
        maxClusters: maxClusters,
      );
    }

    if (_hasSkillClusters(parsed)) {
      return parsed;
    }

    final proxy = await _clusterSkillsViaProxy(
      skills: skills,
      mode: mode,
      maxClusters: maxClusters,
    );
    if (_hasSkillClusters(proxy)) {
      return proxy;
    }

    return parsed ?? proxy;
  }

  Future<Map<String, dynamic>?> validateProjectPost({
    required Map<String, dynamic> post,
  }) async {
    final mediaUrls = post['mediaUrls'];
    final hasMedia = mediaUrls is List && mediaUrls.isNotEmpty;
    if (kIsWeb || _apiKey.isEmpty || hasMedia) {
      return _validateProjectPostViaProxy(post: post);
    }

    final prompt = _projectValidationPrompt(post);
    final raw = await generateJson(prompt);
    if (raw == null || raw.isEmpty) {
      return _validateProjectPostViaProxy(post: post);
    }

    final normalizedRaw = _stripCodeFences(raw).trim();
    try {
      final decoded = jsonDecode(normalizedRaw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      final extracted = _extractFirstJsonObject(normalizedRaw);
      if (extracted != null) {
        try {
          final decoded = jsonDecode(extracted);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
    }

    return _validateProjectPostViaProxy(post: post);
  }

  String _projectValidationPrompt(Map<String, dynamic> post) {
    return '''
Return strict JSON only.
Required shape:
{
  "decision": "approve" | "needs_human" | "reject",
  "confidence": number between 0 and 1,
  "scores": {
    "academic_relevance": 0-100,
    "ownership_evidence": 0-100,
    "content_quality": 0-100,
    "skill_showcase": 0-100,
    "collaboration_fit": 0-100,
    "safety": 0-100
  },
  "findings": string[],
  "evidence": string[],
  "final_take": string
}

MUST StarTrack is for academic projects, skill showcasing, research, practical learning, and collaboration across all university faculties.
Apply faculty-aware evidence rules:
- Computing/FCI/software projects: GitHub, demos, app links, screenshots, architecture notes, or technical detail are strong ownership signals. Missing links can reduce ownership confidence.
- Applied Sciences, Engineering, and hardware projects: prototypes, lab setup, device photos/videos, procedures, measurements, materials, or test results are valid evidence. Links are optional.
- Medicine and health sciences: research abstracts, methodology, ethics-aware descriptions, case/lab summaries, anonymized findings, supervision, and citations are valid evidence. Do not require GitHub/demo links.
- Business, education, humanities, and other faculties: fieldwork, reports, surveys, artifacts, lesson materials, analysis, or portfolio evidence can be valid.
Never penalize a non-computing project merely because it has no external link.
Auto-approve only if the post is clearly academic, safe, and has enough ownership/content evidence for its faculty.
Use needs_human when evidence is ambiguous, ownership is weak, the faculty context is unclear, or the project needs manual academic judgment.
Reject only obvious spam, unrelated promotion, unsafe content, impersonation, or non-academic content.
Give strong weight to the supplied ownershipAnswers and contentValidationAnswers.
For ownership: verify whether the answers clearly state the student's role, contribution, group/individual ownership, process, evidence, and originality.
For content validation: verify whether the answers clearly explain academic purpose, methods, skills/learning, audience/collaboration value, and absence of policy violations.
If a project is really group work but is posted as an individual project, choose needs_human unless the answers explain why the author may post it individually.

Post: ${jsonEncode(post)}
''';
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
          receiveTimeout: _projectValidationReceiveTimeout,
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{
        'ranking': const <Map<String, dynamic>>[],
        'error': 'proxy_invalid_payload',
      };
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      return <String, dynamic>{
        'ranking': const <Map<String, dynamic>>[],
        'error': status == null ? 'proxy_exception' : 'proxy_http_$status',
      };
    } catch (_) {
      return <String, dynamic>{
        'ranking': const <Map<String, dynamic>>[],
        'error': 'proxy_exception',
      };
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
          receiveTimeout: _projectValidationReceiveTimeout,
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{
        'clusters': const <Map<String, dynamic>>[],
        'error': 'proxy_invalid_payload',
      };
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      return <String, dynamic>{
        'clusters': const <Map<String, dynamic>>[],
        'error': status == null ? 'proxy_exception' : 'proxy_http_$status',
      };
    } catch (_) {
      return <String, dynamic>{
        'clusters': const <Map<String, dynamic>>[],
        'error': 'proxy_exception',
      };
    }
  }

  Future<Map<String, dynamic>?> _validateProjectPostViaProxy({
    required Map<String, dynamic> post,
  }) async {
    final endpoint = _projectValidationProxyEndpoint;
    try {
      final response = await _dio.post(
        endpoint,
        data: <String, dynamic>{'post': post},
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
      return <String, dynamic>{'error': 'proxy_invalid_payload'};
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      return <String, dynamic>{
        'error': status == null ? 'proxy_exception' : 'proxy_http_$status',
      };
    } catch (_) {
      return <String, dynamic>{'error': 'proxy_exception'};
    }
  }

  String get _rerankProxyEndpoint {
    final fromEnv = _endpointFromBaseOrOverride(
      overrideUrl: _proxyUrlFromEnv,
      path: 'openAiRerank',
    );
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return 'http://127.0.0.1:8787/openAiRerank';
    return 'http://10.0.2.2:8787/openAiRerank';
  }

  String get _skillPatternProxyEndpoint {
    final fromEnv = _endpointFromBaseOrOverride(
      overrideUrl: _skillPatternProxyUrlFromEnv,
      path: 'openAiSkillPatterns',
    );
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return 'http://127.0.0.1:8787/openAiSkillPatterns';
    return 'http://10.0.2.2:8787/openAiSkillPatterns';
  }

  String get _projectValidationProxyEndpoint {
    final fromEnv = _endpointFromBaseOrOverride(
      overrideUrl: _projectValidationProxyUrlFromEnv,
      path: 'openAiProjectValidation',
    );
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return 'http://127.0.0.1:8787/openAiProjectValidation';
    return 'http://10.0.2.2:8787/openAiProjectValidation';
  }

  String get _chatbotProxyEndpoint {
    final fromEnv = _endpointFromBaseOrOverride(
      overrideUrl: _chatbotProxyUrlFromEnv,
      path: 'openAiChatbot',
    );
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return 'http://127.0.0.1:8787/openAiChatbot';
    return 'http://10.0.2.2:8787/openAiChatbot';
  }

  String _endpointFromBaseOrOverride({
    required String overrideUrl,
    required String path,
  }) {
    final override = overrideUrl.trim();
    if (override.isNotEmpty) return override;

    final base = _proxyBaseUrlFromEnv.trim();
    if (base.isEmpty) return '';
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$normalizedBase/$path';
  }

  String _stripCodeFences(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    final withoutStart =
        trimmed.replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*\s*'), '');
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

  bool _hasRankingRows(Map<String, dynamic>? payload) {
    final ranking = payload?['ranking'];
    return ranking is List && ranking.isNotEmpty;
  }

  bool _hasSkillClusters(Map<String, dynamic>? payload) {
    final clusters = payload?['clusters'];
    return clusters is List && clusters.isNotEmpty;
  }
}
