// lib/core/constants/must_validators.dart
//
// MUST StarTrack — MUST-Specific Validators
//
// Registration number format: 2020/BSE/001/PS or 2020/BSE/001/GS
// Student email format:       2020bse001@std.must.ac.ug
// Staff email format:         firstname.lastname@must.ac.ug
//
// The validator cross-checks that the year and student identifier
// in the registration number match the email prefix — a critical
// anti-fraud measure unique to MUST's institutional context.
//
// HCI Principle: Constraints — guiding users toward valid input
// rather than surprising them with errors after submission.
// HCI Principle: Feedback — real-time inline validation messages.

import 'package:dartz/dartz.dart';

/// Result type for validation: either an error String or null (valid).
typedef ValidationResult = String?;

/// Holds structured data parsed from a MUST registration number.
class ParsedRegNumber {
  final String year;         // e.g. "2020"
  final String programCode;  // e.g. "BSE"
  final String studentId;    // e.g. "001"
  final String type;         // "PS" or "GS"

  const ParsedRegNumber({
    required this.year,
    required this.programCode,
    required this.studentId,
    required this.type,
  });

  /// The email prefix that corresponds to this registration number.
  /// Example: 2020/BSE/001/PS → "2020bse001"
  String get expectedEmailPrefix =>
      '$year${programCode.toLowerCase()}$studentId';

  @override
  String toString() =>
      '$year/${programCode.toUpperCase()}/$studentId/$type';
}

/// Central validator class for all MUST-specific business rules.
abstract final class MustValidators {
  // ── Regular Expressions ───────────────────────────────────────────────────

  /// Matches: 2020/BSE/001/PS  or  2020/bse/001/GS  (case-insensitive program code)
  static final RegExp _regNumberRegex = RegExp(
    r'^(\d{4})/([a-zA-Z]{2,6})/(\d{3})/(PS|GS)$',
    caseSensitive: false,
  );

  /// Matches student emails: 2020bse001@std.must.ac.ug
  /// Pattern: {year}{programCode}{id}@std.must.ac.ug
  static final RegExp _studentEmailRegex = RegExp(
    r'^(\d{4}[a-zA-Z]{2,6}\d{3})@std\.must\.ac\.ug$',
    caseSensitive: false,
  );

  /// Matches staff/lecturer emails: jdoe@must.ac.ug
  static final RegExp _staffEmailRegex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@must\.ac\.ug$',
    caseSensitive: false,
  );

  /// General MUST domain check (student OR staff).
  static final RegExp _mustDomainRegex = RegExp(
    r'^.+@(std\.)?must\.ac\.ug$',
    caseSensitive: false,
  );

  // ── Registration Number ───────────────────────────────────────────────────

  /// Validates and parses a registration number string.
  /// Returns [Either<String, ParsedRegNumber>]:
  ///   Left(errorMessage) on failure, Right(parsed) on success.
  static Either<String, ParsedRegNumber> parseRegNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const Left('Registration number is required.');
    }
    final trimmed = value.trim();
    final match = _regNumberRegex.firstMatch(trimmed);
    if (match == null) {
      return const Left(
        'Format must be YYYY/XXX/NNN/PS or YYYY/XXX/NNN/GS\n'
        'Example: 2020/BSE/001/PS',
      );
    }

    final year = match.group(1)!;
    final yearInt = int.tryParse(year) ?? 0;
    final currentYear = DateTime.now().year;

    if (yearInt < 2000 || yearInt > currentYear) {
      return Left('Admission year $year is not valid.');
    }

    return Right(ParsedRegNumber(
      year: year,
      programCode: match.group(2)!.toUpperCase(),
      studentId: match.group(3)!,
      type: match.group(4)!.toUpperCase(),
    ));
  }

  /// Form field validator — returns error string or null.
  static ValidationResult validateRegNumber(String? value) {
    return parseRegNumber(value).fold((err) => err, (_) => null);
  }

  // ── Student Email ─────────────────────────────────────────────────────────

  /// Validates a student email address.
  static ValidationResult validateStudentEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Student email is required.';
    }
    if (!_studentEmailRegex.hasMatch(value.trim())) {
      return 'Must be a valid MUST student email.\n'
          'Example: 2020bse001@std.must.ac.ug';
    }
    return null;
  }

  // ── Staff/Lecturer Email ──────────────────────────────────────────────────

  /// Validates a staff/lecturer email address.
  static ValidationResult validateStaffEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Staff email is required.';
    }
    if (!_staffEmailRegex.hasMatch(value.trim())) {
      return 'Must be a valid MUST staff email.\nExample: jdoe@must.ac.ug';
    }
    return null;
  }

  // ── Cross-field Validation ────────────────────────────────────────────────

  /// Validates that the student email is consistent with the registration number.
  /// The email prefix (e.g. "2020bse001") must match what the reg number implies.
  static ValidationResult validateRegNumberEmailConsistency({
    required String regNumber,
    required String email,
  }) {
    final parsed = parseRegNumber(regNumber);
    return parsed.fold(
      (err) => err, // reg number itself is invalid
      (reg) {
        final emailPrefix = email.split('@').first.toLowerCase();
        final expected = reg.expectedEmailPrefix.toLowerCase();
        if (emailPrefix != expected) {
          return 'Your email prefix ($emailPrefix) doesn\'t match your '
              'registration number.\nExpected: $expected@std.must.ac.ug';
        }
        return null;
      },
    );
  }

  // ── General Email ─────────────────────────────────────────────────────────

  /// General email format validator (used for login form).
  static ValidationResult validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required.';
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  // ── Password ──────────────────────────────────────────────────────────────

  /// Password strength validator.
  /// Minimum 8 chars, at least one uppercase, one lowercase, one digit.
  static ValidationResult validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    if (value.length < 8) return 'Password must be at least 8 characters.';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Include at least one uppercase letter.';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Include at least one lowercase letter.';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Include at least one number.';
    }
    return null;
  }

  /// Confirms that two password fields match.
  static ValidationResult validatePasswordMatch(
    String? password,
    String? confirm,
  ) {
    if (confirm == null || confirm.isEmpty) {
      return 'Please confirm your password.';
    }
    if (password != confirm) return 'Passwords do not match.';
    return null;
  }

  // ── Phone ─────────────────────────────────────────────────────────────────

  /// Validates a Ugandan phone number.
  /// Accepts: 0701234567, +256701234567, 256701234567
  static ValidationResult validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    final phoneRegex = RegExp(r'^(\+?256|0)[3-9]\d{8}$');
    if (!phoneRegex.hasMatch(value.trim().replaceAll(' ', ''))) {
      return 'Enter a valid Ugandan phone number.\nExample: 0701234567';
    }
    return null;
  }

  // ── Required Field ────────────────────────────────────────────────────────
  static ValidationResult validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    return null;
  }

  // ── URL Validators ────────────────────────────────────────────────────────

  static ValidationResult validateYoutubeUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final ytRegex = RegExp(
      r'^(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)[\w\-]{11}',
    );
    if (!ytRegex.hasMatch(value.trim())) {
      return 'Enter a valid YouTube video URL.';
    }
    return null;
  }

  static ValidationResult validateGithubUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final ghRegex = RegExp(r'^https?://github\.com/[\w\-]+(/[\w\-\.]+)?$');
    if (!ghRegex.hasMatch(value.trim())) {
      return 'Enter a valid GitHub URL (e.g. https://github.com/user/repo).';
    }
    return null;
  }

  static ValidationResult validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final urlRegex = RegExp(r'^https?://[^\s$.?#].[^\s]*$');
    if (!urlRegex.hasMatch(value.trim())) {
      return 'Enter a valid URL starting with http:// or https://';
    }
    return null;
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  /// Returns true if the email belongs to any MUST domain.
  static bool isMustEmail(String email) =>
      _mustDomainRegex.hasMatch(email.trim());

  /// Returns true if the email is a student email.
  static bool isStudentEmail(String email) =>
      _studentEmailRegex.hasMatch(email.trim());

  /// Returns true if the email is a staff/lecturer email.
  static bool isStaffEmail(String email) =>
      _staffEmailRegex.hasMatch(email.trim());
}
