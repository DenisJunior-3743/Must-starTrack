import 'dart:convert';

import 'package:dio/dio.dart';

class GeminiService {
  GeminiService({
    required String apiKey,
    Dio? dio,
    String model = 'gemini-1.5-flash',
  })  : _apiKey = apiKey,
        _model = model,
        _dio = dio ?? Dio();

  final Dio _dio;
  final String _apiKey;
  final String _model;

  bool get isConfigured => _apiKey.trim().isNotEmpty;

  Future<String?> generateJson(String prompt) async {
    if (!isConfigured) return null;

    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

    final response = await _dio.post(
      url,
      queryParameters: {'key': _apiKey},
      data: {
        'generationConfig': {
          'responseMimeType': 'application/json',
          'temperature': 0.2,
        },
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ]
      },
      options: Options(contentType: Headers.jsonContentType),
    );

    final data = response.data;
    final candidates = (data['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) return null;
    final content = candidates.first['content'];
    final parts = (content?['parts'] as List?) ?? const [];
    if (parts.isEmpty) return null;
    return parts.first['text']?.toString();
  }

  Future<Map<String, dynamic>?> rankPosts({
    required Map<String, dynamic> userProfile,
    required List<Map<String, dynamic>> posts,
  }) async {
    final prompt = '''
Return strict JSON with key "ranking" as array of objects {"postId": string, "score": number, "reason": string}.
Use higher score for stronger skill/program/faculty match and recent engagement relevance.
User: ${jsonEncode(userProfile)}
Posts: ${jsonEncode(posts)}
''';

    final raw = await generateJson(prompt);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}