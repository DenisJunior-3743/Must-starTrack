// lib/data/models/faculty_model.dart
//
// MUST StarTrack — Faculty Model
//
// Represents an institutional faculty/school.
// Managed by admins; lecturers and students assigned to faculties.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class FacultyModel {
  final String id;
  final String name;
  final String code;
  final String? description;
  final String? contactEmail;
  final String? headOfFaculty;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int syncStatus; // 0=pending, 1=synced, 2=failed

  FacultyModel({
    required this.id,
    required this.name,
    required this.code,
    this.description,
    this.contactEmail,
    this.headOfFaculty,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 0,
  });

  /// Generate a new faculty with a unique ID.
  factory FacultyModel.create({
    required String name,
    required String code,
    String? description,
    String? contactEmail,
    String? headOfFaculty,
  }) {
    final now = DateTime.now();
    return FacultyModel(
      id: const Uuid().v4(),
      name: name,
      code: code,
      description: description,
      contactEmail: contactEmail,
      headOfFaculty: headOfFaculty,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      syncStatus: 0,
    );
  }

  /// Create a copy with modified fields.
  FacultyModel copyWith({
    String? name,
    String? code,
    String? description,
    String? contactEmail,
    String? headOfFaculty,
    bool? isActive,
    int? syncStatus,
  }) {
    return FacultyModel(
      id: id,
      name: name ?? this.name,
      code: code ?? this.code,
      description: description ?? this.description,
      contactEmail: contactEmail ?? this.contactEmail,
      headOfFaculty: headOfFaculty ?? this.headOfFaculty,
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
      'name': name,
      'code': code,
      'description': description,
      'contact_email': contactEmail,
      'head_of_faculty': headOfFaculty,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  /// Create from database JSON.
  factory FacultyModel.fromMap(Map<String, dynamic> map) {
    return FacultyModel(
      id: map['id'] as String,
      name: map['name'] as String,
      code: map['code'] as String,
      description: map['description'] as String?,
      contactEmail: map['contact_email'] as String?,
      headOfFaculty: map['head_of_faculty'] as String?,
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
      'name': name,
      'code': code,
      'description': description,
      'contactEmail': contactEmail,
      'headOfFaculty': headOfFaculty,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Create from Firestore document.
  factory FacultyModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FacultyModel(
      id: data['id'] as String,
      name: data['name'] as String,
      code: data['code'] as String,
      description: data['description'] as String?,
      contactEmail: data['contactEmail'] as String?,
      headOfFaculty: data['headOfFaculty'] as String?,
      isActive: data['isActive'] as bool? ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      syncStatus: 1, // Firestore documents are already synced
    );
  }

  @override
  String toString() {
    return 'FacultyModel(id: $id, name: $name, code: $code, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FacultyModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          code == other.code &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      id.hashCode ^ name.hashCode ^ code.hashCode ^ isActive.hashCode;
}
