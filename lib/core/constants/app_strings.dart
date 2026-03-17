// lib/core/constants/app_strings.dart
//
// MUST StarTrack — Design Token: Strings
//
// Centralising all user-facing strings here means:
// 1. Easy localisation later (swap this file for an ARB/intl file).
// 2. No typos from duplicated literals scattered across files.
// 3. Consistent tone across all screens.
//
// HCI Principle: Consistency — same terminology everywhere.

abstract final class AppStrings {
  // ── App Identity ──────────────────────────────────────────────────────────
  static const String appName = 'StarTrack';
  static const String appFullName = 'MUST StarTrack';
  static const String appTagline = 'Your skills. Your story. Your network.';
  static const String university = 'Mbarara University of Science and Technology';
  static const String universityShort = 'MUST';

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const String login = 'Log In';
  static const String logout = 'Log Out';
  static const String register = 'Sign Up';
  static const String createAccount = 'Create Account';
  static const String haveAccount = 'Already have an account?';
  static const String noAccount = "Don't have an account?";
  static const String forgotPassword = 'Forgot Password?';
  static const String resetPassword = 'Reset Password';
  static const String resetPasswordSent =
      'Check your email for a reset link.';
  static const String continueWithGoogle = 'Continue with Google';
  static const String emailVerificationSent =
      'Verification email sent. Please check your inbox.';
  static const String verifyEmail = 'Verify Email';

  // ── Onboarding ────────────────────────────────────────────────────────────
  static const String onboardingTitle = 'StarTrack Onboarding';
  static const String step1Title = 'Biographical Data';
  static const String step2Title = 'University Info';
  static const String step3Title = 'Login Credentials';
  static const String step1Of3 = 'Step 1 of 3';
  static const String step2Of3 = 'Step 2 of 3';
  static const String step3Of3 = 'Step 3 of 3';
  static const String nextStep = 'Next';
  static const String previousStep = 'Back';
  static const String completeRegistration = 'Complete Registration';
  static const String profilePhoto = 'Profile Photo';
  static const String photoHint = 'JPG, PNG up to 2MB (optional)';

  // ── Profile Fields ────────────────────────────────────────────────────────
  static const String fullName = 'Full Name';
  static const String firstName = 'First Name';
  static const String lastName = 'Last Name';
  static const String otherNames = 'Other Names';
  static const String gender = 'Gender';
  static const String phone = 'Phone Number';
  static const String biography = 'Short Biography';
  static const String skills = 'Skills';
  static const String addSkill = 'Add a skill...';
  static const String registrationNumber = 'Registration Number';
  static const String regNumberHint = 'e.g. 2020/BSE/001/PS';
  static const String admissionYear = 'Admission Year';
  static const String programName = 'Program Name';
  static const String courseName = 'Course Name';
  static const String faculty = 'Faculty';
  static const String yearOfStudy = 'Year of Study';
  static const String studentEmail = 'Student Email';
  static const String studentEmailHint = 'e.g. 2020bse001@std.must.ac.ug';
  static const String staffEmail = 'Staff Email';
  static const String staffEmailHint = 'e.g. jdoe@must.ac.ug';
  static const String department = 'Department';
  static const String password = 'Password';
  static const String confirmPassword = 'Confirm Password';
  static const String portfolioLinks = 'Portfolio Links';
  static const String githubUrl = 'GitHub URL';
  static const String linkedinUrl = 'LinkedIn URL';
  static const String websiteUrl = 'Website / Demo URL';

  // ── Navigation ────────────────────────────────────────────────────────────
  static const String navHome = 'Home';
  static const String navPeers = 'Peers';
  static const String navInbox = 'Inbox';
  static const String navProjects = 'Projects';
  static const String navDiscover = 'Discover';

  // ── Feed ──────────────────────────────────────────────────────────────────
  static const String feedTitle = 'StarTrack';
  static const String feedDiscover = 'Discover';
  static const String noPostsYet = 'No posts yet.';
  static const String pullToRefresh = 'Pull to refresh';
  static const String loadingMore = 'Loading more...';
  static const String noMorePosts = 'You\'re all caught up!';
  static const String offlineMessage =
      'You\'re offline. Showing cached content.';

  // ── Post Actions ──────────────────────────────────────────────────────────
  static const String like = 'Like';
  static const String dislike = 'Dislike';
  static const String comment = 'Comment';
  static const String share = 'Share';
  static const String follow = 'Follow';
  static const String following = 'Following';
  static const String unfollow = 'Unfollow';
  static const String flag = 'Report';
  static const String flagged = 'Reported';
  static const String save = 'Save';
  static const String viewAll = 'View All';
  static const String reply = 'Reply';
  static const String addComment = 'Add a comment...';
  static const String typeMessage = 'Type a message...';

  // ── Post Creation ─────────────────────────────────────────────────────────
  static const String createProject = 'Create Project';
  static const String createOpportunity = 'Create Opportunity';
  static const String projectTitle = 'Project Title';
  static const String projectDescription = 'Project Description';
  static const String projectCategory = 'Category';
  static const String projectTags = 'Tags';
  static const String addTag = 'Add tag...';
  static const String skillsUsed = 'Skills Used';
  static const String visibility = 'Visibility';
  static const String visibilityPublic = 'Public';
  static const String visibilityFollowers = 'Followers only';
  static const String visibilityCollaborators = 'Collaborators only';
  static const String addMedia = 'Add Media';
  static const String addImages = 'Add Images';
  static const String addVideo = 'Add Video';
  static const String youtubeLink = 'YouTube Link';
  static const String externalLink = 'External Link';
  static const String maxImages = 'Max 1.5MB per image';
  static const String maxVideo = 'Max 2 minutes video';
  static const String publishPost = 'Publish';
  static const String saveDraft = 'Save Draft';

  // ── Discover ──────────────────────────────────────────────────────────────
  static const String discoverTitle = 'Explore MUST StarTrack';
  static const String discoverSubtitle = 'Projects and Opportunities';
  static const String projects = 'Projects';
  static const String challenges = 'Challenges';
  static const String internships = 'Internships';
  static const String jobs = 'Jobs';
  static const String workshops = 'Workshops';
  static const String events = 'Events';
  static const String filterBy = 'Filter by';
  static const String filterFaculty = 'Faculty';
  static const String filterProgram = 'Program';
  static const String filterSkill = 'Skill Area';
  static const String filterAcademicYear = 'Academic Year';
  static const String clearFilters = 'Clear Filters';
  static const String applyFilters = 'Apply Filters';
  static const String noResults = 'No results found.';
  static const String tryDifferentSearch = 'Try a different search term or filter.';

  // ── Peers & Collaboration ─────────────────────────────────────────────────
  static const String peers = 'Peers';
  static const String peersAll = 'All';
  static const String peersPending = 'Pending';
  static const String peersApproved = 'Approved';
  static const String peersPotential = 'Potential Peers';
  static const String sendCollabRequest = 'Send Collaboration Request';
  static const String collabRequestSent = 'Request Sent';
  static const String collabRequestAccepted = 'Accepted';
  static const String collabRequestRejected = 'Declined';
  static const String acceptRequest = 'Accept';
  static const String rejectRequest = 'Decline';
  static const String cancelRequest = 'Cancel Request';
  static const String connect = 'Connect';
  static const String connected = 'Connected';
  static const String sendMentorshipRequest = 'Request Mentorship';
  static const String mentorshipRequestSent = 'Mentorship Request Sent';

  // ── Messaging ─────────────────────────────────────────────────────────────
  static const String inbox = 'Inbox';
  static const String messages = 'Messages';
  static const String noMessages = 'No messages yet.';
  static const String online = 'Online';
  static const String offline = 'Offline';
  static const String lastSeen = 'Last seen';
  static const String typing = 'typing...';
  static const String delivered = 'Delivered';
  static const String read = 'Read';
  static const String sendMessage = 'Send';
  static const String swipeToRefresh = 'Swipe down to refresh';

  // ── Notifications ─────────────────────────────────────────────────────────
  static const String notifications = 'Notifications';
  static const String allNotifications = 'All';
  static const String posts = 'Posts';
  static const String collabNotif = 'Collaboration';
  static const String notifSettings = 'Notification Settings';
  static const String markAllRead = 'Mark all as read';
  static const String noNotifications = 'You\'re all caught up!';

  // ── Admin ─────────────────────────────────────────────────────────────────
  static const String moderationDashboard = 'Moderation Dashboard';
  static const String pendingReviews = 'Pending Reviews';
  static const String flaggedPosts = 'Flagged Posts';
  static const String reportedUsers = 'Reported Users';
  static const String approvePost = 'Approve';
  static const String rejectPost = 'Reject';
  static const String reviewPost = 'Review';
  static const String userManagement = 'User Management';
  static const String suspendUser = 'Suspend User';
  static const String banUser = 'Ban User';
  static const String activityLogs = 'Activity Logs';
  static const String systemReports = 'System Reports';
  static const String generateReport = 'Generate Report';
  static const String exportCsv = 'Export CSV';
  static const String exportPdf = 'Export PDF';

  // ── Super Admin ───────────────────────────────────────────────────────────
  static const String systemAnalytics = 'System Analytics';
  static const String platformSettings = 'Platform Settings';
  static const String adminManagement = 'Admin Management';
  static const String createAdmin = 'Create Admin';
  static const String removeAdmin = 'Remove Admin';
  static const String totalUsers = 'Total Users';
  static const String activeUsers = 'Active Users';
  static const String totalProjects = 'Total Projects';
  static const String serverStatus = 'Server Status';
  static const String syncStatus = 'Sync Status';
  static const String cloudSynced = 'Cloud Synced';

  // ── Guest ─────────────────────────────────────────────────────────────────
  static const String joinNow = 'Join Now';
  static const String exploreAsGuest = 'Explore as Guest';
  static const String guestPromptTitle = 'Join MUST StarTrack';
  static const String guestPromptBody =
      'Create a free account to like posts, collaborate on projects, and connect with peers.';
  static const String guestPromptCta = 'Create Account';
  static const String guestPromptLogin = 'I already have an account';

  // ── Validation Messages ───────────────────────────────────────────────────
  static const String validationRequired = 'This field is required.';
  static const String validationEmailInvalid = 'Please enter a valid email address.';
  static const String validationEmailNotMust =
      'Email must use a MUST domain (@must.ac.ug, @std.must.ac.ug, or @staff.must.ac.ug).';
  static const String validationRegNumFormat =
      'Format must be YYYY/XXX/NNN/PS or YYYY/XXX/NNN/GS (e.g. 2020/BSE/001/PS).';
  static const String validationRegNumYearMismatch =
      'The year in your registration number doesn\'t match the email.';
  static const String validationPasswordMin =
      'Password must be at least 8 characters.';
  static const String validationPasswordMatch = 'Passwords do not match.';
  static const String validationPasswordWeak =
      'Include uppercase, lowercase, and a number.';
  static const String validationPhoneInvalid =
      'Enter a valid Ugandan phone number.';
  static const String validationYoutubeUrl =
      'Please enter a valid YouTube URL.';
  static const String validationGithubUrl = 'Please enter a valid GitHub URL.';

  // ── Error Messages ────────────────────────────────────────────────────────
  static const String errorGeneric = 'Something went wrong. Please try again.';
  static const String errorNetwork =
      'No internet connection. Please check your network.';
  static const String errorUnauthorized =
      'Your session has expired. Please log in again.';
  static const String errorNotFound = 'Content not found.';
  static const String errorServerError = 'Server error. Please try again later.';
  static const String errorImageTooLarge =
      'Image exceeds 1.5MB. It will be compressed automatically.';
  static const String errorVideoTooLong =
      'Video exceeds 2 minutes. Please trim and re-upload.';
  static const String errorStorageFull =
      'Storage quota exceeded. Please free up space.';

  // ── Success Messages ──────────────────────────────────────────────────────
  static const String successProfileUpdated = 'Profile updated successfully.';
  static const String successProjectCreated = 'Project published!';
  static const String successCollabSent = 'Collaboration request sent.';
  static const String successFollowing = 'Now following!';
  static const String successReportSubmitted =
      'Thank you. Your report has been submitted.';
  static const String successPasswordReset = 'Password reset successfully.';

  // ── AI / Recommendations ──────────────────────────────────────────────────
  static const String aiRecommendations = 'Recommended for You';
  static const String aiCollaborators = 'Suggested Collaborators';
  static const String aiStreakTitle = 'Keep Your Streak Going!';
  static const String aiStreakBody =
      'You\'ve been active {days} days in a row. Keep posting to maintain your streak!';

  // ── Empty States ──────────────────────────────────────────────────────────
  static const String emptyFeed = 'Nothing here yet.';
  static const String emptyFeedSub =
      'Follow peers or explore the Discover tab to find interesting projects.';
  static const String emptyInbox = 'No messages yet.';
  static const String emptyInboxSub =
      'Start a conversation with a collaborator or lecturer.';
  static const String emptyNotifications = 'All clear!';
  static const String emptyNotificationsSub =
      'You\'re up to date with all notifications.';
  static const String emptyPeers = 'No connections yet.';
  static const String emptyPeersSub =
      'Explore the Discover tab to find potential collaborators.';
  static const String emptyProjects = 'No projects posted yet.';
  static const String emptyProjectsSub =
      'Tap + to create your first project post.';

  // ── Misc ──────────────────────────────────────────────────────────────────
  static const String loading = 'Loading...';
  static const String cancel = 'Cancel';
  static const String confirm = 'Confirm';
  static const String delete = 'Delete';
  static const String edit = 'Edit';
  static const String update = 'Update';
  static const String close = 'Close';
  static const String done = 'Done';
  static const String skip = 'Skip';
  static const String search = 'Search';
  static const String searchHint = 'Search projects, skills, people...';
  static const String seeMore = 'See more';
  static const String seeLess = 'See less';
  static const String optional = '(optional)';
  static const String comingSoon = 'Coming soon';
  static const String version = 'Version';
  static const String privacyPolicy = 'Privacy Policy';
  static const String termsOfService = 'Terms of Service';
  static const String dataPortability = 'Download My Data';
}
