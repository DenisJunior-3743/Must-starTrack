// lib/data/local/schema/database_schema.dart
//
// MUST StarTrack — Complete SQLite Database Schema
//
// ALL tables are defined here in a single file so the schema is
// reviewed and understood as a whole before any code is written.
// The database is created once at v1 — clean migration design
// means fewer headaches during testing.
//
// Design decisions:
//   - Every table has a TEXT PRIMARY KEY 'id' (UUID v4) generated
//     client-side, so offline-created records get stable IDs before
//     they ever reach Firestore.
//   - 'created_at' and 'updated_at' are stored as ISO-8601 strings
//     (SQLite has no native TIMESTAMP type).
//   - Booleans are stored as INTEGER (0 / 1) per SQLite convention.
//   - JSON blobs (tags, skills, images) are stored as TEXT (JSON string)
//     and decoded in the DAO layer.
//   - A 'sync_status' column on every major table tracks whether the
//     row has been pushed to Firestore: 0=pending, 1=synced, 2=failed.

abstract final class DatabaseSchema {
  static const String databaseName = 'must_startrack.db';
  static const int databaseVersion = 11;

  // ── Table Names ────────────────────────────────────────────────────────────
  static const String tableUsers = 'users';
  static const String tableProfiles = 'profiles';
  static const String tableFaculties = 'faculties';
  static const String tableCourses = 'courses';
  static const String tablePosts = 'posts';
  static const String tableComments = 'comments';
  static const String tableLikes = 'likes';
  static const String tableDislikes = 'dislikes';
  static const String tableFollows = 'follows';
  static const String tableCollabRequests = 'collab_requests';
  static const String tableMessages = 'messages';
  static const String tableConversations = 'conversations';
  static const String tableMessageThreads = 'message_threads';
  static const String tableNotifications = 'notifications';
  static const String tableOpportunities = 'opportunities';
  static const String tablePostJoins = 'post_joins';
  static const String tableSyncQueue = 'sync_queue';
  static const String tableModerationQueue = 'moderation_queue';
  static const String tableProjectMilestones = 'project_milestones';
  static const String tableTasks = 'tasks';
  static const String tableEndorsements = 'endorsements';
  static const String tableActivityLogs = 'activity_logs';
  static const String tableDeviceTokens = 'device_tokens';
  static const String tableSearchHistory = 'search_history';
  static const String tableDraftPosts = 'draft_posts';
  static const String tableAchievements = 'achievements';
  static const String tableRecommendationLogs = 'recommendation_logs';

  // ─────────────────────────────────────────────────────────────────────────
  // CREATE TABLE STATEMENTS
  // Called in order by DatabaseHelper.onCreate()
  // ─────────────────────────────────────────────────────────────────────────

  /// Users — core identity record for all roles.
  /// role: 'guest' | 'student' | 'lecturer' | 'admin' | 'super_admin'
  static const String createUsers = '''
    CREATE TABLE IF NOT EXISTS $tableUsers (
      id                TEXT PRIMARY KEY,
      firebase_uid      TEXT UNIQUE,
      email             TEXT NOT NULL UNIQUE,
      role              TEXT NOT NULL DEFAULT 'student',
      display_name      TEXT,
      photo_url         TEXT,
      is_email_verified INTEGER NOT NULL DEFAULT 0,
      is_suspended      INTEGER NOT NULL DEFAULT 0,
      is_banned         INTEGER NOT NULL DEFAULT 0,
      last_seen_at      TEXT,
      created_at        TEXT NOT NULL,
      updated_at        TEXT NOT NULL,
      sync_status       INTEGER NOT NULL DEFAULT 0
    )
  ''';

  /// Profiles — extended data per user (1-to-1 with users).
  /// skills, portfolio_links, and tags stored as JSON strings.
  static const String createProfiles = '''
    CREATE TABLE IF NOT EXISTS $tableProfiles (
      id                  TEXT PRIMARY KEY,
      user_id             TEXT NOT NULL UNIQUE,
      bio                 TEXT,
      gender              TEXT,
      phone               TEXT,
      reg_number          TEXT,
      admission_year      TEXT,
      program_name        TEXT,
      course_name         TEXT,
      faculty             TEXT,
      department          TEXT,
      year_of_study       INTEGER,
      skills              TEXT DEFAULT '[]',
      portfolio_links     TEXT DEFAULT '{}',
      profile_visibility  TEXT NOT NULL DEFAULT 'public',
      activity_streak     INTEGER NOT NULL DEFAULT 0,
      last_active_date    TEXT,
      total_posts         INTEGER NOT NULL DEFAULT 0,
      total_followers     INTEGER NOT NULL DEFAULT 0,
      total_following     INTEGER NOT NULL DEFAULT 0,
      total_collabs       INTEGER NOT NULL DEFAULT 0,
      created_at          TEXT NOT NULL,
      updated_at          TEXT NOT NULL,
      sync_status         INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Faculties — master data for institutional faculties/schools.
  /// Managed by admins; lecturers and students assigned to faculties.
  static const String createFaculties = '''
    CREATE TABLE IF NOT EXISTS $tableFaculties (
      id              TEXT PRIMARY KEY,
      name            TEXT NOT NULL UNIQUE,
      code            TEXT NOT NULL UNIQUE,
      description     TEXT,
      contact_email   TEXT,
      head_of_faculty TEXT,
      is_active       INTEGER NOT NULL DEFAULT 1,
      created_at      TEXT NOT NULL,
      updated_at      TEXT NOT NULL,
      sync_status     INTEGER NOT NULL DEFAULT 0
    )
  ''';

  /// Courses — master data for academic courses within faculties.
  /// Linked to faculties via foreign key; managed by admins.
  static const String createCourses = '''
    CREATE TABLE IF NOT EXISTS $tableCourses (
      id          TEXT PRIMARY KEY,
      faculty_id  TEXT NOT NULL,
      name        TEXT NOT NULL,
      code        TEXT NOT NULL UNIQUE,
      description TEXT,
      is_active   INTEGER NOT NULL DEFAULT 1,
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      sync_status INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (faculty_id) REFERENCES $tableFaculties(id) ON DELETE CASCADE
    )
  ''';

  /// Posts — project posts, opportunity posts, challenges.
  /// images, videos, tags, skills_used stored as JSON arrays.
  /// visibility: 'public' | 'followers' | 'collaborators'
  /// status: 'draft' | 'pending_review' | 'published' | 'rejected' | 'archived'
  static const String createPosts = '''
    CREATE TABLE IF NOT EXISTS $tablePosts (
      id               TEXT PRIMARY KEY,
      author_id        TEXT NOT NULL,
      type             TEXT NOT NULL DEFAULT 'project',
      title            TEXT NOT NULL,
      description      TEXT,
      category         TEXT,
      faculty          TEXT,
      program          TEXT,
      tags             TEXT DEFAULT '[]',
      skills_used      TEXT DEFAULT '[]',
      images           TEXT DEFAULT '[]',
      videos           TEXT DEFAULT '[]',
      youtube_link     TEXT,
      external_links   TEXT DEFAULT '[]',
      external_link    TEXT,
      github_link      TEXT,
      visibility       TEXT NOT NULL DEFAULT 'public',
      status           TEXT NOT NULL DEFAULT 'published',
      suspicion_score  REAL NOT NULL DEFAULT 0.0,
      like_count       INTEGER NOT NULL DEFAULT 0,
      dislike_count    INTEGER NOT NULL DEFAULT 0,
      comment_count    INTEGER NOT NULL DEFAULT 0,
      share_count      INTEGER NOT NULL DEFAULT 0,
      view_count       INTEGER NOT NULL DEFAULT 0,
      is_cached        INTEGER NOT NULL DEFAULT 1,
      is_archived      INTEGER NOT NULL DEFAULT 0,
      moderation_status TEXT DEFAULT 'approved',
      trust_score      INTEGER NOT NULL DEFAULT 100,
      area_of_expertise TEXT,
      max_participants INTEGER DEFAULT 0,
      join_count       INTEGER NOT NULL DEFAULT 0,
      opportunity_deadline TEXT,
      created_at       TEXT NOT NULL,
      updated_at       TEXT NOT NULL,
      sync_status      INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (author_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Comments — nested via parent_comment_id (one level of replies).
  static const String createComments = '''
    CREATE TABLE IF NOT EXISTS $tableComments (
      id                TEXT PRIMARY KEY,
      post_id           TEXT NOT NULL,
      author_id         TEXT NOT NULL,
      parent_comment_id TEXT,
      content           TEXT NOT NULL,
      like_count        INTEGER NOT NULL DEFAULT 0,
      is_deleted        INTEGER NOT NULL DEFAULT 0,
      created_at        TEXT NOT NULL,
      updated_at        TEXT NOT NULL,
      sync_status       INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (post_id)   REFERENCES $tablePosts(id)    ON DELETE CASCADE,
      FOREIGN KEY (author_id) REFERENCES $tableUsers(id)    ON DELETE CASCADE
    )
  ''';

  /// Likes — one row per (user, post) pair.
  static const String createLikes = '''
    CREATE TABLE IF NOT EXISTS $tableLikes (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      post_id     TEXT NOT NULL,
      created_at  TEXT NOT NULL,
      sync_status INTEGER NOT NULL DEFAULT 0,
      UNIQUE (user_id, post_id),
      FOREIGN KEY (user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE,
      FOREIGN KEY (post_id) REFERENCES $tablePosts(id) ON DELETE CASCADE
    )
  ''';

  /// Dislikes — one row per (user, post) pair.
  static const String createDislikes = '''
    CREATE TABLE IF NOT EXISTS $tableDislikes (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      post_id     TEXT NOT NULL,
      created_at  TEXT NOT NULL,
      sync_status INTEGER NOT NULL DEFAULT 0,
      UNIQUE (user_id, post_id),
      FOREIGN KEY (user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE,
      FOREIGN KEY (post_id) REFERENCES $tablePosts(id) ON DELETE CASCADE
    )
  ''';

  /// Follows — follower_id follows followee_id.
  static const String createFollows = '''
    CREATE TABLE IF NOT EXISTS $tableFollows (
      id           TEXT PRIMARY KEY,
      follower_id  TEXT NOT NULL,
      followee_id  TEXT NOT NULL,
      created_at   TEXT NOT NULL,
      sync_status  INTEGER NOT NULL DEFAULT 0,
      UNIQUE (follower_id, followee_id),
      FOREIGN KEY (follower_id) REFERENCES $tableUsers(id) ON DELETE CASCADE,
      FOREIGN KEY (followee_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Collaboration Requests.
  /// status: 'pending' | 'accepted' | 'rejected' | 'cancelled'
  static const String createCollabRequests = '''
    CREATE TABLE IF NOT EXISTS $tableCollabRequests (
      id           TEXT PRIMARY KEY,
      sender_id    TEXT NOT NULL,
      receiver_id  TEXT NOT NULL,
      post_id      TEXT,
      message      TEXT,
      status       TEXT NOT NULL DEFAULT 'pending',
      responded_at TEXT,
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      sync_status  INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (sender_id)   REFERENCES $tableUsers(id) ON DELETE CASCADE,
      FOREIGN KEY (receiver_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Legacy-compatible conversations table still used by the current inbox.
  static const String createConversations = '''
    CREATE TABLE IF NOT EXISTS $tableConversations (
      id                TEXT PRIMARY KEY,
      user_id           TEXT NOT NULL,
      peer_id           TEXT NOT NULL,
      peer_name         TEXT,
      peer_photo_url    TEXT,
      last_message      TEXT,
      last_message_at   INTEGER,
      unread_count      INTEGER NOT NULL DEFAULT 0,
      is_peer_lecturer  INTEGER NOT NULL DEFAULT 0,
      created_at        TEXT,
      updated_at        TEXT,
      sync_status       INTEGER NOT NULL DEFAULT 0
    )
  ''';

  /// Message Threads — one record per conversation pair.
  static const String createMessageThreads = '''
    CREATE TABLE IF NOT EXISTS $tableMessageThreads (
      id                  TEXT PRIMARY KEY,
      participant_ids     TEXT NOT NULL,
      last_message_id     TEXT,
      last_message_text   TEXT,
      last_message_at     TEXT,
      unread_count        INTEGER NOT NULL DEFAULT 0,
      created_at          TEXT NOT NULL,
      updated_at          TEXT NOT NULL,
      sync_status         INTEGER NOT NULL DEFAULT 0
    )
  ''';

  /// Messages — individual messages within a thread.
  /// status: 'sending' | 'sent' | 'delivered' | 'read' | 'failed'
  static const String createMessages = '''
    CREATE TABLE IF NOT EXISTS $tableMessages (
      id          TEXT PRIMARY KEY,
      thread_id   TEXT NOT NULL,
      conversation_id TEXT,
      sender_id   TEXT NOT NULL,
      content     TEXT NOT NULL,
      message_type TEXT NOT NULL DEFAULT 'text',
      file_url    TEXT,
      file_name   TEXT,
      file_size   TEXT,
      media_url   TEXT,
      status      TEXT NOT NULL DEFAULT 'sending',
      created_at  INTEGER,
      sent_at     TEXT NOT NULL,
      delivered_at TEXT,
      read_at     TEXT,
      is_read        INTEGER NOT NULL DEFAULT 0,
      is_deleted     INTEGER NOT NULL DEFAULT 0,
      is_queued      INTEGER NOT NULL DEFAULT 0,
      sync_status    INTEGER NOT NULL DEFAULT 0,
      reply_to_id    TEXT,
      reply_to_preview TEXT,
      FOREIGN KEY (thread_id)  REFERENCES $tableMessageThreads(id) ON DELETE CASCADE,
      FOREIGN KEY (sender_id)  REFERENCES $tableUsers(id)          ON DELETE CASCADE
    )
  ''';

  /// Notifications.
  /// type: 'like' | 'comment' | 'follow' | 'collab_request' |
  ///        'collab_accepted' | 'message' | 'opportunity' | 'endorsement' |
  ///        'ai_streak' | 'system'
  static const String createNotifications = '''
    CREATE TABLE IF NOT EXISTS $tableNotifications (
      id                TEXT PRIMARY KEY,
      user_id           TEXT NOT NULL,
      type              TEXT NOT NULL,
      sender_id         TEXT,
      sender_name       TEXT,
      sender_photo_url  TEXT,
      body              TEXT NOT NULL,
      detail            TEXT,
      entity_id         TEXT,
      created_at        INTEGER NOT NULL,
      is_read           INTEGER NOT NULL DEFAULT 0,
      extra_json        TEXT,
      FOREIGN KEY (user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Opportunities — created by lecturers/staff.
  /// type: 'research' | 'internship' | 'job' | 'workshop' | 'event'
  static const String createOpportunities = '''
    CREATE TABLE IF NOT EXISTS $tableOpportunities (
      id               TEXT PRIMARY KEY,
      creator_id       TEXT NOT NULL,
      type             TEXT NOT NULL DEFAULT 'internship',
      title            TEXT NOT NULL,
      description      TEXT,
      organization     TEXT,
      faculty          TEXT,
      skills_required  TEXT DEFAULT '[]',
      deadline         TEXT,
      application_link TEXT,
      applicant_ids    TEXT DEFAULT '[]',
      status           TEXT NOT NULL DEFAULT 'open',
      created_at       TEXT NOT NULL,
      updated_at       TEXT NOT NULL,
      sync_status      INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (creator_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Sync Queue — offline operations waiting to be pushed to Firestore.
  /// operation: 'create' | 'update' | 'delete'
  /// entity:    table name (e.g. 'posts', 'likes', 'messages')
  /// payload:   JSON string of the data to write
  /// retry_count: number of failed sync attempts
  static const String createSyncQueue = '''
    CREATE TABLE IF NOT EXISTS $tableSyncQueue (
      id            TEXT PRIMARY KEY,
      operation     TEXT NOT NULL,
      entity        TEXT NOT NULL,
      entity_id     TEXT NOT NULL,
      payload       TEXT NOT NULL,
      retry_count   INTEGER NOT NULL DEFAULT 0,
      max_retries   INTEGER NOT NULL DEFAULT 5,
      last_error    TEXT,
      created_at    TEXT NOT NULL,
      next_retry_at TEXT
    )
  ''';

  /// Moderation Queue — flagged posts awaiting admin review.
  /// status: 'pending' | 'approved' | 'rejected'
  static const String createModerationQueue = '''
    CREATE TABLE IF NOT EXISTS $tableModerationQueue (
      id              TEXT PRIMARY KEY,
      post_id         TEXT NOT NULL,
      reporter_id     TEXT,
      reason          TEXT,
      suspicion_score REAL NOT NULL DEFAULT 0.0,
      status          TEXT NOT NULL DEFAULT 'pending',
      reviewed_by     TEXT,
      reviewed_at     TEXT,
      admin_note      TEXT,
      created_at      TEXT NOT NULL,
      sync_status     INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (post_id) REFERENCES $tablePosts(id) ON DELETE CASCADE
    )
  ''';

  /// Project Milestones — for collaboration tracking.
  /// status: 'todo' | 'in_progress' | 'done'
  static const String createProjectMilestones = '''
    CREATE TABLE IF NOT EXISTS $tableProjectMilestones (
      id          TEXT PRIMARY KEY,
      post_id     TEXT NOT NULL,
      title       TEXT NOT NULL,
      description TEXT,
      due_date    TEXT,
      status      TEXT NOT NULL DEFAULT 'todo',
      created_by  TEXT NOT NULL,
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      sync_status INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (post_id)    REFERENCES $tablePosts(id) ON DELETE CASCADE,
      FOREIGN KEY (created_by) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Tasks — individual tasks under a milestone.
  static const String createTasks = '''
    CREATE TABLE IF NOT EXISTS $tableTasks (
      id           TEXT PRIMARY KEY,
      milestone_id TEXT NOT NULL,
      title        TEXT NOT NULL,
      description  TEXT,
      assigned_to  TEXT,
      due_date     TEXT,
      is_completed INTEGER NOT NULL DEFAULT 0,
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      sync_status  INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (milestone_id) REFERENCES $tableProjectMilestones(id) ON DELETE CASCADE
    )
  ''';

  /// Endorsements — peer skill endorsements.
  static const String createEndorsements = '''
    CREATE TABLE IF NOT EXISTS $tableEndorsements (
      id           TEXT PRIMARY KEY,
      endorser_id  TEXT NOT NULL,
      endorsed_id  TEXT NOT NULL,
      skill        TEXT NOT NULL,
      message      TEXT,
      created_at   TEXT NOT NULL,
      sync_status  INTEGER NOT NULL DEFAULT 0,
      UNIQUE (endorser_id, endorsed_id, skill),
      FOREIGN KEY (endorser_id) REFERENCES $tableUsers(id) ON DELETE CASCADE,
      FOREIGN KEY (endorsed_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Activity Logs — audit trail for admin panel.
  static const String createActivityLogs = '''
    CREATE TABLE IF NOT EXISTS $tableActivityLogs (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      action      TEXT NOT NULL,
      entity_type TEXT,
      entity_id   TEXT,
      metadata    TEXT DEFAULT '{}',
      ip_address  TEXT,
      created_at  TEXT NOT NULL,
      FOREIGN KEY (user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Device Tokens — for FCM push notifications.
  static const String createDeviceTokens = '''
    CREATE TABLE IF NOT EXISTS $tableDeviceTokens (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      token       TEXT NOT NULL UNIQUE,
      platform    TEXT NOT NULL DEFAULT 'android',
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      FOREIGN KEY (user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Search History — recent searches for autocomplete.
  static const String createSearchHistory = '''
    CREATE TABLE IF NOT EXISTS $tableSearchHistory (
      id         TEXT PRIMARY KEY,
      user_id    TEXT NOT NULL,
      query      TEXT NOT NULL,
      type       TEXT NOT NULL DEFAULT 'general',
      created_at TEXT NOT NULL,
      FOREIGN KEY (user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Draft Posts — auto-saved post creation state.
  static const String createDraftPosts = '''
    CREATE TABLE IF NOT EXISTS $tableDraftPosts (
      id          TEXT PRIMARY KEY,
      author_id   TEXT NOT NULL,
      payload     TEXT NOT NULL,
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      FOREIGN KEY (author_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Achievements — student badges and certificates.
  static const String createAchievements = '''
    CREATE TABLE IF NOT EXISTS $tableAchievements (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      type        TEXT NOT NULL,
      title       TEXT NOT NULL,
      description TEXT,
      icon        TEXT,
      earned_at   TEXT NOT NULL,
      sync_status INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE
    )
  ''';

  /// Recommendation Logs — records every scored recommendation for analytics.
  /// algorithm: 'local' | 'hybrid' | 'applicant' | 'collaborator'
  /// item_type:  'post' | 'user'
  static const String createRecommendationLogs = '''
    CREATE TABLE IF NOT EXISTS $tableRecommendationLogs (
      id              TEXT PRIMARY KEY,
      user_id         TEXT NOT NULL,
      item_id         TEXT NOT NULL,
      item_type       TEXT NOT NULL,
      algorithm       TEXT NOT NULL,
      score           REAL NOT NULL DEFAULT 0.0,
      reasons         TEXT DEFAULT '[]',
      was_interacted  INTEGER NOT NULL DEFAULT 0,
      logged_at       TEXT NOT NULL,
      sync_status     INTEGER NOT NULL DEFAULT 0
    )
  ''';

  /// Post Joins — tracks which users have joined an opportunity post.
  static const String createPostJoins = '''
    CREATE TABLE IF NOT EXISTS $tablePostJoins (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      post_id     TEXT NOT NULL,
      created_at  TEXT NOT NULL,
      sync_status INTEGER NOT NULL DEFAULT 0,
      UNIQUE (user_id, post_id),
      FOREIGN KEY (user_id) REFERENCES $tableUsers(id) ON DELETE CASCADE,
      FOREIGN KEY (post_id) REFERENCES $tablePosts(id) ON DELETE CASCADE
    )
  ''';

  // ─────────────────────────────────────────────────────────────────────────
  // INDEX STATEMENTS — for frequently queried columns
  // ─────────────────────────────────────────────────────────────────────────

  static const List<String> indexes = [
    'CREATE INDEX IF NOT EXISTS idx_posts_author  ON $tablePosts(author_id)',
    'CREATE INDEX IF NOT EXISTS idx_posts_faculty ON $tablePosts(faculty)',
    'CREATE INDEX IF NOT EXISTS idx_posts_status  ON $tablePosts(status)',
    'CREATE INDEX IF NOT EXISTS idx_posts_created ON $tablePosts(created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_comments_post ON $tableComments(post_id)',
    'CREATE INDEX IF NOT EXISTS idx_conversations_user ON $tableConversations(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_conversations_time ON $tableConversations(last_message_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_messages_thread ON $tableMessages(thread_id)',
    'CREATE INDEX IF NOT EXISTS idx_messages_sent ON $tableMessages(sent_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_notif_user ON $tableNotifications(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_notif_read ON $tableNotifications(is_read)',
    'CREATE INDEX IF NOT EXISTS idx_sync_queue_retry ON $tableSyncQueue(next_retry_at)',
    'CREATE INDEX IF NOT EXISTS idx_moderation_status ON $tableModerationQueue(status)',
    'CREATE INDEX IF NOT EXISTS idx_follows_follower ON $tableFollows(follower_id)',
    'CREATE INDEX IF NOT EXISTS idx_follows_followee ON $tableFollows(followee_id)',
    'CREATE INDEX IF NOT EXISTS idx_activity_user ON $tableActivityLogs(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_post_joins_user ON $tablePostJoins(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_post_joins_post ON $tablePostJoins(post_id)',
    'CREATE INDEX IF NOT EXISTS idx_courses_faculty ON $tableCourses(faculty_id)',
    'CREATE INDEX IF NOT EXISTS idx_courses_active ON $tableCourses(is_active)',
    'CREATE INDEX IF NOT EXISTS idx_faculties_active ON $tableFaculties(is_active)',
    'CREATE INDEX IF NOT EXISTS idx_rec_logs_user ON $tableRecommendationLogs(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_rec_logs_algo ON $tableRecommendationLogs(algorithm)',
    'CREATE INDEX IF NOT EXISTS idx_rec_logs_time ON $tableRecommendationLogs(logged_at DESC)',
  ];

  // ─────────────────────────────────────────────────────────────────────────
  // ORDERED LIST OF CREATE STATEMENTS
  // DatabaseHelper.onCreate() executes these in order.
  // Foreign key order matters — parent tables must come first.
  // ─────────────────────────────────────────────────────────────────────────
  static const List<String> allCreateStatements = [
    createUsers,
    createProfiles,
    createFaculties,
    createCourses,
    createPosts,
    createComments,
    createLikes,
    createDislikes,
    createFollows,
    createCollabRequests,
    createConversations,
    createMessageThreads,
    createMessages,
    createNotifications,
    createOpportunities,
    createSyncQueue,
    createModerationQueue,
    createProjectMilestones,
    createTasks,
    createEndorsements,
    createActivityLogs,
    createDeviceTokens,
    createSearchHistory,
    createDraftPosts,
    createAchievements,
    createPostJoins,
    createRecommendationLogs,
  ];
}
