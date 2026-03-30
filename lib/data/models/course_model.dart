// lib/data/models/course_model.dart
//
// MUST StarTrack — Course Model
//
// Represents an academic course within a faculty.
// Many courses can belong to one faculty.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class CourseModel {
  final String id;
  final String facultyId;
  final String name;
  final String code;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int syncStatus; // 0=pending, 1=synced, 2=failed

  CourseModel({
    required this.id,
    required this.facultyId,
    required this.name,
    required this.code,
    this.description,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 0,
  });

  /// Generate a new course with a unique ID.
  factory CourseModel.create({
    required String facultyId,
    required String name,
    required String code,
    String? description,
  }) {
    final now = DateTime.now();
    return CourseModel(
      id: const Uuid().v4(),
      facultyId: facultyId,
      name: name,
      code: code,
      description: description,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      syncStatus: 0,
    );
  }

  /// Create a copy with modified fields.
  CourseModel copyWith({
    String? facultyId,
    String? name,
    String? code,
    String? description,
    bool? isActive,
    int? syncStatus,
  }) {
    return CourseModel(
      id: id,
      facultyId: facultyId ?? this.facultyId,
      name: name ?? this.name,
      code: code ?? this.code,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  /// Convert to JSON for database storage.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'faculty_id': facultyId,
      'name': name,
      'code': code,
      'description': description,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  /// Create from database JSON.
  factory CourseModel.fromMap(Map<String, dynamic> map) {
    return CourseModel(
      id: map['id'] as String,
      facultyId: map['faculty_id'] as String,
      name: map['name'] as String,
      code: map['code'] as String,
      description: map['description'] as String?,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncStatus: map['sync_status'] as int? ?? 0,
    );
  }

  /// Convert to Firestore document.
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'facultyId': facultyId,
      'name': name,
      'code': code,
      'description': description,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Create from Firestore document.
  factory CourseModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CourseModel(
      id: data['id'] as String,
      facultyId: data['facultyId'] as String,
      name: data['name'] as String,
      code: data['code'] as String,
      description: data['description'] as String?,
      isActive: data['isActive'] as bool? ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      syncStatus: 1, // Firestore documents are already synced
    );
  }

  @override
  String toString() {
    return 'CourseModel(id: $id, facultyId: $facultyId, name: $name, code: $code, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CourseModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          facultyId == other.facultyId &&
          code == other.code &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      id.hashCode ^ facultyId.hashCode ^ code.hashCode ^ isActive.hashCode;
}
