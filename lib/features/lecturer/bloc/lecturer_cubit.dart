// lib/features/lecturer/bloc/lecturer_cubit.dart
//
// MUST StarTrack — Lecturer Cubit
//
// State management for lecturer-specific features:
//   - Dashboard stats (own opportunity count, total applicants)
//   - Viewing applicants per opportunity
//   - Searching students (delegates to UserDao.searchUsers)
//   - Rating / ranking students

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/post_join_dao.dart';
import '../../../data/local/dao/recommendation_log_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/recommender_service.dart';

// ── States ────────────────────────────────────────────────────────────────────

abstract class LecturerState extends Equatable {
  const LecturerState();
  @override
  List<Object?> get props => [];
}

class LecturerInitial extends LecturerState {
  const LecturerInitial();
}

class LecturerLoading extends LecturerState {
  const LecturerLoading();
}

class LecturerDashboardLoaded extends LecturerState {
  final List<PostModel> opportunities;
  final int totalApplicants;
  final int activeOpportunities;
  final int expiredOpportunities;

  const LecturerDashboardLoaded({
    required this.opportunities,
    required this.totalApplicants,
    required this.activeOpportunities,
    required this.expiredOpportunities,
  });

  @override
  List<Object?> get props => [
        opportunities,
        totalApplicants,
        activeOpportunities,
        expiredOpportunities,
      ];
}

class ApplicantsLoaded extends LecturerState {
  final PostModel opportunity;
  final List<UserModel> applicants;
  final Map<String, RecommendedUser> recommendations;

  const ApplicantsLoaded({
    required this.opportunity,
    required this.applicants,
    this.recommendations = const {},
  });

  @override
  List<Object?> get props => [opportunity, applicants, recommendations];
}

class StudentSearchLoaded extends LecturerState {
  final List<UserModel> results;
  final String query;
  final String? facultyFilter;
  final String? courseFilter;
  final String? skillFilter;

  const StudentSearchLoaded({
    required this.results,
    required this.query,
    this.facultyFilter,
    this.courseFilter,
    this.skillFilter,
  });

  @override
  List<Object?> get props => [
        results,
        query,
        facultyFilter,
        courseFilter,
        skillFilter,
      ];
}

class StudentRankingLoaded extends LecturerState {
  final List<UserModel> students;
  final String sortBy; // 'fit' | 'streak' | 'posts' | 'collabs' | 'followers'
  final Map<String, double> aiScores;

  const StudentRankingLoaded({
    required this.students,
    this.sortBy = 'fit',
    this.aiScores = const {},
  });

  @override
  List<Object?> get props => [students, sortBy, aiScores];
}

class LecturerError extends LecturerState {
  final String message;
  const LecturerError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class LecturerCubit extends Cubit<LecturerState> {
  final PostDao _postDao;
  final PostJoinDao _postJoinDao;
  final UserDao _userDao;
  final RecommenderService _recommenderService;
  final RecommendationLogDao? _recLogDao;

  LecturerCubit({
    required PostDao postDao,
    required PostJoinDao postJoinDao,
    required UserDao userDao,
    required RecommenderService recommenderService,
    RecommendationLogDao? recLogDao,
  })  : _postDao = postDao,
        _postJoinDao = postJoinDao,
        _userDao = userDao,
        _recommenderService = recommenderService,
        _recLogDao = recLogDao,
        super(const LecturerInitial());

  // ── Dashboard ─────────────────────────────────────────────────────────────

  Future<void> loadDashboard(String lecturerId) async {
    emit(const LecturerLoading());
    try {
      // Fetch all posts by this lecturer
      final allPosts = await _postDao.getPostsByAuthor(
        lecturerId,
        pageSize: 200,
        includeArchived: true,
      );

      // Filter to opportunities only
      final opportunities =
          allPosts.where((p) => p.type == 'opportunity').toList();

      // Calculate stats
      int totalApplicants = 0;
      for (final opp in opportunities) {
        totalApplicants += opp.joinCount;
      }

      final now = DateTime.now();
      final active = opportunities.where((o) {
        if (o.isArchived) return false;
        if (o.opportunityDeadline == null) return true;
        return o.opportunityDeadline!.isAfter(now);
      }).length;

      final expired = opportunities.where((o) {
        if (o.isArchived) return false;
        if (o.opportunityDeadline == null) return false;
        return o.opportunityDeadline!.isBefore(now);
      }).length;

      emit(LecturerDashboardLoaded(
        opportunities: opportunities,
        totalApplicants: totalApplicants,
        activeOpportunities: active,
        expiredOpportunities: expired,
      ));
    } catch (e) {
      emit(LecturerError('Failed to load dashboard: $e'));
    }
  }

  // ── Applicants for a specific opportunity ─────────────────────────────────

  Future<void> loadApplicants(PostModel opportunity) async {
    emit(const LecturerLoading());
    try {
      final applicants =
          await _postJoinDao.getApplicantsForPost(opportunity.id);
      final ranked = _recommenderService.rankStudentsForOpportunity(
        opportunity: opportunity,
        candidates: applicants,
      );
      final recommendationMap = {
        for (final item in ranked) item.user.id: item,
      };

      // Log applicant ranking decisions (SQLite + Firestore fire-and-forget)
      if (_recLogDao != null && ranked.isNotEmpty) {
        final entries = ranked
            .map((r) => RecommendationLogEntry(
                  userId: opportunity.authorId,
                  itemId: r.user.id,
                  itemType: 'user',
                  algorithm: 'applicant',
                  score: r.score,
                  reasons: r.reasons,
                ))
            .toList();
        _recLogDao.insertBatch(entries).catchError(
          (e) => debugPrint('[LecturerCubit] rec log failed: $e'),
        );
      }

      emit(ApplicantsLoaded(
        opportunity: opportunity,
        applicants: ranked.map((item) => item.user).toList(),
        recommendations: recommendationMap,
      ));
    } catch (e) {
      emit(LecturerError('Failed to load applicants: $e'));
    }
  }

  // ── Student search ────────────────────────────────────────────────────────

  Future<void> searchStudents({
    required String query,
    String? faculty,
    String? course,
    String? skill,
  }) async {
    emit(const LecturerLoading());
    try {
      final results = await _userDao.searchUsers(
        query: query,
        faculty: faculty,
        course: course,
        skill: skill,
      );

      emit(StudentSearchLoaded(
        results: results,
        query: query,
        facultyFilter: faculty,
        courseFilter: course,
        skillFilter: skill,
      ));
    } catch (e) {
      emit(LecturerError('Search failed: $e'));
    }
  }

  // ── Student ranking ───────────────────────────────────────────────────────

  Future<void> loadRanking({String sortBy = 'fit'}) async {
    emit(const LecturerLoading());
    try {
      // Fetch all active students (broad search with empty query returns all)
      final students = await _userDao.searchUsers(
        query: '',
        pageSize: 100,
      );

      // Sort locally based on profile metrics
      final sorted = List<UserModel>.from(students);
      final aiScores = <String, double>{};
      if (sortBy == 'fit') {
        double scoreFor(UserModel user) {
          final profile = user.profile;
          if (profile == null) return 0;
          final completeness = [profile.bio, profile.faculty, profile.programName]
              .where((value) => value != null && value.trim().isNotEmpty)
                  .length /
              3.0;
          return (0.25 * ((profile.skills.length / 8).clamp(0.0, 1.0)) +
                  0.20 * ((profile.activityStreak / 14).clamp(0.0, 1.0)) +
                  0.20 * ((profile.totalPosts / 12).clamp(0.0, 1.0)) +
                  0.20 * ((profile.totalCollabs / 8).clamp(0.0, 1.0)) +
                  0.15 * completeness)
              .clamp(0.0, 1.0);
        }

        for (final student in sorted) {
          aiScores[student.id] = scoreFor(student);
        }
      }
      sorted.sort((a, b) {
        final ap = a.profile;
        final bp = b.profile;
        if (ap == null && bp == null) return 0;
        if (ap == null) return 1;
        if (bp == null) return -1;

        switch (sortBy) {
          case 'fit':
            return (aiScores[b.id] ?? 0).compareTo(aiScores[a.id] ?? 0);
          case 'posts':
            return bp.totalPosts.compareTo(ap.totalPosts);
          case 'collabs':
            return bp.totalCollabs.compareTo(ap.totalCollabs);
          case 'followers':
            return bp.totalFollowers.compareTo(ap.totalFollowers);
          case 'streak':
          default:
            return bp.activityStreak.compareTo(ap.activityStreak);
        }
      });

      emit(StudentRankingLoaded(
        students: sorted,
        sortBy: sortBy,
        aiScores: aiScores,
      ));
    } catch (e) {
      emit(LecturerError('Failed to load rankings: $e'));
    }
  }
}
