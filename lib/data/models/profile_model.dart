// lib/data/models/profile_model.dart
//
// MUST StarTrack — Profile Model (student digital portfolio)
//
// Maps to the 'profiles' SQLite table and /profiles/{userId} Firestore doc.
// skills and portfolioLinks are stored as JSON strings in SQLite
// and decoded/encoded here in the model layer.

import 'dart:convert';
import 'package:equatable/equatable.dart';

class ProfileModel extends Equatable {
  final String id;
  final String userId;
  final String? bio;
  final String? gender;
  final String? phone;
  final String? regNumber; // e.g. 2020/BSE/001/PS
  final String? admissionYear;
  final String? programName; // e.g. Bachelor of Software Engineering
  final String? courseName; // e.g. BSE
  final String? faculty; // e.g. Computing and Informatics
  final String? department; // for lecturers
  final int? yearOfStudy;
  final List<String> skills;
  final Map<String, String> portfolioLinks; // {github: url, linkedin: url, …}
  final String profileVisibility; // 'public' | 'followers' | 'private'
  final int activityStreak;
  final DateTime? lastActiveDate;
  final int totalPosts;
  final int totalFollowers;
  final int totalFollowing;
  final int totalCollabs;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProfileModel({
    required this.id,
    required this.userId,
    this.bio,
    this.gender,
    this.phone,
    this.regNumber,
    this.admissionYear,
    this.programName,
    this.courseName,
    this.faculty,
    this.department,
    this.yearOfStudy,
    this.skills = const [],
    this.portfolioLinks = const {},
    this.profileVisibility = 'public',
    this.activityStreak = 0,
    this.lastActiveDate,
    this.totalPosts = 0,
    this.totalFollowers = 0,
    this.totalFollowing = 0,
    this.totalCollabs = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── SQLite ────────────────────────────────────────────────────────────────

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      bio: map['bio'] as String?,
      gender: map['gender'] as String?,
      phone: map['phone'] as String?,
      regNumber: map['reg_number'] as String?,
      admissionYear: map['admission_year'] as String?,
      programName: map['program_name'] as String?,
      courseName: map['course_name'] as String?,
      faculty: map['faculty'] as String?,
      department: map['department'] as String?,
      yearOfStudy: map['year_of_study'] as int?,
      skills: _parseJsonList(map['skills'] as String?),
      portfolioLinks: _parseJsonMap(map['portfolio_links'] as String?),
      profileVisibility: map['profile_visibility'] as String? ?? 'public',
      activityStreak: map['activity_streak'] as int? ?? 0,
      lastActiveDate: map['last_active_date'] != null
          ? DateTime.tryParse(map['last_active_date'] as String)
          : null,
      totalPosts: map['total_posts'] as int? ?? 0,
      totalFollowers: map['total_followers'] as int? ?? 0,
      totalFollowing: map['total_following'] as int? ?? 0,
      totalCollabs: map['total_collabs'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'bio': bio,
        'gender': gender,
        'phone': phone,
        'reg_number': regNumber,
        'admission_year': admissionYear,
        'program_name': programName,
        'course_name': courseName,
        'faculty': faculty,
        'department': department,
        'year_of_study': yearOfStudy,
        'skills': jsonEncode(skills),
        'portfolio_links': jsonEncode(portfolioLinks),
        'profile_visibility': profileVisibility,
        'activity_streak': activityStreak,
        'last_active_date': lastActiveDate?.toIso8601String(),
        'total_posts': totalPosts,
        'total_followers': totalFollowers,
        'total_following': totalFollowing,
        'total_collabs': totalCollabs,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'sync_status': 0,
      };

  // ── Firestore ─────────────────────────────────────────────────────────────

  factory ProfileModel.fromJson(Map<String, dynamic> j) => ProfileModel(
        id: (j['id'] ?? '').toString(),
        userId: (j['userId'] ?? j['user_id'] ?? '').toString(),
        bio: (j['bio'] ?? j['bio_text']) as String?,
        gender: j['gender'] as String?,
        phone: j['phone'] as String?,
        regNumber: (j['regNumber'] ?? j['reg_number']) as String?,
        admissionYear: (j['admissionYear'] ?? j['admission_year']) as String?,
        programName: (j['programName'] ?? j['program_name']) as String?,
        courseName: (j['courseName'] ?? j['course_name']) as String?,
        faculty: j['faculty'] as String?,
        department: j['department'] as String?,
        yearOfStudy: _asInt(j['yearOfStudy'] ?? j['year_of_study']),
        skills: List<String>.from(j['skills'] as List? ?? []),
        portfolioLinks: Map<String, String>.from(
          (j['portfolioLinks'] ?? j['portfolio_links']) as Map? ?? {},
        ),
        profileVisibility:
            (j['profileVisibility'] ?? j['profile_visibility']) as String? ??
                'public',
        activityStreak:
            _asInt(j['activityStreak'] ?? j['activity_streak']) ?? 0,
        lastActiveDate: _tryParseDate(
          j['lastActiveDate'] ?? j['last_active_date'],
        ),
        totalPosts: _asInt(j['totalPosts'] ?? j['total_posts']) ?? 0,
        totalFollowers:
            _asInt(j['totalFollowers'] ?? j['total_followers']) ?? 0,
        totalFollowing:
            _asInt(j['totalFollowing'] ?? j['total_following']) ?? 0,
        totalCollabs: _asInt(j['totalCollabs'] ?? j['total_collabs']) ?? 0,
        createdAt:
            _tryParseDate(j['createdAt'] ?? j['created_at']) ?? DateTime.now(),
        updatedAt:
            _tryParseDate(j['updatedAt'] ?? j['updated_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'bio': bio,
        'gender': gender,
        'phone': phone,
        'regNumber': regNumber,
        'admissionYear': admissionYear,
        'programName': programName,
        'courseName': courseName,
        'faculty': faculty,
        'department': department,
        'yearOfStudy': yearOfStudy,
        'skills': skills,
        'portfolioLinks': portfolioLinks,
        'profileVisibility': profileVisibility,
        'activityStreak': activityStreak,
        'lastActiveDate': lastActiveDate?.toIso8601String(),
        'totalPosts': totalPosts,
        'totalFollowers': totalFollowers,
        'totalFollowing': totalFollowing,
        'totalCollabs': totalCollabs,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  // ── Helpers ───────────────────────────────────────────────────────────────

  static List<String> _parseJsonList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  static Map<String, String> _parseJsonMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  ProfileModel copyWith({
    String? id,
    String? userId,
    String? bio,
    String? gender,
    String? phone,
    String? regNumber,
    String? admissionYear,
    String? programName,
    String? courseName,
    String? faculty,
    String? department,
    int? yearOfStudy,
    List<String>? skills,
    Map<String, String>? portfolioLinks,
    String? profileVisibility,
    int? activityStreak,
    DateTime? lastActiveDate,
    int? totalPosts,
    int? totalFollowers,
    int? totalFollowing,
    int? totalCollabs,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ProfileModel(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        bio: bio ?? this.bio,
        gender: gender ?? this.gender,
        phone: phone ?? this.phone,
        regNumber: regNumber ?? this.regNumber,
        admissionYear: admissionYear ?? this.admissionYear,
        programName: programName ?? this.programName,
        courseName: courseName ?? this.courseName,
        faculty: faculty ?? this.faculty,
        department: department ?? this.department,
        yearOfStudy: yearOfStudy ?? this.yearOfStudy,
        skills: skills ?? this.skills,
        portfolioLinks: portfolioLinks ?? this.portfolioLinks,
        profileVisibility: profileVisibility ?? this.profileVisibility,
        activityStreak: activityStreak ?? this.activityStreak,
        lastActiveDate: lastActiveDate ?? this.lastActiveDate,
        totalPosts: totalPosts ?? this.totalPosts,
        totalFollowers: totalFollowers ?? this.totalFollowers,
        totalFollowing: totalFollowing ?? this.totalFollowing,
        totalCollabs: totalCollabs ?? this.totalCollabs,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => [
        id,
        userId,
        bio,
        gender,
        phone,
        regNumber,
        admissionYear,
        programName,
        courseName,
        faculty,
        department,
        yearOfStudy,
        skills,
        portfolioLinks,
        profileVisibility,
        activityStreak,
        lastActiveDate,
        totalPosts,
        totalFollowers,
        totalFollowing,
        totalCollabs,
        createdAt,
        updatedAt,
      ];
}
