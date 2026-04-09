import 'dart:async';
import 'dart:convert';

import '../../../data/remote/gemini_service.dart';
import 'chatbot_knowledge_base.dart';
import '../models/chatbot_models.dart';

class ChatbotRepository {
  ChatbotRepository({
    required List<ChatbotFaqEntry> faqs,
    required List<ChatbotKnowledgeDoc> projectDocs,
    required Set<String> knownRoutes,
    GeminiService? geminiService,
  })  : _faqs = faqs,
        _projectDocs = projectDocs,
        _knownRoutes = knownRoutes,
        _geminiService = geminiService;

  final List<ChatbotFaqEntry> _faqs;
  final List<ChatbotKnowledgeDoc> _projectDocs;
  final Set<String> _knownRoutes;
  final GeminiService? _geminiService;

  Future<ChatbotResponse> answer(
    String query, {
    required bool isGuest,
    String? role,
  }) async {
    final normalized = _normalize(query);
    if (normalized.isEmpty) {
      return const ChatbotResponse(
        answer: 'Ask me anything about MUST StarTrack features, navigation, or what is possible in your role.',
        source: ChatbotSource.fallback,
        confidence: 0,
      );
    }

    if (_isGreeting(normalized)) {
      final greetingReply = _greetingResponse(role: role, isGuest: isGuest);
      return ChatbotResponse(
        answer: greetingReply,
        source: ChatbotSource.faq,
        confidence: 1.0,
        followUps: ChatbotKnowledgeBase.starterPrompts,
      );
    }

    final local = _bestFaqMatch(normalized);
    if (local != null && local.score >= 0.42) {
      final entry = local.entry;
      return ChatbotResponse(
        answer: entry.answer,
        source: ChatbotSource.faq,
        confidence: local.score,
        actions: entry.actions,
        followUps: entry.followUps,
      );
    }

    final localDoc = _bestDocMatch(normalized);
    if (localDoc != null && localDoc.score >= 0.50) {
      final doc = localDoc.doc;
      return ChatbotResponse(
        answer: doc.summary,
        source: ChatbotSource.faq,
        confidence: localDoc.score,
        followUps: doc.followUps,
      );
    }

    final aiResponse = await _tryAiAnswer(
      question: query,
      isGuest: isGuest,
      role: role,
    );
    if (aiResponse != null) {
      return aiResponse;
    }

    final topQuestions = _faqs.take(5).map((f) => f.question).toList(growable: false);
    final categorizedFaqs = <String, List<String>>{};
    for (final faq in _faqs) {
      final group = faq.group ?? 'General';
      categorizedFaqs.putIfAbsent(group, () => []);
      categorizedFaqs[group]!.add(faq.question);
    }

    final categoryList =
        categorizedFaqs.entries.map((e) => '${e.key}: ${e.value.join(", ")}').join('\n');

    return ChatbotResponse(
      answer: '''I am still learning about that specific topic, but I can definitely help with these areas:

$categoryList

Try asking about any of the above, or feel free to ask again with more details about what you are trying to do. I'm continuously learning to better assist you!''',
      source: ChatbotSource.fallback,
      confidence: 0.2,
      followUps: topQuestions,
    );
  }

  Future<ChatbotResponse?> _tryAiAnswer({
    required String question,
    required bool isGuest,
    String? role,
  }) async {
    final gemini = _geminiService;
    if (gemini == null || !gemini.isConfigured) {
      return null;
    }

    final normalizedQuestion = _normalize(question);

    final faqPayload = _topFaqMatches(normalizedQuestion, limit: 8)
        .map((f) => {
              'id': f.id,
              'category': f.group ?? 'General',
              'question': f.question,
              'answer': f.answer,
              'keywords': f.keywords,
              'actions': f.actions
                  .map((a) => {'label': a.label, 'route': a.route})
                  .toList(growable: false),
            })
        .toList(growable: false);

        final projectSearchResults = _topDocMatches(normalizedQuestion, limit: 3)
          .map((doc) => {
              'id': doc.id,
              'title': doc.title,
              'summary': doc.summary,
              'content': doc.content,
              'keywords': doc.keywords,
            })
          .toList(growable: false);

    // ─────────────────────────────────────────────────────────────────────────
    // IMPROVED PROMPT: Comprehensive, context-aware, confidence-building
    // ─────────────────────────────────────────────────────────────────────────
    final prompt = '''
You are MUST StarTrack's intelligent support assistant. Your role is to help users understand platform features and navigate the app.

CRITICAL INSTRUCTIONS:
1. FIRST, check the KNOWLEDGE BASE below for relevant information.
2. If you find a matching FAQ, provide that answer with confidence 0.75+.
3. If you PARTIALLY match the question to multiple FAQs, synthesize a helpful answer combining them. Set confidence 0.65+.
4. If the question is about a FEATURE that SHOULD exist based on the platform description but is not in the FAQ, provide a reasonable, helpful answer based on common platform patterns. Be confident (0.55+) — don't be vague.
5. If truly unable to answer, explain what you CAN help with instead. Maintain a helpful, optimistic tone.

PLATFORM CONTEXT:
MUST StarTrack is a skill-centric academic networking platform with:
- Portfolio & project showcasing
- User discovery and collaboration tools
- AI-powered recommendations
- Role-based features (Student, Lecturer, Admin, Super Admin)
- Real-time messaging and notifications
- Group collaboration features
- Group-based project organization
- Admin moderation and analytics tools

USER CONTEXT:
- Is guest (no account): $isGuest
- User role: ${role ?? 'unknown'} 
- Access level: ${role == null || isGuest ? 'Limited (browsing only)' : 'Full access to platform features'}

AVAILABLE ROUTES FOR ACTIONS:
${_knownRoutes.toList().join(', ')}

═══════════════════════════════════════════════════════════════════════════════
MATCHED FAQ SEARCH RESULTS:
═══════════════════════════════════════════════════════════════════════════════
${jsonEncode(faqPayload)}

═══════════════════════════════════════════════════════════════════════════════
PROJECT SEARCH RESULTS:
═══════════════════════════════════════════════════════════════════════════════
${jsonEncode(projectSearchResults)}

═══════════════════════════════════════════════════════════════════════════════
USER QUESTION:
$question

═══════════════════════════════════════════════════════════════════════════════
RESPONSE REQUIREMENTS:
1. Answer must be helpful and actionable.
2. Maximum 6 sentences — be concise but complete.
3. If user is a guest, mention what requires account creation.
4. If role-specific, acknowledge their role and explain role-based limitations.
5. Always end with a suggestion or follow-up action if possible.
6. Confidence score: 0.85+ (very confident), 0.65-0.84 (confident), 0.45-0.64 (moderately confident), <0.45 (uncertain).
7. Prefer the PROJECT SEARCH RESULTS when the question is implementation-specific, such as recommender algorithms, ranking, group internals, analytics, or workflow details.

Return ONLY valid JSON with this exact shape:
{
  "answer": "string (your helpful response, 1-6 sentences)",
  "confidence": 0.0-1.0 (double, your certainty level),
  "followUps": ["string", "string"] (2-4 logically related follow-up questions),
  "actions": [{"label":"string", "route":"string"}] (relevant navigation actions, max 3)
}

RESPOND WITH ONLY THE JSON, NO ADDITIONAL TEXT.
''';

    try {
      final raw = await gemini.generateJson(prompt).timeout(const Duration(seconds: 8));
      if (raw == null || raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final answer = decoded['answer']?.toString().trim() ?? '';
      if (answer.isEmpty) return null;

      final confidence = (decoded['confidence'] as num?)?.toDouble() ?? 0.45;

      final followUpsRaw = decoded['followUps'];
      final followUps = followUpsRaw is List
          ? followUpsRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).take(4).toList(growable: false)
          : const <String>[];

      final actionsRaw = decoded['actions'];
      final actions = <ChatbotAction>[];
      if (actionsRaw is List) {
        for (final item in actionsRaw) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final label = map['label']?.toString().trim() ?? '';
          final route = map['route']?.toString().trim() ?? '';
          if (label.isEmpty || route.isEmpty) continue;
          if (!_knownRoutes.contains(route)) continue;
          actions.add(ChatbotAction(label: label, route: route));
        }
      }

      return ChatbotResponse(
        answer: answer,
        source: ChatbotSource.ai,
        confidence: confidence.clamp(0.0, 1.0),
        actions: actions,
        followUps: followUps,
      );
    } catch (_) {
      return null;
    }
  }

  _FaqMatch? _bestFaqMatch(String normalizedQuery) {
    final queryTokens = _tokens(normalizedQuery);
    if (queryTokens.isEmpty) return null;

    _FaqMatch? best;
    for (final entry in _faqs) {
      final normalizedQuestion = _normalize(entry.question);
      final normalizedKeywords = entry.keywords.map(_normalize).toList(growable: false);
      if (normalizedQuery == normalizedQuestion || normalizedKeywords.contains(normalizedQuery)) {
        return _FaqMatch(entry: entry, score: 1.0);
      }

      final phraseScore = _phraseScore(
        normalizedQuery,
        [normalizedQuestion, ...normalizedKeywords],
      );
      final tokenSet = <String>{..._tokens(normalizedQuestion)};
      for (final keyword in normalizedKeywords) {
        tokenSet.addAll(_tokens(keyword));
      }
      if (tokenSet.isEmpty) continue;

      final overlap = queryTokens.intersection(tokenSet).length.toDouble();
      final queryCoverage = overlap / queryTokens.length;
      final entryCoverage = overlap / tokenSet.length;
      final total = (queryCoverage * 0.55) + (entryCoverage * 0.20) + phraseScore;

      if (best == null || total > best.score) {
        best = _FaqMatch(entry: entry, score: total.clamp(0.0, 1.0));
      }
    }

    return best;
  }

  _DocMatch? _bestDocMatch(String normalizedQuery) {
    final ranked = _rankDocs(normalizedQuery);
    return ranked.isEmpty ? null : ranked.first;
  }

  List<ChatbotFaqEntry> _topFaqMatches(String normalizedQuery, {required int limit}) {
    final ranked = _faqs
        .map((entry) => _FaqMatch(entry: entry, score: _scoreFaqMatch(entry, normalizedQuery)))
        .where((match) => match.score > 0.12)
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    return ranked.take(limit).map((match) => match.entry).toList(growable: false);
  }

  List<ChatbotKnowledgeDoc> _topDocMatches(String normalizedQuery, {required int limit}) {
    final ranked = _rankDocs(normalizedQuery)
        .where((match) => match.score > 0.12)
        .take(limit)
        .map((match) => match.doc)
        .toList(growable: false);

    return ranked;
  }

  List<_DocMatch> _rankDocs(String normalizedQuery) {
    final queryTokens = _tokens(normalizedQuery);
    if (queryTokens.isEmpty) return const [];

    final ranked = _projectDocs
        .map((doc) {
          final normalizedTitle = _normalize(doc.title);
          final normalizedKeywords = doc.keywords.map(_normalize).toList(growable: false);
          final normalizedContent = _normalize(doc.content);
          final phraseScore = _phraseScore(
            normalizedQuery,
            [normalizedTitle, ...normalizedKeywords, normalizedContent],
          );
          final tokenSet = <String>{..._tokens(normalizedTitle), ..._tokens(normalizedContent)};
          for (final keyword in normalizedKeywords) {
            tokenSet.addAll(_tokens(keyword));
          }
          final overlap = tokenSet.isEmpty ? 0.0 : queryTokens.intersection(tokenSet).length.toDouble();
          final queryCoverage = tokenSet.isEmpty ? 0.0 : overlap / queryTokens.length;
          final docCoverage = tokenSet.isEmpty ? 0.0 : overlap / tokenSet.length;
          final score = (queryCoverage * 0.50) + (docCoverage * 0.10) + phraseScore;
          return _DocMatch(doc: doc, score: score.clamp(0.0, 1.0));
        })
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    return ranked;
  }

  double _scoreFaqMatch(ChatbotFaqEntry entry, String normalizedQuery) {
    final queryTokens = _tokens(normalizedQuery);
    if (queryTokens.isEmpty) return 0;

    final normalizedQuestion = _normalize(entry.question);
    final normalizedKeywords = entry.keywords.map(_normalize).toList(growable: false);
    if (normalizedQuery == normalizedQuestion || normalizedKeywords.contains(normalizedQuery)) {
      return 1.0;
    }

    final phraseScore = _phraseScore(
      normalizedQuery,
      [normalizedQuestion, ...normalizedKeywords],
    );
    final tokenSet = <String>{..._tokens(normalizedQuestion)};
    for (final keyword in normalizedKeywords) {
      tokenSet.addAll(_tokens(keyword));
    }
    if (tokenSet.isEmpty) return phraseScore;

    final overlap = queryTokens.intersection(tokenSet).length.toDouble();
    final queryCoverage = overlap / queryTokens.length;
    final entryCoverage = overlap / tokenSet.length;
    return ((queryCoverage * 0.55) + (entryCoverage * 0.20) + phraseScore)
        .clamp(0.0, 1.0);
  }

  double _phraseScore(String normalizedQuery, List<String> normalizedPhrases) {
    for (final phrase in normalizedPhrases) {
      if (phrase.isEmpty) continue;
      if (normalizedQuery == phrase) return 0.45;
      if (normalizedQuery.contains(phrase) || phrase.contains(normalizedQuery)) {
        return 0.35;
      }
    }
    return 0.0;
  }

  static const _greetingTokens = {
    'hi', 'hey', 'hello', 'hola', 'howdy', 'yo', 'sup', 'heya', 'hiya',
    'greetings', 'morning', 'afternoon', 'evening', 'wassup', 'whatsup',
    'salut', 'bonjour', 'hii', 'helo', 'helloo', 'heyy', 'hihi',
  };

  static const _greetingPhrases = [
    'good morning', 'good afternoon', 'good evening', 'good day',
    'what is up', 'how are you', 'how r you', 'how do you do',
  ];

  bool _isGreeting(String normalized) {
    for (final phrase in _greetingPhrases) {
      if (normalized == phrase || normalized.startsWith('$phrase ')) return true;
    }
    final tokens = normalized.split(' ').toSet();
    // Pure greeting: every non-empty token must be a greeting word (allows "hey there", "hi hi")
    final nonGreeting = tokens.where(
      (t) => t.isNotEmpty && !_greetingTokens.contains(t) && t != 'there' && t != 'all',
    );
    return nonGreeting.isEmpty && tokens.any(_greetingTokens.contains);
  }

  String _greetingResponse({String? role, required bool isGuest}) {
    final roleLabel = switch (role) {
      'lecturer' => 'Lecturer',
      'admin' || 'superAdmin' => 'Admin',
      _ => null,
    };
    final intro = roleLabel != null
        ? 'Hey there, $roleLabel! 👋'
        : 'Hey there! 👋';
    final context = isGuest
        ? 'You are browsing as a guest — you can explore posts and profiles, but you will need to sign in to post, message, or apply.'
        : 'I am here to help you get the most out of MUST StarTrack.';
    return '$intro $context What would you like help with today?';
  }

  String _normalize(String value) {
    return value
      .toLowerCase()
      .replaceAll("what's", 'what is')
      .replaceAll("whats", 'what is')
      .replaceAll('application', 'app')
      .replaceAll('platform', 'app')
      .replaceAll('gemini ai', 'gemini')
      .replaceAll('artificial intelligence', 'ai')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Set<String> _tokens(String value) {
    return value
        .split(' ')
        .where((t) => t.length >= 2 && !_stopWords.contains(t))
        .toSet();
  }

  factory ChatbotRepository.defaultForApp({GeminiService? geminiService}) {
    return ChatbotRepository(
      faqs: ChatbotKnowledgeBase.faqs,
      projectDocs: ChatbotKnowledgeBase.projectDocs,
      knownRoutes: ChatbotKnowledgeBase.knownRoutes,
      geminiService: geminiService,
    );
  }

  static const Set<String> _stopWords = {
    'a',
    'an',
    'and',
    'are',
    'can',
    'do',
    'does',
    'for',
    'how',
    'i',
    'in',
    'is',
    'my',
    'of',
    'on',
    'or',
    'the',
    'this',
    'to',
    'what',
    'with',
    'work',
  };
}

class _FaqMatch {
  final ChatbotFaqEntry entry;
  final double score;

  const _FaqMatch({required this.entry, required this.score});
}

class _DocMatch {
  final ChatbotKnowledgeDoc doc;
  final double score;

  const _DocMatch({required this.doc, required this.score});
}
