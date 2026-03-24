// lib/core/theme/theme_cubit.dart
//
// MUST StarTrack — Theme Mode Cubit
//
// Persists the user's preferred theme (light / dark / system) via
// SharedPreferences so the choice survives app restarts.
//
// Usage example from a settings widget:
//   context.read<ThemeCubit>().setMode(ThemeMode.dark);

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  static const _prefKey = 'app_theme_mode';
  final SharedPreferences _prefs;

  ThemeCubit(SharedPreferences prefs)
      : _prefs = prefs,
        super(_readStored(prefs));

  // ── Read the persisted value synchronously at construction time ──────────
  static ThemeMode _readStored(SharedPreferences prefs) {
    return switch (prefs.getString(_prefKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  // ── Public API ────────────────────────────────────────────────────────────
  void setMode(ThemeMode mode) {
    _prefs.setString(_prefKey, mode.name);
    emit(mode);
  }

  void toggleDark() {
    setMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}
