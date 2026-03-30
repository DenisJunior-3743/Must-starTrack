// lib/data/local/services/faculty_seeder.dart
//
// MUST StarTrack — Faculty Seeder
//
// Seeds the canonical MUST faculties and their programs (courses) into the
// local SQLite database on first run.
//
// This is idempotent: each faculty/course is looked up by unique code before
// inserting, so re-running does NOT create duplicates.
//
// Call:  await FacultySeeder.seed(facultyDao, courseDao);
// from InjectionContainer.init() after all DAOs are registered.

import 'package:flutter/foundation.dart';

import '../../models/faculty_model.dart';
import '../../models/course_model.dart';
import '../dao/faculty_dao.dart';
import '../dao/course_dao.dart';

class FacultySeeder {
  FacultySeeder._();

  /// Canonical MUST faculties: (name, code, description)
  static const _faculties = [
    _FacultySeed(
      name: 'Faculty of Computing and Informatics',
      code: 'FCI',
      description: 'Faculty of Computing and Informatics (FCI)',
    ),
    _FacultySeed(
      name: 'Faculty of Applied Sciences and Technology',
      code: 'FAST',
      description: 'Faculty of Applied Sciences and Technology (FAST)',
    ),
    _FacultySeed(
      name: 'Faculty of Business and Management Sciences',
      code: 'FBMS',
      description: 'Faculty of Business and Management Sciences (FBMS)',
    ),
    _FacultySeed(
      name: 'Faculty of Medicine',
      code: 'FOM',
      description: 'Faculty of Medicine (FOM)',
    ),
  ];

  /// Canonical MUST programs: facultyCode → list of (name, code, description)
  static const _courses = {
    'FCI': [
      _CourseSeed(name: 'Bachelor of Software Engineering', code: 'BSE'),
      _CourseSeed(name: 'Bachelor of Computer Science', code: 'BCS'),
      _CourseSeed(name: 'Bachelor of Information Technology', code: 'BIT'),
    ],
    'FAST': [
      _CourseSeed(name: 'Civil Engineering', code: 'CVE'),
      _CourseSeed(name: 'Electrical and Electronics Engineering', code: 'EEE'),
      _CourseSeed(name: 'Biomedical Engineering', code: 'BME'),
    ],
    'FBMS': [
      _CourseSeed(name: 'Bachelor of Science in Economics', code: 'ECO'),
      _CourseSeed(name: 'Bachelor of Arts in Economics', code: 'BAE'),
      _CourseSeed(name: 'Bachelor of Accounting and Finance', code: 'BAF'),
    ],
    'FOM': [
      _CourseSeed(name: 'Bachelor of Medicine and Surgery', code: 'MBChB'),
      _CourseSeed(name: 'Bachelor of Science in Nursing', code: 'BSN'),
      _CourseSeed(name: 'Bachelor of Public Health', code: 'BPH'),
    ],
  };

  static Future<void> seed(
    FacultyDao facultyDao,
    CourseDao courseDao,
  ) async {
    for (final seed in _faculties) {
      // Idempotency: skip if already in DB
      final existing = await facultyDao.getFacultyByCode(seed.code);
      if (existing != null) continue;

      final faculty = FacultyModel.create(
        name: seed.name,
        code: seed.code,
        description: seed.description,
      );

      await facultyDao.createFaculty(faculty);

      debugPrint('[FacultySeeder] Seeded faculty: ${faculty.name} (${faculty.code})');

      // Seed courses for this faculty
      final courseSeeds = _courses[seed.code] ?? const [];
      for (final cs in courseSeeds) {
        final existingCourse = await courseDao.getCourseByCode(cs.code);
        if (existingCourse != null) continue;

        final course = CourseModel.create(
          facultyId: faculty.id,
          name: cs.name,
          code: cs.code,
        );

        await courseDao.createCourse(course);

        debugPrint('[FacultySeeder]   Seeded course: ${course.name} (${course.code})');
      }
    }
  }
}

class _FacultySeed {
  final String name;
  final String code;
  final String description;

  const _FacultySeed({
    required this.name,
    required this.code,
    required this.description,
  });
}

class _CourseSeed {
  final String name;
  final String code;

  const _CourseSeed({required this.name, required this.code});
}
