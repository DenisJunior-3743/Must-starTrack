PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE android_metadata (locale TEXT);
INSERT INTO android_metadata VALUES('en_GB');
CREATE TABLE users (
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
    );
INSERT INTO users VALUES('CuLGpb1vskOBw7DqOw7yPSdrnyD3','CuLGpb1vskOBw7DqOw7yPSdrnyD3','denisjr@staff.must.ac.ug','lecturer','Denis Junior',NULL,0,0,0,NULL,'2026-03-24T20:47:51.661867','2026-03-24T20:47:51.661867',0);
INSERT INTO users VALUES('iJYCfH2tlsOhqaxaxOifhhcn4G93','iJYCfH2tlsOhqaxaxOifhhcn4G93','2023bse151@std.must.ac.ug','student','Ainamaani Allan',NULL,0,0,0,NULL,'2026-03-17T14:43:56.580280','2026-03-17T14:43:56.580280',0);
INSERT INTO users VALUES('5ct3CxTfGdZo9x3aOvThM77FGz53','5ct3CxTfGdZo9x3aOvThM77FGz53','admin@must.ac.ug','admin','StarTrack Admin',NULL,1,0,0,NULL,'2026-03-14T16:45:16.760Z','2026-03-14T16:45:16.760Z',0);
INSERT INTO users VALUES('kFGBiK3fGZg68mDizPn60EUN9lE2','kFGBiK3fGZg68mDizPn60EUN9lE2','2023bse164@std.must.ac.ug','student','Denis Jr',NULL,0,0,0,NULL,'2026-03-17T02:14:00.142633','2026-03-17T02:14:00.142633',0);
CREATE TABLE profiles (
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
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
INSERT INTO profiles VALUES('CuLGpb1vskOBw7DqOw7yPSdrnyD3','CuLGpb1vskOBw7DqOw7yPSdrnyD3',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'Computing and Informatics','Software Engineering',NULL,'[]','{}','public',0,NULL,0,0,0,0,'2026-03-24T20:47:51.661867','2026-03-24T20:47:51.661867',0);
CREATE TABLE posts (
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
      area_of_expertise TEXT,
      max_participants INTEGER DEFAULT 0,
      join_count       INTEGER NOT NULL DEFAULT 0,
      opportunity_deadline TEXT,
      created_at       TEXT NOT NULL,
      updated_at       TEXT NOT NULL,
      sync_status      INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE
    );
CREATE TABLE comments (
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
      FOREIGN KEY (post_id)   REFERENCES posts(id)    ON DELETE CASCADE,
      FOREIGN KEY (author_id) REFERENCES users(id)    ON DELETE CASCADE
    );
CREATE TABLE likes (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      post_id     TEXT NOT NULL,
      created_at  TEXT NOT NULL,
      sync_status INTEGER NOT NULL DEFAULT 0,
      UNIQUE (user_id, post_id),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
    );
CREATE TABLE dislikes (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      post_id     TEXT NOT NULL,
      created_at  TEXT NOT NULL,
      sync_status INTEGER NOT NULL DEFAULT 0,
      UNIQUE (user_id, post_id),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
    );
CREATE TABLE follows (
      id           TEXT PRIMARY KEY,
      follower_id  TEXT NOT NULL,
      followee_id  TEXT NOT NULL,
      created_at   TEXT NOT NULL,
      sync_status  INTEGER NOT NULL DEFAULT 0,
      UNIQUE (follower_id, followee_id),
      FOREIGN KEY (follower_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (followee_id) REFERENCES users(id) ON DELETE CASCADE
    );
CREATE TABLE collab_requests (
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
      FOREIGN KEY (sender_id)   REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE
    );
INSERT INTO collab_requests VALUES('187ba39e-7f25-46fb-88ab-7a57e8b33208','kFGBiK3fGZg68mDizPn60EUN9lE2','5ct3CxTfGdZo9x3aOvThM77FGz53','e48d8420-4be9-4651-b73c-cd4f261a5652','Can I join you','pending',NULL,'2026-03-18T01:00:48.908','2026-03-18T01:00:48.908',1);
INSERT INTO collab_requests VALUES('42aae693-6589-4e33-be66-cc6e271b6600','5ct3CxTfGdZo9x3aOvThM77FGz53','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','will join you','pending',NULL,'2026-03-18T01:36:26.129','2026-03-18T01:36:26.129',1);
INSERT INTO collab_requests VALUES('56ebacfe-1fb3-4436-9c8e-aab6b39727f8','5ct3CxTfGdZo9x3aOvThM77FGz53','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','Can I join this','pending',NULL,'2026-03-18T01:43:27.431','2026-03-18T01:43:27.431',1);
INSERT INTO collab_requests VALUES('c8423321-8df3-44cd-a200-1c852ead8650','5ct3CxTfGdZo9x3aOvThM77FGz53','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','Good at vibing','pending',NULL,'2026-03-18T03:34:58.253','2026-03-18T03:34:58.253',1);
CREATE TABLE conversations (
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
    );
INSERT INTO conversations VALUES('5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','kFGBiK3fGZg68mDizPn60EUN9lE2','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'Ya man',1774373791503,0,0,'2026-03-27T22:51:39.991073','2026-03-27T22:51:40.888021',1);
INSERT INTO conversations VALUES('CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','kFGBiK3fGZg68mDizPn60EUN9lE2','CuLGpb1vskOBw7DqOw7yPSdrnyD3','Denis Junior',NULL,'Hey Denis',1774374539973,1,1,'2026-03-27T22:51:40.900919','2026-03-27T22:51:41.348246',1);
INSERT INTO conversations VALUES('iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','kFGBiK3fGZg68mDizPn60EUN9lE2','iJYCfH2tlsOhqaxaxOifhhcn4G93','Ainamaani Allan',NULL,'hello denis',1774433524397,1,0,'2026-03-27T22:51:41.354821','2026-03-27T22:51:41.835817',1);
CREATE TABLE message_threads (
      id                  TEXT PRIMARY KEY,
      participant_ids     TEXT NOT NULL,
      last_message_id     TEXT,
      last_message_text   TEXT,
      last_message_at     TEXT,
      unread_count        INTEGER NOT NULL DEFAULT 0,
      created_at          TEXT NOT NULL,
      updated_at          TEXT NOT NULL,
      sync_status         INTEGER NOT NULL DEFAULT 0
    );
INSERT INTO message_threads VALUES('5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','[kFGBiK3fGZg68mDizPn60EUN9lE2,5ct3CxTfGdZo9x3aOvThM77FGz53]',NULL,'Ya man','2026-03-24T20:36:31.503',0,'2026-03-27T22:51:40.003333','2026-03-27T22:51:40.003403',1);
INSERT INTO message_threads VALUES('CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','[kFGBiK3fGZg68mDizPn60EUN9lE2,CuLGpb1vskOBw7DqOw7yPSdrnyD3]',NULL,'Hey Denis','2026-03-24T20:48:59.973',0,'2026-03-27T22:51:40.907721','2026-03-27T22:51:40.907769',1);
INSERT INTO message_threads VALUES('iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','[kFGBiK3fGZg68mDizPn60EUN9lE2,iJYCfH2tlsOhqaxaxOifhhcn4G93]',NULL,'hello denis','2026-03-25T13:12:04.397',0,'2026-03-27T22:51:41.361605','2026-03-27T22:51:41.361658',1);
CREATE TABLE messages (
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
      is_read     INTEGER NOT NULL DEFAULT 0,
      is_deleted  INTEGER NOT NULL DEFAULT 0,
      is_queued   INTEGER NOT NULL DEFAULT 0,
      sync_status INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (thread_id)  REFERENCES message_threads(id) ON DELETE CASCADE,
      FOREIGN KEY (sender_id)  REFERENCES users(id)          ON DELETE CASCADE
    );
INSERT INTO messages VALUES('ce07e797-9755-47be-8b7e-faa2c47f9142','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3','Hey Denis','text',NULL,NULL,NULL,NULL,'sent',1774374539526,'2026-03-24T20:48:59.526',NULL,NULL,0,0,0,1);
INSERT INTO messages VALUES('bd34b424-124e-4762-95a8-726ffcf740d4','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93','hello denis','text',NULL,NULL,NULL,NULL,'sent',1774433523890,'2026-03-25T13:12:03.890',NULL,NULL,0,0,0,1);
CREATE TABLE notifications (
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
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
CREATE TABLE opportunities (
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
      FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE CASCADE
    );
CREATE TABLE sync_queue (
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
    );
CREATE TABLE moderation_queue (
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
      FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
    );
CREATE TABLE project_milestones (
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
      FOREIGN KEY (post_id)    REFERENCES posts(id) ON DELETE CASCADE,
      FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE
    );
CREATE TABLE tasks (
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
      FOREIGN KEY (milestone_id) REFERENCES project_milestones(id) ON DELETE CASCADE
    );
CREATE TABLE endorsements (
      id           TEXT PRIMARY KEY,
      endorser_id  TEXT NOT NULL,
      endorsed_id  TEXT NOT NULL,
      skill        TEXT NOT NULL,
      message      TEXT,
      created_at   TEXT NOT NULL,
      sync_status  INTEGER NOT NULL DEFAULT 0,
      UNIQUE (endorser_id, endorsed_id, skill),
      FOREIGN KEY (endorser_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (endorsed_id) REFERENCES users(id) ON DELETE CASCADE
    );
CREATE TABLE activity_logs (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      action      TEXT NOT NULL,
      entity_type TEXT,
      entity_id   TEXT,
      metadata    TEXT DEFAULT '{}',
      ip_address  TEXT,
      created_at  TEXT NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
CREATE TABLE device_tokens (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      token       TEXT NOT NULL UNIQUE,
      platform    TEXT NOT NULL DEFAULT 'android',
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
CREATE TABLE search_history (
      id         TEXT PRIMARY KEY,
      user_id    TEXT NOT NULL,
      query      TEXT NOT NULL,
      type       TEXT NOT NULL DEFAULT 'general',
      created_at TEXT NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
CREATE TABLE draft_posts (
      id          TEXT PRIMARY KEY,
      author_id   TEXT NOT NULL,
      payload     TEXT NOT NULL,
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE
    );
CREATE TABLE achievements (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      type        TEXT NOT NULL,
      title       TEXT NOT NULL,
      description TEXT,
      icon        TEXT,
      earned_at   TEXT NOT NULL,
      sync_status INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
CREATE TABLE post_joins (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      post_id     TEXT NOT NULL,
      created_at  TEXT NOT NULL,
      sync_status INTEGER NOT NULL DEFAULT 0,
      UNIQUE (user_id, post_id),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
    );
CREATE INDEX idx_posts_author  ON posts(author_id);
CREATE INDEX idx_posts_faculty ON posts(faculty);
CREATE INDEX idx_posts_status  ON posts(status);
CREATE INDEX idx_posts_created ON posts(created_at DESC);
CREATE INDEX idx_comments_post ON comments(post_id);
CREATE INDEX idx_conversations_user ON conversations(user_id);
CREATE INDEX idx_conversations_time ON conversations(last_message_at DESC);
CREATE INDEX idx_messages_thread ON messages(thread_id);
CREATE INDEX idx_messages_sent ON messages(sent_at DESC);
CREATE INDEX idx_notif_user ON notifications(user_id);
CREATE INDEX idx_notif_read ON notifications(is_read);
CREATE INDEX idx_sync_queue_retry ON sync_queue(next_retry_at);
CREATE INDEX idx_moderation_status ON moderation_queue(status);
CREATE INDEX idx_follows_follower ON follows(follower_id);
CREATE INDEX idx_follows_followee ON follows(followee_id);
CREATE INDEX idx_activity_user ON activity_logs(user_id);
CREATE INDEX idx_post_joins_user ON post_joins(user_id);
CREATE INDEX idx_post_joins_post ON post_joins(post_id);
COMMIT;