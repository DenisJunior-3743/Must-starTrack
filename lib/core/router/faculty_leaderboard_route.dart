// lib/core/router/faculty_leaderboard_route.dart
// Route for the faculty leaderboard screen

//import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/lecturer/screens/faculty_leaderboards_screen.dart';

GoRoute facultyLeaderboardRoute = GoRoute(
  path: '/lecturer/leaderboard',
  builder: (_, __) => const FacultyLeaderboardsScreen(),
);
