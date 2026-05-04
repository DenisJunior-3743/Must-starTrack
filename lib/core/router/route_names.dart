// lib/core/router/route_names.dart
//
// MUST StarTrack — Route Path Constants
//
// All route paths are defined here as constants.
// No route string is ever hardcoded inside a screen or widget.
// Use context.goNamed(RouteNames.homeName) throughout the app.

abstract final class RouteNames {
  // ── Paths ──────────────────────────────────────────────────────────────────
  static const String splash = '/';
  static const String guestDiscover = '/explore';
  static const String login = '/auth/login';
  static const String registerStep1 = '/auth/register';
  static const String registerStep2 = '/auth/register/step-2';
  static const String registerStep3 = '/auth/register/step-3';
  static const String lecturerRegister = '/auth/register/lecturer';
  static const String forgotPassword = '/auth/forgot-password';
  static const String passwordReset = '/auth/reset-sent';
  static const String passwordResetSent = '/auth/reset-sent';
  static const String home = '/home';
  static const String discover = '/discover';
  static const String peers = '/peers';
  static const String groupDetail = '/groups/:groupId';
  static const String inbox = '/inbox';
  static const String notifications = '/notifications';
  static const String notificationSettings = '/notifications/settings';
  static const String screenHub = '/screen-hub';
  static const String projectDetail = '/project/:postId';
  static const String postDetail = '/project/:postId';
  static const String authorPortfolio = '/user/:userId/portfolio';
  static const String myProfile = '/profile/me';
  static const String profile = '/profile/:userId';
  static const String editProfile = '/profile/me/edit';
  static const String chat = '/chat/:threadId';
  static const String chatDetail = '/chat/:threadId';
  static const String createPost = '/create-post';
  static const String chatbot = '/assistant';
  static const String about = '/about';
  static const String projects = '/my-projects';
  static const String adminDashboard = '/admin';
  static const String adminModeration = '/admin/moderation';
  static const String adminUsers = '/admin/users';
  static const String adminAnalytics = '/admin/analytics';
  static const String adminReports = '/admin/reports';
  static const String adminSync = '/admin/sync';
  static const String activityLogs = '/admin/activity-logs';
  static const String adminChatbotAnalytics = '/admin/chatbot-analytics';
  static const String adminPostReview = '/admin/review/:postId';
  static const String adminNotifications = '/admin/notifications';
  static const String adminRecommendationLab = '/admin/recommendation-lab';
  static const String superAdminDashboard = '/super-admin';
  static const String superAdminSettings = '/super-admin/settings';
  static const String superAdminUsers = '/super-admin/users';
  static const String superAdminAnalytics = '/super-admin/analytics';

  // ── Lecturer Routes ───────────────────────────────────────────────────────
  static const String lecturerDashboard = '/lecturer';
  static const String lecturerApplicants = '/lecturer/applicants';
  static const String lecturerRanking = '/lecturer/ranking';
  static const String lecturerSearch = '/lecturer/search';
  static const String lecturerLeaderboard = '/lecturer/leaderboard';
  static const String globalRanks = '/ranks/global';

  // ── Named Route Keys ──────────────────────────────────────────────────────
  static const String splashName = 'splash';
  static const String guestDiscoverName = 'guestDiscover';
  static const String loginName = 'login';
  static const String registerStep1Name = 'registerStep1';
  static const String registerStep2Name = 'registerStep2';
  static const String registerStep3Name = 'registerStep3';
  static const String lecturerRegisterName = 'lecturerRegister';
  static const String forgotPasswordName = 'forgotPassword';
  static const String passwordResetSentName = 'passwordResetSent';
  static const String homeName = 'home';
  static const String discoverName = 'discover';
  static const String peersName = 'peers';
  static const String groupDetailName = 'groupDetail';
  static const String inboxName = 'inbox';
  static const String notificationsName = 'notifications';
  static const String notificationSettingsName = 'notificationSettings';
  static const String screenHubName = 'screenHub';
  static const String projectDetailName = 'projectDetail';
  static const String profileName = 'profile';
  static const String editProfileName = 'editProfile';
  static const String chatName = 'chat';
  static const String createPostName = 'createPost';
  static const String chatbotName = 'chatbot';
  static const String aboutName = 'about';
  static const String adminDashboardName = 'adminDashboard';
  static const String adminChatbotAnalyticsName = 'adminChatbotAnalytics';
  static const String adminPostReviewName = 'adminPostReview';
  static const String adminNotificationsName = 'adminNotifications';
  static const String adminRecommendationLabName = 'adminRecommendationLab';
  static const String superAdminDashboardName = 'superAdminDashboard';

  // Lecturer named routes
  static const String lecturerDashboardName = 'lecturerDashboard';
  static const String lecturerApplicantsName = 'lecturerApplicants';
  static const String lecturerRankingName = 'lecturerRanking';
  static const String lecturerSearchName = 'lecturerSearch';
  static const String lecturerLeaderboardName = 'lecturerLeaderboard';
  static const String globalRanksName = 'globalRanks';
}

abstract final class Routes {
  static const String splash = RouteNames.splash;
  static const String guestDiscover = RouteNames.guestDiscover;
  static const String login = RouteNames.login;
  static const String registerStep1 = RouteNames.registerStep1;
  static const String registerStep2 = RouteNames.registerStep2;
  static const String registerStep3 = RouteNames.registerStep3;
  static const String lecturerRegister = RouteNames.lecturerRegister;
  static const String forgotPassword = RouteNames.forgotPassword;
  static const String passwordReset = RouteNames.passwordReset;
  static const String home = RouteNames.home;
  static const String discover = RouteNames.discover;
  static const String peers = RouteNames.peers;
  static const String inbox = RouteNames.inbox;
  static const String groupDetail = RouteNames.groupDetail;
  static const String projects = RouteNames.projects;
  static const String notifications = RouteNames.notifications;
  static const String notificationSettings = RouteNames.notificationSettings;
  static const String screenHub = RouteNames.screenHub;
  static const String postDetail = RouteNames.postDetail;
  static const String authorPortfolio = RouteNames.authorPortfolio;
  static const String createPost = RouteNames.createPost;
  static const String chatbot = RouteNames.chatbot;
  static const String about = RouteNames.about;
  static const String myProfile = RouteNames.myProfile;
  static const String profile = RouteNames.profile;
  static const String editProfile = RouteNames.editProfile;
  static const String chatDetail = RouteNames.chatDetail;
  static const String adminDashboard = RouteNames.adminDashboard;
  static const String adminModeration = RouteNames.adminModeration;
  static const String adminUsers = RouteNames.adminUsers;
  static const String adminAnalytics = RouteNames.adminAnalytics;
  static const String adminReports = RouteNames.adminReports;
  static const String adminSync = RouteNames.adminSync;
  static const String activityLogs = RouteNames.activityLogs;
  static const String adminChatbotAnalytics = RouteNames.adminChatbotAnalytics;
  static const String adminPostReview = RouteNames.adminPostReview;
  static const String adminNotifications = RouteNames.adminNotifications;
  static const String adminRecommendationLab =
      RouteNames.adminRecommendationLab;
  static const String superAdminDashboard = RouteNames.superAdminDashboard;
  static const String superAdminSettings = RouteNames.superAdminSettings;
  static const String superAdminUsers = RouteNames.superAdminUsers;
  static const String superAdminAnalytics = RouteNames.superAdminAnalytics;

  // Lecturer
  static const String lecturerDashboard = RouteNames.lecturerDashboard;
  static const String lecturerApplicants = RouteNames.lecturerApplicants;
  static const String lecturerRanking = RouteNames.lecturerRanking;
  static const String lecturerSearch = RouteNames.lecturerSearch;
  static const String lecturerLeaderboard = RouteNames.lecturerLeaderboard;
  static const String globalRanks = RouteNames.globalRanks;
}
