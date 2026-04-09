# MUST StarTrack Recommender Architecture (Project-Aligned v2)

## 1. Purpose

This document defines the recommendation system for MUST StarTrack with direct alignment to the current Flutter codebase.

Primary product goals:

- Personalized project/opportunity stream in Home Feed
- Collaborator matching for project work
- Opportunity talent matching (lecturer side)
- Opportunity recommendation to students (student side)
- Offline-first resilience with local ranking fallback

---

## 2. Where Recommendation Is Used

Current usage surfaces in the app:

- Home feed ranking for post stream
- Collaborator strip and collaborator ranking
- Discover result reranking
- Lecturer applicant ranking for opportunities
- AI recommendations and nudge screens

Key implementation anchors:

- `lib/data/remote/recommender_service.dart`
- `lib/features/feed/bloc/feed_cubit.dart`
- `lib/features/feed/screens/home_feed_screen.dart`
- `lib/features/lecturer/bloc/lecturer_cubit.dart`
- `lib/features/discover/screens/discover_screen.dart`

---

## 3. System Strategy

The recommender is hybrid and local-first:

1. Local scoring computes robust baseline ranking using profile + behavior + content signals.
2. Optional AI rerank (Gemini) reranks top candidates only.
3. If AI unavailable, local ranking remains fully functional.

This architecture guarantees feed continuity in offline/limited-connectivity conditions.

---

## 4. Ranking Objectives by Surface

### 4.1 Home Feed (project/opportunity stream)

Objective: rank posts by relevance while preserving freshness and exploration.

- Input: candidate posts from local cache/sync
- Output: ordered list shown in Home feed tabs
- Runtime mode: local or hybrid

### 4.2 Collaborator Matching (project -> people)

Objective: recommend peers with strong fit for project collaboration.

- Input: current user profile + candidate users
- Output: ranked `RecommendedUser` list with reasons and matched skills

### 4.3 Opportunity Talent Matching (opportunity -> students)

Objective: help lecturer rank applicants/candidates for a specific opportunity.

- Input: opportunity requirements + student profiles
- Output: ranked students, explainable signals

### 4.4 Opportunity Discovery (student -> opportunities)

Objective: recommend opportunities that fit student skills and intent.

- Input: student profile + opportunity posts
- Output: ranked opportunity feed/list for student workflows

---

## 5. Core Signals (Project-Aligned)

### 5.1 User signals

- Skills
- Faculty
- Program
- Activity streak
- Total posts
- Total collaborations
- Profile completeness
- Recent search terms
- Recent category interaction

### 5.2 Post/opportunity signals

- Skills used
- Type (project/opportunity)
- Faculty/program targeting
- Recency
- Engagement (likes/comments/shares)
- Category
- Role-based ratings (lecturer and student)

### 5.3 Interaction events

Event-based tracking remains the source of behavioral adaptation:

- `view`
- `like`
- `dislike`
- `comment`
- `share`
- `follow`
- `search`
- `collaborate`
- `join_opportunity`

---

## 6. Current Scoring Model (Aligned to Existing Service)

## 6.1 Local post scoring

In the current implementation, post scoring combines:

- skill overlap (strongest component)
- faculty/program alignment
- search intent match
- recency decay (14-day horizon)
- engagement normalization
- recent category behavior
- opportunity fit bonus for matching opportunity posts
- lecturer/student rating blend

Role-rating blend in current implementation:

$$
\text{rating\_blend} = \frac{0.7\cdot r_{lecturer} + 0.3\cdot r_{student}}{\text{available weight}}
$$

Hybrid rerank blend:

$$
\text{final\_score} = 0.65\cdot\text{local\_score} + 0.35\cdot\text{ai\_score}
$$

### 6.2 Collaborator scoring

Collaborator ranking currently considers:

- shared skills
- complementary skills fallback
- faculty/program match
- profile activity score
- profile completeness
- search intent signal

### 6.3 Opportunity applicant scoring

Lecturer-side ranking currently considers:

- matched opportunity skills
- faculty/program fit
- activity score
- profile completeness
- collaboration readiness bonus

---

## 7. Feed Streaming Design for Home Feed

Target behavior for `home_feed_screen.dart`:

1. FeedCubit requests candidate posts page-by-page.
2. Candidate page is ranked before render.
3. Top ranked items are shown first in stream.
4. As user scrolls and more pages load, newly fetched candidates are ranked and merged.
5. User actions (like/comment/share/collab/apply) are logged and reflected in next ranking cycle.

### 7.1 Real-time adaptation policy

- Immediate local UI update for action state
- Near-term ranking refresh trigger after significant actions:
  - like/dislike
  - collaborate request
  - opportunity apply
  - search interaction
- Full re-ranking on pull-to-refresh

### 7.2 Exploration policy (recommended)

Keep quality while avoiding filter bubbles:

- 80% exploit (personalized top-ranked)
- 20% explore (cross-faculty/new category/trending)

Implementation note:

- Exploration should be interleaved at controlled positions in the ranked stream (for example every 4th-5th slot).

---

## 8. Bidirectional Matching (Required Product Logic)

### 8.1 Project -> Collaborators

Use collaborator ranker to suggest teammates for project execution.

Result contract per user:

- `score`
- `reasons`
- `matchedSkills`

### 8.2 Opportunity -> Students (lecturer view)

Use opportunity applicant ranker to shortlist strongest candidates.

Result contract per user:

- `score`
- `reasons`
- `matchedSkills`

### 8.3 Student -> Opportunities (vice versa)

Use post ranker with opportunity-aware features to recommend opportunities to student.

Minimum additional constraints:

- suppress opportunities already joined/applied by the student
- optional boost for close deadline with strong fit
- optional penalty for expired/near-expired if action window is too short

### 8.4 Student -> Projects

Use the same ranked stream, but type-filtered or slot-controlled:

- personalized projects for inspiration and collaboration discovery
- opportunities mixed in by policy for actionability

---

## 9. Cold Start Policies

### 9.1 New user

Blend:

- 60% campus-popular/trending
- 30% registration skill/faculty/program fit
- 10% random exploration

### 9.2 New post/opportunity

- temporary freshness boost
- fast decay if engagement remains weak

---

## 10. Data and Logging Contracts

### 10.1 Event collection

Store interaction events in local DB and sync to cloud. Include:

- userId
- eventType
- targetId
- timestamp
- weight/metadata

### 10.2 Recommendation decision logging

Already supported by recommendation logs (SQLite + Firestore sync). Keep for:

- observability
- quality audits
- future weight tuning

Required fields per decision log:

- userId
- itemId
- itemType
- algorithm
- score
- reasons
- timestamp

---

## 11. Quality Metrics and Acceptance Criteria

Track these metrics for production readiness:

- Feed CTR uplift
- Collaboration request rate
- Opportunity apply rate
- Save/share/comment per session
- Precision@K and NDCG@K on offline replay sets
- Recommendation latency p95 (local and hybrid)

Minimum acceptance gate:

- no regression in engagement guardrails
- measurable uplift in collaboration/apply conversion
- stable latency and no blocking when AI rerank is unavailable

---

## 12. Incremental Implementation Plan

### Phase A: Stabilize formulas and contracts

- Freeze score features and reason labels across surfaces
- Ensure all rankers emit explainable reasons

### Phase B: Home feed streaming improvements

- Add controlled exploration interleaving
- Add post-action refresh triggers
- Keep pagination + lazy loading stable

### Phase C: Full bidirectional matching

- strengthen student -> opportunities ranking constraints
- unify scoring explanations across lecturer and student surfaces

### Phase D: Evaluation and tuning

- run A/B on weight variants
- tune weights from recommendation logs and outcomes

---

## 13. Final Architecture Summary

MUST StarTrack recommendation is now defined as:

- Local-first hybrid ranking engine
- Stream-ready ranked feed for Home
- Bidirectional matching for collaboration and opportunities
- Explainable decisions with logged reasons
- Offline-safe behavior with optional AI rerank

This is practical, scalable, and directly aligned with the current project implementation.