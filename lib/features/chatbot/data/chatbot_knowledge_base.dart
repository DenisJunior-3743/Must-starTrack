import '../../../core/router/route_names.dart';
import '../models/chatbot_models.dart';

class ChatbotKnowledgeBase {
  ChatbotKnowledgeBase._();

  // ─────────────────────────────────────────────────────────────────────────
  // EXPANDED FAQ KNOWLEDGE BASE - Grouped by Category
  // ─────────────────────────────────────────────────────────────────────────
  // Groups: Getting Started, Posts & Projects, Profile & Skills, Collaboration,
  //         Messaging & Notifications, Groups, Admin/Lecturer Features, Account & Security
  // ─────────────────────────────────────────────────────────────────────────

  static const List<ChatbotFaqEntry> faqs = [
    // ═════════════════════════════════════════════════════════════════════════
    // CATEGORY: Getting Started
    // ═════════════════════════════════════════════════════════════════════════
    ChatbotFaqEntry(
      id: 'faq_what_is_startrack',
      group: 'Getting Started',
      question: 'What is MUST StarTrack?',
      answer:
          'MUST StarTrack is a skill-centric academic networking platform designed for Mbarara University of Science and Technology. It connects students, lecturers, and opportunities through digital portfolios, project showcases, collaboration tools, and AI-powered recommendations. You can create posts, find collaborators, apply for opportunities, and build your professional network.',
      keywords: [
        'startrack',
        'platform',
        'network',
        'features',
        'what is',
        'about',
        'what does this app do',
        'what does this application do',
        'what can this app do'
      ],
      actions: [
        ChatbotAction(label: 'Browse Home Feed', route: RouteNames.home),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_app_overview',
      group: 'Getting Started',
      question: 'What does this app do?',
      answer:
          'This app helps MUST students, lecturers, and admins manage academic networking and collaboration. You can showcase projects, create opportunities, discover people by skills, send messages, form groups, and receive AI-assisted recommendations. Lecturers can review and rank applicants, while admins can moderate content and manage platform analytics. Guests can browse public content, but account-based actions like posting and messaging require sign-in.',
      keywords: [
        'what does this app do',
        'what does this application do',
        'what can this app do',
        'what is this app for',
        'purpose of this app',
        'application overview'
      ],
      actions: [
        ChatbotAction(label: 'Browse Home Feed', route: RouteNames.home),
      ],
      followUps: [
        'How do I get started on the platform?',
        'What are the main features of MUST StarTrack?',
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_developers_team',
      group: 'Getting Started',
      question: 'Who developed MUST StarTrack?',
      answer:
          'MUST StarTrack was developed as a third-year group mini project by five Software Engineering students at Mbarara University of Science and Technology (MUST): Denis Junior, Ainamaani Allan Mwesigye, Mwunvaneeza Godfrey, Murungi Kevin Tumaini, and Mbabazi Patience. The project was built to make student work more visible, strengthen collaboration, and connect skills to meaningful academic opportunities.',
      keywords: [
        'developers',
        'developer',
        'who built this app',
        'who created startrack',
        'team behind startrack',
        'about team',
      ],
      actions: [
        ChatbotAction(
            label: 'Open About MUST StarTrack', route: RouteNames.about),
      ],
      followUps: [
        'What is the purpose of MUST StarTrack?',
        'What are the main features of MUST StarTrack?',
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_getting_started',
      group: 'Getting Started',
      question: 'How do I get started on the platform?',
      answer:
          'Welcome to MUST StarTrack! To get started: (1) Sign in with your MUST email account or register if you are new. (2) Complete your profile by adding a bio, skills, and a profile picture. (3) Explore the Home feed to see posts from your peers. (4) Visit Discover to find students and projects matching your interests. (5) Create your first project post to showcase your work. You can browse as a guest without logging in, but posting, messaging, and applying requires an account.',
      keywords: [
        'started',
        'begin',
        'signup',
        'register',
        'newcomer',
        'first time',
        'welcome'
      ],
      actions: [
        ChatbotAction(label: 'Open Home', route: RouteNames.home),
        ChatbotAction(label: 'Edit Profile', route: RouteNames.editProfile),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_what_is_home_feed',
      group: 'Getting Started',
      question: 'What is the Home feed?',
      answer:
          'The Home feed is your personalized dashboard showing posts from peers, collaborators, and your network. It displays project showcases, opportunity postings, and activity from people you follow. You can like posts, comment, share, and apply to opportunities. The feed is sorted by relevance using AI recommendations based on your skills and interests. Pull down to refresh and scroll to load more posts.',
      keywords: ['home', 'feed', 'dashboard', 'posts', 'timeline', 'scroll'],
      actions: [
        ChatbotAction(label: 'Open Home Feed', route: RouteNames.home),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_guest_mode',
      group: 'Getting Started',
      question: 'What can I do in guest mode?',
      answer:
          'As a guest (without signing in), you can: browse the public Home feed to see posts from other students, explore the Discover feature to search for projects and collaborators by skills or faculty, and view public profiles. However, you cannot create posts, send messages, apply for opportunities, or engage with interactions like comments or recommendations. To use these features, sign in with your MUST email account.',
      keywords: [
        'guest',
        'mode',
        'anonymous',
        'without login',
        'login required',
        'limitations'
      ],
      actions: [
        ChatbotAction(label: 'Sign In', route: RouteNames.login),
      ],
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // CATEGORY: Posts & Projects
    // ═════════════════════════════════════════════════════════════════════════
    ChatbotFaqEntry(
      id: 'faq_create_post',
      group: 'Posts & Projects',
      question: 'How do I create a project or opportunity post?',
      answer:
          'To create a post: (1) Tap the Create Post button from the Home feed or bottom navigation. (2) Choose post type: Project (to showcase your work) or Opportunity (to invite collaborators). (3) Fill in the title, description, select your faculty and program. (4) Add details: skills used, tags, category, and visibility (public or private). (5) Upload media: images and videos are supported. (6) Add external links: GitHub repo, YouTube video, or portfolio links. (7) Tap Publish. Your post appears in the feed after being synced to the server.',
      keywords: [
        'create',
        'post',
        'project',
        'opportunity',
        'publish',
        'upload',
        'new post'
      ],
      actions: [
        ChatbotAction(label: 'Create Post', route: RouteNames.createPost),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_post_visibility',
      group: 'Posts & Projects',
      question: 'What does post visibility mean?',
      answer:
          'Post visibility controls who can see your post. Public posts are visible to everyone on the platform and in the Home feed. Private posts are visible only to you and people you choose to share with. When creating a post, you can set visibility in the post settings. This is useful if you want to draft a post before sharing or if you want to keep certain work private until you are ready.',
      keywords: [
        'visibility',
        'public',
        'private',
        'share',
        'who can see',
        'permissions'
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_edit_delete_post',
      group: 'Posts & Projects',
      question: 'Can I edit or delete my post after publishing?',
      answer:
          'Yes, you can edit or delete your own posts. Go to My Profile to see your posts. Tap the More menu on any post to edit the title, description, or media, or to delete the post entirely. Changes are synced to the platform immediately. Once deleted, the post cannot be recovered.',
      keywords: ['edit', 'delete', 'modify', 'remove', 'post', 'profile'],
      actions: [
        ChatbotAction(label: 'Open My Profile', route: RouteNames.myProfile),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_apply_opportunity',
      group: 'Posts & Projects',
      question: 'How do I apply for an opportunity?',
      answer:
          'To apply for an opportunity post: (1) Find the opportunity in the Home feed or via Discover. (2) Tap the post to view details. (3) Tap Apply Now button. (4) Add a brief message explaining your interest or why you are a good fit. (5) Submit your application. The opportunity creator will see your application in their notifications and can accept or reject you. You can track all your applications in Notifications.',
      keywords: ['apply', 'opportunity', 'join', 'application', 'request'],
      actions: [
        ChatbotAction(
            label: 'Check Notifications', route: RouteNames.notifications),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_post_engagement',
      group: 'Posts & Projects',
      question: 'How do I like, comment, or share a post?',
      answer:
          'To engage with a post: (1) Tap the post to open details. (2) Use the action buttons: tap the heart icon to like, comment icon to add a comment, or share icon to share with others. You can also add emoji reactions to comments. Likes and comments help boost the visibility of posts in the feed and show support to creators.',
      keywords: [
        'like',
        'comment',
        'share',
        'reaction',
        'engage',
        'interaction'
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_media_upload',
      group: 'Posts & Projects',
      question: 'What media can I upload to a post?',
      answer:
          'You can upload images (PNG, JPG) and videos (MP4, MOV) to your posts. Images are displayed as galleries and videos are embedded inline. Media is stored securely on Cloudinary. Keep files under reasonable sizes for smooth uploading (images under 10MB, videos under 100MB recommended). You can add multiple images and videos to a single post.',
      keywords: [
        'media',
        'upload',
        'image',
        'video',
        'photo',
        'file',
        'attachment'
      ],
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // CATEGORY: Profile & Skills
    // ═════════════════════════════════════════════════════════════════════════
    ChatbotFaqEntry(
      id: 'faq_profile_overview',
      group: 'Profile & Skills',
      question: 'What should I include in my profile?',
      answer:
          'A complete profile includes: (1) Profile picture to make you recognizable. (2) Bio: a brief 2-3 sentence description of your interests and skills. (3) Skills: add 5-10 skills you are proficient in (e.g. Flutter, UI/UX Design, Python). (4) Links: add your GitHub, portfolio website, or LinkedIn. (5) Faculty and program: automatically set during registration. (6) Achievements: you can add certifications or awards. A complete profile increases visibility in recommendations and helps others find you.',
      keywords: ['profile', 'bio', 'picture', 'complete', 'information'],
      actions: [
        ChatbotAction(label: 'Edit Profile', route: RouteNames.editProfile),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_edit_profile',
      group: 'Profile & Skills',
      question: 'How do I edit my profile?',
      answer:
          'To edit your profile: (1) Go to your My Profile screen. (2) Tap the Edit Profile button. (3) Update your bio, profile picture, skills, links, or other information. (4) Students cannot change their own faculty or program after registration, but admins can update those academic details when reassignment is needed. (5) Tap Save to save changes. Changes are visible immediately to other users.',
      keywords: [
        'edit',
        'profile',
        'bio',
        'picture',
        'skills',
        'links',
        'update'
      ],
      actions: [
        ChatbotAction(label: 'Edit Profile', route: RouteNames.editProfile),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_university_fields_locked',
      group: 'Profile & Skills',
      question: 'Why can\'t I edit my faculty or program?',
      answer:
          'Your faculty and program are locked after registration to keep academic records consistent and authentic. This prevents fraud and ensures the platform maintains reliable data about which students belong to which academic units. If your faculty or program is incorrect due to a registration error, please contact the admin support team.',
      keywords: [
        'faculty',
        'program',
        'university',
        'edit',
        'change',
        'locked',
        'cannot change'
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_skills_tags',
      group: 'Profile & Skills',
      question: 'What are skills and tags?',
      answer:
          'Skills are technical or professional abilities you have (e.g. Flutter, Java, Design, Data Analysis). Tags are keywords used when creating posts to categorize your work. When you add skills to your profile, the AI recommendation system uses them to match you with relevant posts, collaborators, and opportunities. Common skills examples: Programming languages (Python, JavaScript), frameworks (Flutter, React), design tools, project management, etc.',
      keywords: ['skills', 'tags', 'abilities', 'keywords', 'expertise'],
    ),
    ChatbotFaqEntry(
      id: 'faq_achievements',
      group: 'Profile & Skills',
      question: 'How do I add achievements to my profile?',
      answer:
          'Achievements (courses, certifications, awards) help showcase your qualifications. Go to your profile, tap Achievements, and add certifications you have completed or awards you have received. This builds credibility and helps peers and lecturers understand your expertise.',
      keywords: [
        'achievement',
        'certificate',
        'award',
        'course',
        'credential',
        'qualification'
      ],
      actions: [
        ChatbotAction(label: 'View My Profile', route: RouteNames.myProfile),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_peer_endorsement',
      group: 'Profile & Skills',
      question: 'What is peer endorsement?',
      answer:
          'Peer endorsement allows your collaborators and peers to vouch for your skills. When someone you have worked with approves your skills, it adds credibility to your profile. You can endorse others you have collaborated with as well. Endorsements appear on your profile and help build trust within the community.',
      keywords: [
        'endorsement',
        'peer',
        'vouch',
        'skills',
        'verification',
        'credibility'
      ],
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // CATEGORY: Collaboration
    // ═════════════════════════════════════════════════════════════════════════
    ChatbotFaqEntry(
      id: 'faq_finding_collaborators',
      group: 'Collaboration',
      question: 'How do I find collaborators?',
      answer:
          'There are several ways to find collaborators: (1) Use Discover to search by skills or faculty. (2) Browse the Home feed and message people whose work interests you. (3) Check Peers to see people you have worked with before. (4) Send collab requests to suggest working together. (5) Apply to opportunities where you need a team. The AI recommendation system also suggests people with matching skills and interests on your Discover screen.',
      keywords: [
        'collaborators',
        'find',
        'team',
        'peers',
        'discover',
        'matching',
        'skills'
      ],
      actions: [
        ChatbotAction(label: 'Open Discover', route: RouteNames.discover),
        ChatbotAction(label: 'View Peers', route: RouteNames.peers),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_collaboration_request',
      group: 'Collaboration',
      question: 'How do I send or respond to a collaboration request?',
      answer:
          'To send a collab request: (1) Visit someone\'s profile. (2) Tap Send Collab Request. (3) Select the project you want to collaborate on or describe the collaboration. (4) Send. They will see your request in notifications. To respond to a request you received, go to your Peers screen and check pending collaboration requests. You can accept to become collaborators or decline to reject.',
      keywords: [
        'collaboration',
        'collab request',
        'request',
        'team',
        'accept',
        'decline'
      ],
      actions: [
        ChatbotAction(label: 'View Peers', route: RouteNames.peers),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_groups',
      group: 'Collaboration',
      question: 'What are groups and how do I create one?',
      answer:
          'Groups allow you to organize collaborations with multiple team members around a specific project. To create a group: (1) Go to Peers and select Groups. (2) Tap Create Group. (3) Name your group, add a description and group image. (4) Invite collaborators from your accepted peers list (you must have accepted collab requests with them first). (5) Set member roles (owner/admin/member). (6) Confirm to create. Once created, group members can post projects within the group for easy organization.',
      keywords: [
        'groups',
        'create group',
        'team',
        'members',
        'collaboration',
        'organize'
      ],
      actions: [
        ChatbotAction(label: 'View Peers', route: RouteNames.peers),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_group_posts',
      group: 'Collaboration',
      question: 'How do I post projects to a group?',
      answer:
          'To post to a group: (1) Open the group detail page. (2) Tap Create Group Post. (3) Fill in the post details as you would for a regular post (title, description, media, skills). (4) The post will be attributed to the group for easy tracking. (5) Publish. Group posts appear in the group feed and in your group members\' feeds. This helps keep collaboration work organized and visible to the team.',
      keywords: ['group post', 'group project', 'post', 'group', 'share'],
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // CATEGORY: Messaging & Notifications
    // ═════════════════════════════════════════════════════════════════════════
    ChatbotFaqEntry(
      id: 'faq_messaging',
      group: 'Messaging & Notifications',
      question: 'How do I send messages?',
      answer:
          'To message someone: (1) Tap the Inbox or Messages icon in navigation. (2) Tap the plus icon or a conversation to start or open a chat. (3) Type your message or attach media. (4) Tap Send. You can send text, images, and videos. Messages appear instantly if you are online, or are delivered when the recipient comes online. You can delete or edit messages you have sent.',
      keywords: ['message', 'chat', 'inbox', 'send', 'conversation', 'dm'],
      actions: [
        ChatbotAction(label: 'Open Inbox', route: RouteNames.inbox),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_notification_center',
      group: 'Messaging & Notifications',
      question: 'What are notifications?',
      answer:
          'Notifications alert you to important events like: someone commenting on your post, a message from a peer, a collaboration request, an application to your opportunity post, a like on your work, or admin announcements. You can see all notifications in the Notification Center. Each notification links you directly to the related content.',
      keywords: [
        'notification',
        'alert',
        'center',
        'notification center',
        'feedback'
      ],
      actions: [
        ChatbotAction(
            label: 'View Notifications', route: RouteNames.notifications),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_notification_settings',
      group: 'Messaging & Notifications',
      question: 'How do I manage my notification settings?',
      answer:
          'Go to Notification Settings from the drawer menu to customize how you receive alerts. You can enable/disable notifications for: comments, collaboration requests, messages, likes, application updates, recommendations, and more. You can also choose between push notifications, in-app alerts, or email summaries.',
      keywords: [
        'notification settings',
        'manage',
        'alerts',
        'preferences',
        'customize'
      ],
      actions: [
        ChatbotAction(
            label: 'Notification Settings',
            route: RouteNames.notificationSettings),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_activity_streak',
      group: 'Messaging & Notifications',
      question: 'What is an activity streak?',
      answer:
          'An activity streak tracks how many days in a row you have engaged with the platform (posting, commenting, liking, or messaging). The app shows your current streak on your profile. Streaks motivate consistent participation and help build community engagement. You can see your activity stats in your profile achievements section.',
      keywords: ['activity', 'streak', 'days', 'consecutive', 'engagement'],
      actions: [
        ChatbotAction(label: 'View My Profile', route: RouteNames.myProfile),
      ],
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // CATEGORY: Discover & Recommendations
    // ═════════════════════════════════════════════════════════════════════════
    ChatbotFaqEntry(
      id: 'faq_discover',
      group: 'Discover & Recommendations',
      question: 'What is Discover and how do I use it?',
      answer:
          'Discover is a powerful search and exploration feature for finding students, projects, and opportunities. You can search by: (1) Skills to find people with specific abilities. (2) Faculty to see projects from your academic unit. (3) Categories to explore different domains. (4) Keywords in post titles and descriptions. Results show posts and people ranked by relevance to your interests. Use filters to narrow results by program, skills, or date.',
      keywords: [
        'discover',
        'search',
        'explore',
        'find',
        'results',
        'recommendations'
      ],
      actions: [
        ChatbotAction(label: 'Open Discover', route: RouteNames.discover),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_recommendations',
      group: 'Discover & Recommendations',
      question: 'How do the recommender algorithms work?',
      answer:
          'MUST StarTrack uses a hybrid, local-first recommender. First, the app scores posts locally using your skills, faculty, program, recent searches, recent activity, recency of posts, engagement, and opportunity fit. Then, if OpenAI is configured, it can rerank the top results rather than replacing the whole system. This is used in the Home feed, Discover, collaborator suggestions, and lecturer applicant ranking. Even when OpenAI is unavailable, the local ranking still works, so recommendations do not stop completely.',
      keywords: [
        'recommendations',
        'ai',
        'personalized',
        'recommend',
        'ranking',
        'suggested',
        'recommender',
        'algorithms',
        'how does the ai recommendation system work',
        'recommendation system',
        'openai rerank',
        'local first',
      ],
      followUps: [
        'What data does the recommender use?',
        'Where are recommendations used in the app?',
        'What happens when OpenAI is unavailable?',
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_recommender_data',
      group: 'Discover & Recommendations',
      question: 'What data does the recommender use?',
      answer:
          'The recommender uses both user and content signals. User signals include skills, faculty, program, bio presence, activity streak, total posts, collaborations, followers, recent searches, and activity logs. Content signals include post type, category, faculty, program, skills used, tags, recency, likes, comments, shares, and opportunity requirements. These signals are combined into weighted local ranking before OpenAI reranking is considered.',
      keywords: [
        'what data does the recommender use',
        'recommendation signals',
        'what does recommendation use',
        'ranking signals',
        'user signals',
        'content signals',
      ],
      followUps: [
        'How do the recommender algorithms work?',
        'Where are recommendations used in the app?',
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_recommendation_usage',
      group: 'Discover & Recommendations',
      question: 'Where are recommendations used in the app?',
      answer:
          'Recommendations are used in several places. The Home feed uses them to personalize which posts appear first, Discover uses them to rerank search results, collaborator suggestions use them to find relevant peers, and lecturer ranking uses them to prioritize applicants. This means recommendation logic is not limited to a single screen; it supports multiple academic and collaboration workflows across the app.',
      keywords: [
        'where are recommendations used in the app',
        'where is recommendation used',
        'recommendation screens',
        'home feed recommendations',
        'discover recommendations',
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_openai_unavailable',
      group: 'Discover & Recommendations',
      question: 'What happens when OpenAI is unavailable?',
      answer:
          'The app falls back to local-first behavior. Recommendations still work using local ranking, and the assistant still answers using FAQ and embedded project knowledge. OpenAI improves explanation quality and can rerank results, but the app is intentionally designed so that its important workflows do not stop when OpenAI is unavailable or not configured.',
      keywords: [
        'what happens when openai is unavailable',
        'if openai is off',
        'if openai is not configured',
        'without openai',
        'openai unavailable',
      ],
      followUps: [
        'Is OpenAI used in this app?',
        'How do the recommender algorithms work?',
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_ai_nudges',
      group: 'Discover & Recommendations',
      question: 'What are AI nudges?',
      answer:
          'AI nudges are personalized suggestions from the platform to encourage engagement. For example, you might receive nudges like "Complete your profile to improve recommendations" or "You have 3 new skill-matching posts available." Nudges appear as notifications and on your Discover screen. They are designed to help you discover relevant content and build connections.',
      keywords: [
        'nudges',
        'ai nudges',
        'suggestions',
        'recommendations',
        'hints'
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_openai_usage',
      group: 'Discover & Recommendations',
      question: 'Is OpenAI used in this app?',
      answer:
          'Yes. OpenAI is used in two main places when configured: first, as an optional reranking layer for recommendations; second, as the assistant fallback when local FAQ and project knowledge are not enough. The app still keeps important logic local-first, so feed ranking and assistant answers do not depend entirely on OpenAI to work.',
      keywords: [
        'is openai used in this app',
        'openai',
        'ai model',
        'does the app use openai',
        'openai integration',
        'is ai used in this app'
      ],
      followUps: [
        'How do the recommender algorithms work?',
        'What happens when OpenAI is unavailable?',
      ],
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // CATEGORY: Admin & Lecturer Features
    // ═════════════════════════════════════════════════════════════════════════
    ChatbotFaqEntry(
      id: 'faq_lecturer_dashboard',
      group: 'Admin & Lecturer Features',
      question: 'What is the Lecturer Dashboard?',
      answer:
          'The Lecturer Dashboard (for lecturers) provides analytics and management tools: (1) View all opportunity postings you have created. (2) Track applications and applicants. (3) See rankings of applicants based on skill match and activity. (4) Manage shortlisted candidates. (5) Filter and search applicants. (6) View detailed profiles of candidates. (7) Export reports. Use this to manage your recruitment and collaboration workflows.',
      keywords: [
        'lecturer',
        'dashboard',
        'lecturer dashboard',
        'manage',
        'opportunities',
        'applicants'
      ],
      actions: [
        ChatbotAction(
            label: 'Lecturer Dashboard', route: RouteNames.lecturerDashboard),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_admin_dashboard',
      group: 'Admin & Lecturer Features',
      question: 'What is the Admin Dashboard?',
      answer:
          'The Admin Dashboard (for admins and super admins) provides platform management and analytics: (1) User management: view, edit, or suspend users. (2) Activity analytics: see platform engagement trends. (3) Moderation: review reported posts and enforce community guidelines. (4) Faculty management: manage academic units. (5) Course management: organize course data. (6) Groups management: oversee group creation and moderation. (7) Chatbot analytics: track assistant accuracy and training. Use this to maintain a healthy platform ecosystem.',
      keywords: [
        'admin',
        'dashboard',
        'admin dashboard',
        'management',
        'moderation',
        'analytics'
      ],
      actions: [
        ChatbotAction(
            label: 'Admin Dashboard', route: RouteNames.adminDashboard),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_moderation',
      group: 'Admin & Lecturer Features',
      question: 'How does post moderation work?',
      answer:
          'Users can report posts that violate community guidelines. Reports go to the admin moderation queue. Admins review: the reported post, the reason for report, user history, and context. Actions: approve (keep post), remove (delete post), or warn user. Repeat violations may result in account suspension. Reports are anonymous and cases are documented for accountability.',
      keywords: [
        'moderation',
        'report',
        'admin',
        'violation',
        'policy',
        'community guidelines'
      ],
    ),

    // ═════════════════════════════════════════════════════════════════════════
    // CATEGORY: Account & Security
    // ═════════════════════════════════════════════════════════════════════════
    ChatbotFaqEntry(
      id: 'faq_account_types',
      group: 'Account & Security',
      question: 'What types of accounts exist?',
      answer:
          'MUST StarTrack supports multiple roles: (1) Student: can post projects, apply to opportunities, find collaborators. (2) Lecturer: can post opportunities, manage applicants, access lecturer analytics. (3) Admin: can moderate content, manage users and faculty. (4) Super Admin: full platform management including configuration and system settings.',
      keywords: [
        'account',
        'types',
        'roles',
        'student',
        'lecturer',
        'admin',
        'super admin'
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_signin',
      group: 'Account & Security',
      question: 'How do I sign in?',
      answer:
          'To sign in: (1) On the Login screen, enter your MUST email (must@mustmak.ac.ug or similar). (2) Enter your password. (3) Tap Sign In. If you don\'t have an account, tap Register and complete the registration steps. If you forgot your password, tap Forgot Password and follow the email instructions.',
      keywords: ['sign in', 'login', 'signin', 'authenticate', 'password'],
      actions: [
        ChatbotAction(label: 'Sign In', route: RouteNames.login),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_register',
      group: 'Account & Security',
      question: 'How do I register for an account?',
      answer:
          'To register: (1) Tap Register from the Login screen. (2) Enter your MUST email address. (3) Create a strong password. (4) Select your role (Student or Lecturer). (5) Confirm your faculty, program, and other details. Students cannot later change these on their own, but admins can correct them if reassignment is needed. (6) Add your profile information: bio, skills, profile picture. (7) Tap Create Account. You will be signed in automatically and taken to the onboarding.',
      keywords: [
        'register',
        'signup',
        'new account',
        'registration',
        'join',
        'sign up'
      ],
      actions: [
        ChatbotAction(label: 'Sign In', route: RouteNames.login),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_forgot_password',
      group: 'Account & Security',
      question: 'I forgot my password. What should I do?',
      answer:
          'To reset your password: (1) Tap Forgot Password on the Login screen. (2) Enter your MUST email address. (3) Check your email for a reset link from MUST StarTrack. (4) Click the link and create a new password. (5) Return to the app and sign in with your new password. The reset link expires after 24 hours for security.',
      keywords: ['forgot', 'password', 'reset', 'recovery', 'forgot password'],
      actions: [
        ChatbotAction(
            label: 'Forgot Password', route: RouteNames.forgotPassword),
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_delete_account',
      group: 'Account & Security',
      question: 'How do I delete my account?',
      answer:
          'To delete your account: (1) Go to Settings from the drawer menu. (2) Scroll down to Account Settings. (3) Tap Delete Account. (4) Confirm the action (this cannot be undone). You will be signed out immediately. The admin team will review your deletion request over the next 7-30 days. Your data is retained for audit purposes as per MUST policies.',
      keywords: [
        'delete',
        'account',
        'remove',
        'close',
        'deactivate',
        'cancel'
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_privacy_security',
      group: 'Account & Security',
      question: 'How is my data protected?',
      answer:
          'MUST StarTrack uses industry-standard security: (1) All data is encrypted in transit (HTTPS/TLS). (2) Passwords are securely hashed. (3) Firebase Authentication manages secure sign-in. (4) Sensitive data (tokens) are stored securely. (5) Access controls limit who can view your data. (6) Regular backups ensure data recovery. (7) Admins follow strict confidentiality policies. Your private posts are visible only to you; shared posts follow your chosen settings.',
      keywords: [
        'privacy',
        'security',
        'data',
        'protection',
        'encrypted',
        'safe',
        'confidential'
      ],
    ),
    ChatbotFaqEntry(
      id: 'faq_session_timeout',
      group: 'Account & Security',
      question: 'Why was I signed out automatically?',
      answer:
          'For security, MUST StarTrack automatically signs you out after 30 days of inactivity or if the app hasn\'t been used for a while. This prevents unauthorized access if your device is lost or stolen. You can also manually sign out from Settings. If you were signed out unexpectedly, try signing back in. If you experience repeated sign-outs, contact admin support.',
      keywords: [
        'session',
        'timeout',
        'signed out',
        'logout',
        'inactivity',
        'security'
      ],
      actions: [
        ChatbotAction(label: 'Sign In', route: RouteNames.login),
      ],
    ),
  ];

  static const List<ChatbotKnowledgeDoc> projectDocs = [
    ChatbotKnowledgeDoc(
      id: 'doc_recommender_algorithms',
      title: 'Recommender Algorithms',
      summary:
          'The recommendation system is hybrid and local-first. It ranks posts locally using profile signals, behavior signals, recency, engagement, and opportunity fit, then optionally lets OpenAI rerank top results when configured.',
      content:
          'The recommender uses profile signals like skills, faculty, program, bio presence, activity streak, total posts, collaborations, and followers. It also uses post signals such as post type, category, faculty, program, skills used, tags, created time, likes, comments, shares, and area of expertise. Behavior signals come from activity logs like viewing, liking, commenting, sharing, joining opportunities, and recent search terms. The local ranking applies weights to skill overlap, faculty match, program match, search intent, recency, engagement, recent category behavior, and opportunity fit. OpenAI is only used as an optional reranking layer on top of the local results.',
      keywords: [
        'recommender',
        'algorithms',
        'recommendation',
        'ranking',
        'local first',
        'openai',
        'feed ranking',
        'discover reranking',
        'lecturer ranking',
      ],
      followUps: [
        'How do the recommender algorithms work?',
        'What data does the recommender use?',
        'Where are AI recommendations shown?',
      ],
    ),
    ChatbotKnowledgeDoc(
      id: 'doc_recommender_usage',
      title: 'Recommendation Usage Across The App',
      summary:
          'Recommendation logic is used in the Home feed, Discover, collaborator recommendation, AI-facing screens, and lecturer applicant ranking.',
      content:
          'Recommendation logic supports multiple surfaces in the app. Personalized feed ranking orders posts in the Home feed, Discover reranks search results, collaborator recommendation suggests relevant peers, AI-facing screens expose recommendations and nudges, and lecturer ranking helps sort applicants based on fit and activity. This makes recommendations part of both student-facing and lecturer-facing workflows.',
      keywords: [
        'where are recommendations used',
        'recommendation usage',
        'home feed recommendation',
        'discover reranking',
        'collaborator recommendation',
        'lecturer applicant ranking',
      ],
      followUps: [
        'Where are recommendations used in the app?',
        'What data does the recommender use?',
      ],
    ),
    ChatbotKnowledgeDoc(
      id: 'doc_groups',
      title: 'Groups and Group Posts',
      summary:
          'Groups let peers collaborate as a team, invite accepted collaborators, and publish group-attributed posts that appear in group flows and can be filtered in feeds.',
      content:
          'Groups are built around accepted collaborator relationships. A group has members with owner, admin, or member roles. Group posts reuse the normal post pipeline but include a group identifier so they can appear in group feeds and lecturer/admin views. Group creation starts from the peers flow, then users invite eligible collaborators, manage members, and publish work inside the group.',
      keywords: [
        'groups',
        'group posts',
        'group collaboration',
        'team',
        'invite members',
        'group feed',
      ],
      followUps: [
        'What are groups and how do I create one?',
        'How do I post projects to a group?',
      ],
    ),
    ChatbotKnowledgeDoc(
      id: 'doc_architecture',
      title: 'Architecture Overview',
      summary:
          'The app uses Flutter with BLoC, get_it, GoRouter, Firebase, and SQLite in a local-first architecture.',
      content:
          'MUST StarTrack is structured around Flutter UI, feature modules, BLoC/Cubit state management, GoRouter navigation, get_it dependency injection, SQLite persistence, and Firebase-backed remote services. It is designed to remain useful offline or under weak connectivity, with local storage and sync-aware workflows supporting the main experience. OpenAI is integrated as a supporting AI layer rather than the foundation of all app behavior.',
      keywords: [
        'architecture',
        'how is the app built',
        'flutter architecture',
        'offline first',
        'sqlite',
        'firebase',
      ],
      followUps: [
        'What does this app do?',
        'Is OpenAI used in this app?',
      ],
    ),
    ChatbotKnowledgeDoc(
      id: 'doc_platform_overview',
      title: 'Platform Overview',
      summary:
          'MUST StarTrack is a skill-centric academic networking platform for project showcasing, discovery, collaboration, recommendations, messaging, and role-based workflows.',
      content:
          'The app supports students, lecturers, admins, and super admins. Core areas include the Home feed, Discover, Peers, Messaging, Notifications, Profiles, AI recommendations, lecturer ranking tools, and admin analytics. Guests can browse public content, while signed-in users unlock posting, messaging, applications, and collaboration features.',
      keywords: [
        'platform',
        'overview',
        'features',
        'roles',
        'what is must startrack',
        'what does this app do',
        'what does this application do',
        'what can this app do',
      ],
    ),
    ChatbotKnowledgeDoc(
      id: 'doc_openai_usage',
      title: 'OpenAI Usage',
      summary:
          'OpenAI is used in the app as an optional reranking layer for recommendations and as fallback reasoning for the in-app assistant when local knowledge is not enough.',
      content:
          'The recommendation system is local-first, but when OpenAI is configured it can rerank top results. The chatbot assistant also uses OpenAI as a fallback after searching the local FAQ and embedded project knowledge. This means OpenAI supports the app, but critical product behavior does not fully depend on it. If OpenAI is unavailable, the local recommendation logic and FAQ-based answers still continue to work.',
      keywords: [
        'openai',
        'is openai used in this app',
        'openai integration',
        'ai model',
        'assistant fallback',
        'reranking',
      ],
      followUps: [
        'How do the recommender algorithms work?',
        'What does this app do?',
      ],
    ),
    ChatbotKnowledgeDoc(
      id: 'doc_offline_first',
      title: 'Offline-First Behavior',
      summary:
          'The app is designed to remain useful even when connectivity is weak by favoring local persistence and local-first decision paths.',
      content:
          'MUST StarTrack uses a local-first approach so that important workflows continue even when remote AI or network access is limited. SQLite-backed persistence, sync-aware design, and local FAQ or ranking logic help preserve core functionality. OpenAI improves the system when configured, but assistant answers and recommendations still retain local fallbacks.',
      keywords: [
        'offline first',
        'offline',
        'weak network',
        'local first',
        'local fallback',
      ],
      followUps: [
        'What happens when OpenAI is unavailable?',
        'How do the recommender algorithms work?',
      ],
    ),
  ];

  static const List<String> starterPrompts = [
    'How do I create a project or opportunity post?',
    'How do I find collaborators?',
    'What are groups and how do I create one?',
    'How do I apply for an opportunity?',
    'How do the recommender algorithms work?',
  ];

  static const Set<String> knownRoutes = {
    RouteNames.home,
    RouteNames.discover,
    RouteNames.peers,
    RouteNames.inbox,
    RouteNames.notifications,
    RouteNames.myProfile,
    RouteNames.editProfile,
    RouteNames.login,
    RouteNames.createPost,
    RouteNames.projects,
    RouteNames.notificationSettings,
    RouteNames.about,
    RouteNames.forgotPassword,
    RouteNames.adminDashboard,
    RouteNames.lecturerDashboard,
  };
}
