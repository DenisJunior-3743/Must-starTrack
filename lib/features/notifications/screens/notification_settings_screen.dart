// lib/features/notifications/screens/notification_settings_screen.dart
//
// MUST StarTrack - Notification Settings Screen
//
// Glow-shell design matching notification_center_screen:
//   Gradient background + ambient glow blobs
//   Compact switch rows (no oversized SwitchListTile)
//   Section cards with rounded corners and subtle shadow

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/local/services/notification_preferences_service.dart';

// ---------------------------------------------------------------------------
// Glow blob
// ---------------------------------------------------------------------------

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 80, spreadRadius: 25),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final NotificationPreferencesService _preferencesService;
  late NotificationPreferences _preferences;

  static const _categoryLabels = <String, String>{
    'collaboration': 'Collaboration requests',
    'message': 'Direct messages',
    'opportunity': 'Opportunities',
    'achievement': 'Achievements',
    'endorsement': 'Endorsements',
    'system': 'System updates',
    'follow': 'Follows',
    'like': 'Likes',
    'comment': 'Comments',
    'view': 'Views',
  };

  @override
  void initState() {
    super.initState();
    _preferencesService = GetIt.I<NotificationPreferencesService>();
    _preferences = _preferencesService.load();
  }

  Future<void> _save(NotificationPreferences next) async {
    setState(() => _preferences = next);
    await _preferencesService.save(next);
  }

  Future<void> _pickHour({required bool isStart}) async {
    final initialHour =
        isStart ? _preferences.quietStartHour : _preferences.quietEndHour;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: 0),
      helpText: isStart ? 'Quiet hours start' : 'Quiet hours end',
    );
    if (selected == null) return;

    final next = isStart
        ? _preferences.copyWith(quietStartHour: selected.hour)
        : _preferences.copyWith(quietEndHour: selected.hour);
    await _save(next);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgTop =
        isDark ? const Color(0xFF0B1222) : const Color(0xFFF8FBFF);
    final bgBottom =
        isDark ? const Color(0xFF111D36) : const Color(0xFFECF3FF);

    return Scaffold(
      backgroundColor: bgTop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: isDark ? Colors.white : const Color(0xFF1E293B)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Notification Settings',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Gradient background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bgTop, bgBottom],
                ),
              ),
            ),
          ),
          // Glow blobs
          const Positioned(
            top: -60,
            right: -60,
            child: _GlowBlob(
              // ignore: unnecessary_const
              color: const Color(0x332563EB),
            ),
          ),
          const Positioned(
            bottom: 80,
            left: -80,
            child: _GlowBlob(
              // ignore: unnecessary_const
              color: const Color(0x221152D4),
            ),
          ),
          // Content
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'Choose what reaches you and when the app should stay quiet.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: isDark
                      ? Colors.white54
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 20),
              _SettingsCard(
                isDark: isDark,
                title: 'Delivery',
                children: [
                  _SwitchRow(
                    isDark: isDark,
                    label: 'In-app alerts',
                    description:
                        'Show banners and local alerts while using the app.',
                    value: _preferences.inAppEnabled,
                    onChanged: (v) =>
                        _save(_preferences.copyWith(inAppEnabled: v)),
                  ),
                  _Divider(isDark: isDark),
                  _SwitchRow(
                    isDark: isDark,
                    label: 'Push delivery preference',
                    description:
                        'App-side preference for push-style delivery.',
                    value: _preferences.pushEnabled,
                    onChanged: (v) =>
                        _save(_preferences.copyWith(pushEnabled: v)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                isDark: isDark,
                title: 'Quiet Hours',
                children: [
                  _SwitchRow(
                    isDark: isDark,
                    label: 'Mute during quiet hours',
                    description:
                        'Suppress banners and local alerts in the selected window.',
                    value: _preferences.quietHoursEnabled,
                    onChanged: (v) =>
                        _save(_preferences.copyWith(quietHoursEnabled: v)),
                  ),
                  if (_preferences.quietHoursEnabled) ...[
                    _Divider(isDark: isDark),
                    _TimeRow(
                      isDark: isDark,
                      label: 'Starts',
                      time: _preferencesService
                          .formatHour(_preferences.quietStartHour),
                      onTap: () => _pickHour(isStart: true),
                    ),
                    _Divider(isDark: isDark),
                    _TimeRow(
                      isDark: isDark,
                      label: 'Ends',
                      time: _preferencesService
                          .formatHour(_preferences.quietEndHour),
                      onTap: () => _pickHour(isStart: false),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                isDark: isDark,
                title: 'Categories',
                children: [
                  for (int i = 0; i < _categoryLabels.length; i++) ...[
                    if (i > 0) _Divider(isDark: isDark),
                    Builder(builder: (_) {
                      final entry =
                          _categoryLabels.entries.elementAt(i);
                      final enabled =
                          _preferences.categories[entry.key] ?? true;
                      return _SwitchRow(
                        isDark: isDark,
                        label: entry.value,
                        value: enabled,
                        onChanged: (v) {
                          final next = Map<String, bool>.from(
                              _preferences.categories)
                            ..[entry.key] = v;
                          _save(_preferences.copyWith(categories: next));
                        },
                      );
                    }),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.isDark,
    required this.title,
    required this.children,
  });

  final bool isDark;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162035) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.isDark,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
  });

  final bool isDark;
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: isDark
                          ? Colors.white38
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Transform.scale(
            scale: 0.82,
            alignment: Alignment.centerRight,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.isDark,
    required this.label,
    required this.time,
    required this.onTap,
  });

  final bool isDark;
  final String label;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const Icon(
              Icons.schedule_outlined,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ),
            Text(
              time,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 18,
                color: isDark ? Colors.white38 : AppColors.textSecondaryLight),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFE2E8F0),
    );
  }
}