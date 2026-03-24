import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/local/services/notification_preferences_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
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
    final initialHour = isStart ? _preferences.quietStartHour : _preferences.quietEndHour;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: 0),
      helpText: isStart ? 'Quiet hours start' : 'Quiet hours end',
    );
    if (selected == null) {
      return;
    }

    final next = isStart
        ? _preferences.copyWith(quietStartHour: selected.hour)
        : _preferences.copyWith(quietEndHour: selected.hour);
    await _save(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose what reaches you and when the app should stay quiet.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'Delivery',
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In-app alerts'),
                  subtitle: const Text('Show banners and local alerts while using the app.'),
                  value: _preferences.inAppEnabled,
                  onChanged: (value) => _save(_preferences.copyWith(inAppEnabled: value)),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Push delivery preference'),
                  subtitle: const Text('Use this as your app-side preference for push-style delivery.'),
                  value: _preferences.pushEnabled,
                  onChanged: (value) => _save(_preferences.copyWith(pushEnabled: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'Quiet Hours',
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mute alerts during quiet hours'),
                  subtitle: const Text('Suppress app banners and local alerts in the selected window.'),
                  value: _preferences.quietHoursEnabled,
                  onChanged: (value) => _save(_preferences.copyWith(quietHoursEnabled: value)),
                ),
                if (_preferences.quietHoursEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Starts'),
                    subtitle: Text(_preferencesService.formatHour(_preferences.quietStartHour)),
                    trailing: const Icon(Icons.schedule_outlined),
                    onTap: () => _pickHour(isStart: true),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ends'),
                    subtitle: Text(_preferencesService.formatHour(_preferences.quietEndHour)),
                    trailing: const Icon(Icons.schedule_outlined),
                    onTap: () => _pickHour(isStart: false),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'Categories',
            child: Column(
              children: _categoryLabels.entries.map((entry) {
                final enabled = _preferences.categories[entry.key] ?? true;
                return Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value),
                      value: enabled,
                      onChanged: (value) {
                        final nextCategories = Map<String, bool>.from(_preferences.categories)
                          ..[entry.key] = value;
                        _save(_preferences.copyWith(categories: nextCategories));
                      },
                    ),
                    if (entry.key != _categoryLabels.keys.last) const Divider(height: 1),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
