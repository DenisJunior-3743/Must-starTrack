// lib/features/admin/bloc/course_management_cubit.dart
//
// MUST StarTrack — Course Management Cubit
//
// Manages course CRUD operations for the admin dashboard.
// State management for course list, create, update, delete, and archive operations.

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/course_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/models/course_model.dart';
import '../../../data/remote/sync_service.dart';

// ── States ─────────────────────────────────────────────────────────────────

abstract class CourseManagementState extends Equatable {
  const CourseManagementState();

  @override
  List<Object?> get props => [];
}

class CourseManagementInitial extends CourseManagementState {
  const CourseManagementInitial();
}

class CourseManagementLoading extends CourseManagementState {
  const CourseManagementLoading();
}

class CoursesLoaded extends CourseManagementState {
  final List<CourseModel> courses;
  final int totalCount;
  final String? selectedFacultyId;

  const CoursesLoaded({
    required this.courses,
    required this.totalCount,
    this.selectedFacultyId,
  });

  @override
  List<Object?> get props => [courses, totalCount, selectedFacultyId];
}

class CourseCreated extends CourseManagementState {
  final CourseModel course;

  const CourseCreated(this.course);

  @override
  List<Object?> get props => [course];
}

class CourseUpdated extends CourseManagementState {
  final CourseModel course;

  const CourseUpdated(this.course);

  @override
  List<Object?> get props => [course];
}

class CourseArchived extends CourseManagementState {
  final String courseId;

  const CourseArchived(this.courseId);

  @override
  List<Object?> get props => [courseId];
}

class CourseManagementError extends CourseManagementState {
  final String message;

  const CourseManagementError(this.message);

  @override
  List<Object?> get props => [message];
}

// ── Cubit ──────────────────────────────────────────────────────────────────

class CourseManagementCubit extends Cubit<CourseManagementState> {
  final CourseDao _courseDao;
  final SyncQueueDao _syncQueueDao;
  final SyncService _syncService;

  CourseManagementCubit({
    CourseDao? courseDao,
    SyncQueueDao? syncQueueDao,
    SyncService? syncService,
  })  : _courseDao = courseDao ?? sl<CourseDao>(),
        _syncQueueDao = syncQueueDao ?? sl<SyncQueueDao>(),
        _syncService = syncService ?? sl<SyncService>(),
        super(const CourseManagementInitial());

  /// Load all courses or courses for a specific faculty.
  Future<void> loadCourses({
    String? facultyId,
    bool activeOnly = true,
  }) async {
    emit(const CourseManagementLoading());
    try {
        final courses = facultyId != null
          ? await _courseDao.getCoursesByFaculty(facultyId,
            activeOnly: activeOnly)
          : await _courseDao.getAllCourses(activeOnly: activeOnly);

      final totalCount = facultyId != null
          ? await _courseDao.getCourseCountByFaculty(facultyId,
              activeOnly: activeOnly)
          : await _courseDao.getTotalCourseCount(activeOnly: activeOnly);

      emit(CoursesLoaded(
        courses: courses,
        totalCount: totalCount,
        selectedFacultyId: facultyId,
      ));
    } catch (e) {
      emit(CourseManagementError('Failed to load courses: $e'));
    }
  }

  /// Create a new course.
  Future<void> createCourse({
    required String facultyId,
    required String name,
    required String code,
    String? description,
  }) async {
    try {
      final course = CourseModel.create(
        facultyId: facultyId,
        name: name,
        code: code,
        description: description,
      );

      // Insert into local database
      await _courseDao.createCourse(course);

      // Enqueue for sync
      await _syncQueueDao.enqueue(
        operation: 'create',
        entity: 'courses',
        entityId: course.id,
        payload: course.toFirestore(),
      );

      // Process sync in background
      unawaited(_syncService.processPendingSync());

      emit(CourseCreated(course));
      // Reload the list
      await loadCourses(facultyId: facultyId);
    } catch (e) {
      emit(CourseManagementError('Failed to create course: $e'));
    }
  }

  /// Update an existing course.
  Future<void> updateCourse({
    required String id,
    required String name,
    required String code,
    String? description,
  }) async {
    try {
      final existing = await _courseDao.getCourseById(id);
      if (existing == null) {
        emit(const CourseManagementError('Course not found'));
        return;
      }

      final updated = existing.copyWith(
        name: name,
        code: code,
        description: description,
      );

      // Update local database
      await _courseDao.updateCourse(updated);

      // Enqueue for sync
      await _syncQueueDao.enqueue(
        operation: 'update',
        entity: 'courses',
        entityId: id,
        payload: updated.toFirestore(),
      );

      // Process sync in background
      unawaited(_syncService.processPendingSync());

      emit(CourseUpdated(updated));
      // Reload the list
      await loadCourses(facultyId: existing.facultyId);
    } catch (e) {
      emit(CourseManagementError('Failed to update course: $e'));
    }
  }

  /// Archive (soft-delete) a course.
  Future<void> archiveCourse(String id) async {
    try {
      final course = await _courseDao.getCourseById(id);
      if (course == null) {
        emit(const CourseManagementError('Course not found'));
        return;
      }

      // Archive locally
      await _courseDao.archiveCourse(id);

      // Enqueue for sync with is_active: false
      final archivedCourse = course.copyWith(isActive: false);
      await _syncQueueDao.enqueue(
        operation: 'update',
        entity: 'courses',
        entityId: id,
        payload: archivedCourse.toFirestore(),
      );

      // Process sync in background
      unawaited(_syncService.processPendingSync());

      emit(CourseArchived(id));
      // Reload the list
      await loadCourses(facultyId: course.facultyId);
    } catch (e) {
      emit(CourseManagementError('Failed to archive course: $e'));
    }
  }
}

/// Helper to handle unawaited future.
void unawaited(Future<void> future) {}
