import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../admin/screens/activity_logs_screen.dart';
import '../../admin/screens/suspicion_score_screen.dart';
import '../../admin/screens/sync_settings_screen.dart';
import '../../admin/screens/system_reports_screen.dart';
import '../../admin/screens/user_activity_analytics_screen.dart';
import '../../admin/screens/user_management_screen.dart';
import '../../ai/screens/ai_nudges_screen.dart';
import '../../ai/screens/recommendations_screen.dart';
import '../../discover/screens/faculty_detail_screen.dart';
import '../../discover/screens/faculty_discover_screen.dart';
import '../../discover/screens/skill_search_results_screen.dart';
import '../../discover/screens/university_events_screen.dart';
import '../../feed/screens/archive_project_confirmation_screen.dart';
import '../../feed/screens/archived_projects_screen.dart';

import '../../lecturer/screens/advanced_search_screen.dart';
import '../../lecturer/screens/faculty_leaderboards_screen.dart';
import '../../lecturer/screens/lecturer_ranking_screen.dart';
import '../../lecturer/screens/shortlisted_talent_screen.dart';
import '../../notifications/screens/notification_settings_screen.dart';
import '../../peers/screens/collab_dashboard_screen.dart';
import '../../peers/screens/mentor_discovery_screen.dart';
import '../../peers/screens/mentor_profile_screen.dart';
import '../../peers/screens/mentorship_request_sent_screen.dart';
import '../../peers/screens/send_collab_request_screen.dart';
import '../../peers/screens/send_mentorship_request_screen.dart';
import '../../peers/screens/task_creation_screen.dart';
import '../../profile/screens/achievement_certificate_screen.dart';
import '../../profile/screens/achievements_screen.dart';
import '../../profile/screens/peer_endorsement_screen.dart';
import '../../profile/screens/portfolio_screen.dart';
import '../../profile/screens/privacy_settings_screen.dart';
import '../../super_admin/screens/platform_settings_screen.dart';
import '../../super_admin/screens/user_monitoring_detail_screen.dart';

class ScreenHubScreen extends StatelessWidget {
  const ScreenHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_HubItem>[
      const _HubItem('AI Recommendations', 'AI', RecommendationsScreen()),
      const _HubItem('AI Nudges', 'AI', AiNudgesScreen()),
      const _HubItem('Suspicion Score Detail', 'Admin', SuspicionScoreScreen()),
      const _HubItem('Mentor Discovery', 'Peers', MentorDiscoveryScreen()),
      const _HubItem('Mentor Profile', 'Peers', MentorProfileScreen()),
      const _HubItem('Mentorship Request Sent', 'Peers', MentorshipRequestSentScreen()),
      const _HubItem('Send Mentorship Request', 'Peers', SendMentorshipRequestScreen()),
      const _HubItem('Send Collaboration Request', 'Peers', SendCollabRequestScreen()),
      const _HubItem('Collaboration Dashboard', 'Peers', CollabDashboardScreen()),
      const _HubItem('Task Creation', 'Peers', TaskCreationScreen()),
      const _HubItem('Privacy Settings', 'Profile', PrivacySettingsScreen()),
      const _HubItem('Achievements', 'Profile', AchievementsScreen()),
      const _HubItem('Achievement Certificate', 'Profile', AchievementCertificateScreen()),
      const _HubItem('Digital Portfolio', 'Profile', PortfolioScreen()),
      const _HubItem('Peer Endorsements', 'Profile', PeerEndorsementScreen()),

      const _HubItem('Archive Project Confirmation', 'Feed', ArchiveProjectConfirmationScreen()),
      const _HubItem('Archived Projects', 'Feed', ArchivedProjectsScreen()),
      const _HubItem('Discover by Faculty', 'Discover', FacultyDiscoverScreen()),
      const _HubItem('Faculty Detail', 'Discover', FacultyDetailScreen()),
      const _HubItem('Skill Search Results', 'Discover', SkillSearchResultsScreen()),
      const _HubItem('University Events', 'Discover', UniversityEventsScreen()),
      const _HubItem('Advanced Talent Search', 'Lecturer', AdvancedSearchScreen()),
      const _HubItem('Faculty Leaderboards', 'Lecturer', FacultyLeaderboardsScreen()),
      const _HubItem('Lecturer Ranking', 'Lecturer', LecturerRankingScreen()),
      const _HubItem('Shortlisted Talent', 'Lecturer', ShortlistedTalentScreen()),
      const _HubItem('Notification Settings', 'Notifications', NotificationSettingsScreen()),
      const _HubItem('Activity Logs', 'Admin', ActivityLogsScreen()),
      const _HubItem('User Activity Analytics', 'Admin', UserActivityAnalyticsScreen()),
      const _HubItem('User Management', 'Admin', UserManagementScreen()),
      const _HubItem('System Reports', 'Admin', SystemReportsScreen()),
      const _HubItem('Sync Settings', 'Admin', SyncSettingsScreen()),
      const _HubItem('Platform Settings', 'Super Admin', PlatformSettingsScreen()),
      const _HubItem('User Monitoring Detail', 'Super Admin', UserMonitoringDetailScreen()),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Screen Hub'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
            ),
            child: Text(
              'All newly added screens are available here for fast QA and routing checks.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppColors.border(context)),
                  ),
                  tileColor: AppColors.surface(context),
                  title: Text(
                    item.title,
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    item.category,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => item.screen),
                    );
                  },
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: items.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _HubItem {
  const _HubItem(this.title, this.category, this.screen);

  final String title;
  final String category;
  final Widget screen;
}

