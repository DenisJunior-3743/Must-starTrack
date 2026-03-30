// lib/features/admin/bloc/faculty_management_cubit.dart
//
// MUST StarTrack — Faculty Management Cubit
//
// Manages faculty CRUD operations for the admin dashboard.
// State management for faculty list, create, update, delete, and archive operations.

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/faculty_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/models/faculty_model.dart';
import '../../../data/remote/sync_service.dart';

// ── States ─────────────────────────────────────────────────────────────────

abstract class FacultyManagementState extends Equatable {
  const FacultyManagementState();

  @override
  List<Object?> get props => [];
}

class FacultyManagementInitial extends FacultyManagementState {
  const FacultyManagementInitial();
}

class FacultyManagementLoading extends FacultyManagementState {
  const FacultyManagementLoading();
}

class FacultiesLoaded extends FacultyManagementState {
  final List<FacultyModel> faculties;
  final int totalCount;

  const FacultiesLoaded({
    required this.faculties,
    required this.totalCount,
  });

  @override
  List<Object?> get props => [faculties, totalCount];
}

class FacultyCreated extends FacultyManagementState {
  final FacultyModel faculty;

  const FacultyCreated(this.faculty);

  @override
  List<Object?> get props => [faculty];
}

class FacultyUpdated extends FacultyManagementState {
  final FacultyModel faculty;

  const FacultyUpdated(this.faculty);

  @override
  List<Object?> get props => [faculty];
}

class FacultyArchived extends FacultyManagementState {
  final String facultyId;

  const FacultyArchived(this.facultyId);

  @override
  List<Object?> get props => [facultyId];
}

class FacultyManagementError extends FacultyManagementState {
  final String message;

  const FacultyManagementError(this.message);

  @override
  List<Object?> get props => [message];
}

// ── Cubit ──────────────────────────────────────────────────────────────────

class FacultyManagementCubit extends Cubit<FacultyManagementState> {
  final FacultyDao _facultyDao;
  final SyncQueueDao _syncQueueDao;
  final SyncService _syncService;

  FacultyManagementCubit({
    FacultyDao? facultyDao,
    SyncQueueDao? syncQueueDao,
    SyncService? syncService,
  })  : _facultyDao = facultyDao ?? sl<FacultyDao>(),
        _syncQueueDao = syncQueueDao ?? sl<SyncQueueDao>(),
        _syncService = syncService ?? sl<SyncService>(),
        super(const FacultyManagementInitial());

  /// Load all faculties from database.
  Future<void> loadFaculties({bool activeOnly = true}) async {
    emit(const FacultyManagementLoading());
    try {
      final faculties = await _facultyDao.getAllFaculties(activeOnly: activeOnly);
      final totalCount = await _facultyDao.getFacultyCount();
      emit(FacultiesLoaded(faculties: faculties, totalCount: totalCount));
    } catch (e) {
      emit(FacultyManagementError('Failed to load faculties: $e'));
    }
  }

  /// Create a new faculty.
  Future<void> createFaculty({
    required String name,
    required String code,
    String? description,
    String? contactEmail,
    String? headOfFaculty,
  }) async {
    try {
      final faculty = FacultyModel.create(
        name: name,
        code: code,
        description: description,
        contactEmail: contactEmail,
        headOfFaculty: headOfFaculty,
      );

      // Insert into local database
      await _facultyDao.createFaculty(faculty);

      // Enqueue for sync
      await _syncQueueDao.enqueue(
        operation: 'create',
        entity: 'faculties',
        entityId: faculty.id,
        payload: faculty.toFirestore(),
      );

      // Process sync in background
      unawaited(_syncService.processPendingSync());

      emit(FacultyCreated(faculty));
      // Reload the list
      await loadFaculties();
    } catch (e) {
      emit(FacultyManagementError('Failed to create faculty: $e'));
    }
  }

  /// Update an existing faculty.
  Future<void> updateFaculty({
    required String id,
    required String name,
    required String code,
    String? description,
    String? contactEmail,
    String? headOfFaculty,
  }) async {
    try {
      final existing = await _facultyDao.getFacultyById(id);
      if (existing == null) {
        emit(const FacultyManagementError('Faculty not found'));
        return;
      }

      final updated = existing.copyWith(
        name: name,
        code: code,
        description: description,
        contactEmail: contactEmail,
        headOfFaculty: headOfFaculty,
      );

      // Update local database
      await _facultyDao.updateFaculty(updated);

      // Enqueue for sync
      await _syncQueueDao.enqueue(
        operation: 'update',
        entity: 'faculties',
        entityId: id,
        payload: updated.toFirestore(),
      );

      // Process sync in background
      unawaited(_syncService.processPendingSync());

      emit(FacultyUpdated(updated));
      // Reload the list
      await loadFaculties();
    } catch (e) {
      emit(FacultyManagementError('Failed to update faculty: $e'));
    }
  }

  /// Archive (soft-delete) a faculty.
  Future<void> archiveFaculty(String id) async {
    try {
      final faculty = await _facultyDao.getFacultyById(id);
      if (faculty == null) {
        emit(const FacultyManagementError('Faculty not found'));
        return;
      }

      // Archive locally
      await _facultyDao.archiveFaculty(id);

      // Enqueue for sync with is_active: false
      final archivedFaculty = faculty.copyWith(isActive: false);
      await _syncQueueDao.enqueue(
        operation: 'update',
        entity: 'faculties',
        entityId: id,
        payload: archivedFaculty.toFirestore(),
      );

      // Process sync in background
      unawaited(_syncService.processPendingSync());

      emit(FacultyArchived(id));
      // Reload the list
      await loadFaculties();
    } catch (e) {
      emit(FacultyManagementError('Failed to archive faculty: $e'));
    }
  }
}

/// Helper to handle unawaited future.
void unawaited(Future<void> future) {}
