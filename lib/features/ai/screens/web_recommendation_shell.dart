import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/config/openai_config.dart';
import '../../../firebase_options.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../data/remote/openai_service.dart';
import '../../../data/remote/recommender_service.dart';
import 'web_recommendation_benchmark.dart';
import '../../admin/screens/recommendation_web_lab_screen.dart';
import '../../admin/widgets/js_visualization_panel.dart';

const _webOpenAiApiKeyFromEnv = String.fromEnvironment(
  'OPENAI_API_KEY',
  defaultValue: OpenAiConfig.bundledApiKey,
);

enum _WebRecommendationCategory { feed, personalized, general }

enum _DashboardSection {
  overview,
  studentLab,
  projectApproval,
  kmeans,
  localMath,
  aiStage,
  benchmark,
  feedResults,
  personalResults,
  generalResults,
  studentExplorer,
  skillPatternLab,
}

class _ApprovalAiReview {
  const _ApprovalAiReview({
    required this.decision,
    required this.confidence,
    required this.summary,
    required this.findings,
    required this.evidence,
    required this.scores,
  });

  final String decision;
  final double confidence;
  final String summary;
  final List<String> findings;
  final List<String> evidence;
  final Map<String, int> scores;

  factory _ApprovalAiReview.fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) {
      return const _ApprovalAiReview(
        decision: 'needs_human',
        confidence: 0,
        summary: 'Local AI did not return a project review.',
        findings: <String>[],
        evidence: <String>[],
        scores: <String, int>{},
      );
    }

    final rawDecision = (payload['decision'] ?? 'needs_human')
        .toString()
        .trim()
        .toLowerCase();
    final decision = switch (rawDecision) {
      'approve' || 'approved' => 'approve',
      'reject' || 'rejected' => 'reject',
      'needs_human' || 'manual_review' => 'needs_human',
      _ => 'needs_human',
    };

    final rawScores = payload['scores'];
    final scores = <String, int>{};
    if (rawScores is Map) {
      for (final entry in rawScores.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) continue;
        final parsed = _parseInt(entry.value);
        if (parsed != null) {
          scores[key] = parsed.clamp(0, 100);
        }
      }
    }

    final findings = _stringList(payload['findings'] ?? payload['flags']);
    final evidence = _stringList(
      payload['evidence'] ?? payload['evidence_needed'],
    );
    final finalTake = (payload['final_take'] ??
            payload['finalTake'] ??
            payload['admin_summary'] ??
            '')
        .toString()
        .trim();

    return _ApprovalAiReview(
      decision: decision,
      confidence: _parseDouble(payload['confidence'])?.clamp(0, 1) ?? 0,
      summary: finalTake.isNotEmpty ? finalTake : _defaultSummary(decision),
      findings: findings,
      evidence: evidence,
      scores: scores,
    );
  }

  factory _ApprovalAiReview.error(Object error) {
    return _ApprovalAiReview(
      decision: 'needs_human',
      confidence: 0,
      summary: 'Local AI review failed.',
      findings: <String>[error.toString()],
      evidence: const <String>[],
      scores: const <String, int>{},
    );
  }

  static String _defaultSummary(String decision) {
    switch (decision) {
      case 'approve':
        return 'Local AI would approve this project.';
      case 'reject':
        return 'Local AI would reject this project.';
      default:
        return 'Local AI recommends manual review for this project.';
    }
  }

  static List<String> _stringList(Object? raw) {
    if (raw is Iterable) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return const <String>[];
    return <String>[value];
  }

  static double? _parseDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }
}

class StarTrackWebRecommendationsApp extends StatelessWidget {
  const StarTrackWebRecommendationsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MUST StarTrack Recommendation Dashboard',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.backgroundLight,
        textTheme: GoogleFonts.plusJakartaSansTextTheme(),
      ),
      home: const _WebAdminGate(),
    );
  }
}

// ── Dot grid background painter for login left panel ─────────────────────────

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    const spacing = 28.0;
    const radius = 2.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => false;
}

// ── Admin login gate ──────────────────────────────────────────────────────────

class _WebAdminGate extends StatefulWidget {
  const _WebAdminGate();

  @override
  State<_WebAdminGate> createState() => _WebAdminGateState();
}

class _WebAdminGateState extends State<_WebAdminGate> {
  final _emailController =
      TextEditingController(text: 'admin@must.ac.ug');
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Ensure Firebase is ready before auth call.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
            options: DefaultFirebaseOptions.web);
      }

      final credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      // Verify admin/super_admin role via ID token claims or Firestore.
      final token = await credential.user?.getIdTokenResult();
      final role = token?.claims?['role'] as String? ?? '';

      final isAdmin =
          role == 'admin' || role == 'super_admin';

      // If custom claims not set, fall back to checking Firestore profile.
      if (!isAdmin) {
        final doc = await _getFirestoreRole(credential.user!.uid);
        if (doc != 'admin' && doc != 'super_admin') {
          await FirebaseAuth.instance.signOut();
          setState(() {
            _loading = false;
            _error =
                'Access denied. Only admin accounts can access this dashboard.';
          });
          return;
        }
      }

      if (mounted) setState(() => _loading = false);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _loading = false;
        _error = switch (e.code) {
          'user-not-found' => 'No account found for that email.',
          'wrong-password' || 'invalid-credential' => 'Incorrect password.',
          'too-many-requests' => 'Too many attempts. Try again later.',
          _ => 'Sign-in failed: ${e.message}',
        };
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Unexpected error: $e';
      });
    }
  }

  Future<String> _getFirestoreRole(String uid) async {
    try {
      await FirebaseAuth.instance.currentUser
          ?.getIdToken(); // keep session alive
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      return (doc.data()?['role'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1B8F),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    // Check auth synchronously — after _signIn succeeds setState rebuilds here.
    // Wrap in try-catch: if Firebase is not yet initialised (e.g. hot-restart
    // race on web) we treat it as "not signed in" and show the login form.
    User? current;
    try {
      current = FirebaseAuth.instance.currentUser;
    } catch (_) {
      current = null;
    }
    if (current != null) {
      return const _WebRecommendationDashboard();
    }

    return Scaffold(
      body: Row(
        children: [
          // ── Left branding panel ────────────────────────────────────────
          Expanded(
            flex: 55,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D1B8F), Color(0xFF1952C8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  // Background pattern dots
                  Positioned.fill(
                    child: CustomPaint(painter: _DotGridPainter()),
                  ),
                  // Gold top accent
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(height: 5, color: const Color(0xFFF4B400)),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // MUST Star logo
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4B400),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFF4B400)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.star_rounded,
                              color: Color(0xFF0D1B8F),
                              size: 46,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'MUST StarTrack',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Gold accent divider
                          Container(
                            width: 56,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4B400),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'AI Recommendation Dashboard',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Mbarara University of Science and Technology',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 40),
                          const Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              _FeatureChip(
                                icon: Icons.psychology_outlined,
                                label: 'K-Means AI',
                              ),
                              _FeatureChip(
                                icon: Icons.bar_chart_rounded,
                                label: 'Live Analytics',
                              ),
                              _FeatureChip(
                                icon: Icons.people_outline,
                                label: 'Student Profiles',
                              ),
                              _FeatureChip(
                                icon: Icons.auto_awesome,
                                label: 'AI Rerank',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Right form panel ───────────────────────────────────────────
          Expanded(
            flex: 45,
            child: Container(
              color: const Color(0xFFF6F6F8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Padding(
                    padding: const EdgeInsets.all(44),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Welcome back',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0D1B8F),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sign in to access the recommendation lab',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                        const SizedBox(height: 34),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Admin email',
                            labelStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 13),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0D1B8F), width: 2),
                            ),
                            prefixIcon: const Icon(Icons.alternate_email,
                                size: 18),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                          ),
                          onSubmitted: (_) => _signIn(),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 13),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0D1B8F), width: 2),
                            ),
                            prefixIcon: const Icon(Icons.lock_outline,
                                size: 18),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 18,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                          ),
                          onSubmitted: (_) => _signIn(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red.shade600, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _loading ? null : _signIn,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0D1B8F),
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Sign in',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebRecommendationDashboard extends StatefulWidget {
  const _WebRecommendationDashboard();

  @override
  State<_WebRecommendationDashboard> createState() =>
      _WebRecommendationDashboardState();
}

class _WebRecommendationDashboardState
    extends State<_WebRecommendationDashboard> {
  static const String _allFaculties = 'All Faculties';

  late final RecommenderService _recommender;
  late final OpenAiService _openAi;
  FirestoreService? _firestore;

  List<UserModel> _users = const <UserModel>[];
  List<PostModel> _posts = const <PostModel>[];
  List<PostModel> _approvalPosts = const <PostModel>[];
  _KMeansTrace? _kMeansTrace;

  StreamSubscription<List<UserModel>>? _usersSubscription;
  StreamSubscription<List<PostModel>>? _postsSubscription;
  StreamSubscription<List<PostModel>>? _approvalPostsSubscription;
  bool _loadingRemote = true;
  String? _remoteError;
  int _recomputeToken = 0;
  final Map<String, _ApprovalAiReview> _approvalAiByPostId =
      <String, _ApprovalAiReview>{};
  final Set<String> _approvalAiInFlightPostIds = <String>{};

  _WebRecommendationCategory _category = _WebRecommendationCategory.feed;
  String? _selectedUserId;
  String _selectedFaculty = _allFaculties;
  _DashboardSection _activeSection = _DashboardSection.overview;
  _WebRecommendationCategory _studentLabCategory =
      _WebRecommendationCategory.feed;
  bool _algorithmExpanded = true;
  bool _resultsExpanded = true;

  List<RecommendedPost> _feedLocalResults = const <RecommendedPost>[];
  List<RecommendedPost> _feedAiResults = const <RecommendedPost>[];
  List<FeedVideoQueueItem> _feedVideoQueue = const <FeedVideoQueueItem>[];
  List<RecommendedPost> _personalLocalResults = const <RecommendedPost>[];
  List<RecommendedPost> _personalAiResults = const <RecommendedPost>[];
  HybridRerankDiagnostics? _feedHybridDiagnostics;
  HybridRerankDiagnostics? _personalHybridDiagnostics;
  List<RecommendedUser> _collaboratorResults = const <RecommendedUser>[];
  List<_GeneralStudentScore> _generalResults = const <_GeneralStudentScore>[];
  List<Map<String, dynamic>> _remoteRecommendationLogs =
      const <Map<String, dynamic>>[];
  Map<String, int> _followerCountsIndex = const <String, int>{};
  Map<String, List<String>> _projectCommentSnippetsByPost =
      const <String, List<String>>{};
  String _projectCommentSignature = '';
  List<String> _remoteFaculties = const <String>[];
  final bool _useFirestoreRecs = false;
  RecommendationBenchmarkSnapshot? _benchmark;

  @override
  void initState() {
    super.initState();
    _openAi = OpenAiService(apiKey: _webOpenAiApiKeyFromEnv);
    _recommender = RecommenderService(
      openAiService: _openAi,
    );
    unawaited(_bootstrapRemoteData());
  }

  @override
  void dispose() {
    _usersSubscription?.cancel();
    _postsSubscription?.cancel();
    _approvalPostsSubscription?.cancel();
    super.dispose();
  }

  UserModel? get _selectedUser {
    if (_users.isEmpty) return null;
    final requestedId = _selectedUserId;
    if (requestedId == null || requestedId.isEmpty) return null;
    for (final user in _users) {
      if (user.id == requestedId) return user;
    }
    return null;
  }

  _KMeansTrace get _currentKMeansTrace {
    return _kMeansTrace ??
        const _KMeansTrace(
          points: <_StudentPoint>[],
          iterations: <_KMeansIteration>[],
          finalAssignments: <String, int>{},
        );
  }

  List<PostModel> get _videoCandidates =>
      _posts.where(_isVideoCandidate).toList(growable: false);

  int _effectivePostCountForUser(UserModel user) {
    final profileCount = user.profile?.totalPosts ?? 0;
    final inferredCount = _posts.where((post) => post.authorId == user.id).length;
    return math.max(profileCount, inferredCount);
  }

  int _effectiveCollabCountForUser(UserModel user) {
    final profileCount = user.profile?.totalCollabs ?? 0;
    final inferredCount = _posts
        .where((post) => post.authorId == user.id)
        .fold<int>(0, (total, post) => total + math.max(0, post.joinCount));
    return math.max(profileCount, inferredCount);
  }

  int _effectiveFollowerCountForUser(UserModel user) {
    final profileCount = user.profile?.totalFollowers ?? 0;
    final indexedCount = _followerCountsIndex[user.id] ?? 0;
    return math.max(profileCount, indexedCount);
  }

  List<Map<String, dynamic>> _runtimeLogsForSelectedUser(String algorithm) {
    final userId = _selectedUserId;
    if (userId == null || userId.isEmpty) return const <Map<String, dynamic>>[];

    final rows = _remoteRecommendationLogs.where((row) {
      final rowUserId =
          (row['user_id'] ?? row['userId'] ?? '').toString().trim();
      final rowAlgorithm =
          (row['algorithm'] ?? row['algo'] ?? '').toString().trim();
      final rowItemType = (row['item_type'] ?? row['itemType'] ?? 'post')
          .toString()
          .trim();
      return rowUserId == userId &&
          rowAlgorithm == algorithm &&
          rowItemType == 'post';
    }).toList(growable: false);

    rows.sort((a, b) {
      final bTs = (b['logged_at'] ?? b['loggedAt'] ?? '').toString();
      final aTs = (a['logged_at'] ?? a['loggedAt'] ?? '').toString();
      return bTs.compareTo(aTs);
    });
    return rows;
  }

  double _avgScoreFromRuntimeRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return 0.0;
    var total = 0.0;
    var count = 0;
    for (final row in rows) {
      final scoreRaw = row['score'];
      final score = scoreRaw is num
          ? scoreRaw.toDouble()
          : double.tryParse(scoreRaw?.toString() ?? '');
      if (score == null) continue;
      total += score;
      count += 1;
    }
    if (count == 0) return 0.0;
    return total / count;
  }

  int _openAiCountFor(List<RecommendedPost> rows) {
    return rows.where((row) => row.scoreBreakdown['openai_score'] != null).length;
  }

  int _realOpenAiCountFor(List<RecommendedPost> rows) {
    return rows.where((row) => row.scoreBreakdown['ai_source_openai'] == 1.0).length;
  }

  int _proxyAiCountFor(List<RecommendedPost> rows) {
    return rows.where((row) => row.scoreBreakdown['ai_source_proxy'] == 1.0).length;
  }

  HybridRerankDiagnostics? get _activeHybridDiagnostics {
    switch (_category) {
      case _WebRecommendationCategory.feed:
        return _feedHybridDiagnostics;
      case _WebRecommendationCategory.personalized:
        return _personalHybridDiagnostics;
      case _WebRecommendationCategory.general:
        return null;
    }
  }

  double _aiCoverageFor(List<RecommendedPost> rows) {
    if (rows.isEmpty) return 0.0;
    return _openAiCountFor(rows) / rows.length;
  }

  double _avgOpenAiScoreFor(List<RecommendedPost> rows) {
    var total = 0.0;
    var count = 0;
    for (final row in rows) {
      final raw = row.scoreBreakdown['openai_score'];
      final value = (raw as num?)?.toDouble();
      if (value == null) continue;
      total += value;
      count += 1;
    }
    if (count == 0) return 0.0;
    return total / count;
  }

  double _avgAiLiftFor(List<RecommendedPost> rows) {
    if (rows.isEmpty) return 0.0;
    var total = 0.0;
    for (final row in rows) {
      final localRaw = row.scoreBreakdown['local_score'];
      final local = (localRaw as num?)?.toDouble() ?? row.score;
      total += (row.score - local);
    }
    return total / rows.length;
  }

  List<_GeneralStudentScore> get _allStudentScores {
    if (_users.isEmpty) return const <_GeneralStudentScore>[];
    return _buildGeneralRecommendation(
      students: _users,
      faculty: null,
      clusterAssignments: _currentKMeansTrace.finalAssignments,
      commentSentimentByStudent: const <String, double>{},
    );
  }

  String get _bestFacultyName {
    final counts = <String, int>{};
    for (final user in _users) {
      final faculty = (user.profile?.faculty ?? 'Unknown Faculty').trim();
      final key = faculty.isEmpty ? 'Unknown Faculty' : faculty;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (counts.isEmpty) return _allFaculties;
    return (counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
  }

  String get _explorerFaculty {
    return _selectedFaculty;
  }

  List<UserModel> _studentsForFaculty(String faculty) {
    if (faculty == _allFaculties) {
      return _users.toList(growable: false)
        ..sort(
          (a, b) => _displayName(a)
              .toLowerCase()
              .compareTo(_displayName(b).toLowerCase()),
        );
    }
    return _users.where((user) {
      final value = (user.profile?.faculty ?? '').trim();
      final normalized = value.isEmpty ? 'Unknown Faculty' : value;
      return normalized == faculty;
    }).toList(growable: false)
      ..sort(
        (a, b) => _displayName(a)
            .toLowerCase()
            .compareTo(_displayName(b).toLowerCase()),
      );
  }

  List<MapEntry<String, List<_GeneralStudentScore>>> get _topStudentsByFaculty {
    final grouped = <String, List<_GeneralStudentScore>>{};
    for (final item in _allStudentScores) {
      final faculty = (item.user.profile?.faculty ?? 'Unknown Faculty').trim();
      final key = faculty.isEmpty ? 'Unknown Faculty' : faculty;
      grouped.putIfAbsent(key, () => <_GeneralStudentScore>[]).add(item);
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) {
        final bestA = a.value.isEmpty ? 0.0 : a.value.first.score;
        final bestB = b.value.isEmpty ? 0.0 : b.value.first.score;
        return bestB.compareTo(bestA);
      });
    return entries;
  }

  List<String> get _facultyOptions {
    final userFaculties = _users
        .map((user) => (user.profile?.faculty ?? '').trim())
        .where((faculty) => faculty.isNotEmpty);
    final options = <String>{
      _allFaculties,
      ..._remoteFaculties,
      ...userFaculties,
    }.toList(growable: false)
      ..sort((a, b) {
        if (a == _allFaculties) return -1;
        if (b == _allFaculties) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return options;
  }

  List<UserModel> get _visibleStudents {
    return _users.where((user) {
      final rawFaculty = (user.profile?.faculty ?? '').trim();
      final faculty = rawFaculty.isEmpty ? 'Unknown Faculty' : rawFaculty;
      return _selectedFaculty == _allFaculties || faculty == _selectedFaculty;
    }).toList(growable: false);
  }

  void _selectFaculty(String faculty) {
    setState(() {
      _selectedFaculty = faculty;
      final filtered = _visibleStudents;
      if (filtered.isEmpty) {
        _selectedUserId = null;
      } else if (!filtered.any((user) => user.id == _selectedUserId)) {
        _selectedUserId = null;
      }
    });
    unawaited(_recompute());
  }

  void _selectStudent(UserModel user) {
    setState(() {
      _selectedUserId = user.id;
      _activeSection = _DashboardSection.studentLab;
    });
    unawaited(_recompute());
  }

  String _modeLabel(_WebRecommendationCategory category) {
    switch (category) {
      case _WebRecommendationCategory.feed:
        return 'Feed';
      case _WebRecommendationCategory.personalized:
        return 'Personal';
      case _WebRecommendationCategory.general:
        return 'General';
    }
  }

  List<RecommendedPost> _postResultsFor(
    _WebRecommendationCategory category,
    bool ai,
  ) {
    switch (category) {
      case _WebRecommendationCategory.feed:
        return ai ? _feedAiResults : _feedLocalResults;
      case _WebRecommendationCategory.personalized:
        return ai ? _personalAiResults : _personalLocalResults;
      case _WebRecommendationCategory.general:
        return const <RecommendedPost>[];
    }
  }

  String _buildAnalyticsReport({
    required UserModel user,
    required _WebRecommendationCategory category,
  }) {
    final local = _postResultsFor(category, false);
    final ai = _postResultsFor(category, true);
    final profile = user.profile;
    final skills = profile?.skills.join(', ') ?? 'None';
    final effectivePosts = _effectivePostCountForUser(user);
    final effectiveCollabs = _effectiveCollabCountForUser(user);
    final effectiveFollowers = _effectiveFollowerCountForUser(user);

    final lines = <String>[
      'MUST StarTrack Student Analytics Report',
      'Student: ${_displayName(user)} (${user.email})',
      'Mode: ${_modeLabel(category)} Recommendation',
      'Faculty: ${profile?.faculty ?? 'Unknown'}',
      'Program: ${profile?.programName ?? 'Unknown'}',
      'Skills: $skills',
      'Activity streak: ${profile?.activityStreak ?? 0}',
      'Posts: $effectivePosts',
      'Collaborations: $effectiveCollabs',
      'Followers: $effectiveFollowers',
      '',
      'Top Local Results:',
      ...local.take(5).map(
            (item) =>
                '- ${item.post.title}: ${(item.score * 100).toStringAsFixed(1)}%',
          ),
      '',
      if (category != _WebRecommendationCategory.general) ...[
        'Top AI/Hybrid Results:',
        ...ai.take(5).map(
              (item) =>
                  '- ${item.post.title}: ${(item.score * 100).toStringAsFixed(1)}%',
            ),
      ] else
        'General ranking is computed locally (no AI rerank applied).',
      '',
      'Generated: ${DateTime.now().toIso8601String()}',
    ];

    return lines.join('\n');
  }

  Future<void> _openPrintableAnalytics(
    BuildContext context,
    UserModel user,
    _WebRecommendationCategory category,
  ) async {
    final report = _buildAnalyticsReport(user: user, category: category);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Printable Analytics',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: SelectableText(
                report,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report));
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Analytics copied. Open browser print (Ctrl+P) to print.',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_all_rounded, size: 16),
              label: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _studentSignalPanel(
    UserModel user,
    _WebRecommendationCategory category,
  ) {
    final profile = user.profile;
    final cluster = _currentKMeansTrace.finalAssignments[user.id];
    final globalScore = _generalResults
        .where((item) => item.user.id == user.id)
        .map((item) => item.score)
        .cast<double?>()
        .firstWhere((_) => true, orElse: () => null);

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 1: Signal aggregation',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InlineMetricChip(
                label: 'faculty',
                value: profile?.faculty ?? 'Unknown',
              ),
              _InlineMetricChip(
                label: 'program',
                value: profile?.programName ?? 'Unknown',
              ),
              _InlineMetricChip(
                label: 'skills_count',
                value: '${profile?.skills.length ?? 0}',
              ),
              _InlineMetricChip(
                label: 'activity_streak',
                value: '${profile?.activityStreak ?? 0}',
              ),
              _InlineMetricChip(
                label: 'total_posts',
                value: '${_effectivePostCountForUser(user)}',
              ),
              _InlineMetricChip(
                label: 'total_collabs',
                value: '${_effectiveCollabCountForUser(user)}',
              ),
              _InlineMetricChip(
                label: 'total_followers',
                value: '${_effectiveFollowerCountForUser(user)}',
              ),
              _InlineMetricChip(
                label: 'cluster',
                value: cluster != null ? 'C$cluster' : 'Unknown',
              ),
              _InlineMetricChip(
                label: 'global_score',
                value: _d(globalScore),
              ),
              _InlineMetricChip(
                label: 'mode',
                value: _modeLabel(category),
              ),
            ],
          ),
          if ((profile?.skills.isNotEmpty ?? false)) ...[
            const SizedBox(height: 10),
            Text(
              'Skill signals: ${profile!.skills.take(12).join(', ')}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _algorithmStepPanel(_WebRecommendationCategory category) {
    final local = _postResultsFor(category, false);
    final ai = _postResultsFor(category, true);
    final eligibleQueue = _feedVideoQueue.where((item) => item.isEligible);
    final droppedQueue = _feedVideoQueue.where((item) => !item.isEligible);

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 2: Ranking algorithm trace',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            category == _WebRecommendationCategory.general
                ? 'General mode computes cohort score locally using streak, posts, collabs, followers, profile completeness, and skill density.'
                : 'Local scores are computed first, then AI rerank blends with semantic confidence for final ordering.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppColors.textSecondaryLight,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          JsVisualizationPanel(
            chartId:
                'student-lab-${category.name}-${_selectedUserId ?? 'none'}',
            title: category == _WebRecommendationCategory.general
                ? 'Global student score trend'
                : 'Local vs AI top-score comparison',
            labels: category == _WebRecommendationCategory.general
                ? _generalResults
                    .take(6)
                    .map((item) => _displayName(item.user))
                    .toList(growable: false)
                : local.take(6).map((item) => item.post.title).toList(
                      growable: false,
                    ),
            values: category == _WebRecommendationCategory.general
                ? _generalResults.take(6).map((item) => item.score).toList(
                      growable: false,
                    )
                : local.take(6).map((item) => item.score).toList(growable: false),
            color: category == _WebRecommendationCategory.general
                ? AppColors.mustGoldDark
                : AppColors.primary,
            height: 240,
          ),
          if (category != _WebRecommendationCategory.general &&
              ai.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'AI stage preview: ${ai.take(3).map((item) => item.post.title).join(' | ')}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
          if (category == _WebRecommendationCategory.feed &&
              _feedVideoQueue.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Queue stage: eligible ${eligibleQueue.length}/${_feedVideoQueue.length}, dropped ${droppedQueue.length}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _studentOutputPanel(
    _WebRecommendationCategory category,
    Color textPrimary,
    Color textSecondary,
  ) {
    return switch (category) {
      _WebRecommendationCategory.feed =>
        _feedResultsPanel(textPrimary, textSecondary),
      _WebRecommendationCategory.personalized =>
        _personalResultsPanel(textPrimary, textSecondary),
      _WebRecommendationCategory.general =>
        _generalResultsPanel(textPrimary, textSecondary),
    };
  }

  Widget _studentLabTabs() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _WebRecommendationCategory.values.map((category) {
        final selected = _studentLabCategory == category;
        return ChoiceChip(
          selected: selected,
          label: Text(
            _modeLabel(category),
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          avatar: Icon(
            switch (category) {
              _WebRecommendationCategory.feed => Icons.rss_feed_outlined,
              _WebRecommendationCategory.personalized =>
                Icons.person_pin_circle_outlined,
              _WebRecommendationCategory.general => Icons.groups_2_outlined,
            },
            size: 16,
          ),
          selectedColor: AppColors.primaryTint10,
          onSelected: (_) {
            setState(() => _studentLabCategory = category);
          },
        );
      }).toList(growable: false),
    );
  }

  Widget _buildStudentLabSection() {
    const p = AppColors.textPrimaryLight;
    const s = AppColors.textSecondaryLight;
    final user = _selectedUser;

    if (user == null) {
      return Center(
        child: Text(
          'Select a student to open recommendation analytics lab.',
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.textSecondaryLight,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _UserAvatar(user: user, radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName(user),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: p,
                      ),
                    ),
                    Text(
                      'Recommendation signals + step-by-step analytics',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: s,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _openPrintableAnalytics(
                  context,
                  user,
                  _studentLabCategory,
                ),
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('Print Analytics'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _studentLabTabs(),
          const SizedBox(height: 14),
          _studentSignalPanel(user, _studentLabCategory),
          const SizedBox(height: 12),
          _algorithmStepPanel(_studentLabCategory),
          const SizedBox(height: 12),
          _studentOutputPanel(_studentLabCategory, p, s),
        ],
      ),
    );
  }

  Future<void> _bootstrapRemoteData() async {
    try {
      await _ensureFirebaseInitializedForWeb();
      _firestore ??= FirestoreService();
      final firestore = _firestore!;

      final users = await firestore.getAllUsersFromRemote(limit: 600);
      final posts = await firestore.getRecentPosts(limit: 300);
      final approvalPosts = await firestore.getRecentPosts(
        limit: 300,
        includePendingForAdmin: true,
      );
      final logs = await firestore.getRecentRecommendationLogs(limit: 400);
      final faculties = await firestore.getActiveFacultyNames(limit: 200);
      final followerIndex = await firestore.getFollowerCountIndex(limit: 5000);

      _applyRemoteSnapshot(
        users: users,
        posts: posts,
        recommendationLogs: logs,
        faculties: faculties,
        followerCounts: followerIndex,
        allowSetState: true,
      );
      _applyApprovalSnapshot(approvalPosts, allowSetState: true);

      _usersSubscription?.cancel();
      _usersSubscription =
          firestore.watchAllUsers(limit: 600).listen((remoteUsers) {
        _applyRemoteSnapshot(
          users: remoteUsers,
          posts: _posts,
          recommendationLogs: _remoteRecommendationLogs,
          followerCounts: _followerCountsIndex,
        );
      });

      _postsSubscription?.cancel();
      _postsSubscription = firestore.watchRecentPosts(limit: 300).listen(
        (remotePosts) {
          _applyRemoteSnapshot(
            users: _users,
            posts: remotePosts,
            recommendationLogs: _remoteRecommendationLogs,
            followerCounts: _followerCountsIndex,
          );
        },
      );

      _approvalPostsSubscription?.cancel();
      _approvalPostsSubscription = firestore
          .watchRecentPosts(limit: 300, includePendingForAdmin: true)
          .listen(
        (remotePosts) {
          _applyApprovalSnapshot(remotePosts);
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _remoteError =
            'Could not load Firestore data on web. Check your Firebase web config and security rules. Details: $error';
        _loadingRemote = false;
      });
    }
  }

  Future<void> _ensureFirebaseInitializedForWeb() async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  }

  void _applyRemoteSnapshot({
    required List<UserModel> users,
    required List<PostModel> posts,
    List<Map<String, dynamic>>? recommendationLogs,
    List<String>? faculties,
    Map<String, int>? followerCounts,
    bool allowSetState = false,
  }) {
    // Recommendation dashboard is student-centric; exclude lecturers/admins.
    final cleanUsers = users
        .where((user) => user.profile != null && user.isStudent)
        .toList();
    final selectedId = _selectedUserId;
    final resolvedSelectedId = cleanUsers.isEmpty
        ? null
        : (selectedId != null && cleanUsers.any((u) => u.id == selectedId)
            ? selectedId
            : null);

    _users = cleanUsers;
    _posts = posts;
    if (recommendationLogs != null) {
      _remoteRecommendationLogs = recommendationLogs;
    }
    if (faculties != null) {
      _remoteFaculties = faculties;
    }
    if (followerCounts != null) {
      _followerCountsIndex = followerCounts;
    }

    if (_selectedFaculty != _allFaculties) {
      final facultyExists = _remoteFaculties.contains(_selectedFaculty) ||
          cleanUsers.any((u) => u.profile?.faculty == _selectedFaculty);
      if (!facultyExists) {
        _selectedFaculty = _allFaculties;
      }
    }

    _selectedUserId = resolvedSelectedId;
    _kMeansTrace = cleanUsers.isEmpty ? null : _buildKMeansTrace(cleanUsers);
    _loadingRemote = false;
    _remoteError = null;
    _refreshProjectCommentSnippets(posts);

    if (cleanUsers.isEmpty) {
      _feedLocalResults = const <RecommendedPost>[];
      _feedAiResults = const <RecommendedPost>[];
      _feedVideoQueue = const <FeedVideoQueueItem>[];
      _personalLocalResults = const <RecommendedPost>[];
      _personalAiResults = const <RecommendedPost>[];
      _feedHybridDiagnostics = null;
      _personalHybridDiagnostics = null;
      _collaboratorResults = const <RecommendedUser>[];
      _generalResults = const <_GeneralStudentScore>[];
      _benchmark = null;
      if (mounted && allowSetState) setState(() {});
      return;
    }

    unawaited(_recompute(allowSetState: allowSetState));
  }

  void _applyApprovalSnapshot(
    List<PostModel> posts, {
    bool allowSetState = false,
  }) {
    final approvalPosts = posts
        .where((post) => post.type.toLowerCase() == 'project')
        .where((post) => !post.isArchived)
        .toList(growable: false)
      ..sort((a, b) {
        final aPending = a.moderationStatus.name == 'pending' ? 0 : 1;
        final bPending = b.moderationStatus.name == 'pending' ? 0 : 1;
        if (aPending != bPending) return aPending.compareTo(bPending);
        return b.createdAt.compareTo(a.createdAt);
      });

    _approvalPosts = approvalPosts;
    for (final post in approvalPosts.take(12)) {
      if (post.moderationStatus.name == 'pending') {
        _ensureApprovalAiReview(post);
      }
    }

    if (mounted && allowSetState) {
      setState(() {});
    } else if (mounted && _activeSection == _DashboardSection.projectApproval) {
      setState(() {});
    }
  }

  void _ensureApprovalAiReview(PostModel post) {
    if (_approvalAiByPostId.containsKey(post.id) ||
        _approvalAiInFlightPostIds.contains(post.id)) {
      return;
    }
    _approvalAiInFlightPostIds.add(post.id);
    unawaited(() async {
      try {
        final payload = await _openAi.validateProjectPost(post: post.toJson());
        final review = _ApprovalAiReview.fromPayload(payload);
        if (!mounted) return;
        setState(() {
          _approvalAiByPostId[post.id] = review;
          _approvalAiInFlightPostIds.remove(post.id);
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _approvalAiByPostId[post.id] = _ApprovalAiReview.error(error);
          _approvalAiInFlightPostIds.remove(post.id);
        });
      }
    }());
  }

  void _refreshProjectCommentSnippets(List<PostModel> posts) {
    final firestore = _firestore;
    if (firestore == null) return;

    final projectPosts = posts
        .where((post) => post.type == 'project')
        .toList(growable: false);
    final postIds = projectPosts
        .map((post) => post.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false)
      ..sort();
    final signature = postIds.join('|');
    if (signature == _projectCommentSignature) return;

    _projectCommentSignature = signature;
    if (postIds.isEmpty) {
      _projectCommentSnippetsByPost = const <String, List<String>>{};
      return;
    }

    unawaited(() async {
      try {
        final snippets = await firestore.getRecentCommentSnippetsForPosts(
          postIds: postIds,
          perPost: 5,
        );
        _projectCommentSnippetsByPost = snippets;
        if (mounted) {
          unawaited(_recompute());
        }
      } catch (_) {
        _projectCommentSnippetsByPost = const <String, List<String>>{};
      }
    }());
  }

  Future<Map<String, double>> _aiCommentSentimentByStudent({
    required List<UserModel> students,
    required String? faculty,
  }) async {
    if (!_openAi.isConfigured) return const <String, double>{};

    final projectPosts = _posts.where((post) => post.type == 'project');
    final selectedStudents = students.where((student) {
      if (faculty == null || faculty.isEmpty) return true;
      return student.profile?.faculty == faculty;
    }).toList(growable: false);

    final payloadRows = <Map<String, dynamic>>[];
    for (final student in selectedStudents) {
      final comments = <String>[];
      for (final post in projectPosts) {
        if (post.authorId != student.id) continue;
        comments.addAll(_projectCommentSnippetsByPost[post.id] ?? const <String>[]);
      }
      final compactComments = comments
          .map((comment) => comment.trim())
          .where((comment) => comment.isNotEmpty)
          .take(8)
          .toList(growable: false);
      if (compactComments.isEmpty) continue;

      payloadRows.add({
        'id': student.id,
        'title': 'Comment sentiment profile for ${_displayName(student)}',
        'category': student.profile?.faculty,
        'skills': student.profile?.skills ?? const <String>[],
        'type': 'project_comment_sentiment',
        'commentCount': compactComments.length,
        'comments': compactComments,
      });
    }

    if (payloadRows.isEmpty) return const <String, double>{};

    try {
      final response = await _openAi.rankPosts(
        userProfile: {
          'requestType': 'general_comment_sentiment',
          'objective':
              'Score each student by positivity and constructiveness of project comments. Positive sentiment should increase score, negative sentiment should lower score.',
          'faculty': faculty,
        },
        posts: payloadRows,
      );

      final ranking = (response?['ranking'] as List?) ?? const [];
      final scoreByStudent = <String, double>{};
      for (final row in ranking) {
        if (row is! Map) continue;
        final data = Map<String, dynamic>.from(row);
        final id = (data['postId'] ?? data['id'])?.toString();
        if (id == null || id.isEmpty) continue;
        final rawScore = data['score'] ?? data['sentimentScore'] ?? data['finalScore'];
        final parsed = rawScore is num
            ? rawScore.toDouble()
            : double.tryParse(rawScore?.toString() ?? '');
        if (parsed == null) continue;
        scoreByStudent[id] = parsed.clamp(0.0, 1.0).toDouble();
      }
      return scoreByStudent;
    } catch (_) {
      return const <String, double>{};
    }
  }

  Future<void> _recompute({bool allowSetState = true}) async {
    final recomputeToken = ++_recomputeToken;
    final currentUser = _selectedUser;
    final trace = _currentKMeansTrace;
    if (currentUser == null) {
      return;
    }

    // If Firestore mode enabled and precomputed data exists, use it directly
    if (_useFirestoreRecs) {
      final firestore = _firestore;
      if (firestore != null) {
        final precomputed =
            await firestore.getUserRecommendations(userId: currentUser.id);
        if (precomputed.isNotEmpty && recomputeToken == _recomputeToken) {
          _applyFirestoreRecs(precomputed, currentUser);
          if (mounted && allowSetState) setState(() {});
          return;
        }
      }
    }

    debugPrint(
      '[WebRecommendation] category=${_category.name} user=${currentUser.displayName}',
    );

    final feedSearchTerms =
        currentUser.profile?.skills.take(2).toSet() ?? const <String>{};
    final feedViewedCategories = {
      if ((currentUser.profile?.faculty ?? '').isNotEmpty)
        currentUser.profile!.faculty!,
    };
    final feedSourceCandidates =
        _videoCandidates.isNotEmpty ? _videoCandidates : _posts;

    final feedQueue = _recommender.buildFeedVideoQueue(
      user: currentUser,
      candidates: feedSourceCandidates,
      recentSearchTerms: feedSearchTerms,
      recentlyViewedCategories: feedViewedCategories,
    );
    final eligibleFeedVideos = feedQueue
        .where((item) => item.isEligible)
        .map((item) => item.post)
        .toList(growable: false);
    final feedCandidates =
      eligibleFeedVideos.isEmpty ? feedSourceCandidates : eligibleFeedVideos;

    final feedLocal = _recommender.rankLocally(
      user: currentUser,
      candidates: feedCandidates,
      recentSearchTerms: feedSearchTerms,
      recentlyViewedCategories: feedViewedCategories,
    );
    final feedHybrid = await _recommender.rankHybridWithDiagnostics(
      user: currentUser,
      candidates: feedCandidates,
      recentSearchTerms: feedSearchTerms,
      recentlyViewedCategories: feedViewedCategories,
      allowProxyFallback: false,
    );
    final feedAi = feedHybrid.posts;

    final personalLocal = _recommender.rankLocally(
      user: currentUser,
      candidates: _posts,
      recentSearchTerms: {
        ...currentUser.profile?.skills.take(3) ?? const <String>[],
        if ((currentUser.profile?.programName ?? '').isNotEmpty)
          currentUser.profile!.programName!,
      },
      recentlyViewedCategories: {
        if ((currentUser.profile?.faculty ?? '').isNotEmpty)
          currentUser.profile!.faculty!,
        if ((currentUser.profile?.programName ?? '').isNotEmpty)
          currentUser.profile!.programName!,
      },
    );
    final personalHybrid = await _recommender.rankHybridWithDiagnostics(
      user: currentUser,
      candidates: _posts,
      recentSearchTerms: {
        ...currentUser.profile?.skills.take(3) ?? const <String>[],
        if ((currentUser.profile?.programName ?? '').isNotEmpty)
          currentUser.profile!.programName!,
      },
      recentlyViewedCategories: {
        if ((currentUser.profile?.faculty ?? '').isNotEmpty)
          currentUser.profile!.faculty!,
        if ((currentUser.profile?.programName ?? '').isNotEmpty)
          currentUser.profile!.programName!,
      },
      allowProxyFallback: false,
    );
    final personalAi = personalHybrid.posts;

    final collaborators = _recommender.rankCollaborators(
      currentUser: currentUser,
      candidates: _users,
      recentSearchTerms:
          currentUser.profile?.skills.toSet() ?? const <String>{},
    );

    final commentSentimentByStudent = await _aiCommentSentimentByStudent(
      students: _users,
      faculty: _selectedFaculty == _allFaculties ? null : _selectedFaculty,
    );

    final general = _buildGeneralRecommendation(
      students: _users,
      faculty: _selectedFaculty == _allFaculties ? null : _selectedFaculty,
      clusterAssignments: trace.finalAssignments,
      commentSentimentByStudent: commentSentimentByStudent,
    );

    final benchmark = buildRecommendationBenchmark(
      localResults: personalLocal,
      hybridResults: personalAi,
      remoteLogs: _remoteRecommendationLogs,
      topN: 10,
    );

    if (recomputeToken != _recomputeToken) return;

    void applyRecomputeResults() {
      _feedLocalResults = feedLocal;
      _feedAiResults = _stableAiRows(
        nextRows: feedAi,
        previousRows: _feedAiResults,
        diagnostics: feedHybrid.diagnostics,
      );
      _feedVideoQueue = feedQueue;
      _personalLocalResults = personalLocal;
      _personalAiResults = _stableAiRows(
        nextRows: personalAi,
        previousRows: _personalAiResults,
        diagnostics: personalHybrid.diagnostics,
      );
      _feedHybridDiagnostics = feedHybrid.diagnostics;
      _personalHybridDiagnostics = personalHybrid.diagnostics;
      _collaboratorResults = collaborators;
      _generalResults = general;
      _benchmark = benchmark;
    }

    if (allowSetState && mounted) {
      setState(applyRecomputeResults);
    } else {
      applyRecomputeResults();
    }
  }

  List<RecommendedPost> _stableAiRows({
    required List<RecommendedPost> nextRows,
    required List<RecommendedPost> previousRows,
    required HybridRerankDiagnostics diagnostics,
  }) {
    if (nextRows.isEmpty) return previousRows.isNotEmpty ? previousRows : nextRows;
    final nextHasAi = _openAiCountFor(nextRows) > 0;
    final previousHasAi = _openAiCountFor(previousRows) > 0;
    if (!nextHasAi &&
        previousHasAi &&
        diagnostics.openAiAttempted &&
        !diagnostics.openAiSucceeded) {
      return previousRows;
    }
    return nextRows;
  }

  List<_GeneralStudentScore> _buildGeneralRecommendation({
    required List<UserModel> students,
    required Map<String, int> clusterAssignments,
    required Map<String, double> commentSentimentByStudent,
    String? faculty,
  }) {
    final filtered = students.where((student) {
      if (faculty == null || faculty.isEmpty) return true;
      return student.profile?.faculty == faculty;
    }).toList(growable: false);

    final ranked = filtered.map((student) {
      final profile = student.profile!;
      final streak = (profile.activityStreak / 30).clamp(0.0, 1.0).toDouble();
        final posts =
          (_effectivePostCountForUser(student) / 12).clamp(0.0, 1.0).toDouble();
        final collabs = (_effectiveCollabCountForUser(student) / 8)
          .clamp(0.0, 1.0)
          .toDouble();
        final followers = (_effectiveFollowerCountForUser(student) / 40)
          .clamp(0.0, 1.0)
          .toDouble();
      final completeness = _profileCompleteness(student);
      final skillDensity =
          (profile.skills.length / 8).clamp(0.0, 1.0).toDouble();
        final aiCommentSentiment =
          (commentSentimentByStudent[student.id] ?? 0.5).clamp(0.0, 1.0);
        final sentimentDelta = ((aiCommentSentiment - 0.5) * 0.22)
          .clamp(-0.11, 0.11)
          .toDouble();

        final baseScore = ((0.24 * streak) +
            (0.22 * posts) +
            (0.20 * collabs) +
            (0.14 * followers) +
            (0.12 * completeness) +
            (0.08 * skillDensity))
          .clamp(0.0, 1.0)
          .toDouble();

        final score = (baseScore + sentimentDelta)
          .clamp(0.0, 1.0)
          .toDouble();

      return _GeneralStudentScore(
        user: student,
        score: score,
        cluster: clusterAssignments[student.id] ?? 0,
        scoreBreakdown: {
          'streak_score': streak,
          'post_score': posts,
          'collab_score': collabs,
          'follower_score': followers,
          'profile_completeness': completeness,
          'skill_density': skillDensity,
          'ai_comment_sentiment': aiCommentSentiment,
          'sentiment_delta': sentimentDelta,
        },
      );
    }).toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    return ranked;
  }

  _KMeansTrace _buildKMeansTrace(List<UserModel> students) {
    final points = students
        .map(
          (user) => _StudentPoint(
            user: user,
            vector: _FeatureVector(
              skillsDensity: ((user.profile?.skills.length ?? 0) / 10.0)
                  .clamp(0.0, 1.0)
                  .toDouble(),
              activityDensity:
                  (((_effectivePostCountForUser(user) / 12.0) * 0.55) +
                      ((_effectiveCollabCountForUser(user) / 8.0) * 0.45))
                      .clamp(0.0, 1.0)
                      .toDouble(),
              completeness: _profileCompleteness(user),
            ),
          ),
        )
        .toList(growable: false);

    final seedA = points.first.vector;
    final seedB = points[(points.length / 2).floor()].vector;
    final seedC = points.last.vector;

    var centroids = <_FeatureVector>[seedA, seedB, seedC];
    final iterations = <_KMeansIteration>[];

    for (var i = 0; i < 4; i++) {
      final assignments = <String, int>{};
      final grouped = <int, List<_StudentPoint>>{0: [], 1: [], 2: []};

      for (final point in points) {
        var bestCluster = 0;
        var bestDistance = double.infinity;
        for (var cluster = 0; cluster < centroids.length; cluster++) {
          final distance = point.vector.distanceTo(centroids[cluster]);
          if (distance < bestDistance) {
            bestDistance = distance;
            bestCluster = cluster;
          }
        }
        assignments[point.user.id] = bestCluster;
        grouped[bestCluster]!.add(point);
      }

      final nextCentroids = List<_FeatureVector>.generate(3, (cluster) {
        final members = grouped[cluster]!;
        if (members.isEmpty) return centroids[cluster];

        final summed = members.fold<_FeatureVector>(
          const _FeatureVector(
            skillsDensity: 0,
            activityDensity: 0,
            completeness: 0,
          ),
          (acc, point) => _FeatureVector(
            skillsDensity: acc.skillsDensity + point.vector.skillsDensity,
            activityDensity: acc.activityDensity + point.vector.activityDensity,
            completeness: acc.completeness + point.vector.completeness,
          ),
        );

        return _FeatureVector(
          skillsDensity: summed.skillsDensity / members.length,
          activityDensity: summed.activityDensity / members.length,
          completeness: summed.completeness / members.length,
        );
      });

      iterations.add(
        _KMeansIteration(
          iteration: i + 1,
          centroids: centroids,
          assignments: assignments,
        ),
      );

      centroids = nextCentroids;
    }

    return _KMeansTrace(
      points: points,
      iterations: iterations,
      finalAssignments: iterations.last.assignments,
    );
  }

  double _profileCompleteness(UserModel user) {
    final profile = user.profile;
    if (profile == null) return 0.0;

    final completed = [
      (profile.bio ?? '').trim().isNotEmpty,
      (profile.programName ?? '').trim().isNotEmpty,
      (profile.faculty ?? '').trim().isNotEmpty,
      profile.skills.isNotEmpty,
    ].where((value) => value).length;

    return (completed / 4.0).clamp(0.0, 1.0).toDouble();
  }

  void _applyFirestoreRecs(Map<String, dynamic> recs, UserModel user) {
    final feed =
        (recs['feed'] as List?)?.cast<Map<String, dynamic>>().toList() ?? [];
    final personal =
        (recs['personal'] as List?)?.cast<Map<String, dynamic>>().toList() ??
            [];
    final collaborators = (recs['collaborators'] as List?)
            ?.cast<Map<String, dynamic>>()
            .toList() ??
        [];

    final postsById = <String, PostModel>{for (final post in _posts) post.id: post};
    final usersById = <String, UserModel>{for (final candidate in _users) candidate.id: candidate};

    List<RecommendedPost> mapPostRecommendations(List<Map<String, dynamic>> rows) {
      final mapped = <RecommendedPost>[];
      for (final row in rows) {
        final postId = row['postId'] as String?;
        if (postId == null || postId.isEmpty) continue;
        final post = postsById[postId];
        if (post == null) continue;
        mapped.add(
          RecommendedPost(
            post: post,
            score: (row['score'] as num?)?.toDouble() ?? 0.0,
            reasons: (row['reasons'] as List?)?.cast<String>() ?? const <String>[],
          ),
        );
      }
      return mapped;
    }

    final mappedCollaborators = <RecommendedUser>[];
    for (final row in collaborators) {
      final userId = row['userId'] as String?;
      if (userId == null || userId.isEmpty) continue;
      final collabUser = usersById[userId];
      if (collabUser == null) continue;
      mappedCollaborators.add(
        RecommendedUser(
          user: collabUser,
          score: (row['score'] as num?)?.toDouble() ?? 0.0,
          reasons: (row['reasons'] as List?)?.cast<String>() ?? const <String>[],
          matchedSkills:
              (row['matchedSkills'] as List?)?.cast<String>() ?? const <String>[],
        ),
      );
    }

    _feedAiResults = mapPostRecommendations(feed);
    _feedVideoQueue = const <FeedVideoQueueItem>[];
    _personalAiResults = mapPostRecommendations(personal);
    _feedHybridDiagnostics = null;
    _personalHybridDiagnostics = null;
    _collaboratorResults = mappedCollaborators;

    _feedLocalResults = _feedAiResults;
    _personalLocalResults = _personalAiResults;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(),
                Expanded(child: _buildMainContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    const sidebarBg = Color(0xFF0D1B8F);
    const activeBg = Color(0xFF8CC63F);
    const goldAccent = Color(0xFFF4B400);
    const itemTextColor = Color(0xFFCDD5F0);

    return Container(
      width: 256,
      color: sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Logo header ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(18, 26, 18, 18),
            color: Colors.black.withValues(alpha: 0.18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: goldAccent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.star_rounded,
                          color: Color(0xFF0D1B8F), size: 24),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'StarTrack',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'MUST Admin',
                          style: GoogleFonts.plusJakartaSans(
                            color: goldAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _loadingRemote
                              ? goldAccent
                              : const Color(0xFF8CC63F),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _loadingRemote
                              ? 'Loading data...'
                              : '${_users.length} students · ${_posts.length} posts',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Nav items ──────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              children: [
                _sidebarNavItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Overview',
                  section: _DashboardSection.overview,
                  activeBg: activeBg,
                  textColor: itemTextColor,
                ),
                _sidebarNavItem(
                  icon: Icons.people_alt_outlined,
                  label: 'Student Explorer',
                  section: _DashboardSection.studentExplorer,
                  activeBg: activeBg,
                  textColor: itemTextColor,
                ),
                _sidebarNavItem(
                  icon: Icons.verified_user_outlined,
                  label: 'Project Approval',
                  section: _DashboardSection.projectApproval,
                  activeBg: activeBg,
                  textColor: itemTextColor,
                ),
                const SizedBox(height: 10),
                _sidebarParentItem(
                  icon: Icons.science_outlined,
                  label: 'Algorithm Steps',
                  goldAccent: goldAccent,
                  expanded: _algorithmExpanded,
                  onToggle: () =>
                      setState(() => _algorithmExpanded = !_algorithmExpanded),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  child: _algorithmExpanded
                      ? Column(
                          children: [
                            _sidebarChildItem(
                                label: 'K-Means Clustering',
                                section: _DashboardSection.kmeans,
                                activeBg: activeBg,
                                textColor: itemTextColor),
                            _sidebarChildItem(
                                label: 'Local Math',
                                section: _DashboardSection.localMath,
                                activeBg: activeBg,
                                textColor: itemTextColor),
                            _sidebarChildItem(
                                label: 'AI Rerank',
                                section: _DashboardSection.aiStage,
                                activeBg: activeBg,
                                textColor: itemTextColor),
                            _sidebarChildItem(
                                label: 'Benchmark',
                                section: _DashboardSection.benchmark,
                                activeBg: activeBg,
                                textColor: itemTextColor),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 10),
                _sidebarParentItem(
                  icon: Icons.bar_chart_outlined,
                  label: 'Recommendations',
                  goldAccent: goldAccent,
                  expanded: _resultsExpanded,
                  onToggle: () =>
                      setState(() => _resultsExpanded = !_resultsExpanded),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  child: _resultsExpanded
                      ? Column(
                          children: [
                            _sidebarChildItem(
                                label: 'Feed',
                                section: _DashboardSection.feedResults,
                                activeBg: activeBg,
                                textColor: itemTextColor),
                            _sidebarChildItem(
                                label: 'Personalized',
                                section: _DashboardSection.personalResults,
                                activeBg: activeBg,
                                textColor: itemTextColor),
                            _sidebarChildItem(
                                label: 'General Ranking',
                                section: _DashboardSection.generalResults,
                                activeBg: activeBg,
                                textColor: itemTextColor),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 10),
                _sidebarExternalNavItem(
                  icon: Icons.hub_outlined,
                  label: 'Open Skill Pattern Lab (Step 0)',
                  onTap: _openRecommendationWebLab,
                  textColor: itemTextColor,
                ),
              ],
            ),
          ),
          // ── Sign-out footer ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  child:
                      const Icon(Icons.person, color: Colors.white, size: 17),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    FirebaseAuth.instance.currentUser?.email ?? 'Admin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.logout, color: Colors.white54, size: 17),
                  tooltip: 'Sign out',
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarNavItem({
    required IconData icon,
    required String label,
    required _DashboardSection section,
    required Color activeBg,
    required Color textColor,
  }) {
    final isActive = _activeSection == section;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isActive ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: () => setState(() => _activeSection = section),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon,
                    color: isActive ? Colors.white : textColor, size: 18),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    color: isActive ? Colors.white : textColor,
                    fontSize: 13,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebarParentItem({
    required IconData icon,
    required String label,
    required Color goldAccent,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Icon(icon, color: goldAccent, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  color: goldAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: goldAccent,
              size: 15,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarChildItem({
    required String label,
    required _DashboardSection section,
    required Color activeBg,
    required Color textColor,
  }) {
    final isActive = _activeSection == section;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 16),
      child: Material(
        color: isActive ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: () {
            // Sync _category with result sections so panels render correctly.
            if (section == _DashboardSection.feedResults) {
              _category = _WebRecommendationCategory.feed;
            } else if (section == _DashboardSection.personalResults) {
              _category = _WebRecommendationCategory.personalized;
            } else if (section == _DashboardSection.generalResults) {
              _category = _WebRecommendationCategory.general;
            }
            setState(() => _activeSection = section);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white : Colors.white38,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    color: isActive ? Colors.white : textColor,
                    fontSize: 12,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebarExternalNavItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color textColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, color: textColor, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.open_in_new, color: Colors.white54, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openRecommendationWebLab() async {
    setState(() {
      _activeSection = _DashboardSection.skillPatternLab;
    });
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final aiCoveragePercent = (_aiCoverageFor(_activeAiPostResults) * 100)
        .toStringAsFixed(0);
    const sectionNames = {
      _DashboardSection.overview: 'Dashboard Overview',
      _DashboardSection.studentLab: 'Student Recommendation Lab',
      _DashboardSection.projectApproval: 'Project Approval',
      _DashboardSection.kmeans: 'K-Means Clustering',
      _DashboardSection.localMath: 'Local Ranking Math',
      _DashboardSection.aiStage: 'AI Rerank Stage',
      _DashboardSection.benchmark: 'Benchmark & Validation',
      _DashboardSection.feedResults: 'Feed Recommendations',
      _DashboardSection.personalResults: 'Personalized Recommendations',
      _DashboardSection.generalResults: 'General Student Ranking',
      _DashboardSection.studentExplorer: 'Student Explorer',
      _DashboardSection.skillPatternLab: 'Step 0: AI Skill Pattern Lab',
    };

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: AppColors.borderLight)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF8CC63F),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            sectionNames[_activeSection] ?? 'Dashboard',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimaryLight,
            ),
          ),
          if (_loadingRemote) ...[
            const SizedBox(width: 14),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            Text(
              'Syncing...',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: AppColors.textSecondaryLight),
            ),
          ],
          const Spacer(),
          if (_remoteError != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red.shade600, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Firestore error',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome,
                    color: Color(0xFF7C3AED), size: 14),
                const SizedBox(width: 4),
                Text(
                  'AI $aiCoveragePercent%',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: const Color(0xFF7C3AED),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Selected student chip in top bar
          if (_selectedUser != null) ...[
            _UserAvatar(user: _selectedUser!, radius: 14),
            const SizedBox(width: 6),
            Text(
              _displayName(_selectedUser!),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Main content switcher ─────────────────────────────────────────────────

  Widget _buildMainContent() {
    const p = AppColors.textPrimaryLight;
    const s = AppColors.textSecondaryLight;
    return switch (_activeSection) {
      _DashboardSection.overview => _buildOverviewSection(),
      _DashboardSection.studentLab => _buildStudentLabSection(),
      _DashboardSection.studentExplorer => _buildStudentExplorer(),
      _DashboardSection.projectApproval => _buildProjectApprovalSection(p, s),
      _DashboardSection.kmeans => ListView(
          padding: const EdgeInsets.all(20),
          children: [_kMeansPanel(p, s)],
        ),
      _DashboardSection.localMath => ListView(
          padding: const EdgeInsets.all(20),
          children: [_localMathPanel(p, s)],
        ),
      _DashboardSection.aiStage => ListView(
          padding: const EdgeInsets.all(20),
          children: [_aiStagePanel(p, s)],
        ),
      _DashboardSection.benchmark => ListView(
          padding: const EdgeInsets.all(20),
          children: [_benchmarkPanel(p, s)],
        ),
      _DashboardSection.feedResults => ListView(
          padding: const EdgeInsets.all(20),
          children: [_feedResultsPanel(p, s)],
        ),
      _DashboardSection.personalResults => ListView(
          padding: const EdgeInsets.all(20),
          children: [_personalResultsPanel(p, s)],
        ),
      _DashboardSection.generalResults => ListView(
          padding: const EdgeInsets.all(20),
          children: [_generalResultsPanel(p, s)],
        ),
      _DashboardSection.skillPatternLab => const RecommendationWebLabScreen(),
    };
  }

  // ── Overview section ──────────────────────────────────────────────────────

  Widget _buildOverviewSection() {
    const p = AppColors.textPrimaryLight;
    const s = AppColors.textSecondaryLight;
    // Use SingleChildScrollView + Column instead of ListView to avoid the
    // Flutter web sliver hit-test bug where RenderIndexedSemantics can have
    // layoutOffset set but size MISSING when a pointer event arrives before
    // performLayout completes for a lazily-built sliver child.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatsRow(),
          const SizedBox(height: 16),
          _heroCard(p),
          const SizedBox(height: 16),
          _overviewFacultySummaryPanel(p, s),
          const SizedBox(height: 16),
          _overviewFacultySpotlightsPanel(p, s),
          if (_remoteError != null) ...[
            const SizedBox(height: 14),
            _panel(
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red.shade600, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _remoteError!,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!_loadingRemote && _users.isEmpty) ...[
            const SizedBox(height: 14),
            _panel(
              child: Text(
                'No users found from Firestore. Ensure your users collection contains profile data.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: s),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _overviewFacultySummaryPanel(Color textPrimary, Color textSecondary) {
    final bestFaculty = _bestFacultyName;
    final students = _studentsForFaculty(bestFaculty);
    final topStudent = _topStudentsByFaculty
        .where((entry) => entry.key == bestFaculty)
        .map((entry) => entry.value.firstOrNull)
        .cast<_GeneralStudentScore?>()
        .firstWhere((_) => true, orElse: () => null);

    return _panel(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.mustGoldLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              color: AppColors.mustGoldDark,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Best Performing Faculty',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  bestFaculty,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${students.length} students${topStudent != null ? ' · top student ${_displayName(topStudent.user)}' : ''}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewFacultySpotlightsPanel(
    Color textPrimary,
    Color textSecondary,
  ) {
    final topEntries = _topStudentsByFaculty.take(4).toList(growable: false);

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Best Students Per Faculty',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'A clean snapshot of the strongest student in each top faculty based on the current global scoring model.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          ...topEntries.map((entry) {
            final topStudent = entry.value.first;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                children: [
                  _UserAvatar(user: topStudent.user, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _displayName(topStudent.user),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint10,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${(topStudent.score * 100).round()}%',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProjectApprovalSection(Color textPrimary, Color textSecondary) {
    if (_loadingRemote && _approvalPosts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final pending = _approvalPosts
        .where((post) => post.moderationStatus.name == 'pending')
        .toList(growable: false);
    final approved = _approvalPosts
        .where((post) => post.moderationStatus.name == 'approved')
        .length;
    final rejected = _approvalPosts
        .where((post) => post.moderationStatus.name == 'rejected')
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Project Approval',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Pending projects are checked through the local AI proxy, then mapped to approve, reject, or manual review.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        for (final post in pending) {
                          _ensureApprovalAiReview(post);
                        }
                      },
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('Run AI Review'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InlineMetricChip(
                      label: 'pending_projects',
                      value: '${pending.length}',
                    ),
                    _InlineMetricChip(
                      label: 'approved_visible',
                      value: '$approved',
                    ),
                    _InlineMetricChip(
                      label: 'rejected',
                      value: '$rejected',
                    ),
                    _InlineMetricChip(
                      label: 'ai_reviewed',
                      value: '${_approvalAiByPostId.length}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_approvalPosts.isEmpty)
            _panel(
              child: Text(
                'No project approval records loaded yet.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: textSecondary,
                ),
              ),
            )
          else
            ..._approvalPosts.take(80).map(
                  (post) => _projectApprovalCard(
                    post: post,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _projectApprovalCard({
    required PostModel post,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final review = _approvalAiByPostId[post.id];
    final inFlight = _approvalAiInFlightPostIds.contains(post.id);
    final status = post.moderationStatus.name;
    final decision = review?.decision ?? (inFlight ? 'checking' : 'not_run');
    final decisionColor = _approvalDecisionColor(decision);
    final finalResult = _approvalFinalResult(status, review);

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  post.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
              ),
              _statusPill(status, AppColors.textSecondaryLight),
              const SizedBox(width: 8),
              _statusPill(decision, decisionColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${post.authorName ?? post.authorId} • ${post.faculty ?? 'Unknown faculty'} • ${post.createdAt.toLocal()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            post.description?.trim().isNotEmpty == true
                ? post.description!.trim()
                : 'No project description supplied.',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.45,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InlineMetricChip(
                label: 'skills',
                value: post.skillsUsed.isEmpty
                    ? '0'
                    : post.skillsUsed.take(4).join(', '),
              ),
              _InlineMetricChip(
                label: 'media',
                value: '${post.mediaUrls.length}',
              ),
              _InlineMetricChip(
                label: 'links',
                value: '${post.externalLinks.length}',
              ),
              _InlineMetricChip(
                label: 'final_result',
                value: finalResult,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (inFlight)
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Local AI is reviewing this project...',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: textSecondary,
                  ),
                ),
              ],
            )
          else if (review != null) ...[
            Text(
              review.summary,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: decisionColor,
              ),
            ),
            if (review.findings.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                review.findings.take(3).join(' | '),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            if (review.scores.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: review.scores.entries
                    .take(6)
                    .map(
                      (entry) => _InlineMetricChip(
                        label: entry.key,
                        value: entry.value.toStringAsFixed(0),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ] else
            OutlinedButton.icon(
              onPressed: () => _ensureApprovalAiReview(post),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Run local AI review'),
            ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Color _approvalDecisionColor(String decision) {
    switch (decision.toLowerCase()) {
      case 'approve':
      case 'approved':
        return const Color(0xFF0F9D58);
      case 'reject':
      case 'rejected':
        return Colors.red.shade700;
      case 'needs_human':
      case 'pending':
        return AppColors.mustGoldDark;
      case 'checking':
        return AppColors.primaryDark;
      default:
        return AppColors.textSecondaryLight;
    }
  }

  String _approvalFinalResult(String currentStatus, _ApprovalAiReview? review) {
    if (currentStatus != 'pending') return currentStatus;
    final decision = review?.decision.toLowerCase();
    if (decision == 'approve') return 'would_approve';
    if (decision == 'reject') return 'would_reject';
    if (decision == 'needs_human') return 'manual_review';
    return 'pending_ai';
  }

  Widget _buildStatsRow() {
    final byFaculty = <String, int>{};
    for (final u in _users) {
      final f = u.profile?.faculty ?? 'Unknown';
      byFaculty[f] = (byFaculty[f] ?? 0) + 1;
    }
    final topFaculty = byFaculty.isEmpty
        ? 'N/A'
        : (byFaculty.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    final short = topFaculty.length > 18
        ? '${topFaculty.substring(0, 18)}…'
        : topFaculty;

    return Row(
      children: [
        _statCard(
          icon: Icons.people_rounded,
          label: 'Total Students',
          value: '${_users.length}',
          color: const Color(0xFF0D1B8F),
        ),
        const SizedBox(width: 12),
        _statCard(
          icon: Icons.article_outlined,
          label: 'Content Pool',
          value: '${_posts.length}',
          color: const Color(0xFF1B8A4B),
        ),
        const SizedBox(width: 12),
        _statCard(
          icon: Icons.videocam_outlined,
          label: 'Video Posts',
          value: '${_videoCandidates.length}',
          color: const Color(0xFF7C3AED),
        ),
        const SizedBox(width: 12),
        _statCard(
          icon: Icons.school_outlined,
          label: 'Top Faculty',
          value: short,
          color: const Color(0xFFE65100),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimaryLight,
                    ),
                  ),
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Student Explorer ──────────────────────────────────────────────────────

  Widget _buildStudentExplorer() {
    if (_loadingRemote) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_users.isEmpty) {
      return Center(
        child: Text(
          'No students loaded yet.',
          style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondaryLight),
        ),
      );
    }

    final studentScores = <String, double>{
      for (final item in _allStudentScores) item.user.id: item.score,
    };
    final clusterColors = [
      const Color(0xFF0D1B8F),
      const Color(0xFF1B8A4B),
      const Color(0xFFE65100),
    ];
    final activeFaculty = _explorerFaculty;
    final students = _studentsForFaculty(activeFaculty);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.account_balance_outlined,
                    size: 18,
                    color: AppColors.primaryDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      activeFaculty,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimaryLight,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint10,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${students.length} students',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    tooltip: 'Select faculty',
                    icon: const Icon(
                      Icons.filter_alt_outlined,
                      color: AppColors.textSecondaryLight,
                    ),
                    onSelected: _selectFaculty,
                    itemBuilder: (context) {
                      return _facultyOptions
                          .where((faculty) => faculty != _allFaculties)
                          .map(
                            (faculty) => PopupMenuItem<String>(
                              value: faculty,
                              child: Text(
                                faculty,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (students.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No students found for this faculty. Use the filter icon to switch faculty.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textSecondaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        (constraints.maxWidth / 280).floor().clamp(1, 6);
                    final totalSpacing = (columns - 1) * 14;
                    final itemWidth =
                        (constraints.maxWidth - totalSpacing) / columns;

                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: students.asMap().entries.map((studentEntry) {
                        final user = studentEntry.value;
                        final score = studentScores[user.id];
                        final cluster =
                            _currentKMeansTrace.finalAssignments[user.id];
                        final color = cluster != null
                            ? clusterColors[cluster % 3]
                            : AppColors.primary;
                        final studentDelay =
                            math.min(studentEntry.key * 24, 140);

                        return TweenAnimationBuilder<double>(
                          duration: Duration(milliseconds: 220 + studentDelay),
                          curve: Curves.easeOutCubic,
                          tween: Tween(begin: 0, end: 1),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, (1 - value) * 10),
                                child: child,
                              ),
                            );
                          },
                          child: SizedBox(
                            width: itemWidth,
                            child: _StudentExplorerCard(
                              user: user,
                              score: score,
                              cluster: cluster,
                              clusterColor: color,
                              onSelect: () => _selectStudent(user),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard(Color textPrimary) {
    final currentUser = _selectedUser;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1B8F), Color(0xFF1963D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D1B8F).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Gold top accent bar ─────────────────────────────────────
          Container(
            height: 4,
            decoration: const BoxDecoration(
              color: Color(0xFFF4B400),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppDimensions.radiusLg),
                topRight: Radius.circular(AppDimensions.radiusLg),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4B400).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              const Color(0xFFF4B400).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        'LIVE',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFFF4B400),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Recommendation Lab',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _categoryDescription,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricPill(
                        label: 'Students', value: '${_users.length}'),
                    _MetricPill(
                        label: 'Content Pool', value: '${_posts.length}'),
                    _MetricPill(
                      label: 'AI Stage',
                      value:
                          '${(_aiCoverageFor(_activeAiPostResults) * 100).toStringAsFixed(0)}% scored',
                    ),
                  ],
                ),
                if (currentUser != null) ...[
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _UserAvatar(user: currentUser, radius: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName(currentUser),
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              currentUser.profile?.faculty ??
                                  currentUser.email,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if ((currentUser.profile?.programName ?? '')
                          .isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            currentUser.profile!.programName!,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kMeansPanel(Color textPrimary, Color textSecondary) {
    final trace = _currentKMeansTrace;
    final counts = <int, int>{0: 0, 1: 0, 2: 0};
    for (final cluster in trace.finalAssignments.values) {
      counts[cluster] = (counts[cluster] ?? 0) + 1;
    }

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 1: K-means clustering trace',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Students are projected into a 3D feature vector: skills density, activity density, and profile completeness. The chart and iteration blocks below show how cluster membership stabilizes over time.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.45,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          ...trace.iterations.map((iteration) {
            final iterationCounts = <int, int>{0: 0, 1: 0, 2: 0};
            for (final cluster in iteration.assignments.values) {
              iterationCounts[cluster] = (iterationCounts[cluster] ?? 0) + 1;
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Iteration ${iteration.iteration}',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          'C0:${iterationCounts[0]}  C1:${iterationCounts[1]}  C2:${iterationCounts[2]}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      iteration.centroids
                          .asMap()
                          .entries
                          .map(
                            (entry) => 'Centroid ${entry.key}: '
                                'skills=${_d(entry.value.skillsDensity)}, '
                                'activity=${_d(entry.value.activityDensity)}, '
                                'complete=${_d(entry.value.completeness)}',
                          )
                          .join(' | '),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: trace.points.map((point) {
              final cluster = trace.finalAssignments[point.user.id] ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_displayName(point.user)} -> C$cluster',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 900;
              final histogram = JsVisualizationPanel(
                chartId:
                    'kmeans-${_selectedUserId ?? 'none'}-${_chartToken(_selectedFaculty)}',
                title: 'Cluster distribution (histogram)',
                labels: const ['Cluster 0', 'Cluster 1', 'Cluster 2'],
                values: [
                  (counts[0] ?? 0).toDouble(),
                  (counts[1] ?? 0).toDouble(),
                  (counts[2] ?? 0).toDouble(),
                ],
                color: AppColors.primary,
                height: 240,
              );
              final scatter = _ClusterScatterPlot(
                points: trace.points,
                assignments: trace.finalAssignments,
              );

              if (isCompact) {
                return Column(
                  children: [
                    histogram,
                    const SizedBox(height: 12),
                    scatter,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: histogram),
                  const SizedBox(width: 12),
                  Expanded(child: scatter),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _localMathPanel(Color textPrimary, Color textSecondary) {
    if (_category == _WebRecommendationCategory.general) {
      return _generalLocalMathPanel(textPrimary, textSecondary);
    }

    final results = _activeLocalPostResults;
    const weights = {
      'content_similarity': 0.30,
      'behavioral_relevance': 0.18,
      'cluster_affinity': 0.08,
      'quality_score': 0.18,
      'freshness': 0.13,
      'diversity': 0.07,
      'trust_adjusted': 0.06,
    };

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 2: Local ranking mathematics',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.mustGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.mustGold.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aim',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Score each post by relevance + quality, then rank by final blended local score.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Formula',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'final_local = Σ(weight_i × component_i) + advert_adjustment',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: weights.entries
                .map(
                  (entry) => _InlineMetricChip(
                    label: entry.key,
                    value: entry.value.toStringAsFixed(2),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          JsVisualizationPanel(
            chartId: 'local-${_category.name}-${_selectedUserId ?? 'none'}',
            title: 'Top local scores',
            labels: results.take(8).map((item) => item.post.title).toList(),
            values: results.take(8).map((item) => item.score).toList(),
            color: const Color(0xFF1B8A4B),
            height: 250,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 12,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columns: const [
                DataColumn(label: Text('Post')),
                DataColumn(label: Text('Content')),
                DataColumn(label: Text('Behavior')),
                DataColumn(label: Text('Cluster')),
                DataColumn(label: Text('Quality')),
                DataColumn(label: Text('Freshness')),
                DataColumn(label: Text('Final')),
              ],
              rows: results.take(8).map((item) {
                final breakdown = item.scoreBreakdown;
                return DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 160,
                        child: Text(
                          item.post.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(fontSize: 11),
                        ),
                      ),
                    ),
                    DataCell(SizedBox(width: 54, child: Text(_d(breakdown['content_similarity']), style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(breakdown['behavioral_relevance']), style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(breakdown['cluster_affinity']), style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(breakdown['quality_score']), style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(breakdown['freshness']), style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(item.score), style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700)))),
                  ],
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _generalLocalMathPanel(Color textPrimary, Color textSecondary) {
    const weights = {
      'streak_score': 0.24,
      'post_score': 0.22,
      'collab_score': 0.20,
      'follower_score': 0.14,
      'profile_completeness': 0.12,
      'skill_density': 0.08,
    };

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 2: General ranking formula',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aim',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rank students by cohort contribution, then adjust with AI sentiment from project comments.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Working',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'base_score = Σ(weight_i × cohort_signal_i)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'sentiment_delta = (ai_comment_sentiment - 0.5) × 0.22',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'final_score = clamp(base_score + sentiment_delta, 0, 1)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: weights.entries
                .map(
                  (entry) => _InlineMetricChip(
                    label: entry.key,
                    value: entry.value.toStringAsFixed(2),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          JsVisualizationPanel(
            chartId: 'general-${_chartToken(_selectedFaculty)}',
            title: 'General student scores',
            labels: _generalResults
                .take(8)
                .map((item) => _displayName(item.user))
                .toList(),
            values: _generalResults.take(8).map((item) => item.score).toList(),
            color: AppColors.mustGoldDark,
            height: 250,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 12,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columns: const [
                DataColumn(label: Text('Student')),
                DataColumn(label: Text('Cluster')),
                DataColumn(label: Text('Streak')),
                DataColumn(label: Text('Posts')),
                DataColumn(label: Text('Collabs')),
                DataColumn(label: Text('Followers')),
                DataColumn(label: Text('AI Sent')),
                DataColumn(label: Text('Final')),
              ],
              rows: _generalResults.take(8).map((item) {
                final breakdown = item.scoreBreakdown;
                return DataRow(
                  cells: [
                    DataCell(SizedBox(width: 130, child: Text(_displayName(item.user), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 40, child: Text('C${item.cluster}', style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(breakdown['streak_score']), style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(breakdown['post_score']), style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(breakdown['collab_score']), style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(breakdown['follower_score']), style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(breakdown['ai_comment_sentiment']), style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(item.score), style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700)))),
                  ],
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiStagePanel(Color textPrimary, Color textSecondary) {
    if (_category == _WebRecommendationCategory.general) {
      return _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Step 3: AI stage',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'General recommendation is cohort-wide and stays local in this dashboard. No AI reranking is applied here because the goal is a stable faculty-filtered leaderboard.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                height: 1.45,
                color: textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final rows = _activeAiPostResults.take(8).toList(growable: false);
    final diagnostics = _activeHybridDiagnostics;
    final aiCoverage = _aiCoverageFor(rows);
    final aiCoveragePercent = (aiCoverage * 100).toStringAsFixed(1);
    final aiCount = _openAiCountFor(rows);
    final realAiCount = _realOpenAiCountFor(rows);
    final proxyAiCount = _proxyAiCountFor(rows);
    final appLocalRows = _runtimeLogsForSelectedUser('local');
    final appHybridRows = _runtimeLogsForSelectedUser('hybrid');
    final appQueueRows = _runtimeLogsForSelectedUser('feed_video_queue');

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 3: AI rerank stage',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            realAiCount > 0
                ? 'Hybrid ranking is active with real OpenAI rerank values in this batch.'
                : proxyAiCount > 0
                    ? 'Hybrid ranking is active with deterministic proxy-AI rerank (OpenAI response unavailable for this batch).'
                    : 'Hybrid ranking currently has no AI score entries for this batch.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.45,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InlineMetricChip(
                label: 'ai_coverage',
                value: '$aiCount/${rows.length} ($aiCoveragePercent%)',
              ),
              _InlineMetricChip(
                label: 'ai_real',
                value: '$realAiCount',
              ),
              _InlineMetricChip(
                label: 'ai_proxy',
                value: '$proxyAiCount',
              ),
              _InlineMetricChip(
                label: 'openai_avg',
                value: _d(_avgOpenAiScoreFor(rows)),
              ),
              _InlineMetricChip(
                label: 'avg_ai_lift',
                value: _d(_avgAiLiftFor(rows)),
              ),
              _InlineMetricChip(
                label: 'app_local_logs',
                value: '${appLocalRows.length}',
              ),
              _InlineMetricChip(
                label: 'app_hybrid_logs',
                value: '${appHybridRows.length}',
              ),
              _InlineMetricChip(
                label: 'app_queue_logs',
                value: '${appQueueRows.length}',
              ),
              _InlineMetricChip(
                label: 'app_local_avg',
                value: _d(_avgScoreFromRuntimeRows(appLocalRows)),
              ),
              _InlineMetricChip(
                label: 'app_hybrid_avg',
                value: _d(_avgScoreFromRuntimeRows(appHybridRows)),
              ),
              if (diagnostics != null) ...[
                _InlineMetricChip(
                  label: 'openai_configured',
                  value: diagnostics.openAiConfigured ? '1' : '0',
                ),
                _InlineMetricChip(
                  label: 'openai_attempted',
                  value: diagnostics.openAiAttempted ? '1' : '0',
                ),
                _InlineMetricChip(
                  label: 'openai_succeeded',
                  value: diagnostics.openAiSucceeded ? '1' : '0',
                ),
                _InlineMetricChip(
                  label: 'openai_rows',
                  value: '${diagnostics.rankingRows}',
                ),
              ],
            ],
          ),
          if (diagnostics != null) ...[
            const SizedBox(height: 8),
            Text(
              'rerank_status: ${diagnostics.reason}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          JsVisualizationPanel(
            chartId: 'ai-${_category.name}-${_selectedUserId ?? 'none'}',
            title: 'Blended AI scores',
            labels: rows.take(8).map((item) => item.post.title).toList(),
            values: rows.take(8).map((item) => item.score).toList(),
            color: const Color(0xFF7C3AED),
            height: 250,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 12,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columns: const [
                DataColumn(label: Text('Post')),
                DataColumn(label: Text('Local')),
                DataColumn(label: Text('AI')),
                DataColumn(label: Text('Blended')),
              ],
              rows: rows.map((item) {
                final breakdown = item.scoreBreakdown;
                final localScore =
                    breakdown['local_score'] ?? breakdown['blended_score'] ?? item.score;
                final aiScore =
                    breakdown['openai_score'] ?? breakdown['blended_score'] ?? item.score;
                return DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 160,
                        child: Text(
                          item.post.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(fontSize: 11),
                        ),
                      ),
                    ),
                    DataCell(SizedBox(width: 54, child: Text(_d(localScore), style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(aiScore), style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(SizedBox(width: 54, child: Text(_d(item.score), style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700)))),
                  ],
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }


  Widget _benchmarkPanel(Color textPrimary, Color textSecondary) {
    final benchmark = _benchmark;
    if (benchmark == null) {
      return _panel(
        child: Text(
          'Benchmark will appear after recommendation computation completes.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: textSecondary,
          ),
        ),
      );
    }

    final reasonEntries = benchmark.reasonDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final logEntries = benchmark.algorithmLogCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 3.5: Benchmark and validation layer',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Benchmarks compare local ranking and hybrid ranking on the same Firestore records. This quantifies whether reranking changes quality and ordering.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.45,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InlineMetricChip(
                label: 'local_avg@10',
                value: benchmark.localAverageTopN.toStringAsFixed(3),
              ),
              _InlineMetricChip(
                label: 'hybrid_avg@10',
                value: benchmark.hybridAverageTopN.toStringAsFixed(3),
              ),
              _InlineMetricChip(
                label: 'lift_%',
                value: benchmark.liftPercent.toStringAsFixed(2),
              ),
              _InlineMetricChip(
                label: 'top10_overlap',
                value: benchmark.topNOverlapRatio.toStringAsFixed(3),
              ),
              _InlineMetricChip(
                label: 'compared_count',
                value: '${benchmark.comparedCount}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          JsVisualizationPanel(
            chartId: 'benchmark-${_category.name}-${_selectedUserId ?? 'none'}',
            title: 'Local vs Hybrid average score (Top 10)',
            labels: const ['Local', 'Hybrid'],
            values: [
              benchmark.localAverageTopN,
              benchmark.hybridAverageTopN,
            ],
            color: AppColors.primaryDark,
            height: 230,
          ),
          const SizedBox(height: 10),
          if (reasonEntries.isNotEmpty) ...[
            Text(
              'Top reasons in current hybrid output',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: reasonEntries
                  .take(8)
                  .map(
                    (entry) => _InlineMetricChip(
                      label: entry.key,
                      value: '${entry.value}',
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 10),
          ],
          if (logEntries.isNotEmpty) ...[
            Text(
              'Recent recommendation_logs distribution (Firestore)',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: logEntries
                  .take(8)
                  .map(
                    (entry) => _InlineMetricChip(
                      label: entry.key,
                      value: '${entry.value}',
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _feedResultsPanel(Color textPrimary, Color textSecondary) {
    final results = _feedAiResults;
    final eligibleQueue = _feedVideoQueue
        .where((item) => item.isEligible)
        .take(5)
        .toList(growable: false);
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 4: Feed recommendation output',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'These are the video-first items that the selected student would see after local ranking and the AI-preview blend.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: textSecondary,
            ),
          ),
          if (_feedVideoQueue.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Potential queue: ${eligibleQueue.length} eligible from ${_feedVideoQueue.length} video candidates before ranking.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...results
              .take(10)
              .toList(growable: false)
              .asMap()
              .entries
              .map((entry) {
            final rank = entry.key + 1;
            final item = entry.value;
            return _RankedPostTile(rank: rank, item: item);
          }),
        ],
      ),
    );
  }

  Widget _personalResultsPanel(Color textPrimary, Color textSecondary) {
    final projectResults = _personalAiResults
        .where((item) => item.post.type != 'opportunity')
        .take(4)
        .toList(growable: false);
    final opportunityResults = _personalAiResults
        .where((item) => item.post.type == 'opportunity')
        .take(4)
        .toList(growable: false);

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 4: Personal recommendation outputs',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Personal recommendation combines ranked projects, ranked opportunities, and collaborator suggestions generated from the selected student profile and recent-session signals.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.45,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          _ResultSubsection(
            title: 'Projects',
            child: Column(
              children: projectResults
                  .asMap()
                  .entries
                  .map(
                    (entry) => _RankedPostTile(
                      rank: entry.key + 1,
                      item: entry.value,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 10),
          _ResultSubsection(
            title: 'Opportunities',
            child: Column(
              children: opportunityResults
                  .asMap()
                  .entries
                  .map(
                    (entry) => _RankedPostTile(
                      rank: entry.key + 1,
                      item: entry.value,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 10),
          _ResultSubsection(
            title: 'Potential collaborators',
            child: Column(
              children: _collaboratorResults
                  .take(4)
                  .toList(growable: false)
                  .asMap()
                  .entries
                  .map((entry) {
                final item = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Row(
                    children: [
                      _UserAvatar(user: item.user, radius: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '#${entry.key + 1}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _displayName(item.user),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _d(item.score),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryDark,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (item.matchedSkills.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Skills: ${item.matchedSkills.join(', ')}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _generalResultsPanel(Color textPrimary, Color textSecondary) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 4: General recommendation output',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This list ranks students irrespective of viewer. The only applied filter is faculty, which lets you inspect the global leaderboard inside a cohort.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.45,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ..._generalResults
              .take(12)
              .toList(growable: false)
              .asMap()
              .entries
              .map((entry) {
            final rank = entry.key + 1;
            final item = entry.value;
            final clusterColors = [
              const Color(0xFF0D1B8F),
              const Color(0xFF1B8A4B),
              const Color(0xFFE65100),
            ];
            final clusterColor = clusterColors[item.cluster % 3];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.mustGoldLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.mustGold.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                children: [
                  // Rank badge
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: rank <= 3
                          ? AppColors.mustGold
                          : AppColors.mustGold.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w900,
                          color: rank <= 3
                              ? Colors.white
                              : AppColors.mustGoldDark,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _UserAvatar(user: item.user, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName(item.user),
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          item.scoreBreakdown.entries
                              .map((e) => '${e.key}=${_d(e.value)}')
                              .join(' · '),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: clusterColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'C${item.cluster}',
                      style: GoogleFonts.plusJakartaSans(
                        color: clusterColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _d(item.score),
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w900,
                      color: AppColors.mustGoldDark,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  List<RecommendedPost> get _activeLocalPostResults {
    switch (_category) {
      case _WebRecommendationCategory.feed:
        return _feedLocalResults;
      case _WebRecommendationCategory.personalized:
        return _personalLocalResults;
      case _WebRecommendationCategory.general:
        return const <RecommendedPost>[];
    }
  }

  List<RecommendedPost> get _activeAiPostResults {
    switch (_category) {
      case _WebRecommendationCategory.feed:
        return _feedAiResults;
      case _WebRecommendationCategory.personalized:
        return _personalAiResults;
      case _WebRecommendationCategory.general:
        return const <RecommendedPost>[];
    }
  }

  String get _categoryDescription {
    switch (_category) {
      case _WebRecommendationCategory.feed:
        return 'Feed recommendation ranks video-first posts for the selected student. It explains why one video rises above another using local weights, then shows a separate AI rerank stage.';
      case _WebRecommendationCategory.personalized:
        return 'Personal recommendation combines projects, opportunities, and collaborator suggestions using the selected student profile together with recent-session signals.';
      case _WebRecommendationCategory.general:
        return 'General recommendation ranks students irrespective of a viewer. It is cohort-based, faculty-filtered, and designed to surface the strongest overall student profiles.';
    }
  }

  String _displayName(UserModel user) {
    final name = (user.displayName ?? '').trim();
    return name.isNotEmpty ? name : user.email;
  }

  String _chartToken(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String _d(double? value) => (value ?? 0).toStringAsFixed(3);
}

class _ResultSubsection extends StatelessWidget {
  const _ResultSubsection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _RankedPostTile extends StatelessWidget {
  const _RankedPostTile({required this.rank, required this.item});

  final int rank;
  final RecommendedPost item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.primary.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#$rank',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.post.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${(item.score * 100).round()}%',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Reasons: ${item.reasons.join(', ')}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.scoreBreakdown.entries
                .map(
                  (entry) => '${entry.key}=${entry.value.toStringAsFixed(3)}',
                )
                .join(' | '),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: Colors.white,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMetricChip extends StatelessWidget {
  const _InlineMetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryTint10,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label = $value',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}

class _ClusterScatterPlot extends StatelessWidget {
  const _ClusterScatterPlot({
    required this.points,
    required this.assignments,
  });

  final List<_StudentPoint> points;
  final Map<String, int> assignments;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cluster spread plot (skills vs activity)',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: CustomPaint(
              painter: _ClusterScatterPainter(
                points: points,
                assignments: assignments,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClusterScatterPainter extends CustomPainter {
  const _ClusterScatterPainter({
    required this.points,
    required this.assignments,
  });

  final List<_StudentPoint> points;
  final Map<String, int> assignments;

  static const _clusterColors = <Color>[
    Color(0xFF1F6FEB),
    Color(0xFF0F9D58),
    Color(0xFFE67E22),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTWH(30, 8, size.width - 42, size.height - 32);
    final axisPaint = Paint()
      ..color = const Color(0xFF9AA4B2)
      ..strokeWidth = 1;

    canvas.drawLine(chart.bottomLeft, chart.bottomRight, axisPaint);
    canvas.drawLine(chart.bottomLeft, chart.topLeft, axisPaint);

    final gridPaint = Paint()
      ..color = const Color(0x1A0F172A)
      ..strokeWidth = 1;
    for (var i = 1; i <= 4; i++) {
      final y = chart.bottom - (chart.height * (i / 5));
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    for (final point in points) {
      final cluster = assignments[point.user.id] ?? 0;
      final color = _clusterColors[cluster.clamp(0, _clusterColors.length - 1)];
      final x = chart.left + (point.vector.skillsDensity.clamp(0.0, 1.0) * chart.width);
      final y = chart.bottom - (point.vector.activityDensity.clamp(0.0, 1.0) * chart.height);

      final dotPaint = Paint()..color = color;
      canvas.drawCircle(Offset(x, y), 4.5, dotPaint);
      canvas.drawCircle(
        Offset(x, y),
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.35),
      );
    }

    final labelStyle = GoogleFonts.plusJakartaSans(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF5B6676),
    );
    final xPainter = TextPainter(
      text: TextSpan(text: 'Skills density', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    xPainter.paint(canvas, Offset(chart.right - xPainter.width, chart.bottom + 8));

    final yPainter = TextPainter(
      text: TextSpan(text: 'Activity', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    yPainter.paint(canvas, Offset(2, chart.top));
  }

  @override
  bool shouldRepaint(covariant _ClusterScatterPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.assignments != assignments;
  }
}

class _GeneralStudentScore {
  const _GeneralStudentScore({
    required this.user,
    required this.score,
    required this.cluster,
    required this.scoreBreakdown,
  });

  final UserModel user;
  final double score;
  final int cluster;
  final Map<String, double> scoreBreakdown;
}

// ── Profile picture avatar with initials fallback ─────────────────────────────

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user, this.radius = 20});

  final UserModel user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.photoUrl;
    final name = (user.displayName ?? user.email).trim();
    final initials = name.isNotEmpty
        ? name
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .join()
        : '?';

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.18),
      backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
          ? NetworkImage(photoUrl)
          : null,
      child: (photoUrl == null || photoUrl.isEmpty)
          ? Text(
              initials,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: radius * 0.65,
                color: AppColors.primary,
              ),
            )
          : null,
    );
  }
}

// ── Student Explorer grid card ────────────────────────────────────────────────

class _StudentExplorerCard extends StatefulWidget {
  const _StudentExplorerCard({
    required this.user,
    required this.onSelect,
    this.score,
    this.cluster,
    this.clusterColor,
  });

  final UserModel user;
  final double? score;
  final int? cluster;
  final Color? clusterColor;
  final VoidCallback onSelect;

  @override
  State<_StudentExplorerCard> createState() => _StudentExplorerCardState();
}

class _StudentExplorerCardState extends State<_StudentExplorerCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final profile = widget.user.profile;
    final faculty = profile?.faculty ?? '';
    final skills = profile?.skills.take(3).toList() ?? const <String>[];
    final color = widget.clusterColor ?? AppColors.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.015 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onSelect,
            hoverColor: AppColors.primaryTint10,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _hovered
                      ? color.withValues(alpha: 0.38)
                      : AppColors.borderLight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: _hovered ? 0.09 : 0.04,
                    ),
                    blurRadius: _hovered ? 16 : 8,
                    offset: Offset(0, _hovered ? 6 : 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _UserAvatar(user: widget.user, radius: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.user.displayName ?? widget.user.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: AppColors.textPrimaryLight,
                              ),
                            ),
                            if (faculty.isNotEmpty)
                              Text(
                                faculty,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (widget.cluster != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'C${widget.cluster}',
                            style: GoogleFonts.plusJakartaSans(
                              color: color,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (skills.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: skills
                          .map(
                            (skill) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTint10,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                skill,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 9,
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (widget.score != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: widget.score,
                            backgroundColor: AppColors.borderLight,
                            color: color,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(widget.score! * 100).round()}%',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Feature chip for login branding panel ─────────────────────────────────────

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _KMeansTrace {
  const _KMeansTrace({
    required this.points,
    required this.iterations,
    required this.finalAssignments,
  });

  final List<_StudentPoint> points;
  final List<_KMeansIteration> iterations;
  final Map<String, int> finalAssignments;
}

class _KMeansIteration {
  const _KMeansIteration({
    required this.iteration,
    required this.centroids,
    required this.assignments,
  });

  final int iteration;
  final List<_FeatureVector> centroids;
  final Map<String, int> assignments;
}

class _StudentPoint {
  const _StudentPoint({required this.user, required this.vector});

  final UserModel user;
  final _FeatureVector vector;
}

class _FeatureVector {
  const _FeatureVector({
    required this.skillsDensity,
    required this.activityDensity,
    required this.completeness,
  });

  final double skillsDensity;
  final double activityDensity;
  final double completeness;

  double distanceTo(_FeatureVector other) {
    return math.sqrt(
      math.pow(skillsDensity - other.skillsDensity, 2) +
          math.pow(activityDensity - other.activityDensity, 2) +
          math.pow(completeness - other.completeness, 2),
    );
  }
}

bool _isVideoCandidate(PostModel post) {
  if (post.youtubeUrl != null && post.youtubeUrl!.trim().isNotEmpty) {
    return true;
  }

  final videoPattern = RegExp(
    r'\.(mp4|mov|m4v|3gp|webm|mkv)(\?|$)',
    caseSensitive: false,
  );

  return post.mediaUrls.any((url) {
    final lower = url.toLowerCase();
    return videoPattern.hasMatch(lower) ||
        lower.contains('/videos/') ||
        lower.contains('video/upload');
  });
}


