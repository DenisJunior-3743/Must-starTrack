import 'dart:async';
import 'dart:convert';

import '../../../data/remote/openai_service.dart';
import 'chatbot_knowledge_base.dart';
import '../models/chatbot_models.dart';

class ChatbotRepository {
  ChatbotRepository({
    required List<ChatbotFaqEntry> faqs,
    required List<ChatbotKnowledgeDoc> projectDocs,
    required Set<String> knownRoutes,
    OpenAiService? openAiService,
  })  : _faqs = faqs,
        _projectDocs = projectDocs,
        _knownRoutes = knownRoutes,
        _openAiService = openAiService;

  final List<ChatbotFaqEntry> _faqs;
  final List<ChatbotKnowledgeDoc> _projectDocs;
  final Set<String> _knownRoutes;
  final OpenAiService? _openAiService;

  Future<ChatbotResponse> answer(
    String query, {
    required bool isGuest,
    String? role,
    List<ChatbotMessage>? conversation,
    List<ChatbotLearnedExample> learnedExamples =
        const <ChatbotLearnedExample>[],
    ChatbotBehaviorContext behaviorContext = const ChatbotBehaviorContext(),
  }) async {
    final normalized = _normalize(query);
    if (normalized.isEmpty) {
      return const ChatbotResponse(
        answer:
            'Ask me anything about MUST StarTrack features, navigation, or what is possible in your role.',
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
    if (local != null && local.score >= 0.62) {
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
        answer: _answerFromKnowledgeDoc(doc, isGuest: isGuest),
        source: ChatbotSource.faq,
        confidence: localDoc.score,
        followUps: doc.followUps,
      );
    }

    final learned = _bestLearnedMatch(
      normalized,
      examples: learnedExamples,
      role: role,
    );
    if (learned != null && learned.score >= 0.84) {
      final helper = isGuest
          ? 'You can explore this flow as a guest, but sign-in is needed for actions like posting, applying, and messaging.'
          : 'If you want, I can give you exact steps for your role.';
      return ChatbotResponse(
        answer: '${learned.example.answer} $helper',
        source: ChatbotSource.faq,
        confidence: learned.score,
        followUps: _topLearnedMatches(
          normalized,
          examples: learnedExamples,
          role: role,
          limit: 3,
        ).map((entry) => entry.question).toList(growable: false),
      );
    }

    final aiResponse = await _tryAiAnswer(
      question: query,
      isGuest: isGuest,
      role: role,
      conversation: conversation ?? const <ChatbotMessage>[],
      learnedExamples: learnedExamples,
      behaviorContext: behaviorContext,
    );
    if (aiResponse != null) {
      return aiResponse;
    }

    final topFaqQuestions =
        _topFaqMatches(normalized, limit: 4).map((f) => f.question);
    final topLearnedQuestions = _topLearnedMatches(
      normalized,
      examples: learnedExamples,
      role: role,
      limit: 4,
    ).map((e) => e.question);
    final topQuestions = <String>{
      ...topFaqQuestions,
      ...topLearnedQuestions,
    }.take(4).toList(growable: false);
    final closestFaq = _bestFaqMatch(normalized);
    final closestDoc = _bestDocMatch(normalized);
    final closestLearned = _bestLearnedMatch(
      normalized,
      examples: learnedExamples,
      role: role,
    );

    if (closestFaq != null && closestFaq.score >= 0.35) {
      final entry = closestFaq.entry;
      final helper = isGuest
          ? 'If you want, I can also tell you which parts need sign-in.'
          : 'If you want, I can give you exact steps in your current role.';
      return ChatbotResponse(
        answer: '${entry.answer} $helper',
        source: ChatbotSource.fallback,
        confidence: (closestFaq.score * 0.85).clamp(0.25, 0.78),
        actions: entry.actions,
        followUps: entry.followUps.isNotEmpty ? entry.followUps : topQuestions,
      );
    }

    if (closestDoc != null && closestDoc.score >= 0.30) {
      final doc = closestDoc.doc;
      return ChatbotResponse(
        answer:
            '${doc.summary} Ask me a specific part of this and I will walk you through it step by step.',
        source: ChatbotSource.fallback,
        confidence: (closestDoc.score * 0.80).clamp(0.22, 0.72),
        followUps: doc.followUps.isNotEmpty ? doc.followUps : topQuestions,
      );
    }

    if (closestLearned != null && closestLearned.score >= 0.46) {
      final helper = isGuest
          ? 'I can also point out which steps need sign-in.'
          : 'I can also tailor this to your role step by step.';
      return ChatbotResponse(
        answer: '${closestLearned.example.answer} $helper',
        source: ChatbotSource.fallback,
        confidence: (closestLearned.score * 0.88).clamp(0.24, 0.82),
        followUps: topQuestions,
      );
    }

    return ChatbotResponse(
      answer:
          'I can help with navigation, posting projects, opportunities, collaboration requests, groups, messaging, profile setup, recommendations, and admin tools. Tell me what you want to do in MUST StarTrack and I will give you the exact steps.',
      source: ChatbotSource.fallback,
      confidence: 0.2,
      followUps: topQuestions,
    );
  }

  String _answerFromKnowledgeDoc(
    ChatbotKnowledgeDoc doc, {
    required bool isGuest,
  }) {
    final guestHint = isGuest
        ? ' You can browse related information as a guest, but sign in for actions like posting, applying, messaging, or collaboration.'
        : '';
    return '${doc.summary} ${doc.content}$guestHint'.trim();
  }

  Future<ChatbotResponse?> _tryAiAnswer({
    required String question,
    required bool isGuest,
    String? role,
    required List<ChatbotMessage> conversation,
    required List<ChatbotLearnedExample> learnedExamples,
    required ChatbotBehaviorContext behaviorContext,
  }) async {
    final openAi = _openAiService;
    if (openAi == null || !openAi.isConfigured) {
      return null;
    }

    final normalizedQuestion = _normalize(question);
    final conversationPayload = conversation
        .where((msg) => msg.text.trim().isNotEmpty)
        .take(10)
        .map((msg) => {
              'role': msg.isUser ? 'user' : 'assistant',
              'text': msg.text,
            })
        .toList(growable: false);

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

    final learnedPayload = _topLearnedMatches(
      normalizedQuestion,
      examples: learnedExamples,
      role: role,
      limit: 6,
    )
        .map((example) => {
              'question': example.question,
              'answer': example.answer,
              'confidence': example.confidence,
              'source': example.source,
              'role': example.role,
            })
        .toList(growable: false);

    final behaviorPayload = behaviorContext.toPromptMap();
    final learnedCount = learnedExamples.length;

    // ─────────────────────────────────────────────────────────────────────────
    // Full project knowledge injected so OpenAI understands the app deeply
    // ─────────────────────────────────────────────────────────────────────────
    final projectKnowledge = '''
MUST STARTRACK — FULL PROJECT KNOWLEDGE

PRODUCT PURPOSE:
MUST StarTrack is an academic networking and collaboration platform for Mbarara University of Science and Technology (MUST), Uganda. It connects students, lecturers, and admins through digital portfolios, project showcases, collaboration tools, and AI-powered recommendations.

ROLES AND PERMISSIONS:
- Student: create project/opportunity posts, apply to opportunities, discover peers, request collaborations, join groups, message peers, build a profile with skills/achievements/portfolio.
- Lecturer: manage and post opportunities, review applicants, rank and shortlist candidates using AI-assisted scoring, access advanced applicant search, view student profiles and skills.
- Admin: moderate posts and users, manage academic data (faculties, programs, courses), view platform analytics, run assistant benchmarks, manage user accounts.
- Super Admin: full platform oversight including all admin capabilities plus system configuration.
- Guest (not signed in): browse public feed and public profiles, view opportunities. Cannot post, message, apply, or collaborate.

CORE FEATURES:
1. HOME FEED — Personalized project and opportunity posts ranked by AI recommendation based on skills, faculty, program, engagement, and recency.
2. DISCOVER — Search by skills, faculty, category. AI-reranked results surface the most relevant people and posts.
3. PEERS & COLLABORATION — Find collaborators, send collaboration requests, accept/decline. Groups are created from accepted collaborators.
4. GROUPS — Group owners invite accepted collaborators as members. Roles: owner, admin, member. Group posts are linked to the group and appear in group feeds. Lecturers and admins can inspect group-attributed work.
5. MESSAGING — Real-time chat between users. Notification center for all platform events.
6. PROFILE — Skills, bio, achievements, portfolio links, endorsements, profile picture (uploaded to Cloudinary), academic identity (faculty, program, year of study).
7. POSTS — Two types: Project post (showcasing work) and Opportunity post (job/internship/collaboration offer). Posts have tags, skills used, category, faculty, engagement (likes, comments, shares), and moderation status.
8. LECTURER TOOLS — Opportunity management dashboard, applicant list with AI-generated fit scores, advanced search, shortlisting, and ranking.
9. ADMIN TOOLS — Content moderation queue, user management, faculty/program/course management, analytics dashboard, assistant benchmarking screen.
10. AI RECOMMENDATIONS — Hybrid local-first system. Local ranking uses skills overlap, faculty match, program match, engagement, recency, behavior signals (views, likes, searches). OpenAI optionally reranks top candidates for even better precision.
11. CHATBOT ASSISTANT — In-app assistant that answers questions about features, navigation, and troubleshooting. Uses local FAQ matching first, project knowledge search second, then OpenAI fallback for anything not covered locally.

RECOMMENDATION SYSTEM DETAIL:
- Runs locally first using: user skills, faculty, program, bio, activity streak, total posts, collaborations, followers, recent searches, post recency, likes, comments, shares, opportunity fit.
- Used in: Home feed ranking, Discover reranking, collaborator suggestions, lecturer applicant ranking.
- OpenAI is an optional reranking layer — NOT the core engine. App works fully without it.

TECHNICAL ARCHITECTURE:
- Flutter (Dart) — cross-platform mobile + web
- BLoC/Cubit for state management
- GoRouter for guarded role-aware navigation
- get_it for dependency injection
- SQLite (local-first offline storage via DAOs)
- Firebase Auth (identity and session management)
- Firestore (remote sync for posts, users, groups, notifications)
- Cloudinary (profile picture and media uploads)
- OpenAI GPT-4o-mini (optional AI layer for recommendations and assistant fallback)

DEVELOPER TEAM:
Built as a third-year Software Engineering mini-project at MUST by: Denis Junior, Ainamaani Allan Mwesigye, Mwunvaneeza Godfrey, Murungi Kevin Tumaini, and Mbabazi Patience.

NAVIGATION ROUTES AVAILABLE:
${_knownRoutes.toList().join(', ')}
'''
        ''; // concat to avoid lint on multi-line string end

    final prompt = '''
You are the MUST StarTrack in-app assistant. You know this platform completely. Your job is to give users accurate, confident, and actionable answers.

FULL PROJECT KNOWLEDGE:
$projectKnowledge

USER CONTEXT:
- Guest (no account): $isGuest
- Role: ${role ?? 'student'}
- Access level: ${isGuest ? 'Read-only (sign in to post, message, or apply)' : 'Full access for ${role ?? 'student'} role'}
- Learned examples loaded: $learnedCount
- Recent user behavior: ${jsonEncode(behaviorPayload)}

RECENT CONVERSATION (for continuity):
${jsonEncode(conversationPayload)}

═══════════════════════════════════════════════════════════════════════════════
LOCAL FAQ MATCHES (use these when relevant — they are authoritative):
═══════════════════════════════════════════════════════════════════════════════
${jsonEncode(faqPayload)}

═══════════════════════════════════════════════════════════════════════════════
PROJECT DOC MATCHES:
═══════════════════════════════════════════════════════════════════════════════
${jsonEncode(projectSearchResults)}

LEARNED FROM HELPFUL USER INTERACTIONS (secondary to local knowledge):
${jsonEncode(learnedPayload)}

═══════════════════════════════════════════════════════════════════════════════
USER QUESTION: $question
═══════════════════════════════════════════════════════════════════════════════

INSTRUCTIONS:
0. Priority order: chatbot_knowledge_base.dart FAQ/docs first, helpful learned user interactions second, recent behavior only for personalization, then OpenAI reasoning.
0. Never let learned interactions or behavior override the local knowledge base.
1. Check local FAQ matches first — if there is a clear match use it as the base of your answer.
2. Use the FULL PROJECT KNOWLEDGE above to fill in details or answer questions not covered by the FAQs.
3. Be specific and confident. Never say "I don't know" without offering an alternative.
4. If the user is a guest, note what requires sign-in.
5. Tailor the answer to the user role (${role ?? 'student'}) — explain what they can and cannot do.
6. Keep the answer to 1-5 sentences. Be direct, natural, and conversational (human tone, not robotic).
7. Suggest a follow-up action or next step at the end of your answer.

Return ONLY valid JSON:
{
  "answer": "Your concise, accurate, helpful response (1-5 sentences)",
  "confidence": 0.0-1.0,
  "followUps": ["related question 1", "related question 2", "related question 3"],
  "actions": [{"label": "Button label", "route": "/route"}]
}

RESPOND WITH ONLY THE JSON. NO EXTRA TEXT.
''';

    try {
      final raw = await openAi
          .generateJson(prompt)
          .timeout(const Duration(seconds: 45));
      if (raw == null || raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final answer = decoded['answer']?.toString().trim() ?? '';
      if (answer.isEmpty) return null;

      final confidence = (decoded['confidence'] as num?)?.toDouble() ?? 0.45;

      final followUpsRaw = decoded['followUps'];
      final followUps = followUpsRaw is List
          ? followUpsRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .take(4)
              .toList(growable: false)
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
      final normalizedKeywords =
          entry.keywords.map(_normalize).toList(growable: false);
      if (normalizedQuery == normalizedQuestion ||
          normalizedKeywords.contains(normalizedQuery)) {
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
      final total =
          (queryCoverage * 0.55) + (entryCoverage * 0.20) + phraseScore;

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

  _LearnedMatch? _bestLearnedMatch(
    String normalizedQuery, {
    required List<ChatbotLearnedExample> examples,
    String? role,
  }) {
    if (examples.isEmpty) return null;

    final normalizedRole = _normalizeRole(role);
    _LearnedMatch? best;
    for (final example in examples) {
      final score = _scoreLearnedMatch(
        example,
        normalizedQuery,
        normalizedRole: normalizedRole,
      );
      if (best == null || score > best.score) {
        best = _LearnedMatch(example: example, score: score);
      }
    }
    return best;
  }

  List<ChatbotFaqEntry> _topFaqMatches(String normalizedQuery,
      {required int limit}) {
    final ranked = _faqs
        .map((entry) => _FaqMatch(
            entry: entry, score: _scoreFaqMatch(entry, normalizedQuery)))
        .where((match) => match.score > 0.12)
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    return ranked
        .take(limit)
        .map((match) => match.entry)
        .toList(growable: false);
  }

  List<ChatbotKnowledgeDoc> _topDocMatches(String normalizedQuery,
      {required int limit}) {
    final ranked = _rankDocs(normalizedQuery)
        .where((match) => match.score > 0.12)
        .take(limit)
        .map((match) => match.doc)
        .toList(growable: false);

    return ranked;
  }

  List<ChatbotLearnedExample> _topLearnedMatches(
    String normalizedQuery, {
    required List<ChatbotLearnedExample> examples,
    String? role,
    required int limit,
  }) {
    if (examples.isEmpty || limit <= 0) {
      return const <ChatbotLearnedExample>[];
    }

    final normalizedRole = _normalizeRole(role);
    final ranked = examples
        .map(
          (entry) => _LearnedMatch(
            example: entry,
            score: _scoreLearnedMatch(
              entry,
              normalizedQuery,
              normalizedRole: normalizedRole,
            ),
          ),
        )
        .where((entry) => entry.score > 0.18)
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    return ranked
        .take(limit)
        .map((entry) => entry.example)
        .toList(growable: false);
  }

  List<_DocMatch> _rankDocs(String normalizedQuery) {
    final queryTokens = _tokens(normalizedQuery);
    if (queryTokens.isEmpty) return const [];

    final ranked = _projectDocs.map((doc) {
      final normalizedTitle = _normalize(doc.title);
      final normalizedKeywords =
          doc.keywords.map(_normalize).toList(growable: false);
      final normalizedContent = _normalize(doc.content);
      final phraseScore = _phraseScore(
        normalizedQuery,
        [normalizedTitle, ...normalizedKeywords, normalizedContent],
      );
      final tokenSet = <String>{
        ..._tokens(normalizedTitle),
        ..._tokens(normalizedContent)
      };
      for (final keyword in normalizedKeywords) {
        tokenSet.addAll(_tokens(keyword));
      }
      final overlap = tokenSet.isEmpty
          ? 0.0
          : queryTokens.intersection(tokenSet).length.toDouble();
      final queryCoverage =
          tokenSet.isEmpty ? 0.0 : overlap / queryTokens.length;
      final docCoverage = tokenSet.isEmpty ? 0.0 : overlap / tokenSet.length;
      final score = (queryCoverage * 0.50) + (docCoverage * 0.10) + phraseScore;
      return _DocMatch(doc: doc, score: score.clamp(0.0, 1.0));
    }).toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    return ranked;
  }

  double _scoreFaqMatch(ChatbotFaqEntry entry, String normalizedQuery) {
    final queryTokens = _tokens(normalizedQuery);
    if (queryTokens.isEmpty) return 0;

    final normalizedQuestion = _normalize(entry.question);
    final normalizedKeywords =
        entry.keywords.map(_normalize).toList(growable: false);
    if (normalizedQuery == normalizedQuestion ||
        normalizedKeywords.contains(normalizedQuery)) {
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

  double _scoreLearnedMatch(
    ChatbotLearnedExample example,
    String normalizedQuery, {
    required String normalizedRole,
  }) {
    final queryTokens = _tokens(normalizedQuery);
    if (queryTokens.isEmpty) return 0;

    final normalizedQuestion = _normalize(example.question);
    final normalizedAnswer = _normalize(example.answer);
    if (normalizedQuestion.isEmpty) return 0;
    if (normalizedQuery == normalizedQuestion) return 1.0;

    final phraseScore = _phraseScore(
      normalizedQuery,
      [normalizedQuestion, normalizedAnswer],
    );
    final tokenSet = <String>{
      ..._tokens(normalizedQuestion),
      ..._tokens(normalizedAnswer),
    };
    if (tokenSet.isEmpty) return phraseScore;

    final overlap = queryTokens.intersection(tokenSet).length.toDouble();
    final queryCoverage = overlap / queryTokens.length;
    final entryCoverage = overlap / tokenSet.length;

    final confidenceBoost = example.confidence.clamp(0.0, 1.0) * 0.05;
    final exampleRole = _normalizeRole(example.role);
    final roleBoost = normalizedRole.isNotEmpty &&
            exampleRole.isNotEmpty &&
            exampleRole == normalizedRole
        ? 0.05
        : 0.0;

    return ((queryCoverage * 0.60) +
            (entryCoverage * 0.15) +
            phraseScore +
            confidenceBoost +
            roleBoost)
        .clamp(0.0, 1.0);
  }

  double _phraseScore(String normalizedQuery, List<String> normalizedPhrases) {
    for (final phrase in normalizedPhrases) {
      if (phrase.isEmpty) continue;
      if (normalizedQuery == phrase) return 0.45;
      if (normalizedQuery.contains(phrase) ||
          phrase.contains(normalizedQuery)) {
        return 0.35;
      }
    }
    return 0.0;
  }

  static const _greetingTokens = {
    'hi',
    'hey',
    'hello',
    'hola',
    'howdy',
    'yo',
    'sup',
    'heya',
    'hiya',
    'greetings',
    'morning',
    'afternoon',
    'evening',
    'wassup',
    'whatsup',
    'salut',
    'bonjour',
    'hii',
    'helo',
    'helloo',
    'heyy',
    'hihi',
  };

  static const _greetingPhrases = [
    'good morning',
    'good afternoon',
    'good evening',
    'good day',
    'what is up',
    'how are you',
    'how r you',
    'how do you do',
  ];

  bool _isGreeting(String normalized) {
    for (final phrase in _greetingPhrases) {
      if (normalized == phrase || normalized.startsWith('$phrase ')) {
        return true;
      }
    }
    final tokens = normalized.split(' ').toSet();
    // Pure greeting: every non-empty token must be a greeting word (allows "hey there", "hi hi")
    final nonGreeting = tokens.where(
      (t) =>
          t.isNotEmpty &&
          !_greetingTokens.contains(t) &&
          t != 'there' &&
          t != 'all',
    );
    return nonGreeting.isEmpty && tokens.any(_greetingTokens.contains);
  }

  String _greetingResponse({String? role, required bool isGuest}) {
    final roleLabel = switch (role) {
      'lecturer' => 'Lecturer',
      'admin' || 'superAdmin' => 'Admin',
      _ => null,
    };
    final intro =
        roleLabel != null ? 'Hey there, $roleLabel! 👋' : 'Hey there! 👋';
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
        .replaceAll('openai ai', 'openai')
        .replaceAll('gemini ai', 'openai')
        .replaceAll('artificial intelligence', 'ai')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _normalizeRole(String? role) =>
      (role ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  Set<String> _tokens(String value) {
    return value
        .split(' ')
        .where((t) => t.length >= 2 && !_stopWords.contains(t))
        .toSet();
  }

  factory ChatbotRepository.defaultForApp({OpenAiService? openAiService}) {
    return ChatbotRepository(
      faqs: ChatbotKnowledgeBase.faqs,
      projectDocs: ChatbotKnowledgeBase.projectDocs,
      knownRoutes: ChatbotKnowledgeBase.knownRoutes,
      openAiService: openAiService,
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

class _LearnedMatch {
  final ChatbotLearnedExample example;
  final double score;

  const _LearnedMatch({required this.example, required this.score});
}
