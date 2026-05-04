import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/skill_pattern_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/openai_service.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/remote/recommender_service.dart';
import '../../../data/remote/skill_pattern_service.dart';
import '../widgets/js_visualization_panel.dart';

enum _LabCategory { feed, personalized, global }
enum _PersonalizedTab { opportunities, collaborators }

class _RankedStudentItem {
  const _RankedStudentItem({required this.user, required this.globalScore});
  final UserModel user;
  final double globalScore;
}

class RecommendationWebLabScreen extends StatefulWidget {
  const RecommendationWebLabScreen({super.key});

  @override
  State<RecommendationWebLabScreen> createState() =>
      _RecommendationWebLabScreenState();
}

class _RecommendationWebLabScreenState extends State<RecommendationWebLabScreen> {
  static const int _studentSampleSize = 20;

  bool _loading = true;
  String? _error;
  _LabCategory _category = _LabCategory.feed;
  _PersonalizedTab _personalizedTab = _PersonalizedTab.opportunities;

  List<UserModel> _students = const <UserModel>[];
  List<PostModel> _posts = const <PostModel>[];
  String? _selectedStudentId;

  List<FeedVideoQueueItem> _feedVideoQueue = const <FeedVideoQueueItem>[];
  List<RecommendedPost> _personalizedOpportunities = const <RecommendedPost>[];
  List<RecommendedUser> _personalizedCollaborators = const <RecommendedUser>[];
  List<_RankedStudentItem> _globalStudentRanks = const <_RankedStudentItem>[];
  SkillPatternResult _skillPatterns = SkillPatternResult.empty();

  _KMeansTrace? _kMeansTrace;
  Map<String, double> _globalImpactByStudentId = const <String, double>{};
  bool _aiConfigured = false;

  @override
  void initState() {
    super.initState();
    _aiConfigured = sl<OpenAiService>().isConfigured;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final firestore = sl<FirestoreService>();
      final recommender = sl<RecommenderService>();

      final users = await firestore.getAllUsersFromRemote(limit: 500);
      final students = users
          .where((u) => u.role.name == 'student' && u.isActive && u.profile != null)
          .toList(growable: false);

      if (students.isEmpty) {
        throw StateError('No active students with profile data were found.');
      }

      final impactMap = <String, double>{
        for (final u in students) u.id: _impactScoreForProfile(u.profile!),
      };

      final sampled = [...students]..sort((a, b) {
          final ai = impactMap[a.id] ?? 0;
          final bi = impactMap[b.id] ?? 0;
          return bi.compareTo(ai);
        });

      final sampledStudents = sampled.take(_studentSampleSize).toList(growable: false);
      final selected = _selectedStudentId != null && sampledStudents.any((u) => u.id == _selectedStudentId)
          ? _selectedStudentId!
          : sampledStudents.first.id;

      final posts = await firestore.getRecentPosts(limit: 160);
      if (posts.isEmpty) {
        throw StateError('No posts were found.');
      }

      final selectedStudent = sampledStudents.firstWhere((u) => u.id == selected);
      final skillPatterns = await sl<SkillPatternService>().buildFromContext(
        userSkills: selectedStudent.profile?.skills ?? const <String>[],
        candidatePosts: posts,
        mode: 'personalized',
      );

      final feedQueue = recommender.buildFeedVideoQueue(
        user: selectedStudent,
        candidates: posts,
      );

      final opportunities = await recommender.rankHybrid(
        user: selectedStudent,
        candidates: posts.where((p) => p.type == 'opportunity').toList(),
        skillPatterns: skillPatterns,
      );

      final collaborators = recommender.rankCollaborators(
        currentUser: selectedStudent,
        candidates: sampledStudents,
      );

      final globalRanks = sampledStudents.map((u) {
        return _RankedStudentItem(
          user: u,
          globalScore: recommender.computeGlobalStudentScore(u),
        );
      }).toList(growable: false)
        ..sort((a, b) => b.globalScore.compareTo(a.globalScore));

      final kMeansTrace = _buildKMeansTrace(sampledStudents);

      if (!mounted) return;

      setState(() {
        _students = sampledStudents;
        _posts = posts;
        _selectedStudentId = selected;
        _globalImpactByStudentId = impactMap;

        _feedVideoQueue = feedQueue;
        _personalizedOpportunities = opportunities;
        _personalizedCollaborators = collaborators;
        _globalStudentRanks = globalRanks;
        
        _skillPatterns = skillPatterns;
        _kMeansTrace = kMeansTrace;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }


  _KMeansTrace _buildKMeansTrace(List<UserModel> students) {
    final points = students
        .map(
          (u) => _StudentPoint(
            user: u,
            vector: _FeatureVector(
              skillsDensity: ((u.profile?.skills.length ?? 0) / 12.0)
                  .clamp(0.0, 1.0)
                  .toDouble(),
              activityDensity: (((u.profile?.totalPosts ?? 0) / 25.0) * 0.6 +
                      ((u.profile?.totalCollabs ?? 0) / 10.0) * 0.4)
                  .clamp(0.0, 1.0)
                  .toDouble(),
              completeness: _profileCompleteness(u),
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
        if (members.isEmpty) {
          return centroids[cluster];
        }

        final s = members.fold<_FeatureVector>(
          const _FeatureVector(skillsDensity: 0, activityDensity: 0, completeness: 0),
          (acc, p) => _FeatureVector(
            skillsDensity: acc.skillsDensity + p.vector.skillsDensity,
            activityDensity: acc.activityDensity + p.vector.activityDensity,
            completeness: acc.completeness + p.vector.completeness,
          ),
        );

        return _FeatureVector(
          skillsDensity: s.skillsDensity / members.length,
          activityDensity: s.activityDensity / members.length,
          completeness: s.completeness / members.length,
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

    final finalAssignments = iterations.isNotEmpty
        ? iterations.last.assignments
        : <String, int>{};

    return _KMeansTrace(
      points: points,
      iterations: iterations,
      finalAssignments: finalAssignments,
    );
  }

  double _profileCompleteness(UserModel user) {
    final p = user.profile;
    if (p == null) {
      return 0.0;
    }
    final completed = [
      (p.bio ?? '').trim().isNotEmpty,
      (p.programName ?? '').trim().isNotEmpty,
      (p.faculty ?? '').trim().isNotEmpty,
      p.skills.isNotEmpty,
    ].where((v) => v).length;
    return (completed / 4.0).clamp(0.0, 1.0).toDouble();
  }

  double _impactScoreForProfile(dynamic profile) {
    final streak = (profile.activityStreak / 30).clamp(0.0, 1.0).toDouble();
    final posts = (profile.totalPosts / 20).clamp(0.0, 1.0).toDouble();
    final collabs = (profile.totalCollabs / 12).clamp(0.0, 1.0).toDouble();
    final followers = (profile.totalFollowers / 150).clamp(0.0, 1.0).toDouble();

    var completed = 0;
    if ((profile.bio ?? '').trim().isNotEmpty) completed += 1;
    if ((profile.programName ?? '').trim().isNotEmpty) completed += 1;
    if ((profile.faculty ?? '').trim().isNotEmpty) completed += 1;
    if (profile.skills.isNotEmpty) completed += 1;
    final completeness = (completed / 4.0).clamp(0.0, 1.0).toDouble();

    final weighted = (0.32 * streak) +
        (0.24 * posts) +
        (0.19 * collabs) +
        (0.15 * followers) +
        (0.10 * completeness);
    return (weighted * 100).clamp(0.0, 100.0).toDouble();
  }

  Future<void> _onStudentChanged(String? userId) async {
    if (userId == null || userId == _selectedStudentId) {
      return;
    }

    setState(() {
      _selectedStudentId = userId;
      _loading = true;
    });

    try {
      final selected = _students.firstWhere((u) => u.id == userId);
      final recommender = sl<RecommenderService>();
      final skillPatterns = await sl<SkillPatternService>().buildFromContext(
        userSkills: selected.profile?.skills ?? const <String>[],
        candidatePosts: _posts,
        mode: _category == _LabCategory.personalized ? 'personalized' : 'feed',
      );

      final feedQueue = recommender.buildFeedVideoQueue(
        user: selected,
        candidates: _posts,
      );

      final opportunities = await recommender.rankHybrid(
        user: selected,
        candidates: _posts.where((p) => p.type == 'opportunity').toList(),
        skillPatterns: skillPatterns,
      );

      final collaborators = recommender.rankCollaborators(
        currentUser: selected,
        candidates: _students,
      );

      if (!mounted) return;

      setState(() {
        _feedVideoQueue = feedQueue;
        _personalizedOpportunities = opportunities;
        _personalizedCollaborators = collaborators;
        _skillPatterns = skillPatterns;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'Recommendation Web Lab',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                    children: [
                      _heroCard(textPrimary, textSecondary),
                      const SizedBox(height: 12),
                      _controlsCard(textPrimary, textSecondary),
                      const SizedBox(height: 12),
                      _skillPatternPanel(textPrimary, textSecondary),
                      const SizedBox(height: 12),
                      _kMeansPanel(textPrimary, textSecondary),
                      const SizedBox(height: 12),
                      _localMathPanel(textPrimary, textSecondary),
                      const SizedBox(height: 12),
                      _aiPanel(textPrimary, textSecondary),
                      const SizedBox(height: 12),
                      _resultsPanel(textPrimary, textSecondary),
                      const SizedBox(height: 12),
                      _masterComparisonPanel(textPrimary, textSecondary),
                    ],
                  ),
                ),
    );
  }

  Widget _heroCard(Color textPrimary, Color textSecondary) {
    final selectedStudent = _students.firstWhere(
      (u) => u.id == _selectedStudentId,
      orElse: () => _students.first,
    );

    final impact = _globalImpactByStudentId[selectedStudent.id] ?? 0;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF113A9E), Color(0xFF1963D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Independent Firestore-Based Module',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sampled ${_students.length} students directly from Firestore.\n'
            'Visualizing Feed, Personalized, and General recommendation pipelines with full math trace.',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricPill(label: 'Selected Student Impact', value: '${impact.toStringAsFixed(1)}%'),
              _MetricPill(label: 'Posts Pool', value: '${_posts.length}'),
              _MetricPill(label: 'AI Available', value: _aiConfigured ? 'Yes' : 'No'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlsCard(Color textPrimary, Color textSecondary) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Category + Student Controls',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _categoryChip(_LabCategory.feed, 'Feed'),
              _categoryChip(_LabCategory.personalized, 'Personalized'),
              _categoryChip(_LabCategory.global, 'Global'),
            ],
          ),
          if (_category == _LabCategory.personalized) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _personalizedTabChip(_PersonalizedTab.opportunities, 'Opportunities'),
                _personalizedTabChip(_PersonalizedTab.collaborators, 'Collaborators'),
              ],
            ),
          ],
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedStudentId,
            decoration: InputDecoration(
              labelText: 'Student sample (max 20)',
              labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
            ),
            items: _students
                .map(
                  (u) => DropdownMenuItem(
                    value: u.id,
                    child: Text(
                      _displayName(u),
                      style: GoogleFonts.plusJakartaSans(fontSize: 12),
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged:
                _category == _LabCategory.global ? null : _onStudentChanged,
          ),
        ],
      ),
    );
  }

  Widget _personalizedTabChip(_PersonalizedTab value, String label) {
    final selected = _personalizedTab == value;
    return ChoiceChip(
      selected: selected,
      label: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: selected ? Colors.white : null,
        ),
      ),
      onSelected: (bool sel) {
        if (sel) {
          setState(() => _personalizedTab = value);
        }
      },
      selectedColor: AppColors.info,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _kMeansPanel(Color textPrimary, Color textSecondary) {
    final trace = _kMeansTrace;
    if (trace == null) {
      return const SizedBox.shrink();
    }

    final finalCounts = <int, int>{0: 0, 1: 0, 2: 0};
    for (final cluster in trace.finalAssignments.values) {
      finalCounts[cluster] = (finalCounts[cluster] ?? 0) + 1;
    }

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 1: K-Means (Cluster Visualization Layer)',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This module computes K-means over normalized student vectors: '
            '[skills_density, activity_density, profile_completeness]. '
            'The production recommender uses cluster tags in content metadata; '
            'this layer visualizes how cohort grouping behaves.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.45,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          ...trace.iterations.map((it) {
            final counts = <int, int>{0: 0, 1: 0, 2: 0};
            for (final cluster in it.assignments.values) {
              counts[cluster] = (counts[cluster] ?? 0) + 1;
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Iteration ${it.iteration}',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      'C0:${counts[0]}  C1:${counts[1]}  C2:${counts[2]}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          Text(
            'Final mapping (Student -> Cluster):',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _students.map((u) {
              final cluster = trace.finalAssignments[u.id] ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_displayName(u)} -> C$cluster',
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
              final isCompact = constraints.maxWidth < 600;
              final histogram = JsVisualizationPanel(
                chartId:
                    'kmeans-${_selectedStudentId ?? 'none'}-${_students.length}',
                title: 'Cluster distribution (histogram)',
                labels: const ['Cluster 0', 'Cluster 1', 'Cluster 2'],
                values: [
                  (finalCounts[0] ?? 0).toDouble(),
                  (finalCounts[1] ?? 0).toDouble(),
                  (finalCounts[2] ?? 0).toDouble(),
                ],
                color: AppColors.primary,
                height: 240,
              );
              final centroids = trace.iterations.isNotEmpty
                  ? trace.iterations.last.centroids
                  : const <_FeatureVector>[];
              final scatter = _LabClusterScatterPlot(
                points: trace.points,
                assignments: trace.finalAssignments,
                centroids: centroids,
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

  Widget _skillPatternPanel(Color textPrimary, Color textSecondary) {
    final clusters = _skillPatterns.clusters;
    final correlations = _skillPatterns.correlations.toList(growable: false)
      ..sort((a, b) => b.weight.compareTo(a.weight));

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 0: AI Skill Pattern Layer (Backend Trace)',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The backend groups semantically similar skills into reusable clusters. '
            'These clusters then feed both the feed ranking and personalized reranking.',
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
              _MetricPill(label: 'Source', value: _skillPatterns.source),
              _MetricPill(label: 'Clusters', value: '${clusters.length}'),
              _MetricPill(
                label: 'Skills Processed',
                value: '${_skillPatterns.normalizedSkills.length}',
              ),
              _MetricPill(
                label: 'Correlations',
                value: '${correlations.length}',
              ),
            ],
          ),
          if (clusters.isNotEmpty) ...[
            const SizedBox(height: 10),
            JsVisualizationPanel(
              chartId: 'skill-pattern-${_selectedStudentId ?? 'none'}-${clusters.length}',
              title: 'Cluster Size Distribution (Backend Skill Patterns)',
              labels: clusters.map((cluster) => cluster.label).toList(growable: false),
              values: clusters
                  .map((cluster) => cluster.skills.length.toDouble())
                  .toList(growable: false),
              color: const Color(0xFF0E7C86),
              height: 250,
            ),
            const SizedBox(height: 10),
            ...clusters.take(6).map((cluster) {
              final preview = cluster.skills.take(8).join(', ');
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF0E7C86).withValues(alpha: 0.06),
                  border: Border.all(
                    color: const Color(0xFF0E7C86).withValues(alpha: 0.22),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${cluster.label} (${cluster.id})',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'No clusters were produced for this student context.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: textSecondary,
              ),
            ),
          ],
          if (correlations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Top correlation edges',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            ...correlations.take(4).map((corr) {
              return Text(
                '${corr.fromClusterId} -> ${corr.toClusterId}  (${corr.weight.toStringAsFixed(2)})  ${corr.reason ?? ''}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: textSecondary,
                ),
              );
            }),
          ],
          const SizedBox(height: 10),
          Text(
            'Raw backend response snapshot',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              const JsonEncoder.withIndent('  ').convert(
                _skillPatterns.rawPayload.isEmpty
                    ? <String, dynamic>{
                        'source': _skillPatterns.source,
                        'clusters': clusters.map((c) => c.toMap()).toList(),
                        'correlations': correlations.map((c) => c.toMap()).toList(),
                      }
                    : _skillPatterns.rawPayload,
              ),
              style: GoogleFonts.robotoMono(
                fontSize: 10,
                color: const Color(0xFFB8FFC9),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _localMathPanel(Color textPrimary, Color textSecondary) {
    if (_category == _LabCategory.global) {
       return const SizedBox.shrink(); 
    }

    List<dynamic> items = [];
    String title = '';
    Map<String, double> weights = {};

    if (_category == _LabCategory.feed) {
      items = _feedVideoQueue.take(10).toList(growable: false);
      title = 'Feed Local Calculation';
      weights = {
        'skill_signal': 0.28,
        'faculty_signal': 0.15,
        'program_signal': 0.10,
        'category_signal': 0.20,
        'search_signal': 0.17,
        'engagement_signal': 0.05,
        'freshness_signal': 0.05,
      };
    } else if (_personalizedTab == _PersonalizedTab.opportunities) {
      items = _personalizedOpportunities.take(10).toList(growable: false);
      title = 'Opportunities Local Math';
      weights = {
        'content_similarity': 0.30,
        'behavioral_relevance': 0.18,
        'cluster_affinity': 0.08,
        'quality_score': 0.18,
        'freshness': 0.13,
        'diversity': 0.07,
        'trust_adjusted': 0.06,
      };
    } else {
      items = _personalizedCollaborators.take(10).toList(growable: false);
      title = 'Collaborator Matching Math';
      weights = {
        'content_similarity': 0.34,
        'behavioral_relevance': 0.20,
        'quality_score': 0.18,
        'freshness': 0.10,
        'diversity': 0.10,
        'trust_adjusted': 0.08,
      };
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 2: $title (Calculation Trace)',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: weights.entries.map((e) => _MetricPill(label: e.key, value: e.value.toStringAsFixed(2))).toList(growable: false),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Item')),
                ...weights.keys.take(5).map((k) => DataColumn(label: Text(k.split('_').first))),
                const DataColumn(label: Text('Final')),
              ],
              rows: items.take(8).map((item) {
                Map<String, double> b;
                String name;
                double finalScore;

                if (item is FeedVideoQueueItem) {
                  b = item.signalBreakdown;
                  name = item.post.title;
                  finalScore = item.eligibilityScore;
                } else if (item is RecommendedPost) {
                  b = item.scoreBreakdown;
                  name = item.post.title;
                  finalScore = item.score;
                } else if (item is RecommendedUser) {
                  b = item.scoreBreakdown;
                  name = _displayName(item.user);
                  finalScore = item.score;
                } else {
                  return const DataRow(cells: []);
                }

                return DataRow(
                  cells: [
                    DataCell(SizedBox(
                      width: 150,
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(fontSize: 11)),
                    )),
                    ...weights.keys.take(5).map((k) => DataCell(Text(_d(b[k])))),
                    DataCell(Text(_d(finalScore), style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700))),
                  ],
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiPanel(Color textPrimary, Color textSecondary) {
    if (_category != _LabCategory.personalized || _personalizedTab != _PersonalizedTab.opportunities) {
      return const SizedBox.shrink();
    }

    final aiRows = _personalizedOpportunities.where((r) => r.scoreBreakdown.containsKey('openai_score')).take(8).toList(growable: false);

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 3: AI Stage (OpenAI Rerank)', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
          const SizedBox(height: 8),
          if (!_aiConfigured)
            Text('OpenAI is not configured. Local ranking is active.', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.warningText))
          else if (aiRows.isEmpty)
            Text('No OpenAI rerank rows were produced.', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textSecondary))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Post')),
                  DataColumn(label: Text('Local')),
                  DataColumn(label: Text('OpenAI')),
                  DataColumn(label: Text('Blended')),
                ],
                rows: aiRows.map((item) {
                  final b = item.scoreBreakdown;
                  return DataRow(cells: [
                    DataCell(SizedBox(width: 180, child: Text(item.post.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(fontSize: 11)))),
                    DataCell(Text(_d(b['local_score'] ?? item.score))),
                    DataCell(Text(_d(b['openai_score']))),
                    DataCell(Text(_d(item.score))),
                  ]);
                }).toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultsPanel(Color textPrimary, Color textSecondary) {
    return const SizedBox.shrink(); // Using Master Comparison Panel
  }

  Widget _masterComparisonPanel(Color textPrimary, Color textSecondary) {
    switch (_category) {
      case _LabCategory.feed:
        return _buildFeedComparisonTable(textPrimary, textSecondary);
      case _LabCategory.personalized:
        if (_personalizedTab == _PersonalizedTab.opportunities) {
          return _buildOpportunitiesComparisonTable(textPrimary, textSecondary);
        } else {
          return _buildCollaboratorsComparisonTable(textPrimary, textSecondary);
        }
      case _LabCategory.global:
        return _buildGlobalComparisonTable(textPrimary, textSecondary);
    }
  }

  Widget _buildFeedComparisonTable(Color textPrimary, Color textSecondary) {
    if (_posts.isEmpty) return const SizedBox.shrink();
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Feed Tabulation (Before & After)', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
          const SizedBox(height: 16),
          _buildTableWrapper(
            headers: const ['DB Rank', 'Video Title', 'Feed Rank', 'Eligibility'],
            itemCount: _posts.length,
            builder: (context, index) {
              final post = _posts[index];
              final originalRank = index + 1;
              final qIndex = _feedVideoQueue.indexWhere((r) => r.post.id == post.id);
              return Row(
                children: [
                  SizedBox(width: 60, child: Text(originalRank.toString(), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textSecondary))),
                  Expanded(flex: 3, child: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textPrimary))),
                  Expanded(child: _rankBadge(qIndex >= 0 ? (qIndex + 1).toString() : '-', originalRank, qIndex >= 0 ? qIndex + 1 : null)),
                  Expanded(child: Text(qIndex >= 0 ? _d(_feedVideoQueue[qIndex].eligibilityScore) : '-', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(fontSize: 12))),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOpportunitiesComparisonTable(Color textPrimary, Color textSecondary) {
    final opportunities = _posts.where((p) => p.type == 'opportunity').toList(growable: false);
    if (opportunities.isEmpty) return const SizedBox.shrink();
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Personalized Opportunities Tabulation', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
          const SizedBox(height: 16),
          _buildTableWrapper(
            headers: const ['DB Rank', 'Opportunity Title', 'Personalized Rank', 'Score'],
            itemCount: opportunities.length,
            builder: (context, index) {
              final post = opportunities[index];
              final originalRank = index + 1;
              final qIndex = _personalizedOpportunities.indexWhere((r) => r.post.id == post.id);
              return Row(
                children: [
                  SizedBox(width: 60, child: Text(originalRank.toString(), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textSecondary))),
                  Expanded(flex: 3, child: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textPrimary))),
                  Expanded(child: _rankBadge(qIndex >= 0 ? (qIndex + 1).toString() : '-', originalRank, qIndex >= 0 ? qIndex + 1 : null)),
                  Expanded(child: Text(qIndex >= 0 ? _d(_personalizedOpportunities[qIndex].score) : '-', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(fontSize: 12))),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCollaboratorsComparisonTable(Color textPrimary, Color textSecondary) {
    if (_students.isEmpty) return const SizedBox.shrink();
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Personalized Collaborators Tabulation', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
          const SizedBox(height: 16),
          _buildTableWrapper(
            headers: const ['DB Rank', 'Collaborator Name', 'Recommended Rank', 'Score'],
            itemCount: _students.length,
            builder: (context, index) {
              final student = _students[index];
              final originalRank = index + 1;
              final qIndex = _personalizedCollaborators.indexWhere((r) => r.user.id == student.id);
              return Row(
                children: [
                  SizedBox(width: 60, child: Text(originalRank.toString(), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textSecondary))),
                  Expanded(flex: 3, child: Text(_displayName(student), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textPrimary))),
                  Expanded(child: _rankBadge(qIndex >= 0 ? (qIndex + 1).toString() : '-', originalRank, qIndex >= 0 ? qIndex + 1 : null)),
                  Expanded(child: Text(qIndex >= 0 ? _d(_personalizedCollaborators[qIndex].score) : '-', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(fontSize: 12))),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalComparisonTable(Color textPrimary, Color textSecondary) {
    if (_students.isEmpty) return const SizedBox.shrink();
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Global Students Tabulation', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
          const SizedBox(height: 16),
          _buildTableWrapper(
            headers: const ['DB Rank', 'Student Name', 'Global Rank', 'Global Score'],
            itemCount: _students.length,
            builder: (context, index) {
              final student = _students[index];
              final originalRank = index + 1;
              final qIndex = _globalStudentRanks.indexWhere((r) => r.user.id == student.id);
              return Row(
                children: [
                  SizedBox(width: 60, child: Text(originalRank.toString(), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textSecondary))),
                  Expanded(flex: 3, child: Text(_displayName(student), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textPrimary))),
                  Expanded(child: _rankBadge(qIndex >= 0 ? (qIndex + 1).toString() : '-', originalRank, qIndex >= 0 ? qIndex + 1 : null)),
                  Expanded(child: Text(qIndex >= 0 ? _d(_globalStudentRanks[qIndex].globalScore) : '-', textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(fontSize: 12))),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTableWrapper({
    required List<String> headers,
    required int itemCount,
    required Widget Function(BuildContext, int) builder,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 430,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppColors.surfaceDark, const Color(0xFF121B2F)]
              : const [Color(0xFFFFFFFF), Color(0xFFF7FAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFFD9E4FB),
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D1B8F).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        headers[0],
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800, fontSize: 11),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        headers[1],
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800, fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        headers[2],
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800, fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        headers[3],
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Smart view: before/after rank movement with compact score trace',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: itemCount == 0
                ? Center(
                    child: Text(
                      'No rows available for this view.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: itemCount,
                    separatorBuilder: (context, index) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final stripe = index.isEven
                          ? AppColors.primary.withValues(alpha: 0.035)
                          : Colors.transparent;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: stripe,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: stripe == Colors.transparent
                                ? Colors.transparent
                                : AppColors.primary.withValues(alpha: 0.12),
                          ),
                        ),
                        child: builder(context, index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _rankBadge(String rankText, int originalRank, int? currentRank) {
    if (currentRank == null) return Text(rankText, textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(fontSize: 12));
    final diff = originalRank - currentRank;
    final icon = diff > 0 ? Icons.arrow_upward_rounded : diff < 0 ? Icons.arrow_downward_rounded : Icons.remove_rounded;
    final color = diff > 0 ? AppColors.success : diff < 0 ? AppColors.danger : Colors.grey;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(rankText, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Icon(icon, size: 12, color: color),
      ],
    );
  }

  Widget _categoryChip(_LabCategory value, String label) {
    final selected = _category == value;
    return ChoiceChip(
      selected: selected,
      label: Text(label, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 12, color: selected ? Colors.white : null)),
      onSelected: (_) => setState(() => _category = value),
      selectedColor: AppColors.primary,
    );
  }

  Widget _panel({required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppColors.surfaceDark, const Color(0xFF121B2F)]
              : const [Color(0xFFFFFFFF), Color(0xFFF8FBFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFFD9E4FB),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D1B8F).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  String _displayName(UserModel user) {
    final name = (user.displayName ?? '').trim();
    if (name.isNotEmpty) return name;
    return user.email;
  }

  String _d(double? value) => (value ?? 0).toStringAsFixed(3);
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
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
          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.white),
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

// ── K-means scatter plot ───────────────────────────────────────────────────

class _LabClusterScatterPlot extends StatelessWidget {
  const _LabClusterScatterPlot({
    required this.points,
    required this.assignments,
    required this.centroids,
  });

  final List<_StudentPoint> points;
  final Map<String, int> assignments;
  final List<_FeatureVector> centroids;

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
          Row(
            children: [
              Text(
                'Cluster spread (skills vs activity)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryLight,
                ),
              ),
              const Spacer(),
              _legendDot(const Color(0xFF1F6FEB), 'C0'),
              const SizedBox(width: 8),
              _legendDot(const Color(0xFF0F9D58), 'C1'),
              const SizedBox(width: 8),
              _legendDot(const Color(0xFFE67E22), 'C2'),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: CustomPaint(
              painter: _LabClusterScatterPainter(
                points: points,
                assignments: assignments,
                centroids: centroids,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }
}

class _LabClusterScatterPainter extends CustomPainter {
  const _LabClusterScatterPainter({
    required this.points,
    required this.assignments,
    required this.centroids,
  });

  final List<_StudentPoint> points;
  final Map<String, int> assignments;
  final List<_FeatureVector> centroids;

  static const _clusterColors = <Color>[
    Color(0xFF1F6FEB),
    Color(0xFF0F9D58),
    Color(0xFFE67E22),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTWH(30, 8, size.width - 42, size.height - 30);

    // Axes
    final axisPaint = Paint()
      ..color = const Color(0xFF9AA4B2)
      ..strokeWidth = 1;
    canvas.drawLine(chart.bottomLeft, chart.bottomRight, axisPaint);
    canvas.drawLine(chart.bottomLeft, chart.topLeft, axisPaint);

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0x1A0F172A)
      ..strokeWidth = 1;
    for (var i = 1; i <= 4; i++) {
      final y = chart.bottom - chart.height * (i / 5);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    // Data points
    for (final point in points) {
      final cluster = assignments[point.user.id] ?? 0;
      final color =
          _clusterColors[cluster.clamp(0, _clusterColors.length - 1)];
      final x =
          chart.left + point.vector.skillsDensity.clamp(0.0, 1.0) * chart.width;
      final y = chart.bottom -
          point.vector.activityDensity.clamp(0.0, 1.0) * chart.height;

      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = color);
      canvas.drawCircle(
        Offset(x, y),
        5.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.35),
      );
    }

    // Centroid markers (×)
    for (var i = 0; i < centroids.length; i++) {
      final c = centroids[i];
      final color = _clusterColors[i.clamp(0, _clusterColors.length - 1)];
      final cx = chart.left + c.skillsDensity.clamp(0.0, 1.0) * chart.width;
      final cy =
          chart.bottom - c.activityDensity.clamp(0.0, 1.0) * chart.height;

      final crossPaint = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      const r = 6.0;
      canvas.drawLine(
          Offset(cx - r, cy - r), Offset(cx + r, cy + r), crossPaint);
      canvas.drawLine(
          Offset(cx + r, cy - r), Offset(cx - r, cy + r), crossPaint);
      canvas.drawCircle(
        Offset(cx, cy),
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.55),
      );
    }

    // Axis labels
    final labelStyle = GoogleFonts.plusJakartaSans(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF5B6676),
    );
    final xPainter = TextPainter(
      text: TextSpan(text: 'Skills density →', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    xPainter.paint(
        canvas, Offset(chart.right - xPainter.width, chart.bottom + 6));

    final yPainter = TextPainter(
      text: TextSpan(text: 'Activity ↑', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    yPainter.paint(canvas, Offset(2, chart.top));
  }

  @override
  bool shouldRepaint(covariant _LabClusterScatterPainter old) =>
      old.points != points ||
      old.assignments != assignments ||
      old.centroids != centroids;
}
