Let me explore the codebase to understand the full picture before brainstorming. 

Search complete: Explore codebase for architecture

Searched codebase for "data models posts users collaborations collab_requests", 22 results

Searched codebase for "DAO classes database methods Firestore", 26 results

Searched for files matching `must_startrack` · `lib/**/*.dart`, 138 matches

Read [](file:///d%3A/start_track/must_startrack/lib/data/local/schema/database_schema.dart#1-1), lines 1 to 100

Read [](file:///d%3A/start_track/must_startrack/lib/data/models/post_model.dart#1-1), lines 1 to 310

Read [](file:///d%3A/start_track/must_startrack/lib/data/models/user_model.dart)

Read [](file:///d%3A/start_track/must_startrack/lib/data/local/schema/database_schema.dart#100-100), lines 100 to 580

Read [](file:///d%3A/start_track/must_startrack/lib/data/local/dao/post_dao.dart#1-1), lines 1 to 200

Read [](file:///d%3A/start_track/must_startrack/lib/data/models/profile_model.dart)

Here's the full brainstorm after understanding the entire architecture:

---

## Groups Module — Brainstorm

### What we're building

A self-contained **Groups** module that sits alongside the existing Peers/Collabs graph and extends the existing Posts pipeline for group-attributed uploads.

---

### Eligibility Rules (enforced at invite time)

The eligibility query draws from two existing relationships:
1. **Peers** — users with an `accepted` row in `collab_requests` with the inviter
2. **Same-project collabs** — users sharing any `post_id` across accepted collab requests

This means "eligible invitees" = a single SQL query joining `collab_requests` and `users` — no new data needed from outside.

---

### Data Layer

**Three additions to the schema (DB v12):**

| Table | Key Columns |
|---|---|
| `groups` | `id, name, description, avatar_url, creator_id, member_count, is_dissolved, created_at, updated_at, sync_status` |
| `group_members` | `id, group_id, user_id, role (owner/admin/member), status (pending/active/declined), invited_by, joined_at, created_at, sync_status` |
| `posts` migration | Add `group_id TEXT` column (nullable — existing posts untouched) |

Group posts are **regular posts with a `group_id`** — no separate table. This reuses the entire existing CreatePost → PostDao → SyncQueue → Firestore → Feed pipeline for free.

---

### Firestore Collections

```
groups/{groupId}              ← group profile + metadata
group_members/{groupId_userId} ← one doc per membership
posts/{postId}                 ← already exists, just gains group_id field
```

---

### Screens (6 screens)

| Screen | Entry Point |
|---|---|
| `GroupsListScreen` | Peers tab — "Groups" section or tab |
| `CreateGroupScreen` | FAB on GroupsList or Peers AppBar |
| `GroupDetailScreen` | Tap a group — tabs: Feed / Members / Info |
| `GroupUploadScreen` | "Upload Project" button inside GroupDetail |
| `GroupEditScreen` | Edit button (owner/admin only) |
| `GroupInviteScreen` | Manage pending invites (owner/admin) |

---

### Feature Flow

```
User → Peers Screen (new "Groups" tab)
  └─ FAB "Create Group"
       ├─ Step 1: Name + description + avatar
       ├─ Step 2: Invite eligible peers (pre-filtered list)
       └─ Step 3: Review + Create → GroupDetailScreen

GroupDetailScreen
  ├─ Feed tab: group posts (PostCard, infinite scroll)
  ├─ Members tab: member list, roles, pending invites
  └─ Info tab: group description, stats, leave/dissolve

GroupUploadScreen (= CreatePostScreen + group_id attached)
  ├─ Title, description
  ├─ Media (images/videos, same Cloudinary pipeline)
  ├─ Links (YouTube, external links, GitHub)
  ├─ Tags + skills
  └─ Visibility: Group-only or Public
```

---

### Feed Integration

- Add **"Groups"** chip to the home feed filter bar
- `PostDao.getFeedPage()` gets a `filterGroupId` optional param; `null` = all, `'any'` = group posts only
- Group posts show a **group badge** on the PostCard (group avatar + name)
- **Lecturer dashboard**: filter feed by groups to see group submissions
- **Admin dashboard**: new "Groups" tab — list of groups, member counts, post counts, dissolve action

---

### Sync / Firestore wiring

- `SyncService` gets two new entity cases: `groups` + `group_members`
- `FirestoreService` gets `setGroup`, `setGroupMember`, `deleteGroupMember`, `getGroupMembers`
- firestore.rules gets `groups` + `group_members` collection rules
- Group invitations trigger a **push notification** via the existing `NotificationDao` + FCM pipeline

---

### Admin / Lecturer

**Admin dashboard (new tab T14 "Groups"):**
- Total groups, active this week, dissolved
- Group list with member count, post count
- Moderate group posts (same moderation queue)
- Dissolve a group (soft-delete `is_dissolved = true`)

**Lecturer dashboard:**
- "Group feed" toggle — filters posts to `group_id IS NOT NULL`
- Can see which group submitted which project

---

### What we DON'T build (to stay focused)

- Group chat (separate from DMs — out of scope for now)
- Group milestones/tasks (existing ColabDashboard placeholder can handle later)
- Public groups (groups are always invite-only among eligible peers)

---

### Implementation Order

1. **DB migration** — add `groups`, `group_members` tables + `group_id` on posts
2. **Data models + DAOs** — `GroupModel`, `GroupMemberModel`, `GroupDao`, `GroupMemberDao`
3. **Firestore service + sync** — 2 new collections, 2 new sync entity handlers
4. **Firestore rules** — groups + group_members
5. **Screens** — GroupsList → CreateGroup → GroupDetail → GroupUpload → GroupEdit
6. **Peers screen** — add Groups tab/section
7. **Feed integration** — `group_id` column read, filter chip, group badge on PostCard
8. **Admin tab** — Groups analytics + dissolve
9. **Lecturer filter** — toggle in lecturer dashboard

---

Ready to start implementing? I'd suggest starting with **step 1–4** (data layer) so every screen has a solid foundation to build on. Say the word and I'll begin.