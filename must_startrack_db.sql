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
INSERT INTO users VALUES('5ct3CxTfGdZo9x3aOvThM77FGz53','5ct3CxTfGdZo9x3aOvThM77FGz53','admin@must.ac.ug','admin','StarTrack Admin',NULL,1,0,0,NULL,'2026-03-14T16:45:16.760Z','2026-03-14T16:45:16.760Z',0);
INSERT INTO users VALUES('CuLGpb1vskOBw7DqOw7yPSdrnyD3','CuLGpb1vskOBw7DqOw7yPSdrnyD3','denisjr@staff.must.ac.ug','lecturer','Denis Junior',NULL,0,0,0,NULL,'2026-03-24T20:47:51.661867','2026-03-24T20:47:51.661867',0);
INSERT INTO users VALUES('hDRagdKqtDX7jbXIQJtjCgmBnwU2','hDRagdKqtDX7jbXIQJtjCgmBnwU2','2023bse080@std.must.ac.ug','student','Oliviah Mucuurezi','https://res.cloudinary.com/dsdsjjayt/image/upload/v1775224843/avatars/nmpsdyjud428b8etzfcv.jpg',0,0,0,NULL,'2026-04-03T14:46:41.892914','2026-04-03T17:00:42.851673',0);
INSERT INTO users VALUES('iJYCfH2tlsOhqaxaxOifhhcn4G93','iJYCfH2tlsOhqaxaxOifhhcn4G93','2023bse151@std.must.ac.ug','student','Ainamaani Allan',NULL,0,0,0,NULL,'2026-03-17T14:43:56.580280','2026-03-17T14:43:56.580280',0);
INSERT INTO users VALUES('kFGBiK3fGZg68mDizPn60EUN9lE2','kFGBiK3fGZg68mDizPn60EUN9lE2','2023bse164@std.must.ac.ug','student','Denis Jr','https://res.cloudinary.com/dsdsjjayt/image/upload/v1774657455/avatars/lpgqek5mtxowzoytw0vi.jpg',0,0,0,NULL,'2026-03-17T02:14:00.142633','2026-03-28T03:24:16.365644',0);
INSERT INTO users VALUES('q4naqbIitPcctx0n7gx4dOxUyus1','q4naqbIitPcctx0n7gx4dOxUyus1','2023bse079@std.must.ac.ug','student','Mbabazi Patience',NULL,0,0,0,NULL,'2026-04-02T14:02:04.404827','2026-04-02T14:02:04.404827',0);
INSERT INTO users VALUES('4sKORV1powRlsE7UWRkPTG243Lv1','4sKORV1powRlsE7UWRkPTG243Lv1','placeholder+4sKORV1powRlsE7UWRkPTG243Lv1@must-startrack.invalid','guest','MBABAZI Patience','https://res.cloudinary.com/dsdsjjayt/image/upload/v1774945662/avatars/jhqbvyzhnbb8l3uvl3qk.jpg',0,0,0,NULL,'2026-04-09T12:28:29.821843','2026-04-09T12:28:29.821843',0);
INSERT INTO users VALUES('PX8Z7sspeHPquhOMinisyVh1wdU2','PX8Z7sspeHPquhOMinisyVh1wdU2','2023bse094@std.must.ac.ug','student','Murungi Kevin Tumaini',NULL,0,0,0,NULL,'2026-03-31T22:46:39.022805','2026-03-31T22:46:39.022805',0);
INSERT INTO users VALUES('XbONIGMyNBYKgyOeLERdEc4eLyk2','XbONIGMyNBYKgyOeLERdEc4eLyk2','2023bcs077@std.must.ac.ug','student','Muwanguzi Esther','https://res.cloudinary.com/dsdsjjayt/image/upload/v1775220882/avatars/o5ky8takvp1inmyqqnvk.jpg',0,0,0,NULL,'2026-04-03T15:33:11.901398','2026-04-03T15:55:18.456174',0);
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
INSERT INTO profiles VALUES('hDRagdKqtDX7jbXIQJtjCgmBnwU2','hDRagdKqtDX7jbXIQJtjCgmBnwU2','React developer','Female','0785774501','2023/BSE/080/PS','2023','Bachelor of Software Engineering (BSE)','Bachelor of Software Engineering (BSE)','Faculty of Computing and Informatics',NULL,3,'["react","flutter"]','{}','public',0,NULL,0,0,0,0,'2026-04-03T14:46:41.892914','2026-04-03T17:00:42.851673',0);
INSERT INTO profiles VALUES('kFGBiK3fGZg68mDizPn60EUN9lE2','kFGBiK3fGZg68mDizPn60EUN9lE2',NULL,NULL,NULL,NULL,NULL,'B.Sc. Computer Science',NULL,'Computing and Informatics',NULL,1,'[]','{}','public',0,NULL,0,0,0,0,'2026-03-28T03:24:16.365644','2026-03-28T03:24:16.365644',0);
INSERT INTO profiles VALUES('q4naqbIitPcctx0n7gx4dOxUyus1','q4naqbIitPcctx0n7gx4dOxUyus1',NULL,'Female','0785774501','2023/BSE/079/PS','2023','Bachelor of Software Engineering (BSE)','Bachelor of Software Engineering (BSE)','Faculty of Computing and Informatics',NULL,3,'["web_developer"]','{}','public',0,NULL,0,0,0,0,'2026-04-02T14:02:04.404827','2026-04-02T14:02:04.404827',0);
INSERT INTO profiles VALUES('PX8Z7sspeHPquhOMinisyVh1wdU2','PX8Z7sspeHPquhOMinisyVh1wdU2',NULL,'Male','0777555222','2023/BSE/094/PS','2023','Bachelor of Software Engineering (BSE)','Bachelor of Software Engineering (BSE)','Faculty of Computing and Informatics',NULL,3,'["programming"]','{}','public',0,NULL,0,0,0,0,'2026-03-31T22:46:39.022805','2026-03-31T22:46:39.022805',0);
INSERT INTO profiles VALUES('XbONIGMyNBYKgyOeLERdEc4eLyk2','XbONIGMyNBYKgyOeLERdEc4eLyk2','Hardware programmer','Female','0785774501','2023/BCS/077/PS','2023','Bachelor of Computer Science (BCS)','Bachelor of Computer Science (BCS)','Faculty of Computing and Informatics',NULL,3,'["Hardware_programming"]','{}','public',0,NULL,0,0,0,0,'2026-04-03T15:33:11.901398','2026-04-03T15:55:18.456174',0);
CREATE TABLE faculties (
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
    );
INSERT INTO faculties VALUES('fbd4d7d1-9682-4b44-a7ce-a324b7bbea66','Faculty of Computing and Informatics','FCI','Faculty of Computing and Informatics (FCI)',NULL,NULL,1,'2026-04-09T12:14:47.208439','2026-04-09T12:14:47.208439',0);
INSERT INTO faculties VALUES('17e0789f-ee7e-4cf1-bab4-f47d91f8ae2c','Faculty of Applied Sciences and Technology','FAST','Faculty of Applied Sciences and Technology (FAST)',NULL,NULL,1,'2026-04-09T12:14:47.321318','2026-04-09T12:14:47.321318',0);
INSERT INTO faculties VALUES('9e8359b8-1158-4e5e-8108-4a3763778577','Faculty of Business and Management Sciences','FBMS','Faculty of Business and Management Sciences (FBMS)',NULL,NULL,1,'2026-04-09T12:14:47.369207','2026-04-09T12:14:47.369207',0);
INSERT INTO faculties VALUES('cf7bdb0d-96ea-4139-8a93-7a69a5f28686','Faculty of Medicine','FOM','Faculty of Medicine (FOM)',NULL,NULL,1,'2026-04-09T12:14:47.413479','2026-04-09T12:14:47.413479',0);
CREATE TABLE courses (
      id          TEXT PRIMARY KEY,
      faculty_id  TEXT NOT NULL,
      name        TEXT NOT NULL,
      code        TEXT NOT NULL UNIQUE,
      description TEXT,
      is_active   INTEGER NOT NULL DEFAULT 1,
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      sync_status INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (faculty_id) REFERENCES faculties(id) ON DELETE CASCADE
    );
INSERT INTO courses VALUES('ab372eed-7e7b-41fd-b453-6a25221e972a','fbd4d7d1-9682-4b44-a7ce-a324b7bbea66','Bachelor of Software Engineering','BSE',NULL,1,'2026-04-09T12:14:47.284358','2026-04-09T12:14:47.284358',0);
INSERT INTO courses VALUES('2221c0f6-ad69-4f04-9945-42eb8fea16a9','fbd4d7d1-9682-4b44-a7ce-a324b7bbea66','Bachelor of Computer Science','BCS',NULL,1,'2026-04-09T12:14:47.297757','2026-04-09T12:14:47.297757',0);
INSERT INTO courses VALUES('5f554f38-fa63-4315-bdc0-0403ef6e753c','fbd4d7d1-9682-4b44-a7ce-a324b7bbea66','Bachelor of Information Technology','BIT',NULL,1,'2026-04-09T12:14:47.309041','2026-04-09T12:14:47.309041',0);
INSERT INTO courses VALUES('a0ef3588-0b19-4b8a-9698-c7e240801b30','17e0789f-ee7e-4cf1-bab4-f47d91f8ae2c','Civil Engineering','CVE',NULL,1,'2026-04-09T12:14:47.333838','2026-04-09T12:14:47.333838',0);
INSERT INTO courses VALUES('b66fd22e-ffa1-47ad-ae02-788c62b58a8d','17e0789f-ee7e-4cf1-bab4-f47d91f8ae2c','Electrical and Electronics Engineering','EEE',NULL,1,'2026-04-09T12:14:47.346757','2026-04-09T12:14:47.346757',0);
INSERT INTO courses VALUES('0133ca6b-30d2-4ae3-9dc9-1f256e41aee0','17e0789f-ee7e-4cf1-bab4-f47d91f8ae2c','Biomedical Engineering','BME',NULL,1,'2026-04-09T12:14:47.357822','2026-04-09T12:14:47.357822',0);
INSERT INTO courses VALUES('8c2b723f-a280-4615-aa46-e3fb871c0e77','9e8359b8-1158-4e5e-8108-4a3763778577','Bachelor of Science in Economics','ECO',NULL,1,'2026-04-09T12:14:47.380527','2026-04-09T12:14:47.380527',0);
INSERT INTO courses VALUES('200b089e-1d14-439f-a64e-123936359313','9e8359b8-1158-4e5e-8108-4a3763778577','Bachelor of Arts in Economics','BAE',NULL,1,'2026-04-09T12:14:47.391542','2026-04-09T12:14:47.391542',0);
INSERT INTO courses VALUES('7519f3b0-43b0-4e64-a7e3-d400c222dde9','9e8359b8-1158-4e5e-8108-4a3763778577','Bachelor of Accounting and Finance','BAF',NULL,1,'2026-04-09T12:14:47.402484','2026-04-09T12:14:47.402484',0);
INSERT INTO courses VALUES('2e9f11a6-474b-4c53-89b6-8763d7d2b7cc','cf7bdb0d-96ea-4139-8a93-7a69a5f28686','Bachelor of Medicine and Surgery','MBChB',NULL,1,'2026-04-09T12:14:47.423633','2026-04-09T12:14:47.423633',0);
INSERT INTO courses VALUES('ca53387b-0c58-4e2d-b6d6-bae44a4548f8','cf7bdb0d-96ea-4139-8a93-7a69a5f28686','Bachelor of Science in Nursing','BSN',NULL,1,'2026-04-09T12:14:47.434715','2026-04-09T12:14:47.434715',0);
INSERT INTO courses VALUES('7926de00-a5f2-4af0-a9ce-152d9497e543','cf7bdb0d-96ea-4139-8a93-7a69a5f28686','Bachelor of Public Health','BPH',NULL,1,'2026-04-09T12:14:47.445286','2026-04-09T12:14:47.445286',0);
CREATE TABLE groups (
      id              TEXT PRIMARY KEY,
      name            TEXT NOT NULL,
      description     TEXT,
      avatar_url      TEXT,
      creator_id      TEXT NOT NULL,
      creator_name    TEXT,
      member_count    INTEGER NOT NULL DEFAULT 1,
      is_dissolved    INTEGER NOT NULL DEFAULT 0,
      created_at      TEXT NOT NULL,
      updated_at      TEXT NOT NULL,
      sync_status     INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE CASCADE
    );
INSERT INTO "groups" VALUES('018044b6-7750-407e-b08e-b9aecce3ff43','BSE UNITED','FULL STACK DEVELOPER',NULL,'q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',1,0,'2026-04-02T16:20:55.385351','2026-04-09T14:06:32.533824',0);
INSERT INTO "groups" VALUES('2a568b6f-ec51-41ab-a2b8-f8b239b24b92','yy','tt',NULL,'q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',1,0,'2026-04-02T16:26:07.350966','2026-04-09T14:06:32.502788',0);
INSERT INTO "groups" VALUES('31803fc4-476d-449c-90a4-43ba249b948d','Murife Innovators','Creativity above all',NULL,'kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr',1,0,'2026-03-31T12:03:36.423269','2026-04-09T14:06:32.573261',0);
INSERT INTO "groups" VALUES('63657955-80c1-407f-933d-7e4061ea8130','hhh','hhh',NULL,'q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',1,0,'2026-04-02T18:10:45.327505','2026-04-09T14:06:32.478793',0);
INSERT INTO "groups" VALUES('8b0c7cd7-dffc-4a0b-a7d6-01a092c42e1e','Murife innovators','Creativity above all',NULL,'kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr',1,1,'2026-03-30T18:47:40.441989','2026-04-09T14:06:32.614596',0);
INSERT INTO "groups" VALUES('9c070bfb-04fa-49a7-83c7-d9d4510d63ce','BSE United','Health systems',NULL,'4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience',1,0,'2026-03-31T12:06:38.907613','2026-04-09T14:06:32.553438',0);
INSERT INTO "groups" VALUES('f5e24b02-0c47-45b9-a6fc-6a1a282b5f7f','BSE INNOVATORS','health systems',NULL,'4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience',1,0,'2026-03-31T11:37:08.518056','2026-04-09T14:06:32.590218',0);
CREATE TABLE group_members (
      id              TEXT PRIMARY KEY,
      group_id        TEXT NOT NULL,
      user_id         TEXT NOT NULL,
      user_name       TEXT,
      user_photo_url  TEXT,
      role            TEXT NOT NULL DEFAULT 'member',
      status          TEXT NOT NULL DEFAULT 'pending',
      invited_by      TEXT,
      invited_by_name TEXT,
      joined_at       TEXT,
      created_at      TEXT NOT NULL,
      updated_at      TEXT NOT NULL,
      sync_status     INTEGER NOT NULL DEFAULT 0,
      UNIQUE (group_id, user_id),
      FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
INSERT INTO group_members VALUES('018044b6-7750-407e-b08e-b9aecce3ff43_5ct3CxTfGdZo9x3aOvThM77FGz53','018044b6-7750-407e-b08e-b9aecce3ff43','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'member','pending','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'2026-04-02T16:20:55.385351','2026-04-02T16:20:55.385351',0);
INSERT INTO group_members VALUES('018044b6-7750-407e-b08e-b9aecce3ff43_CuLGpb1vskOBw7DqOw7yPSdrnyD3','018044b6-7750-407e-b08e-b9aecce3ff43','CuLGpb1vskOBw7DqOw7yPSdrnyD3','Denis Junior',NULL,'member','pending','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'2026-04-02T16:20:55.385351','2026-04-02T16:20:55.385351',0);
INSERT INTO group_members VALUES('018044b6-7750-407e-b08e-b9aecce3ff43_iJYCfH2tlsOhqaxaxOifhhcn4G93','018044b6-7750-407e-b08e-b9aecce3ff43','iJYCfH2tlsOhqaxaxOifhhcn4G93','Ainamaani Allan',NULL,'member','pending','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'2026-04-02T16:20:55.385351','2026-04-02T16:20:55.385351',0);
INSERT INTO group_members VALUES('018044b6-7750-407e-b08e-b9aecce3ff43_kFGBiK3fGZg68mDizPn60EUN9lE2','018044b6-7750-407e-b08e-b9aecce3ff43','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr','https://res.cloudinary.com/dsdsjjayt/image/upload/v1774657455/avatars/lpgqek5mtxowzoytw0vi.jpg','member','pending','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'2026-04-02T16:20:55.385351','2026-04-02T16:20:55.385351',0);
INSERT INTO group_members VALUES('018044b6-7750-407e-b08e-b9aecce3ff43_q4naqbIitPcctx0n7gx4dOxUyus1','018044b6-7750-407e-b08e-b9aecce3ff43','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'owner','active','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience','2026-04-02T16:20:55.385351','2026-04-02T16:20:55.385351','2026-04-02T16:20:55.385351',0);
INSERT INTO group_members VALUES('2a568b6f-ec51-41ab-a2b8-f8b239b24b92_iJYCfH2tlsOhqaxaxOifhhcn4G93','2a568b6f-ec51-41ab-a2b8-f8b239b24b92','iJYCfH2tlsOhqaxaxOifhhcn4G93','Ainamaani Allan',NULL,'member','pending','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'2026-04-02T16:26:07.350966','2026-04-02T16:26:07.350966',0);
INSERT INTO group_members VALUES('2a568b6f-ec51-41ab-a2b8-f8b239b24b92_q4naqbIitPcctx0n7gx4dOxUyus1','2a568b6f-ec51-41ab-a2b8-f8b239b24b92','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'owner','active','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience','2026-04-02T16:26:07.350966','2026-04-02T16:26:07.350966','2026-04-02T16:26:07.350966',0);
INSERT INTO group_members VALUES('31803fc4-476d-449c-90a4-43ba249b948d_4sKORV1powRlsE7UWRkPTG243Lv1','31803fc4-476d-449c-90a4-43ba249b948d','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience','https://res.cloudinary.com/dsdsjjayt/image/upload/v1774945662/avatars/jhqbvyzhnbb8l3uvl3qk.jpg','member','pending','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr',NULL,'2026-03-31T12:03:36.423269','2026-03-31T12:03:36.423269',0);
INSERT INTO group_members VALUES('31803fc4-476d-449c-90a4-43ba249b948d_iJYCfH2tlsOhqaxaxOifhhcn4G93','31803fc4-476d-449c-90a4-43ba249b948d','iJYCfH2tlsOhqaxaxOifhhcn4G93','Ainamaani Allan',NULL,'member','pending','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr',NULL,'2026-03-31T12:09:20.413978','2026-03-31T12:09:20.413978',0);
INSERT INTO group_members VALUES('31803fc4-476d-449c-90a4-43ba249b948d_kFGBiK3fGZg68mDizPn60EUN9lE2','31803fc4-476d-449c-90a4-43ba249b948d','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr','https://res.cloudinary.com/dsdsjjayt/image/upload/v1774657455/avatars/lpgqek5mtxowzoytw0vi.jpg','owner','active','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr','2026-03-31T12:03:36.423269','2026-03-31T12:03:36.423269','2026-03-31T12:03:36.423269',0);
INSERT INTO group_members VALUES('63657955-80c1-407f-933d-7e4061ea8130_CuLGpb1vskOBw7DqOw7yPSdrnyD3','63657955-80c1-407f-933d-7e4061ea8130','CuLGpb1vskOBw7DqOw7yPSdrnyD3','Denis Junior',NULL,'member','pending','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'2026-04-02T18:10:45.327505','2026-04-02T18:10:45.327505',0);
INSERT INTO group_members VALUES('63657955-80c1-407f-933d-7e4061ea8130_iJYCfH2tlsOhqaxaxOifhhcn4G93','63657955-80c1-407f-933d-7e4061ea8130','iJYCfH2tlsOhqaxaxOifhhcn4G93','Ainamaani Allan',NULL,'member','pending','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'2026-04-02T18:10:45.327505','2026-04-02T18:10:45.327505',0);
INSERT INTO group_members VALUES('63657955-80c1-407f-933d-7e4061ea8130_kFGBiK3fGZg68mDizPn60EUN9lE2','63657955-80c1-407f-933d-7e4061ea8130','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr','https://res.cloudinary.com/dsdsjjayt/image/upload/v1774657455/avatars/lpgqek5mtxowzoytw0vi.jpg','member','pending','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'2026-04-02T18:10:45.327505','2026-04-02T18:10:45.327505',0);
INSERT INTO group_members VALUES('63657955-80c1-407f-933d-7e4061ea8130_q4naqbIitPcctx0n7gx4dOxUyus1','63657955-80c1-407f-933d-7e4061ea8130','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'owner','active','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience','2026-04-02T18:10:45.327505','2026-04-02T18:10:45.327505','2026-04-02T18:10:45.327505',0);
INSERT INTO group_members VALUES('8b0c7cd7-dffc-4a0b-a7d6-01a092c42e1e_4sKORV1powRlsE7UWRkPTG243Lv1','8b0c7cd7-dffc-4a0b-a7d6-01a092c42e1e','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience','https://lh3.googleusercontent.com/a/ACg8ocI9LxztYtpUXj1yAbHGFZZSf36BLLefgNv1cjzQpFiQQ8a2Yw=s96-c','member','pending','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr',NULL,'2026-03-30T18:47:40.441989','2026-03-30T18:47:40.441989',0);
INSERT INTO group_members VALUES('8b0c7cd7-dffc-4a0b-a7d6-01a092c42e1e_iJYCfH2tlsOhqaxaxOifhhcn4G93','8b0c7cd7-dffc-4a0b-a7d6-01a092c42e1e','iJYCfH2tlsOhqaxaxOifhhcn4G93','Ainamaani Allan',NULL,'member','pending','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr',NULL,'2026-03-30T18:47:40.441989','2026-03-30T18:47:40.441989',0);
INSERT INTO group_members VALUES('8b0c7cd7-dffc-4a0b-a7d6-01a092c42e1e_kFGBiK3fGZg68mDizPn60EUN9lE2','8b0c7cd7-dffc-4a0b-a7d6-01a092c42e1e','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr','https://res.cloudinary.com/dsdsjjayt/image/upload/v1774657455/avatars/lpgqek5mtxowzoytw0vi.jpg','owner','active','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr','2026-03-30T18:47:40.441989','2026-03-30T18:47:40.441989','2026-03-30T18:47:40.441989',0);
INSERT INTO group_members VALUES('9c070bfb-04fa-49a7-83c7-d9d4510d63ce_4sKORV1powRlsE7UWRkPTG243Lv1','9c070bfb-04fa-49a7-83c7-d9d4510d63ce','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience','https://res.cloudinary.com/dsdsjjayt/image/upload/v1774945662/avatars/jhqbvyzhnbb8l3uvl3qk.jpg','owner','active','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience','2026-03-31T12:06:38.907613','2026-03-31T12:06:38.907613','2026-03-31T12:06:38.907613',0);
INSERT INTO group_members VALUES('9c070bfb-04fa-49a7-83c7-d9d4510d63ce_CuLGpb1vskOBw7DqOw7yPSdrnyD3','9c070bfb-04fa-49a7-83c7-d9d4510d63ce','CuLGpb1vskOBw7DqOw7yPSdrnyD3','Denis Junior',NULL,'member','pending','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience',NULL,'2026-03-31T12:06:38.907613','2026-03-31T12:06:38.907613',0);
INSERT INTO group_members VALUES('9c070bfb-04fa-49a7-83c7-d9d4510d63ce_iJYCfH2tlsOhqaxaxOifhhcn4G93','9c070bfb-04fa-49a7-83c7-d9d4510d63ce','iJYCfH2tlsOhqaxaxOifhhcn4G93','Ainamaani Allan',NULL,'member','pending','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience',NULL,'2026-03-31T12:06:38.907613','2026-03-31T12:06:38.907613',0);
INSERT INTO group_members VALUES('9c070bfb-04fa-49a7-83c7-d9d4510d63ce_kFGBiK3fGZg68mDizPn60EUN9lE2','9c070bfb-04fa-49a7-83c7-d9d4510d63ce','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr','https://res.cloudinary.com/dsdsjjayt/image/upload/v1774657455/avatars/lpgqek5mtxowzoytw0vi.jpg','member','pending','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience',NULL,'2026-03-31T12:06:38.907613','2026-03-31T12:06:38.907613',0);
INSERT INTO group_members VALUES('f5e24b02-0c47-45b9-a6fc-6a1a282b5f7f_4sKORV1powRlsE7UWRkPTG243Lv1','f5e24b02-0c47-45b9-a6fc-6a1a282b5f7f','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience','https://res.cloudinary.com/dsdsjjayt/image/upload/v1774945662/avatars/jhqbvyzhnbb8l3uvl3qk.jpg','owner','active','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience','2026-03-31T11:37:08.518056','2026-03-31T11:37:08.518056','2026-03-31T11:37:08.518056',0);
INSERT INTO group_members VALUES('f5e24b02-0c47-45b9-a6fc-6a1a282b5f7f_5ct3CxTfGdZo9x3aOvThM77FGz53','f5e24b02-0c47-45b9-a6fc-6a1a282b5f7f','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'member','pending','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience',NULL,'2026-03-31T11:57:12.867319','2026-03-31T11:57:12.867319',0);
INSERT INTO group_members VALUES('f5e24b02-0c47-45b9-a6fc-6a1a282b5f7f_CuLGpb1vskOBw7DqOw7yPSdrnyD3','f5e24b02-0c47-45b9-a6fc-6a1a282b5f7f','CuLGpb1vskOBw7DqOw7yPSdrnyD3','Denis Junior',NULL,'member','pending','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience',NULL,'2026-03-31T11:37:08.518056','2026-03-31T11:37:08.518056',0);
INSERT INTO group_members VALUES('f5e24b02-0c47-45b9-a6fc-6a1a282b5f7f_iJYCfH2tlsOhqaxaxOifhhcn4G93','f5e24b02-0c47-45b9-a6fc-6a1a282b5f7f','iJYCfH2tlsOhqaxaxOifhhcn4G93','Ainamaani Allan',NULL,'member','pending','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience',NULL,'2026-03-31T11:57:12.867319','2026-03-31T11:57:12.867319',0);
INSERT INTO group_members VALUES('f5e24b02-0c47-45b9-a6fc-6a1a282b5f7f_kFGBiK3fGZg68mDizPn60EUN9lE2','f5e24b02-0c47-45b9-a6fc-6a1a282b5f7f','kFGBiK3fGZg68mDizPn60EUN9lE2','Denis Jr','https://res.cloudinary.com/dsdsjjayt/image/upload/v1774657455/avatars/lpgqek5mtxowzoytw0vi.jpg','member','pending','4sKORV1powRlsE7UWRkPTG243Lv1','MBABAZI Patience',NULL,'2026-03-31T11:37:08.518056','2026-03-31T11:37:08.518056',0);
CREATE TABLE posts (
      id               TEXT PRIMARY KEY,
      author_id        TEXT NOT NULL,
      group_id         TEXT,
      group_name       TEXT,
      group_avatar_url TEXT,
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
      FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE SET NULL
    );
INSERT INTO posts VALUES('462bec84-d957-4088-a8ba-ba9329479f3d','hDRagdKqtDX7jbXIQJtjCgmBnwU2',NULL,NULL,NULL,'project','Symptom checker','checks symptoms','Innovation','Computing and Informatics',NULL,'[]','[]','[]','["https://res.cloudinary.com/dsdsjjayt/video/upload/v1775232495/startrack/owjdwze21mmbof26zc3b.mp4"]',NULL,'[]',NULL,NULL,'public','published',100.0,1,1,5,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-04-03T19:08:17.748','2026-04-09T14:11:53.274037',0);
INSERT INTO posts VALUES('6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','q4naqbIitPcctx0n7gx4dOxUyus1',NULL,'BSE UNITED',NULL,'project','ATTENDANCE SYSTEM','Capture attendance for your employees','Innovation','Computing and Informatics',NULL,'[]','[]','[]','["https://res.cloudinary.com/dsdsjjayt/video/upload/v1775136243/startrack/xn9fv44g5yul0sox48w6.mp4"]',NULL,'[]',NULL,NULL,'public','published',100.0,0,1,1,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-04-02T16:24:03.289','2026-04-09T14:07:12.918420',0);
INSERT INTO posts VALUES('877c237c-d52b-4971-964f-186c63415ee5','q4naqbIitPcctx0n7gx4dOxUyus1',NULL,NULL,NULL,'project','Student task Manager','Mange your daily tasks','Innovation','Computing and Informatics',NULL,'[]','[]','[]','["https://res.cloudinary.com/dsdsjjayt/video/upload/v1775135882/startrack/djbilam4gsnv05xclmqv.mp4"]',NULL,'[]',NULL,NULL,'public','published',100.0,1,1,0,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-04-02T16:18:23.277','2026-04-09T14:07:15.283009',0);
INSERT INTO posts VALUES('43857002-0470-437f-9207-805136f6168a','kFGBiK3fGZg68mDizPn60EUN9lE2',NULL,NULL,NULL,'project','Child care system','System to showcase child care techniques','Innovation','Medicine',NULL,'["nursing"]','["nursing"]','[]','["https://res.cloudinary.com/dsdsjjayt/video/upload/v1774964683/startrack/x5x9imon4bwwikdhoqdo.mp4"]',NULL,'[{"description":"Directing to child care","url":"childcare.com"}]','Directing to child care',NULL,'public','published',100.0,2,1,7,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-03-31T16:44:00.902','2026-04-09T14:07:17.916700',0);
INSERT INTO posts VALUES('6d8fabc7-1e85-4947-aa67-c6a201ae079e','CuLGpb1vskOBw7DqOw7yPSdrnyD3',NULL,NULL,NULL,'opportunity','Cyber Security','This project aims at implementing cyber security measures in a school website',NULL,'Computing and Informatics, Applied Sciences and Technology',NULL,'[]','[]','[]','[]',NULL,'[]',NULL,NULL,'public','published',100.0,0,0,0,0,0,1,0,'approved',100,'Kali Linux, Python scripting, Networking',0,0,'2026-03-31T00:00:00.000','2026-03-29T22:31:49.631','2026-04-09T14:07:19.673856',0);
INSERT INTO posts VALUES('954c2999-bea9-4ee0-ae82-49d110e65045','kFGBiK3fGZg68mDizPn60EUN9lE2',NULL,NULL,NULL,'opportunity','Examination Malpractice app','This project aims at coming up with a mobile app that students can use to cheat exms',NULL,'Computing and Informatics, Business and Management Sciences',NULL,'[]','[]','[]','[]',NULL,'[{"description":"For cheaters throughout the the world","url":"www.cheating.com"},{"description":"For plots of past papers roaming around campus","url":"www.uniplots.com"}]','For cheaters throughout the the world',NULL,'public','published',100.0,2,1,2,0,0,1,0,'approved',100,'Programming, Cheating skills and creativity',0,0,'2026-04-26T00:00:00.000','2026-03-24T20:33:58.289','2026-04-09T14:07:22.780287',0);
INSERT INTO posts VALUES('393c36d1-2c44-4f0d-a005-793414fb6e4c','5ct3CxTfGdZo9x3aOvThM77FGz53',NULL,NULL,NULL,'project','Match plots App','This app helps share plots about competitive matches','Design','Applied Sciences and Technology',NULL,'["programming"]','["programming"]','[]','[]',NULL,'[{"description":"My hosting platform ","url":"infinity free.com"}]','My hosting platform ',NULL,'public','published',100.0,0,0,0,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-03-23T01:19:16.539','2026-04-09T14:07:26.105175',0);
INSERT INTO posts VALUES('3d2c0804-622c-4a4e-ba29-8019c2a2cb77','iJYCfH2tlsOhqaxaxOifhhcn4G93',NULL,NULL,NULL,'project','Juice','I make juce','Innovation','Computing and Informatics',NULL,'[]','[]','[]','["https://res.cloudinary.com/dsdsjjayt/video/upload/v1773758118/startrack/liipckbghhvp083l51dl.mp4"]',NULL,'[]',NULL,NULL,'public','published',100.0,1,0,2,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-03-17T17:35:09.358','2026-04-09T14:07:29.458125',0);
INSERT INTO posts VALUES('d94f6d3a-a340-46b2-8ac6-309a8f4919a6','iJYCfH2tlsOhqaxaxOifhhcn4G93',NULL,NULL,NULL,'project','Alma','alma','Innovation','Computing and Informatics',NULL,'[]','[]','[]','[]',NULL,'[]',NULL,NULL,'public','published',100.0,0,0,0,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-03-17T17:32:36.902','2026-04-09T14:07:33.849423',0);
INSERT INTO posts VALUES('dd6169b3-8814-4fa9-9113-42b1d226266a','kFGBiK3fGZg68mDizPn60EUN9lE2',NULL,NULL,NULL,'project','Eating system','App for monitoring eating rate','Innovation','Computing and Informatics',NULL,'["eating"]','[]','["https://res.cloudinary.com/dsdsjjayt/image/upload/v1773747554/startrack/v8bvtcy5w1elskhmu31k.jpg","https://res.cloudinary.com/dsdsjjayt/image/upload/v1773846347/startrack/lprigg7lycbldgxz4knx.jpg"]','[]',NULL,'[]',NULL,NULL,'public','published',100.0,1,0,2,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-03-17T14:35:54.401','2026-04-09T14:07:36.852689',0);
INSERT INTO posts VALUES('e1e7e3e3-2705-4b15-a870-b4eeab0d045a','kFGBiK3fGZg68mDizPn60EUN9lE2',NULL,NULL,NULL,'project','Diet App','Application to plan daily recipes for a healthy campuser','Innovation','Computing and Informatics',NULL,'["nutrition"]','[]','["https://res.cloudinary.com/dsdsjjayt/image/upload/v1773712180/startrack/z3szelury16sq7kkym9c.jpg","https://res.cloudinary.com/dsdsjjayt/image/upload/v1773712185/startrack/acakpsdw6bvnx42jtcej.jpg","https://res.cloudinary.com/dsdsjjayt/image/upload/v1773712189/startrack/ntptkezjazojbn0xiwol.jpg"]','[]',NULL,'[]',NULL,NULL,'public','published',100.0,1,0,0,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-03-17T04:49:49.587','2026-04-09T14:07:41.589710',0);
INSERT INTO posts VALUES('be39c77c-6847-4447-8682-2ee33f3b7f44','kFGBiK3fGZg68mDizPn60EUN9lE2',NULL,NULL,NULL,'project','Dating app','Dating application for uni','Innovation','Computing and Informatics',NULL,'["programming"]','[]','[]','[]',NULL,'[]',NULL,NULL,'public','published',100.0,1,0,1,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-03-17T04:32:06.856','2026-04-09T14:07:43.552119',0);
INSERT INTO posts VALUES('e48d8420-4be9-4651-b73c-cd4f261a5652','5ct3CxTfGdZo9x3aOvThM77FGz53',NULL,NULL,NULL,'project','Thieves Tracking app','For tracking thieves','Innovation','Computing and Informatics',NULL,'[]','[]','[]','[]',NULL,'[]',NULL,NULL,'public','published',100.0,0,0,0,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-03-16T03:13:41.617','2026-04-09T14:07:47.050539',0);
INSERT INTO posts VALUES('6ff493da-2246-4416-a468-5815de0c71fd','5ct3CxTfGdZo9x3aOvThM77FGz53',NULL,NULL,NULL,'project','Church Management System','This is a mobile application for tracking church activities','Innovation','Computing and Informatics',NULL,'[]','[]','[]','[]',NULL,'[]',NULL,NULL,'public','published',100.0,0,0,0,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-03-16T03:06:51.113','2026-04-09T14:07:48.597575',0);
INSERT INTO posts VALUES('c5a17fd5-9964-493d-ade6-8d7cceed1f30','5ct3CxTfGdZo9x3aOvThM77FGz53',NULL,NULL,NULL,'project','farm','farm mgt','Innovation','Computing and Informatics',NULL,'[]','[]','[]','[]',NULL,'[]',NULL,NULL,'public','published',100.0,0,0,0,0,0,1,0,'approved',100,NULL,0,0,NULL,'2026-03-16T02:59:20.994','2026-04-09T14:07:51.726330',0);
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
INSERT INTO comments VALUES('82ae7822-cfa8-4b1f-b0db-0d97820b5c70','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','kFGBiK3fGZg68mDizPn60EUN9lE2',NULL,'wow',0,0,'2026-04-06T14:29:52.618','2026-04-06T14:29:52.618',1);
INSERT INTO comments VALUES('05a90369-f51e-4b29-9fb1-1b346ef1a39c','43857002-0470-437f-9207-805136f6168a','XbONIGMyNBYKgyOeLERdEc4eLyk2',NULL,'jjjjj',0,0,'2026-04-04T12:32:07.232','2026-04-04T12:32:07.232',1);
INSERT INTO comments VALUES('dbc38769-b459-4dc9-b1a4-83ee26e3dcee','43857002-0470-437f-9207-805136f6168a','q4naqbIitPcctx0n7gx4dOxUyus1',NULL,'hhh',0,0,'2026-04-02T18:07:07.262','2026-04-02T18:07:07.262',1);
INSERT INTO comments VALUES('45dfa4e9-8c17-4d6e-9d21-935d565ef826','43857002-0470-437f-9207-805136f6168a','q4naqbIitPcctx0n7gx4dOxUyus1',NULL,'gghhh',0,0,'2026-04-02T18:06:27.881','2026-04-02T18:06:27.881',1);
INSERT INTO comments VALUES('009d3ada-5876-44df-9942-94b08c38108b','43857002-0470-437f-9207-805136f6168a','q4naqbIitPcctx0n7gx4dOxUyus1',NULL,'hhhhh',0,0,'2026-04-02T18:06:25.246','2026-04-02T18:06:25.246',1);
INSERT INTO comments VALUES('e77c4c1e-8577-410b-9806-f9a2f268515d','43857002-0470-437f-9207-805136f6168a','q4naqbIitPcctx0n7gx4dOxUyus1',NULL,'gggg',0,0,'2026-04-02T18:06:21.925','2026-04-02T18:06:21.925',1);
INSERT INTO comments VALUES('950489b6-b53e-4ca4-87d2-bc02d5e67e88','43857002-0470-437f-9207-805136f6168a','q4naqbIitPcctx0n7gx4dOxUyus1',NULL,'Great work',0,0,'2026-04-02T15:49:39.938','2026-04-02T15:49:39.938',1);
INSERT INTO comments VALUES('38c00dd1-c89d-455b-8f57-f7deb9a98d48','43857002-0470-437f-9207-805136f6168a','q4naqbIitPcctx0n7gx4dOxUyus1',NULL,'Great work',0,0,'2026-04-02T15:46:49.439','2026-04-02T15:46:49.439',1);
INSERT INTO comments VALUES('3a77291a-f9cd-43dd-89a7-453c7ddeaab1','954c2999-bea9-4ee0-ae82-49d110e65045','PX8Z7sspeHPquhOMinisyVh1wdU2',NULL,'how does it work',0,0,'2026-04-01T13:55:49.727','2026-04-01T13:55:49.727',1);
INSERT INTO comments VALUES('f1910805-cefc-4e12-b36b-78c28336ee05','954c2999-bea9-4ee0-ae82-49d110e65045','kFGBiK3fGZg68mDizPn60EUN9lE2',NULL,'This will help students pass',0,0,'2026-03-28T11:47:13.220','2026-03-28T11:47:13.220',1);
INSERT INTO comments VALUES('7c7ea06a-380c-4e49-a5b0-6f3df0e2687c','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','4sKORV1powRlsE7UWRkPTG243Lv1',NULL,'Great work done',0,0,'2026-03-28T00:46:56.358','2026-03-28T00:46:56.358',1);
INSERT INTO comments VALUES('9de88e9c-fe8d-4ad1-b4c5-4e91b72be8af','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','4sKORV1powRlsE7UWRkPTG243Lv1',NULL,'great',0,0,'2026-03-28T00:46:31.797','2026-03-28T00:46:31.797',1);
INSERT INTO comments VALUES('356e743c-ad96-4c9e-beb7-1eb8fee6c392','dd6169b3-8814-4fa9-9113-42b1d226266a','iJYCfH2tlsOhqaxaxOifhhcn4G93',NULL,'I have noticed that I cant edit or delete my comment, atleast I should be able to edit in less than 2 min and delete at any time',0,0,'2026-03-29T10:20:31.255','2026-03-29T10:20:31.255',1);
INSERT INTO comments VALUES('50905e09-836f-4427-8764-796cefae5c8d','dd6169b3-8814-4fa9-9113-42b1d226266a','iJYCfH2tlsOhqaxaxOifhhcn4G93',NULL,'Confirm if you have seen my collaboration request on this specific project',0,0,'2026-03-29T10:19:44.951','2026-03-29T10:19:44.951',1);
INSERT INTO comments VALUES('756ddb38-d9ce-40ed-ba1f-6691293c54d0','be39c77c-6847-4447-8682-2ee33f3b7f44','5ct3CxTfGdZo9x3aOvThM77FGz53',NULL,'awesome',0,0,'2026-03-18T03:33:36.289','2026-03-18T03:33:36.289',1);
INSERT INTO comments VALUES('8ec853be-d527-4351-8e4f-b771b2a16553','462bec84-d957-4088-a8ba-ba9329479f3d','hDRagdKqtDX7jbXIQJtjCgmBnwU2',NULL,'thank you',0,0,'2026-04-04T14:31:18.407','2026-04-04T14:31:18.407',1);
INSERT INTO comments VALUES('7588c440-abba-4642-9268-f74c89bfc1c8','462bec84-d957-4088-a8ba-ba9329479f3d','kFGBiK3fGZg68mDizPn60EUN9lE2',NULL,'Project is cool',0,0,'2026-04-04T14:14:26.143','2026-04-04T14:14:26.143',1);
INSERT INTO comments VALUES('4a5a4cd1-0126-4d20-9311-6739c38883e6','462bec84-d957-4088-a8ba-ba9329479f3d','XbONIGMyNBYKgyOeLERdEc4eLyk2',NULL,'I look forward to collaborating with you',0,0,'2026-04-04T12:32:54.222','2026-04-04T12:32:54.222',1);
INSERT INTO comments VALUES('78fbe15c-0d5e-4804-b71f-b89b342f3228','462bec84-d957-4088-a8ba-ba9329479f3d','XbONIGMyNBYKgyOeLERdEc4eLyk2',NULL,'symptom checker is a really nice idea',0,0,'2026-04-04T12:32:42.299','2026-04-04T12:32:42.299',1);
INSERT INTO comments VALUES('b2057f9b-e467-4cf7-9082-bcd1419c6000','462bec84-d957-4088-a8ba-ba9329479f3d','XbONIGMyNBYKgyOeLERdEc4eLyk2',NULL,'your  work looks great',0,0,'2026-04-04T12:32:38.763','2026-04-04T12:32:38.763',1);
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
INSERT INTO likes VALUES('kFGBiK3fGZg68mDizPn60EUN9lE2','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','1774970963583',1);
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
INSERT INTO follows VALUES('kFGBiK3fGZg68mDizPn60EUN9lE2_5ct3CxTfGdZo9x3aOvThM77FGz53','kFGBiK3fGZg68mDizPn60EUN9lE2','5ct3CxTfGdZo9x3aOvThM77FGz53','2026-03-18T01:00:48.298',1);
INSERT INTO follows VALUES('kFGBiK3fGZg68mDizPn60EUN9lE2_hDRagdKqtDX7jbXIQJtjCgmBnwU2','kFGBiK3fGZg68mDizPn60EUN9lE2','hDRagdKqtDX7jbXIQJtjCgmBnwU2','2026-04-04T14:48:34.076',1);
INSERT INTO follows VALUES('kFGBiK3fGZg68mDizPn60EUN9lE2_q4naqbIitPcctx0n7gx4dOxUyus1','kFGBiK3fGZg68mDizPn60EUN9lE2','q4naqbIitPcctx0n7gx4dOxUyus1','2026-04-06T14:29:49.771',1);
INSERT INTO follows VALUES('5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2','5ct3CxTfGdZo9x3aOvThM77FGz53','kFGBiK3fGZg68mDizPn60EUN9lE2','2026-03-18T03:33:22.709',1);
INSERT INTO follows VALUES('XbONIGMyNBYKgyOeLERdEc4eLyk2_kFGBiK3fGZg68mDizPn60EUN9lE2','XbONIGMyNBYKgyOeLERdEc4eLyk2','kFGBiK3fGZg68mDizPn60EUN9lE2','2026-04-04T12:31:52.916',1);
INSERT INTO follows VALUES('iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2','iJYCfH2tlsOhqaxaxOifhhcn4G93','kFGBiK3fGZg68mDizPn60EUN9lE2','2026-03-29T10:18:50.223',1);
INSERT INTO follows VALUES('kFGBiK3fGZg68mDizPn60EUN9lE2_kFGBiK3fGZg68mDizPn60EUN9lE2','kFGBiK3fGZg68mDizPn60EUN9lE2','kFGBiK3fGZg68mDizPn60EUN9lE2','2026-03-18T01:00:47.739',1);
INSERT INTO follows VALUES('q4naqbIitPcctx0n7gx4dOxUyus1_kFGBiK3fGZg68mDizPn60EUN9lE2','q4naqbIitPcctx0n7gx4dOxUyus1','kFGBiK3fGZg68mDizPn60EUN9lE2','2026-04-02T15:51:28.214',1);
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
INSERT INTO collab_requests VALUES('5885f4b6-d5fd-41ac-8c17-3b55c38fe419','kFGBiK3fGZg68mDizPn60EUN9lE2','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','Would like to join this','accepted','2026-03-28T12:25:08.191445','2026-03-28T12:23:33.630','2026-04-09T14:08:13.761434',1);
INSERT INTO collab_requests VALUES('kFGBiK3fGZg68mDizPn60EUN9lE2_6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032_1775306113214','kFGBiK3fGZg68mDizPn60EUN9lE2','q4naqbIitPcctx0n7gx4dOxUyus1','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','would like to be part of this','pending',NULL,'2026-04-06T14:29:53.950','2026-04-06T14:29:53.950',1);
INSERT INTO collab_requests VALUES('1ffa5967-ff6c-4811-9da3-760916d699f1','4sKORV1powRlsE7UWRkPTG243Lv1','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','I want to collaborate','pending',NULL,'2026-03-31T12:55:43.732','2026-03-31T12:55:43.732',1);
INSERT INTO collab_requests VALUES('42aae693-6589-4e33-be66-cc6e271b6600','5ct3CxTfGdZo9x3aOvThM77FGz53','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','will join you','rejected','2026-03-28T11:49:15.524558','2026-03-18T01:36:26.129','2026-04-09T14:08:13.859730',1);
INSERT INTO collab_requests VALUES('56ebacfe-1fb3-4436-9c8e-aab6b39727f8','5ct3CxTfGdZo9x3aOvThM77FGz53','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','Can I join this','accepted','2026-03-28T11:49:02.527300','2026-03-18T01:43:27.431','2026-04-09T14:08:13.893306',1);
INSERT INTO collab_requests VALUES('7a8d48e7-991b-4ce6-9d70-4fec251d022f','PX8Z7sspeHPquhOMinisyVh1wdU2','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','I would like to collaborate','pending',NULL,'2026-04-01T13:56:07.338','2026-04-01T13:56:07.338',1);
INSERT INTO collab_requests VALUES('b057bd72-795c-41f2-b28a-6afd16717aae','q4naqbIitPcctx0n7gx4dOxUyus1','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','hh','pending',NULL,'2026-04-02T15:51:47.263','2026-04-02T15:51:47.263',1);
INSERT INTO collab_requests VALUES('c5b31051-4b4c-4adc-bfda-ff2caebd7968','4sKORV1powRlsE7UWRkPTG243Lv1','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','gggggg','pending',NULL,'2026-03-31T12:55:41.547','2026-03-31T12:55:41.547',1);
INSERT INTO collab_requests VALUES('c7d9b337-5943-48b8-aa73-ad876811697f','q4naqbIitPcctx0n7gx4dOxUyus1','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','developer ... software engineer','pending',NULL,'2026-04-02T15:50:11.756','2026-04-02T15:50:11.756',1);
INSERT INTO collab_requests VALUES('c8423321-8df3-44cd-a200-1c852ead8650','5ct3CxTfGdZo9x3aOvThM77FGz53','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','Good at vibing','accepted','2026-03-28T11:48:29.910416','2026-03-18T03:34:58.253','2026-04-09T14:08:14.069372',1);
INSERT INTO collab_requests VALUES('daaa1990-13d0-4beb-8cfa-9811643617a3','iJYCfH2tlsOhqaxaxOifhhcn4G93','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','Hello Denis, I request to collaborate on this project. Am good at eating','pending',NULL,'2026-03-29T10:19:18.511','2026-03-29T10:19:18.511',1);
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
INSERT INTO conversations VALUES('5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','kFGBiK3fGZg68mDizPn60EUN9lE2','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'Ya man',1774373791503,0,0,'2026-04-09T14:06:36.465137','2026-04-09T14:06:39.485412',1);
INSERT INTO conversations VALUES('CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','kFGBiK3fGZg68mDizPn60EUN9lE2','CuLGpb1vskOBw7DqOw7yPSdrnyD3','Denis Junior',NULL,'Voice message (00:05)',1774795356087,0,1,'2026-04-09T14:06:39.493184','2026-04-09T14:06:40.086392',1);
INSERT INTO conversations VALUES('PX8Z7sspeHPquhOMinisyVh1wdU2_kFGBiK3fGZg68mDizPn60EUN9lE2_1775040769701','kFGBiK3fGZg68mDizPn60EUN9lE2','PX8Z7sspeHPquhOMinisyVh1wdU2','Murungi Kevin Tumaini',NULL,'I can see you are online',1775040924771,3,0,'2026-04-09T14:06:40.093508','2026-04-09T14:06:42.309785',1);
INSERT INTO conversations VALUES('iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','kFGBiK3fGZg68mDizPn60EUN9lE2','iJYCfH2tlsOhqaxaxOifhhcn4G93','Ainamaani Allan',NULL,'alright',1774795972903,0,0,'2026-04-09T14:06:42.317330','2026-04-09T14:06:44.872079',1);
INSERT INTO conversations VALUES('q4naqbIitPcctx0n7gx4dOxUyus1_kFGBiK3fGZg68mDizPn60EUN9lE2_1775135669520','kFGBiK3fGZg68mDizPn60EUN9lE2','q4naqbIitPcctx0n7gx4dOxUyus1','Mbabazi Patience',NULL,'good evening',1775135681756,2,0,'2026-04-09T14:06:44.881530','2026-04-09T14:06:45.402609',1);
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
INSERT INTO message_threads VALUES('5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','[kFGBiK3fGZg68mDizPn60EUN9lE2,5ct3CxTfGdZo9x3aOvThM77FGz53]',NULL,'Ya man','2026-03-24T20:36:31.503',0,'2026-04-09T14:06:36.474404','2026-04-09T14:06:36.474456',1);
INSERT INTO message_threads VALUES('CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','[kFGBiK3fGZg68mDizPn60EUN9lE2,CuLGpb1vskOBw7DqOw7yPSdrnyD3]',NULL,'Voice message (00:05)','2026-03-29T17:42:36.087',0,'2026-04-09T14:06:39.503377','2026-04-09T14:06:39.503413',1);
INSERT INTO message_threads VALUES('PX8Z7sspeHPquhOMinisyVh1wdU2_kFGBiK3fGZg68mDizPn60EUN9lE2_1775040769701','[kFGBiK3fGZg68mDizPn60EUN9lE2,PX8Z7sspeHPquhOMinisyVh1wdU2]',NULL,'I can see you are online','2026-04-01T13:55:24.771',0,'2026-04-09T14:06:40.102774','2026-04-09T14:06:40.102821',1);
INSERT INTO message_threads VALUES('iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','[kFGBiK3fGZg68mDizPn60EUN9lE2,iJYCfH2tlsOhqaxaxOifhhcn4G93]',NULL,'alright','2026-03-29T17:52:52.903',0,'2026-04-09T14:06:42.330830','2026-04-09T14:06:42.330861',1);
INSERT INTO message_threads VALUES('q4naqbIitPcctx0n7gx4dOxUyus1_kFGBiK3fGZg68mDizPn60EUN9lE2_1775135669520','[kFGBiK3fGZg68mDizPn60EUN9lE2,q4naqbIitPcctx0n7gx4dOxUyus1]',NULL,'good evening','2026-04-02T16:14:41.756',0,'2026-04-09T14:06:44.889197','2026-04-09T14:06:44.889227',1);
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
      is_read        INTEGER NOT NULL DEFAULT 0,
      is_deleted     INTEGER NOT NULL DEFAULT 0,
      is_queued      INTEGER NOT NULL DEFAULT 0,
      sync_status    INTEGER NOT NULL DEFAULT 0,
      reply_to_id    TEXT,
      reply_to_preview TEXT,
      FOREIGN KEY (thread_id)  REFERENCES message_threads(id) ON DELETE CASCADE,
      FOREIGN KEY (sender_id)  REFERENCES users(id)          ON DELETE CASCADE
    );
INSERT INTO messages VALUES('e675222b-6979-41b2-aea6-e10c2be82a74','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53','Alright , it''s well, you can join','text',NULL,NULL,NULL,NULL,'read',1773872090686,'2026-03-19T01:14:50.686',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('9020fad8-f52b-4b91-a19b-e64ee4d6f745','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53','Man, seriously u can''t join us','text',NULL,NULL,NULL,NULL,'read',1773872091381,'2026-03-19T01:14:51.381',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('f0eafa69-8183-4fd5-8d28-12028ab68cc6','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53','You''re welcome please','text',NULL,NULL,NULL,NULL,'read',1773872092458,'2026-03-19T01:14:52.458',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('3c7e6ebb-2733-45cf-9a72-555e48202b2e','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53','We shall see','text',NULL,NULL,NULL,NULL,'read',1773872176253,'2026-03-19T01:16:16.253',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('b0a9977a-4393-4026-b5df-bdd947dd5868','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53','Hahaha','text',NULL,NULL,NULL,NULL,'read',1773872290834,'2026-03-19T01:18:10.834',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('6471aaa9-71d5-455c-bb65-f8c36669b1d1','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53','most welcome bro','text',NULL,NULL,NULL,NULL,'read',1773873129238,'2026-03-19T01:32:09.238',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('a31f86ee-415b-461e-abc7-916d24244131','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2_1773870330146','kFGBiK3fGZg68mDizPn60EUN9lE2','Ya man','text',NULL,NULL,NULL,NULL,'sent',1774373791024,'2026-03-24T20:36:31.024',NULL,NULL,0,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('ce07e797-9755-47be-8b7e-faa2c47f9142','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3','Hey Denis','text',NULL,NULL,NULL,NULL,'read',1774374539526,'2026-03-24T20:48:59.526',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('1db2d591-abc3-4b82-8204-36666a809cdd','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3','Voice message (00:05)','audio','https://res.cloudinary.com/dsdsjjayt/video/upload/v1774790672/chat_audio/ndgd1nh3uwducgquosvj.mp4','voice_1774790662316.m4a','45518','https://res.cloudinary.com/dsdsjjayt/video/upload/v1774790672/chat_audio/ndgd1nh3uwducgquosvj.mp4','read',1774790674060,'2026-03-29T16:24:34.060',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('9fdbe0f7-1a10-4161-8afd-892f6d95829e','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3','Voice message (00:02)','audio','https://res.cloudinary.com/dsdsjjayt/video/upload/v1774790704/chat_audio/nm5dkxqyve5vjafs56wc.mp4','voice_1774790697022.m4a','24687','https://res.cloudinary.com/dsdsjjayt/video/upload/v1774790704/chat_audio/nm5dkxqyve5vjafs56wc.mp4','read',1774790706483,'2026-03-29T16:25:06.483',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('f9dd8add-cc87-40f9-a9bf-1185e958dfa7','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3','Voice message (00:00)','audio','https://res.cloudinary.com/dsdsjjayt/video/upload/v1774790709/chat_audio/pnrifkxiackmsvdlbq4t.mp4','voice_1774790702236.m4a','10754','https://res.cloudinary.com/dsdsjjayt/video/upload/v1774790709/chat_audio/pnrifkxiackmsvdlbq4t.mp4','read',1774790711105,'2026-03-29T16:25:11.105',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('4c1b4c53-99c4-451b-a9b6-2c5c93cb0906','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','kFGBiK3fGZg68mDizPn60EUN9lE2','Voice message (00:12)','audio','https://res.cloudinary.com/dsdsjjayt/video/upload/v1774793738/chat_audio/kthpze8zxpa6ze9nomrx.mp4','voice_1774793721763.m4a','103302','https://res.cloudinary.com/dsdsjjayt/video/upload/v1774793738/chat_audio/kthpze8zxpa6ze9nomrx.mp4','read',1774793740997,'2026-03-29T17:15:40.997',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('c749afb7-4113-403c-bbbb-45229e604482','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','CuLGpb1vskOBw7DqOw7yPSdrnyD3_kFGBiK3fGZg68mDizPn60EUN9lE2_1774374531618','kFGBiK3fGZg68mDizPn60EUN9lE2','Voice message (00:05)','audio','https://res.cloudinary.com/dsdsjjayt/video/upload/v1774795353/chat_audio/nrnbhb5ibbn4sul49yh3.mp4','voice_1774795341650.m4a','48717','https://res.cloudinary.com/dsdsjjayt/video/upload/v1774795353/chat_audio/nrnbhb5ibbn4sul49yh3.mp4','read',1774795355630,'2026-03-29T17:42:35.630',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('8381f205-623c-494a-a9b5-a8d6909319af','PX8Z7sspeHPquhOMinisyVh1wdU2_kFGBiK3fGZg68mDizPn60EUN9lE2_1775040769701','PX8Z7sspeHPquhOMinisyVh1wdU2_kFGBiK3fGZg68mDizPn60EUN9lE2_1775040769701','PX8Z7sspeHPquhOMinisyVh1wdU2','hello Denis','text',NULL,NULL,NULL,NULL,'sent',1775040793998,'2026-04-01T13:53:13.998',NULL,NULL,0,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('81930d8f-a1d1-4ef1-b7b8-b74f3620fd56','PX8Z7sspeHPquhOMinisyVh1wdU2_kFGBiK3fGZg68mDizPn60EUN9lE2_1775040769701','PX8Z7sspeHPquhOMinisyVh1wdU2_kFGBiK3fGZg68mDizPn60EUN9lE2_1775040769701','PX8Z7sspeHPquhOMinisyVh1wdU2','how are you doing','text',NULL,NULL,NULL,NULL,'sent',1775040923264,'2026-04-01T13:55:23.264',NULL,NULL,0,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('3da2e2b1-b5fe-407f-88fd-2820b258ce80','PX8Z7sspeHPquhOMinisyVh1wdU2_kFGBiK3fGZg68mDizPn60EUN9lE2_1775040769701','PX8Z7sspeHPquhOMinisyVh1wdU2_kFGBiK3fGZg68mDizPn60EUN9lE2_1775040769701','PX8Z7sspeHPquhOMinisyVh1wdU2','I can see you are online','text',NULL,NULL,NULL,NULL,'sent',1775040924294,'2026-04-01T13:55:24.294',NULL,NULL,0,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('bd34b424-124e-4762-95a8-726ffcf740d4','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93','hello denis','text',NULL,NULL,NULL,NULL,'read',1774433523890,'2026-03-25T13:12:03.890',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('48a12432-ef9e-400b-a45a-7c6e93c3ff40','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','kFGBiK3fGZg68mDizPn60EUN9lE2','Hello Alma','text',NULL,NULL,NULL,NULL,'read',1774687964191,'2026-03-28T11:52:44.191',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('2b3134d1-298f-4b11-8cb8-7929f29ec0eb','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93','the inbox works well','text',NULL,NULL,NULL,NULL,'read',1774768556341,'2026-03-29T10:15:56.341',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('e69cec4c-d49e-47e5-a7db-beea9b52e8e5','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93','there are a few fixes left like detecting that the app is off-line and removing the online badge from the user. but the 1 tick is okay','text',NULL,NULL,NULL,NULL,'read',1774768604940,'2026-03-29T10:16:44.940',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('1d4ee124-11c5-4df0-ac1a-596baf12372f','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93','the also voice notes need fixing.','text',NULL,NULL,NULL,NULL,'read',1774768605975,'2026-03-29T10:16:45.975',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('690a0b8c-7661-46da-a952-ac6dfc866446','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93','the conversation menu is also not implemented. so we agreed that I switch to front end modifications. I will design the menu and you will integrate the back end of it','text',NULL,NULL,NULL,NULL,'read',1774768607016,'2026-03-29T10:16:47.016',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('0e605b51-fd2e-464e-ae9f-9a9523b73ac5','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93','then I also want to know if messages sent come in correct order. like the one sent last shouldn''t arrive first at the recipient side','text',NULL,NULL,NULL,NULL,'read',1774768608026,'2026-03-29T10:16:48.026',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('7c506ae1-911c-4a44-9a30-13a44234217e','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93','then the chat screen has a problem, it shows an old message instead of current one. I think the chat head should have the last sent message with its time stamp and its status of delivery (sent, read, delivered)','text',NULL,NULL,NULL,NULL,'read',1774768688204,'2026-03-29T10:18:08.204',NULL,NULL,1,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('2f8f38d7-4c93-4b28-bce6-1509393f8677','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','kFGBiK3fGZg68mDizPn60EUN9lE2','Alright ,, am trying several fixes hete and there','text',NULL,NULL,NULL,NULL,'sent',1774795317289,'2026-03-29T17:41:57.289',NULL,NULL,0,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('85e0907b-14f1-4092-bd60-6c0b5310d21f','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','kFGBiK3fGZg68mDizPn60EUN9lE2','messages come in order','text',NULL,NULL,NULL,NULL,'sent',1774795483442,'2026-03-29T17:44:43.442',NULL,NULL,0,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('ba4128a4-f0e4-418d-8e11-7361fc6b3659','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','iJYCfH2tlsOhqaxaxOifhhcn4G93_kFGBiK3fGZg68mDizPn60EUN9lE2_1774433517676','kFGBiK3fGZg68mDizPn60EUN9lE2','alright','text',NULL,NULL,NULL,NULL,'sent',1774795972378,'2026-03-29T17:52:52.378',NULL,NULL,0,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('9ed4a2b5-aec9-4fac-a1e0-5dc2ca98e262','q4naqbIitPcctx0n7gx4dOxUyus1_kFGBiK3fGZg68mDizPn60EUN9lE2_1775135669520','q4naqbIitPcctx0n7gx4dOxUyus1_kFGBiK3fGZg68mDizPn60EUN9lE2_1775135669520','q4naqbIitPcctx0n7gx4dOxUyus1','hey','text',NULL,NULL,NULL,NULL,'sent',1775135675125,'2026-04-02T16:14:35.125',NULL,NULL,0,0,0,1,NULL,NULL);
INSERT INTO messages VALUES('eba9a7f7-ec13-4e87-aca9-1a92f1f92dfb','q4naqbIitPcctx0n7gx4dOxUyus1_kFGBiK3fGZg68mDizPn60EUN9lE2_1775135669520','q4naqbIitPcctx0n7gx4dOxUyus1_kFGBiK3fGZg68mDizPn60EUN9lE2_1775135669520','q4naqbIitPcctx0n7gx4dOxUyus1','good evening','text',NULL,NULL,NULL,NULL,'sent',1775135681031,'2026-04-02T16:14:41.031',NULL,NULL,0,0,0,1,NULL,NULL);
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
INSERT INTO notifications VALUES('collab_notif_c8423321-8df3-44cd-a200-1c852ead8650','kFGBiK3fGZg68mDizPn60EUN9lE2','collaboration','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin sent you a collaboration request for "Dating app"','Good at vibing','c8423321-8df3-44cd-a200-1c852ead8650',1773794099724,1,'{"accepted":true}');
INSERT INTO notifications VALUES('comment_756ddb38-d9ce-40ed-ba1f-6691293c54d0','kFGBiK3fGZg68mDizPn60EUN9lE2','comment','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin commented on "Dating app"','awesome','be39c77c-6847-4447-8682-2ee33f3b7f44',1773794016994,1,NULL);
INSERT INTO notifications VALUES('follow_5ct3CxTfGdZo9x3aOvThM77FGz53_kFGBiK3fGZg68mDizPn60EUN9lE2','kFGBiK3fGZg68mDizPn60EUN9lE2','follow','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin started following you',NULL,'kFGBiK3fGZg68mDizPn60EUN9lE2',1773794003273,1,NULL);
INSERT INTO notifications VALUES('view_5ct3CxTfGdZo9x3aOvThM77FGz53_be39c77c-6847-4447-8682-2ee33f3b7f44','kFGBiK3fGZg68mDizPn60EUN9lE2','view','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin viewed "Dating app"',NULL,'be39c77c-6847-4447-8682-2ee33f3b7f44',1773793994496,1,NULL);
INSERT INTO notifications VALUES('comment_5e933aa4-6228-4e57-84b1-9e46b1745e7e','kFGBiK3fGZg68mDizPn60EUN9lE2','comment','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin commented on "Pilao monitoring app"','It''s awesome','80cfeed3-e743-44c9-a827-d3e2b634d757',1773793958730,1,NULL);
INSERT INTO notifications VALUES('view_5ct3CxTfGdZo9x3aOvThM77FGz53_80cfeed3-e743-44c9-a827-d3e2b634d757','kFGBiK3fGZg68mDizPn60EUN9lE2','view','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin viewed "Pilao monitoring app"',NULL,'80cfeed3-e743-44c9-a827-d3e2b634d757',1773791744383,1,NULL);
INSERT INTO notifications VALUES('like_5ct3CxTfGdZo9x3aOvThM77FGz53_80cfeed3-e743-44c9-a827-d3e2b634d757','kFGBiK3fGZg68mDizPn60EUN9lE2','like','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin liked "Pilao monitoring app"',NULL,'80cfeed3-e743-44c9-a827-d3e2b634d757',1773790404060,1,NULL);
INSERT INTO notifications VALUES('view_5ct3CxTfGdZo9x3aOvThM77FGz53_dd6169b3-8814-4fa9-9113-42b1d226266a','kFGBiK3fGZg68mDizPn60EUN9lE2','view','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin viewed "Eating system"',NULL,'dd6169b3-8814-4fa9-9113-42b1d226266a',1773790086945,1,NULL);
INSERT INTO notifications VALUES('view_5ct3CxTfGdZo9x3aOvThM77FGz53_e1e7e3e3-2705-4b15-a870-b4eeab0d045a','kFGBiK3fGZg68mDizPn60EUN9lE2','view','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin viewed "Diet App"',NULL,'e1e7e3e3-2705-4b15-a870-b4eeab0d045a',1773790086448,1,NULL);
INSERT INTO notifications VALUES('like_5ct3CxTfGdZo9x3aOvThM77FGz53_dd6169b3-8814-4fa9-9113-42b1d226266a','kFGBiK3fGZg68mDizPn60EUN9lE2','like','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin liked "Eating system"',NULL,'dd6169b3-8814-4fa9-9113-42b1d226266a',1773789740718,1,NULL);
INSERT INTO notifications VALUES('collab_notif_56ebacfe-1fb3-4436-9c8e-aab6b39727f8','kFGBiK3fGZg68mDizPn60EUN9lE2','collaboration','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin sent you a collaboration request for "Diet App"','Can I join this','56ebacfe-1fb3-4436-9c8e-aab6b39727f8',1773787408891,1,'{"accepted":true}');
INSERT INTO notifications VALUES('collab_notif_42aae693-6589-4e33-be66-cc6e271b6600','kFGBiK3fGZg68mDizPn60EUN9lE2','collaboration','5ct3CxTfGdZo9x3aOvThM77FGz53','StarTrack Admin',NULL,'StarTrack Admin sent you a collaboration request for "Diet App"','will join you','42aae693-6589-4e33-be66-cc6e271b6600',1773786987242,1,'{"accepted":false}');
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
INSERT INTO sync_queue VALUES('3a6d7183-cbd9-4a50-853a-6eedf60d39f3','create','recommendation_logs','1f30af4b-86ee-4798-b60e-f6105fd824af','{"id":"1f30af4b-86ee-4798-b60e-f6105fd824af","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"462bec84-d957-4088-a8ba-ba9329479f3d","item_type":"post","algorithm":"hybrid","score":0.2771071428571429,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.006465','2026-04-09T14:06:07.006469');
INSERT INTO sync_queue VALUES('4a35fc9b-f53e-4f1f-9b75-4f99353c1043','create','recommendation_logs','3d5e8612-c154-4f09-861d-d78893c37ed6','{"id":"3d5e8612-c154-4f09-861d-d78893c37ed6","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032","item_type":"post","algorithm":"hybrid","score":0.2581607142857143,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.032189','2026-04-09T14:06:07.032192');
INSERT INTO sync_queue VALUES('c87e8cb9-87ad-477a-ba9e-844854cb6785','create','recommendation_logs','e15c49ab-96fd-42cc-a346-ed37eceb7937','{"id":"e15c49ab-96fd-42cc-a346-ed37eceb7937","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"877c237c-d52b-4971-964f-186c63415ee5","item_type":"post","algorithm":"hybrid","score":0.2566607142857143,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.274747','2026-04-09T14:06:07.274751');
INSERT INTO sync_queue VALUES('a940bcdd-5171-4c16-86ac-b2c8f6904466','create','recommendation_logs','fbee2897-04fd-4b9b-ac56-b57c4b844496','{"id":"fbee2897-04fd-4b9b-ac56-b57c4b844496","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"3d2c0804-622c-4a4e-ba29-8019c2a2cb77","item_type":"post","algorithm":"hybrid","score":0.1945,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.734534','2026-04-09T14:06:07.734540');
INSERT INTO sync_queue VALUES('b405991a-f80b-4e98-83db-2678cdc1dea1','create','recommendation_logs','1c0bd066-dc34-48ec-8491-eeb5bfd661e2','{"id":"1c0bd066-dc34-48ec-8491-eeb5bfd661e2","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"dd6169b3-8814-4fa9-9113-42b1d226266a","item_type":"post","algorithm":"hybrid","score":0.1945,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.775828','2026-04-09T14:06:07.775832');
INSERT INTO sync_queue VALUES('586afec1-3464-4f0d-b76c-de7e9773e520','create','recommendation_logs','0d2ff149-1dc9-42ab-999c-0fa2b8af65cf','{"id":"0d2ff149-1dc9-42ab-999c-0fa2b8af65cf","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"be39c77c-6847-4447-8682-2ee33f3b7f44","item_type":"post","algorithm":"hybrid","score":0.1925,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.817004','2026-04-09T14:06:07.817009');
INSERT INTO sync_queue VALUES('25fdfbd3-a5b3-4f3b-a5b0-754ad23220eb','create','recommendation_logs','c78d18fd-ff58-48aa-8ee8-2a5a742082cc','{"id":"c78d18fd-ff58-48aa-8ee8-2a5a742082cc","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"e1e7e3e3-2705-4b15-a870-b4eeab0d045a","item_type":"post","algorithm":"hybrid","score":0.1905,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.838530','2026-04-09T14:06:07.838534');
INSERT INTO sync_queue VALUES('896aa7be-04df-4c7a-badf-c774ed319b3c','create','recommendation_logs','9c107cf6-5944-46f1-8b54-58a09b8213d1','{"id":"9c107cf6-5944-46f1-8b54-58a09b8213d1","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"d94f6d3a-a340-46b2-8ac6-309a8f4919a6","item_type":"post","algorithm":"hybrid","score":0.19,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.874173','2026-04-09T14:06:07.874177');
INSERT INTO sync_queue VALUES('6802eb0d-cd22-40ea-ba19-07ce2a7c7158','create','recommendation_logs','84e766e6-5e5c-43bf-8367-b757710d5f65','{"id":"84e766e6-5e5c-43bf-8367-b757710d5f65","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"e48d8420-4be9-4651-b73c-cd4f261a5652","item_type":"post","algorithm":"hybrid","score":0.19,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.897523','2026-04-09T14:06:07.897528');
INSERT INTO sync_queue VALUES('caabb140-d8c2-4078-a726-ef9ea3a500ec','create','recommendation_logs','6fd661cc-f60a-490f-8367-e720c32265a3','{"id":"6fd661cc-f60a-490f-8367-e720c32265a3","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"6ff493da-2246-4416-a468-5815de0c71fd","item_type":"post","algorithm":"hybrid","score":0.19,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.926054','2026-04-09T14:06:07.926059');
INSERT INTO sync_queue VALUES('3471ca97-1c9a-4e80-a386-86207724a2a4','create','recommendation_logs','0ff7eb2b-3891-426c-aacc-b2c3865ce55f','{"id":"0ff7eb2b-3891-426c-aacc-b2c3865ce55f","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"c5a17fd5-9964-493d-ade6-8d7cceed1f30","item_type":"post","algorithm":"hybrid","score":0.19,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.942653','2026-04-09T14:06:07.942669');
INSERT INTO sync_queue VALUES('7f6e6fe3-089d-48f6-96f3-91dee0a8b9d2','create','recommendation_logs','689c2edd-e1ea-44bf-8f83-677f51bf6c90','{"id":"689c2edd-e1ea-44bf-8f83-677f51bf6c90","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"43857002-0470-437f-9207-805136f6168a","item_type":"post","algorithm":"hybrid","score":0.11258928571428573,"reasons":"[]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.971745','2026-04-09T14:06:07.971749');
INSERT INTO sync_queue VALUES('0301efda-45f3-4f44-82a7-7687bb7c8cb0','create','recommendation_logs','61a410a9-c538-493a-8c75-aefcbce3f0a7','{"id":"61a410a9-c538-493a-8c75-aefcbce3f0a7","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"6d8fabc7-1e85-4947-aa67-c6a201ae079e","item_type":"post","algorithm":"hybrid","score":0.08133928571428573,"reasons":"[]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:07.994733','2026-04-09T14:06:07.994739');
INSERT INTO sync_queue VALUES('fe540e06-f522-4980-b0a9-06848be45408','create','recommendation_logs','5de9fcf4-4667-4b66-91dc-af0133e438df','{"id":"5de9fcf4-4667-4b66-91dc-af0133e438df","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"954c2999-bea9-4ee0-ae82-49d110e65045","item_type":"post","algorithm":"hybrid","score":0.05500000000000001,"reasons":"[]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:08.049702','2026-04-09T14:06:08.049706');
INSERT INTO sync_queue VALUES('f6c0f305-1b5e-47b3-88bd-565abc9694fe','create','recommendation_logs','70ca2c8b-8293-40ec-9e39-2e3ceb91d7ee','{"id":"70ca2c8b-8293-40ec-9e39-2e3ceb91d7ee","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"393c36d1-2c44-4f0d-a005-793414fb6e4c","item_type":"post","algorithm":"hybrid","score":0.05,"reasons":"[]","was_interacted":0,"logged_at":"2026-04-09T14:06:05.464281","sync_status":0}',0,5,NULL,'2026-04-09T14:06:08.072788','2026-04-09T14:06:08.072792');
INSERT INTO sync_queue VALUES('32170f1e-9f1e-43d6-aaa1-0343958e9093','create','recommendation_logs','77a00d62-6cae-4590-8b03-7e0ccffa51dd','{"id":"77a00d62-6cae-4590-8b03-7e0ccffa51dd","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"462bec84-d957-4088-a8ba-ba9329479f3d","item_type":"post","algorithm":"hybrid","score":0.2721071428571429,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:17.692557','2026-04-09T14:08:17.692567');
INSERT INTO sync_queue VALUES('f6af39d8-1a55-4859-80fc-7e0ee6fb78a0','create','recommendation_logs','1e0cfc23-88c7-46c9-9b10-62911994ee89','{"id":"1e0cfc23-88c7-46c9-9b10-62911994ee89","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032","item_type":"post","algorithm":"hybrid","score":0.2571607142857143,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:17.731030','2026-04-09T14:08:17.731034');
INSERT INTO sync_queue VALUES('86545a6d-87bc-4b85-a4d0-fd247c16c12a','create','recommendation_logs','3d43da4f-3bcc-44b1-84f7-f5d1a4f01282','{"id":"3d43da4f-3bcc-44b1-84f7-f5d1a4f01282","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"877c237c-d52b-4971-964f-186c63415ee5","item_type":"post","algorithm":"hybrid","score":0.2566607142857143,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:17.808087','2026-04-09T14:08:17.808090');
INSERT INTO sync_queue VALUES('e2fc1bad-8e15-4c05-9487-9b77497d4c9f','create','recommendation_logs','d249fc44-8bc8-4c9b-a670-5f5c9b69ccff','{"id":"d249fc44-8bc8-4c9b-a670-5f5c9b69ccff","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"3d2c0804-622c-4a4e-ba29-8019c2a2cb77","item_type":"post","algorithm":"hybrid","score":0.1925,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:17.837803','2026-04-09T14:08:17.837807');
INSERT INTO sync_queue VALUES('3c68f909-1931-44f9-b76d-c11a3c607e29','create','recommendation_logs','8948a81b-18bc-4448-a9ce-d3b253253335','{"id":"8948a81b-18bc-4448-a9ce-d3b253253335","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"dd6169b3-8814-4fa9-9113-42b1d226266a","item_type":"post","algorithm":"hybrid","score":0.1925,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:17.856966','2026-04-09T14:08:17.856971');
INSERT INTO sync_queue VALUES('01776ca8-e156-49bd-8aec-ea201dfda09f','create','recommendation_logs','c2920940-ee14-4227-976e-49da6a8964c3','{"id":"c2920940-ee14-4227-976e-49da6a8964c3","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"be39c77c-6847-4447-8682-2ee33f3b7f44","item_type":"post","algorithm":"hybrid","score":0.1915,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:17.886103','2026-04-09T14:08:17.886107');
INSERT INTO sync_queue VALUES('eec9aa06-80d4-4fa3-8d1c-9c405fb7ef54','create','recommendation_logs','3f83ec8e-6214-4b5c-9106-a7e41f08ad12','{"id":"3f83ec8e-6214-4b5c-9106-a7e41f08ad12","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"e1e7e3e3-2705-4b15-a870-b4eeab0d045a","item_type":"post","algorithm":"hybrid","score":0.1905,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:17.918068','2026-04-09T14:08:17.918073');
INSERT INTO sync_queue VALUES('c7ebca23-66de-446a-aefb-dec4e9ecba3e','create','recommendation_logs','cbd43873-65ac-434a-85d8-d167d2a8c5f3','{"id":"cbd43873-65ac-434a-85d8-d167d2a8c5f3","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"d94f6d3a-a340-46b2-8ac6-309a8f4919a6","item_type":"post","algorithm":"hybrid","score":0.19,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:17.928749','2026-04-09T14:08:17.928753');
INSERT INTO sync_queue VALUES('64a3c2f4-493b-4586-8a01-03f19d4c6511','create','recommendation_logs','31d2e6d0-2b77-4084-97e7-161766d206c1','{"id":"31d2e6d0-2b77-4084-97e7-161766d206c1","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"e48d8420-4be9-4651-b73c-cd4f261a5652","item_type":"post","algorithm":"hybrid","score":0.19,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:17.945455','2026-04-09T14:08:17.945458');
INSERT INTO sync_queue VALUES('2f790404-9a5a-4b08-98a2-9f18fac7e02c','create','recommendation_logs','d6d8528e-6126-47b4-a308-4ae6aab4daf3','{"id":"d6d8528e-6126-47b4-a308-4ae6aab4daf3","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"6ff493da-2246-4416-a468-5815de0c71fd","item_type":"post","algorithm":"hybrid","score":0.19,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:17.977942','2026-04-09T14:08:17.977947');
INSERT INTO sync_queue VALUES('d53860e7-6bea-42d4-a634-9737048f631d','create','recommendation_logs','e2f6767a-dc56-4f72-80ef-4aa9a7fabaff','{"id":"e2f6767a-dc56-4f72-80ef-4aa9a7fabaff","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"c5a17fd5-9964-493d-ade6-8d7cceed1f30","item_type":"post","algorithm":"hybrid","score":0.19,"reasons":"[\"faculty_match\"]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:17.995365','2026-04-09T14:08:17.995369');
INSERT INTO sync_queue VALUES('15d756d9-dd9a-437b-bec2-58a9ebecd9a8','create','recommendation_logs','a5dd6ba9-1ea6-4d2a-a6c4-e5207211f80a','{"id":"a5dd6ba9-1ea6-4d2a-a6c4-e5207211f80a","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"43857002-0470-437f-9207-805136f6168a","item_type":"post","algorithm":"hybrid","score":0.10558928571428572,"reasons":"[]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:18.009910','2026-04-09T14:08:18.009949');
INSERT INTO sync_queue VALUES('ad7aa145-9682-442c-a0a0-7535652fd98f','create','recommendation_logs','74a69cb5-10a0-412e-ab66-72f25d6569c8','{"id":"74a69cb5-10a0-412e-ab66-72f25d6569c8","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"6d8fabc7-1e85-4947-aa67-c6a201ae079e","item_type":"post","algorithm":"hybrid","score":0.08133928571428573,"reasons":"[]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:18.027942','2026-04-09T14:08:18.027981');
INSERT INTO sync_queue VALUES('3c18ca81-4cc7-4bb2-9e90-cdb28cb4af2a','create','recommendation_logs','36df6cfd-5c6d-4541-a231-1958141f1d23','{"id":"36df6cfd-5c6d-4541-a231-1958141f1d23","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"954c2999-bea9-4ee0-ae82-49d110e65045","item_type":"post","algorithm":"hybrid","score":0.053000000000000005,"reasons":"[]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:18.044766','2026-04-09T14:08:18.044770');
INSERT INTO sync_queue VALUES('cca6e483-167a-4c3f-828f-332173c39a01','create','recommendation_logs','830a2b63-0d74-43b0-a64b-b10ad11a54d4','{"id":"830a2b63-0d74-43b0-a64b-b10ad11a54d4","user_id":"kFGBiK3fGZg68mDizPn60EUN9lE2","item_id":"393c36d1-2c44-4f0d-a005-793414fb6e4c","item_type":"post","algorithm":"hybrid","score":0.05,"reasons":"[]","was_interacted":0,"logged_at":"2026-04-09T14:08:17.256775","sync_status":0}',0,5,NULL,'2026-04-09T14:08:18.062904','2026-04-09T14:08:18.062910');
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
INSERT INTO activity_logs VALUES('cc0f3d2d-bdb8-433f-a1dc-08daa991b1da','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T12:28:21.217649');
INSERT INTO activity_logs VALUES('834efead-bcf5-4f60-ab81-90374486546b','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T12:31:03.656987');
INSERT INTO activity_logs VALUES('f32af0bf-abe8-4191-9dbd-e84bff2f1fdd','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T12:32:17.252252');
INSERT INTO activity_logs VALUES('731b08e1-ac62-4a34-9c86-480df77b9530','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T12:34:41.323216');
INSERT INTO activity_logs VALUES('14ed32e2-67b6-46d1-8d50-e36cb2776e79','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T12:34:43.023593');
INSERT INTO activity_logs VALUES('1ee665ca-4b8a-45d2-a454-81df954b9221','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_filter_applied','posts',NULL,'{"from":{"faculty":null,"type":null,"groupsOnly":false,"followingOnly":false,"searchedUserId":null},"to":{"faculty":null,"type":"project","groupsOnly":false,"followingOnly":false,"searchedUserId":null,"searchedUserName":null}}',NULL,'2026-04-09T13:02:07.286352');
INSERT INTO activity_logs VALUES('3052c32c-235e-4909-85cb-df327347c656','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":13}',NULL,'2026-04-09T13:02:09.787022');
INSERT INTO activity_logs VALUES('ff52710e-f897-4f19-9c8f-f0de065ec927','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_filter_applied','posts',NULL,'{"from":{"faculty":null,"type":"project","groupsOnly":false,"followingOnly":false,"searchedUserId":null},"to":{"faculty":"Faculty of Business and Management Sciences","type":null,"groupsOnly":false,"followingOnly":false,"searchedUserId":null,"searchedUserName":null}}',NULL,'2026-04-09T13:03:20.631807');
INSERT INTO activity_logs VALUES('b1889d7a-65d1-4451-bdad-099359ec3d47','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T13:15:24.650722');
INSERT INTO activity_logs VALUES('50971e16-6971-49d2-b387-1b896fb420fd','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T13:16:40.855185');
INSERT INTO activity_logs VALUES('a0641b75-6505-428c-a675-fcef30c61fca','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_filter_applied','posts',NULL,'{"from":{"faculty":null,"type":null,"groupsOnly":false,"followingOnly":false,"searchedUserId":null},"to":{"faculty":null,"type":null,"groupsOnly":false,"followingOnly":true,"searchedUserId":null,"searchedUserName":null}}',NULL,'2026-04-09T13:16:41.079574');
INSERT INTO activity_logs VALUES('db939894-8a8d-49f6-af94-792c8252518b','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T13:36:07.984470');
INSERT INTO activity_logs VALUES('c436249a-7d76-488e-bd21-fcd50ab447d0','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T13:37:49.603185');
INSERT INTO activity_logs VALUES('87d4ccb8-287b-46e4-b718-2c5566ed876f','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T13:38:21.707068');
INSERT INTO activity_logs VALUES('a83cf5b3-aae0-4ac5-bded-d43366fcd631','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T13:38:32.462537');
INSERT INTO activity_logs VALUES('0dfad9c2-649f-437d-9f33-e4a14de25593','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T13:51:00.384800');
INSERT INTO activity_logs VALUES('e7398271-62e6-474c-9262-4a853d62eeb8','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_filter_applied','posts',NULL,'{"from":{"faculty":null,"type":null,"groupsOnly":false,"followingOnly":false,"searchedUserId":null},"to":{"faculty":null,"type":null,"groupsOnly":false,"followingOnly":true,"searchedUserId":null,"searchedUserName":null}}',NULL,'2026-04-09T13:51:38.148515');
INSERT INTO activity_logs VALUES('7bd507db-09b2-4540-aeb7-d1d5544a576f','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T14:06:05.433735');
INSERT INTO activity_logs VALUES('8d22fae6-314b-44c4-b8db-30dc0e33b08a','kFGBiK3fGZg68mDizPn60EUN9lE2','feed_fairness_injected','posts',NULL,'{"strategy":"cross_faculty_video_3_to_1","movedSlots":2,"candidateCount":15}',NULL,'2026-04-09T14:08:17.235749');
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
INSERT INTO post_joins VALUES('kFGBiK3fGZg68mDizPn60EUN9lE2_954c2999-bea9-4ee0-ae82-49d110e65045','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','2026-03-28T11:46:37.668',1);
CREATE TABLE recommendation_logs (
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
    );
INSERT INTO recommendation_logs VALUES('44275aa5-3b68-4004-9c3b-f77f4a710084','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2669940476190476586,'["faculty_match"]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('359117a1-1fd3-400f-ac56-e823f100846d','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2565476190476190243,'["faculty_match"]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('183b2347-3761-4eb5-8729-96879fc8a250','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2565476190476190243,'["faculty_match"]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('60189d53-dc6c-4849-8507-33b95710def1','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1955000000000000071,'["faculty_match"]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('5f9cb8ee-a51a-4a94-a6ad-2be23d804ffd','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('a9813144-247c-4ea6-8a0e-b95240d7e4f9','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('d91fdaa4-2364-4c01-ba55-9e57674d05e7','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('7c3e9ca4-00da-46a6-958e-741b02529c8b','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('7d2c20ce-5da1-4b5e-9933-bc785433f8b7','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('e8cac5f9-ae79-422c-994d-0bbb157b011d','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('e50ffc6e-cd5b-4a8e-8f5d-690a39bb42b1','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('e66ffe06-b76b-4d69-8bb6-55034a2faf82','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.0983630952380952494,'[]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('8fcd808a-e3a7-4f5f-861f-dae192a76edc','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08211309523809523503,'[]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('1e8fcd1d-896c-4391-a88e-8eb003f6551e','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('ce9f760f-a0af-450f-9e0c-5b2f725a46bc','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T12:28:21.319721',0);
INSERT INTO recommendation_logs VALUES('140ccf20-1b94-4a12-bac1-2578aa1e0f9a','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2724940476190476635,'["faculty_match"]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('1b57a74e-c3cd-4eba-b712-0a049373cdaf','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2575476190476190252,'["faculty_match"]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('4f7915b5-db2a-47e0-b93d-cebe6d247785','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2570476190476190248,'["faculty_match"]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('7677d665-3e94-47ed-ad8c-e039542fe3c6','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('cb129ee1-34ea-4d15-a185-3124d612fa18','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('394232a7-f3a9-483a-bbe2-c9d37cc6e13a','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('7b700039-4a27-423e-91ca-366c0951b660','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('32cb15de-e83d-4553-bef5-76ea2c313c48','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('ac4bc3f9-efa5-4b4f-aba5-0253f10ac77e','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('2faab5f4-f8f0-4a03-8ce3-4ab0bcc2463d','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('e6b00dfe-fb35-479d-a8cb-143010b301a9','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('b86aeb20-2ae7-45e7-9ef3-cea0dda8ae5f','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1063630952380952566,'[]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('7dde22be-20f1-47d2-a07e-56f0bbbd02f8','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08211309523809523503,'[]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('0d0dce8b-7109-4115-8ff0-9be9869d912a','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('c81b6aae-bb25-43e3-8fd8-dce7e9133ab9','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T12:31:03.687113',0);
INSERT INTO recommendation_logs VALUES('586f9790-51fc-40dd-9c1d-5030c3d562af','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2669940476190476586,'["faculty_match"]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('9d580ada-9d0c-4a49-9c96-e62aa9624b60','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2565476190476190243,'["faculty_match"]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('907cfa04-53a2-4c55-b045-438e485b735b','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2565476190476190243,'["faculty_match"]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('b03ee64d-9aad-40bc-a486-fb91da9b1909','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1955000000000000071,'["faculty_match"]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('550fbe61-cb1a-40cc-88b0-8f078bc93bed','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('21918c86-4a83-4efd-8f86-621489d7272b','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('85e60746-6b68-42d9-a259-f21cd10eed15','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('65dd7e8c-e1ed-4c68-b822-b3db484124ea','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('f2002507-3024-4bfb-97bc-6b5250cd1d8d','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('93054a74-e55e-4d7d-99c0-67c4dbdcabfa','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('f74a15cd-4244-4b32-aac0-871a4a4741db','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('8740963c-be5f-493f-b323-b5e873e5a4a7','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.0983630952380952494,'[]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('e95e9360-e9d7-4a58-a5b6-fdfe1eab3f80','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08172619047619048005,'[]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('181bd07b-8165-400c-a3aa-59363b0a713a','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('cdccd1d6-7286-45d5-af8b-76200f661e46','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T12:32:17.312001',0);
INSERT INTO recommendation_logs VALUES('33942b6d-a7ea-46a9-b994-25c49156b064','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2724940476190476635,'["faculty_match"]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('a020da56-50b0-40b2-93e2-2cf4170e6017','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2575476190476190252,'["faculty_match"]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('94165fa9-3083-4f02-a519-e57215f022eb','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2570476190476190248,'["faculty_match"]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('b8f6d625-a897-4c77-b6c1-4bf6b7d76a13','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('fc94aa91-d210-44f9-b91f-133b3ea6b664','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('899197d5-a14a-4870-b795-6115cd8c1e97','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('09212caa-9ade-4835-9c61-d7e1fd6dc512','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('7f219ea2-ba84-43a4-8ef3-68cfb5e176ea','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('15aa6705-8b3e-467d-bd88-c3f3821affcb','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('c0d476e5-3482-4c92-8131-f96b668b0cb5','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('7ea011e4-5eb1-4e0d-b8bc-50ac4396fb7f','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('2441f621-44fb-4496-b5ce-187524ab0644','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1063630952380952566,'[]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('90a69a40-ddad-47c9-800c-72029049d8c4','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08172619047619048005,'[]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('5bf457d8-2749-489a-bcc5-4c112b0e6361','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('5d2497ec-23e6-4bba-aeb7-7abd159a36e5','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T12:34:41.344139',0);
INSERT INTO recommendation_logs VALUES('d49f716c-bd4b-415a-a245-aaaaef152464','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2724940476190476635,'["faculty_match"]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('17a085de-be7c-4579-ba7e-f0d40d44a3cf','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2575476190476190252,'["faculty_match"]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('4e57dcea-e92c-4d70-8eb4-8dafeab46340','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2570476190476190248,'["faculty_match"]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('ccb8bf1d-551e-470f-96f8-2abe994c3bc0','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('efb3cdd7-2720-48a6-812c-e571f31ac7a3','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('448a476b-7a0b-41b6-b2ed-9767cd057f74','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('0d1d9128-a9de-4518-b58f-3fc0753ce94a','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('25b68349-ce04-4172-a555-10d500821819','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('c071da0b-b317-4dbc-aa60-06c40912e0d0','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('25b80c2d-a378-40d9-84cf-07dd6da02f38','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('d1a7d2b5-b8be-4db7-9187-d43def2cede3','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('94a68e32-dcdf-4efa-b640-2f7e777a96f9','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1063630952380952566,'[]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('e9a541d6-7ea5-4255-bc89-06f71e87a435','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08172619047619048005,'[]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('744b4479-3256-480a-8d7b-d656dc9beaa7','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('f18b3146-e03a-42ee-b013-5e8004ddbfeb','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T12:34:43.078785',0);
INSERT INTO recommendation_logs VALUES('d87def29-3f8a-4a63-8659-2cd751adf2dd','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2669940476190476586,'["faculty_match"]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('506d73a0-bbe3-4bb2-8fb8-3e5d81cc552f','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2565476190476190243,'["faculty_match"]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('ad7617bb-9e17-4a57-bcc3-104515e76e1d','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2565476190476190243,'["faculty_match"]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('ff079e91-30a8-4f42-97c9-883f87123551','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1955000000000000071,'["faculty_match"]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('6528708c-68c3-463f-8b52-c4a7b645d300','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('b0a2069f-489b-470c-82e1-b03f4c574a6e','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('3a619364-b2ea-4b1d-973f-4d55e8080523','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('1b324365-d4c6-4fb5-9afb-f22947efcb10','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('1a147e78-7888-4b82-8e0b-61b46c7b8fca','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('0b31c0d1-16f1-486c-953d-7fac36ff3baf','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('62fa974e-1053-4aa0-be5a-0fd18fa19e99','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('13730897-6a1e-4a79-835d-e7025ff766a0','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.0979761904761904806,'[]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('187db24f-4a26-4513-8f9c-ebcc871d56c7','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:02:09.821784',0);
INSERT INTO recommendation_logs VALUES('ef65ea74-2e5e-4b72-9c9e-9a32562d5551','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2721071428571428808,'["faculty_match"]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('7fbd17a1-f0e2-43a3-a635-98ec341fa7e7','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2575476190476190252,'["faculty_match"]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('cb22e049-a5e0-42b4-8a0b-fbb1647fa0e8','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2570476190476190248,'["faculty_match"]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('9b28a885-4244-44be-a85d-1a8b520cbd2d','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('7886f6d2-4d87-4a0e-94c9-d7ef899a0969','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('bc95c582-936c-448f-8956-e64a5bbba5ad','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('56856ba8-f365-4e7a-a249-5972a449c020','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('9e2fed7e-1180-4818-b0b5-1dad86d76456','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('c5f59b77-f5bf-46f3-a8c0-2ec438775d33','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('0b51250c-fbd8-4203-bac2-7b4ba6d8323b','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('58f466f8-8cb1-4191-b0ea-90f30ecf758a','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('49656756-54fd-4941-b3f8-d55f7b0093ed','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1059761904761904739,'[]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('9c8dd0a7-20fa-4881-a3ad-2a5858f99e50','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08172619047619048005,'[]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('b6b435a7-2790-473e-8f43-d3b991f1b032','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('f02ac86e-ffd4-4170-bac8-3569560898d2','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:15:24.674869',0);
INSERT INTO recommendation_logs VALUES('58ff24ba-65a0-44d9-9f6d-68bf437ad97d','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2721071428571428808,'["faculty_match"]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('57674982-429e-466a-a006-f97b9073ec26','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2575476190476190252,'["faculty_match"]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('e51d7549-a634-4deb-bb80-1d6b05e5801a','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2570476190476190248,'["faculty_match"]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('2d80f96d-6ee1-4734-83d0-68ef137b6957','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('6cefa04c-055e-47ba-9ef3-a5ff92f65317','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('b94cb330-bca5-4aa4-8bff-3fcbef08bc91','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('f29434e2-450d-4e6d-8463-745ec31a0c53','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('c9e09e17-8897-4b57-b390-0af41c4ac9d3','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('00af7422-9a3e-40b1-8509-20009b3dd271','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('8001cc29-930b-4e19-892e-2aeddb7f7b5c','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('340c0f9c-5500-40e1-82b0-f580d0f9751b','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('5b262ad3-3ddc-4f2a-9265-a5de22c6826c','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1059761904761904739,'[]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('2a5688bc-fe3e-4e32-985a-8f2d36e2d0f0','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08172619047619048005,'[]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('b58a4ff9-4221-4446-ad1c-d2837da7ea4b','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('6fe5354a-d85d-4229-9d6e-f5108c60a9c5','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:16:40.897619',0);
INSERT INTO recommendation_logs VALUES('5f1b8d41-a2d7-484e-a98c-caccae2f4daf','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2721071428571428808,'["faculty_match"]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('97d1cad9-d1a8-4913-aacb-6984dc861ba2','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2575476190476190252,'["faculty_match"]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('6d8d844b-41c3-47dc-9d9a-22715370c37e','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2570476190476190248,'["faculty_match"]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('c572eb7f-60a1-4918-8932-a897e37c639f','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('c3155e4d-cbf3-4c56-b4b5-d5689e5f3afe','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('e348fd62-12b9-4912-b615-9d4f837ce8b0','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('41990480-281d-48c5-98f7-10df438deadc','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('0d20058a-ac02-4e59-985d-306cc506f6c0','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('a6c4a72c-240b-4e3b-8c85-fb92adbe55ce','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('69563b16-5a55-456e-9f07-befba26a02e5','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1059761904761904739,'[]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('0df2f9a7-6794-43e0-9113-6d68a7e48d19','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('9527d6b3-b341-40af-9f03-667daae99125','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:16:41.701598',0);
INSERT INTO recommendation_logs VALUES('67ccd72d-9846-4c73-90a0-290772ca94ba','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2721071428571428808,'["faculty_match"]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('1796740a-5686-4a27-883a-47345ca9ee74','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2575476190476190252,'["faculty_match"]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('824d2fc8-613c-499a-ae6c-690c683fc2b9','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2570476190476190248,'["faculty_match"]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('741acae4-f1ea-4704-a701-1bb570951c14','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('6d087931-ee3c-49a2-b4ef-d2f6d94bb1d7','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('9f7800fc-9246-43bf-b285-f9286e972dfd','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('13563782-8548-4a2d-bfac-fbccf7590e4b','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('04868c9c-f845-419b-a4ac-9b5e3c02cb88','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('fe5cf007-162d-42dd-ab92-7a426636b25a','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('6a0e63a3-3fbb-427b-96ae-14e99bbea47f','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1059761904761904739,'[]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('51facc81-8d09-436b-93ee-abd035904267','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('29031fe9-2239-48c6-bf8b-8d7703d189de','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:17:47.431853',0);
INSERT INTO recommendation_logs VALUES('32604b26-cadb-4615-b7e6-0022858ddf2a','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2721071428571428808,'["faculty_match"]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('37aefa72-a23a-48cb-a810-bef287edc901','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.257160714285714298,'["faculty_match"]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('a118916f-befe-473c-bba8-cb42c9ae4277','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2566607142857142975,'["faculty_match"]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('02631a06-e7db-4a90-a235-5bcb242df69f','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('a8afcdfe-2089-4226-a656-457c416e6518','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('1e010316-c449-4d49-bd5c-1ecf6aa53eb9','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('b3f36650-7cfe-4673-85f8-7e54dfd7bea0','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('910a58da-36da-41fb-a454-3fb000faa119','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('5c81220f-3143-4396-b86d-ab0b5aea6216','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('f814affc-8a7e-4aaa-b8c8-07bbc4f21bfb','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('832d46d7-e473-407b-9b6b-a4118cc2d5b5','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('6dc2399f-8d8e-40c2-bab8-80a30065b6a9','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1059761904761904739,'[]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('f8f045f1-5d28-4d11-a00c-e61de5c36881','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08133928571428572507,'[]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('d51a7c21-59c1-4e19-9e22-a7ca1218c065','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('7b1af568-f923-4ded-abc8-aabcd84c6de0','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:36:08.117883',0);
INSERT INTO recommendation_logs VALUES('6b743829-969b-40b6-ab24-e0ca9c858b48','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2721071428571428808,'["faculty_match"]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('3a5cf93e-02b6-4337-ae19-72102f5ea5e9','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.257160714285714298,'["faculty_match"]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('48cdeea5-d622-482b-919e-92f856d6b2de','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2566607142857142975,'["faculty_match"]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('b46b8011-4aad-4950-be05-e7454520c671','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('8bc07778-3f2d-441c-b7dd-2ecc09e4bd0b','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('3d6b33db-17c0-4e2e-889e-38385b171fc4','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('aa73c5c2-a42f-49bb-a9f4-375178276928','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('9234e58e-8cdd-4144-89ae-e35fac077de6','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('af954758-cd22-463f-a1e2-008c4158949c','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('4d49356f-6894-43eb-8e5f-aa5c6481f6a0','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('1d6dd9dd-3454-4a76-8ff7-4ec445f91e70','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('885398ab-d11f-46fb-bc26-978ddb81eadc','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1059761904761904739,'[]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('379b0809-e75e-49ac-b87e-d0c427747bfb','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08133928571428572507,'[]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('e6aca41e-f3a6-447e-90fa-c4c322ddd117','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('7e76b24f-1cf8-459e-aa99-c6aff2fce815','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:37:49.629674',0);
INSERT INTO recommendation_logs VALUES('5203af50-640f-4049-ada6-64414cc550e9','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2721071428571428808,'["faculty_match"]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('23aa4887-eca2-4346-95ad-938d33e76728','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.257160714285714298,'["faculty_match"]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('fb754caa-2748-4c75-a1f2-fe975b06563e','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2566607142857142975,'["faculty_match"]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('067ece10-69fa-415e-84f0-3334c073c2fb','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('9b5d9b8d-c9b8-44c2-99bd-add6caaba452','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('86c28210-8fe5-4e3f-b634-5b853789b55c','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('b2da50a1-f0d7-435b-9f03-f2bbab361db1','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('cf129edd-76c9-4c45-a227-675aa3deeb21','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('e4e74aea-2153-42c6-86c4-802973c53b8c','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('1a788238-0d31-4c37-b19c-312bc2eccb64','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('7d880e22-4c3e-4aab-b6b2-e3860bd25195','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('1084e1bf-d24e-41b5-8c54-f03b977da36f','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1059761904761904739,'[]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('01710caa-beab-4fcb-b1e8-65c1c1f92149','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08133928571428572507,'[]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('5fe7eb57-d4d8-40ae-a6d8-d7aec32b241f','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('cee75cef-33af-49ef-b731-1e67dd853867','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:38:21.742870',0);
INSERT INTO recommendation_logs VALUES('897d3286-8920-4675-a3f6-d13ffad3a6c2','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2721071428571428808,'["faculty_match"]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('fd024a66-5015-4006-bfb8-d37b067cfd41','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.257160714285714298,'["faculty_match"]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('611121d9-dcc1-4eb4-af50-2f1c93448cdf','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2566607142857142975,'["faculty_match"]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('0c331123-51ff-410e-8fe6-d66fc5cdd0cb','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('91d50340-d8e1-475c-9853-46ffd8d3d1d3','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('37976f2d-4053-460a-b141-c2a962b3fbc8','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('3bcb3d58-286e-4ac7-ac5e-a9af4ee2460d','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('a6e225e1-90c8-4fd5-925b-b1f1b1404d89','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('3fdaf884-d2fd-43ae-aa42-36b94e5e5a78','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('1d9431e5-dd64-4b7f-abb8-57f7cc8236fd','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('430df337-11de-44d7-8100-02166d17f36e','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('888e60a5-8e8e-4ae1-8915-f5c903310425','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1059761904761904739,'[]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('c3855fda-6e1b-448f-9002-c4a93bdccaa3','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08133928571428572507,'[]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('7ae0e6a1-6172-4b35-a270-da2489df6047','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('c5ee8720-0a6d-4cd1-ad51-3597d55061c4','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:38:32.502102',0);
INSERT INTO recommendation_logs VALUES('e27a862e-f708-4dda-98ea-4cb07a45de55','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2666071428571428759,'["faculty_match"]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('19744e99-e831-4e62-b276-98829e8a6a13','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2561607142857142971,'["faculty_match"]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('b3c21e5d-66c7-472b-8ad6-323a6423656c','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2561607142857142971,'["faculty_match"]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('7e9d1f6e-fa9a-4699-913e-866f8f88a378','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1955000000000000071,'["faculty_match"]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('6418a1b9-d60b-4fc3-aa7a-d77a34e3bee2','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('c182e7ad-0376-4e57-b03e-d7f8e785a328','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('c5dee178-81c2-41d5-9143-5195b8d437a3','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('46eef927-15e4-4da4-a671-8284ef1cf382','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('af38c89e-09e4-494c-8b6a-434cf11ea853','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('047ea500-f9ed-4494-80ff-8e4d7f3c070c','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('b4df20ed-9643-4fbf-8068-51c45766d4e3','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('6ad7c50a-41f1-428b-adc1-8830d0d95510','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.0975892857142857256,'[]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('d79d0dbf-1f42-41ee-b211-3b160be3d107','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08133928571428572507,'[]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('5b75d3d6-e593-45b8-a071-3ba73cafd17e','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('d0bc75b5-70f4-4d66-909a-ece2cce43b85','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:51:00.424757',0);
INSERT INTO recommendation_logs VALUES('db92b35a-af62-41a6-ae4a-31551c316853','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2721071428571428808,'["faculty_match"]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('7a227bb1-31ff-4852-baf1-f1657fb97bd7','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.257160714285714298,'["faculty_match"]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('fcbef1af-4244-4c81-a091-bc63025a2b1d','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2566607142857142975,'["faculty_match"]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('56baa3d1-a982-4ae8-b8ed-85237a2d3de5','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1955000000000000071,'["faculty_match"]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('2c324407-f05c-4177-93e1-135b39a82ea6','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('c64786a4-0b27-4819-a8ed-925c8f3d7843','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('c5c0d3b6-fcdd-4ea7-afc5-9c42781f5811','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('f1880aa4-e89f-4a60-b168-0af39816b66c','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('dfb77a8e-c794-4d75-ad65-c570f36e463d','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('e42ed8e1-3198-4852-adbc-58a7b17968ec','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.0975892857142857256,'[]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('e2288932-1f9d-48da-8d25-8bc153a89a14','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('24b260cc-4515-49e1-bd78-c27610b999f5','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:51:39.111123',0);
INSERT INTO recommendation_logs VALUES('312b99d4-5344-4363-8cc0-ccb8bdae0540','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2721071428571428808,'["faculty_match"]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('db7e936e-841c-4a44-9eb9-b617eb33d0f9','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.257160714285714298,'["faculty_match"]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('e9ed7415-481a-4d35-b0de-697cf3b2ece5','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2566607142857142975,'["faculty_match"]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('72c3f77b-7445-47ed-a646-0a01ecc4eb41','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('a7319438-5a53-4802-a35e-ede753c3d2d6','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('5b7d9f66-ad83-4275-9c08-a0a6b5343b00','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('86357179-5ef9-48a7-92ed-c4b7361ab8db','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('8ae625d7-80ff-4db7-8c6a-dd041ef7e14c','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('53aa97ed-5597-4a7c-951f-73731f72bc82','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('2a22465c-dbad-402c-89c0-f4cece2366be','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1055892857142857189,'[]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('270a9904-07c6-4c4e-94fc-ce63a17f6bfc','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('843c259e-c04e-46ff-b258-c783b3420b34','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T13:52:14.971412',0);
INSERT INTO recommendation_logs VALUES('1f30af4b-86ee-4798-b60e-f6105fd824af','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2771071428571428852,'["faculty_match"]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('3d5e8612-c154-4f09-861d-d78893c37ed6','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.2581607142857142989,'["faculty_match"]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('e15c49ab-96fd-42cc-a346-ed37eceb7937','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2566607142857142975,'["faculty_match"]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('fbee2897-04fd-4b9b-ac56-b57c4b844496','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1945000000000000062,'["faculty_match"]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('1c0bd066-dc34-48ec-8491-eeb5bfd661e2','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1945000000000000062,'["faculty_match"]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('0d2ff149-1dc9-42ab-999c-0fa2b8af65cf','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('c78d18fd-ff58-48aa-8ee8-2a5a742082cc','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('9c107cf6-5944-46f1-8b54-58a09b8213d1','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('84e766e6-5e5c-43bf-8367-b757710d5f65','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('6fd661cc-f60a-490f-8367-e720c32265a3','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('0ff7eb2b-3891-426c-aacc-b2c3865ce55f','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('689c2edd-e1ea-44bf-8f83-677f51bf6c90','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.112589285714285725,'[]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('61a410a9-c538-493a-8c75-aefcbce3f0a7','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08133928571428572507,'[]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('5de9fcf4-4667-4b66-91dc-af0133e438df','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05500000000000000722,'[]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('70ca2c8b-8293-40ec-9e39-2e3ceb91d7ee','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T14:06:05.464281',0);
INSERT INTO recommendation_logs VALUES('77a00d62-6cae-4590-8b03-7e0ccffa51dd','kFGBiK3fGZg68mDizPn60EUN9lE2','462bec84-d957-4088-a8ba-ba9329479f3d','post','hybrid',0.2721071428571428808,'["faculty_match"]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('1e0cfc23-88c7-46c9-9b10-62911994ee89','kFGBiK3fGZg68mDizPn60EUN9lE2','6d9ebc6e-2cc2-4f6d-a3d8-14e0fa337032','post','hybrid',0.257160714285714298,'["faculty_match"]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('3d43da4f-3bcc-44b1-84f7-f5d1a4f01282','kFGBiK3fGZg68mDizPn60EUN9lE2','877c237c-d52b-4971-964f-186c63415ee5','post','hybrid',0.2566607142857142975,'["faculty_match"]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('d249fc44-8bc8-4c9b-a670-5f5c9b69ccff','kFGBiK3fGZg68mDizPn60EUN9lE2','3d2c0804-622c-4a4e-ba29-8019c2a2cb77','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('8948a81b-18bc-4448-a9ce-d3b253253335','kFGBiK3fGZg68mDizPn60EUN9lE2','dd6169b3-8814-4fa9-9113-42b1d226266a','post','hybrid',0.1925000000000000044,'["faculty_match"]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('c2920940-ee14-4227-976e-49da6a8964c3','kFGBiK3fGZg68mDizPn60EUN9lE2','be39c77c-6847-4447-8682-2ee33f3b7f44','post','hybrid',0.1915000000000000035,'["faculty_match"]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('3f83ec8e-6214-4b5c-9106-a7e41f08ad12','kFGBiK3fGZg68mDizPn60EUN9lE2','e1e7e3e3-2705-4b15-a870-b4eeab0d045a','post','hybrid',0.1905000000000000026,'["faculty_match"]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('cbd43873-65ac-434a-85d8-d167d2a8c5f3','kFGBiK3fGZg68mDizPn60EUN9lE2','d94f6d3a-a340-46b2-8ac6-309a8f4919a6','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('31d2e6d0-2b77-4084-97e7-161766d206c1','kFGBiK3fGZg68mDizPn60EUN9lE2','e48d8420-4be9-4651-b73c-cd4f261a5652','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('d6d8528e-6126-47b4-a308-4ae6aab4daf3','kFGBiK3fGZg68mDizPn60EUN9lE2','6ff493da-2246-4416-a468-5815de0c71fd','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('e2f6767a-dc56-4f72-80ef-4aa9a7fabaff','kFGBiK3fGZg68mDizPn60EUN9lE2','c5a17fd5-9964-493d-ade6-8d7cceed1f30','post','hybrid',0.1900000000000000022,'["faculty_match"]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('a5dd6ba9-1ea6-4d2a-a6c4-e5207211f80a','kFGBiK3fGZg68mDizPn60EUN9lE2','43857002-0470-437f-9207-805136f6168a','post','hybrid',0.1055892857142857189,'[]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('74a69cb5-10a0-412e-ab66-72f25d6569c8','kFGBiK3fGZg68mDizPn60EUN9lE2','6d8fabc7-1e85-4947-aa67-c6a201ae079e','post','hybrid',0.08133928571428572507,'[]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('36df6cfd-5c6d-4541-a231-1958141f1d23','kFGBiK3fGZg68mDizPn60EUN9lE2','954c2999-bea9-4ee0-ae82-49d110e65045','post','hybrid',0.05300000000000000545,'[]',0,'2026-04-09T14:08:17.256775',0);
INSERT INTO recommendation_logs VALUES('830a2b63-0d74-43b0-a64b-b10ad11a54d4','kFGBiK3fGZg68mDizPn60EUN9lE2','393c36d1-2c44-4f0d-a005-793414fb6e4c','post','hybrid',0.05000000000000000277,'[]',0,'2026-04-09T14:08:17.256775',0);
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
CREATE INDEX idx_courses_faculty ON courses(faculty_id);
CREATE INDEX idx_courses_active ON courses(is_active);
CREATE INDEX idx_faculties_active ON faculties(is_active);
CREATE INDEX idx_groups_creator ON groups(creator_id);
CREATE INDEX idx_groups_dissolved ON groups(is_dissolved);
CREATE INDEX idx_group_members_group ON group_members(group_id);
CREATE INDEX idx_group_members_user ON group_members(user_id);
CREATE INDEX idx_group_members_status ON group_members(status);
CREATE INDEX idx_posts_group ON posts(group_id);
CREATE INDEX idx_rec_logs_user ON recommendation_logs(user_id);
CREATE INDEX idx_rec_logs_algo ON recommendation_logs(algorithm);
CREATE INDEX idx_rec_logs_time ON recommendation_logs(logged_at DESC);
COMMIT;