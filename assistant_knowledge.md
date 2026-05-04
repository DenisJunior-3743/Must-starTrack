# MUST StarTrack Assistant Knowledge

This document is a compact, stable source of truth for the in-app assistant and future AI grounding.

## Product Purpose

MUST StarTrack is an academic networking and collaboration platform for Mbarara University of Science and Technology. It helps students, lecturers, and admins manage project showcasing, opportunity discovery, collaboration, messaging, recommendations, and moderation workflows.

## Main Capabilities

- Project and opportunity posting
- Skill-based discovery of people and content
- Collaboration requests and peer networking
- Group creation and group-attributed project posting
- Messaging and notification flows
- Profile building with skills, achievements, portfolio, and endorsements
- Lecturer dashboards for applicant review, ranking, and shortlisting
- Admin dashboards for moderation, analytics, user management, and assistant benchmarking

## Recommendation System

The recommendation system is hybrid and local-first.

- Local ranking always runs first.
- Signals include user skills, faculty, program, bio, activity streak, total posts, collaborations, followers, recent activity, recent searches, post recency, engagement, and opportunity fit.
- Recommendations are used in the home feed, discover, collaborator suggestions, and lecturer applicant ranking.
- If OpenAI is configured, it can rerank top candidates but does not replace the local model.
- If OpenAI is unavailable, recommendations still work through local ranking.

## OpenAI Usage

OpenAI is used in the app in a supporting role.

- Assistant fallback: when local FAQ and project knowledge are insufficient
- Recommendation reranking: optional reranking of already-ranked local candidates

OpenAI is not the core engine of the app. Critical product behavior stays local-first.

## Groups

Groups let users organize collaboration around a shared project.

- Groups are created from the peers and collaboration flow
- Members are invited from accepted collaborator relationships
- Groups can have owner, admin, and member roles
- Group posts reuse the normal post pipeline but are tagged with a group identifier
- Lecturer and admin views can inspect group-related work

## Roles

- Student: create projects, apply to opportunities, discover peers, collaborate
- Lecturer: manage opportunities, review applicants, rank candidates, shortlist talent
- Admin: moderate content, manage users, monitor analytics, configure academic data
- Super Admin: full platform oversight and configuration

## Offline-First Behavior

- The app uses local persistence and sync-aware workflows
- Core usage should remain functional even when network quality is poor
- Assistant and recommender features should prefer local knowledge first, then OpenAI if configured

## Assistant Answering Rules

- Prefer exact FAQ answers when the question is directly supported
- Prefer project knowledge summaries for implementation-specific questions
- Use OpenAI only after local FAQ and project knowledge have been searched
- Do not claim OpenAI is required for the app to work
- When answering role-specific questions, explain what the user can do in that role
