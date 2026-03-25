import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationPreferences {
  final bool inAppEnabled;
  final bool pushEnabled;
  final bool quietHoursEnabled;
  final int quietStartHour;
  final int quietEndHour;
  final Map<String, bool> categories;

  const NotificationPreferences({
    required this.inAppEnabled,
    required this.pushEnabled,
    required this.quietHoursEnabled,
    required this.quietStartHour,
    required this.quietEndHour,
    required this.categories,
  });

  static const defaultCategories = <String, bool>{
    'collaboration': true,
    'message': true,
    'opportunity': true,
    'achievement': true,
    'endorsement': true,
    'system': true,
    'follow': true,
    'like': true,
    'comment': true,
    'view': true,
  };

  factory NotificationPreferences.defaults() => const NotificationPreferences(
        inAppEnabled: true,
        pushEnabled: true,
        quietHoursEnabled: false,
        quietStartHour: 22,
        quietEndHour: 7,
        categories: defaultCategories,
      );

  NotificationPreferences copyWith({
    bool? inAppEnabled,
    bool? pushEnabled,
    bool? quietHoursEnabled,
    int? quietStartHour,
    int? quietEndHour,
    Map<String, bool>? categories,
  }) {
    return NotificationPreferences(
      inAppEnabled: inAppEnabled ?? this.inAppEnabled,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietStartHour: quietStartHour ?? this.quietStartHour,
      quietEndHour: quietEndHour ?? this.quietEndHour,
      categories: categories ?? this.categories,
    );
  }

  bool get quietHoursCrossMidnight => quietStartHour > quietEndHour;

  bool isWithinQuietHours(DateTime time) {
    if (!quietHoursEnabled) {
      return false;
    }

    final hour = time.hour;
    if (quietStartHour == quietEndHour) {
      return true;
    }
    if (quietHoursCrossMidnight) {
      return hour >= quietStartHour || hour < quietEndHour;
    }
    return hour >= quietStartHour && hour < quietEndHour;
  }
}

class NotificationPreferencesService {
  NotificationPreferencesService({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;

  static const _inAppKey = 'notif.in_app_enabled';
  static const _pushKey = 'notif.push_enabled';
  static const _quietEnabledKey = 'notif.quiet_hours_enabled';
  static const _quietStartKey = 'notif.quiet_start_hour';
  static const _quietEndKey = 'notif.quiet_end_hour';
  static const _categoryPrefix = 'notif.category.';

  NotificationPreferences load() {
    final defaults = NotificationPreferences.defaults();
    final categories = <String, bool>{};
    for (final entry in NotificationPreferences.defaultCategories.entries) {
      categories[entry.key] = _prefs.getBool('$_categoryPrefix${entry.key}') ?? entry.value;
    }

    return NotificationPreferences(
      inAppEnabled: _prefs.getBool(_inAppKey) ?? defaults.inAppEnabled,
      pushEnabled: _prefs.getBool(_pushKey) ?? defaults.pushEnabled,
      quietHoursEnabled: _prefs.getBool(_quietEnabledKey) ?? defaults.quietHoursEnabled,
      quietStartHour: _prefs.getInt(_quietStartKey) ?? defaults.quietStartHour,
      quietEndHour: _prefs.getInt(_quietEndKey) ?? defaults.quietEndHour,
      categories: categories,
    );
  }

  Future<void> save(NotificationPreferences preferences) async {
    await _prefs.setBool(_inAppKey, preferences.inAppEnabled);
    await _prefs.setBool(_pushKey, preferences.pushEnabled);
    await _prefs.setBool(_quietEnabledKey, preferences.quietHoursEnabled);
    await _prefs.setInt(_quietStartKey, preferences.quietStartHour);
    await _prefs.setInt(_quietEndKey, preferences.quietEndHour);
    for (final entry in preferences.categories.entries) {
      await _prefs.setBool('$_categoryPrefix${entry.key}', entry.value);
    }
  }

  bool shouldPresentAlert({
    required String type,
    DateTime? now,
    bool requirePushEnabled = false,
  }) {
    final preferences = load();
    if (!preferences.inAppEnabled) {
      return false;
    }
    if (requirePushEnabled && !preferences.pushEnabled) {
      return false;
    }
    if (!(preferences.categories[type] ?? true)) {
      return false;
    }
    if (preferences.isWithinQuietHours(now ?? DateTime.now())) {
      return false;
    }
    return true;
  }

  String formatHour(int hour) {
    final tod = TimeOfDay(hour: hour, minute: 0);
    final suffix = tod.period == DayPeriod.am ? 'AM' : 'PM';
    final displayHour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
    return '$displayHour:00 $suffix';
  }
}