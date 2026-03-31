# MUST StarTrack

MUST StarTrack is a skill-centric academic networking and collaboration platform for Mbarara University of Science and Technology. The app helps students showcase projects, discover peers, apply for opportunities, collaborate in groups, message each other, and receive AI-assisted recommendations. Lecturers and administrators also get role-specific dashboards for applicant review, moderation, and platform analytics.

## What The App Does

- Showcase student projects and academic work through a rich media feed.
- Match users to relevant posts, collaborators, and opportunities using a hybrid local-first recommender.
- Support direct messaging, notifications, collaboration requests, and group-based project organization.
- Provide lecturer workflows for applicant ranking, advanced search, shortlisting, and opportunity management.
- Provide admin workflows for moderation, user management, academic configuration, analytics, and chatbot benchmarking.
- Support an in-app assistant that answers FAQ and project-guided questions with Gemini fallback.

## Core Feature Areas

### Student Features

- Home feed for projects, opportunities, and activity updates.
- Create and manage project or opportunity posts.
- Discover people and content by skills, faculty, program, and relevance.
- Build a profile with bio, skills, links, achievements, and endorsements.
- Send messages, receive notifications, and track activity streaks.
- Apply to opportunities and manage collaborations.
- Create groups and publish group-attributed work.

### Lecturer Features

- Lecturer dashboard for opportunity management.
- Applicant review, ranking, advanced search, and shortlisting.
- Visibility into skill-fit and activity-based applicant relevance.

### Admin Features

- User management and moderation flows.
- Activity analytics and audit logs.
- Faculty and course management.
- Chatbot analytics and assistant quality tracking.

## Architecture Summary

The project is a Flutter application with a local-first, offline-aware architecture.

- UI: Flutter Material with Google Fonts and responsive feature screens.
- State management: `flutter_bloc` with Cubit/BLoC patterns.
- Dependency injection: `get_it`.
- Navigation: `go_router` with route guards and role-aware routing.
- Local data: SQLite via `sqflite`.
- Remote services: Firebase Authentication, Cloud Firestore, Firebase Storage, Firebase Messaging.
- AI integration: Gemini for recommendation reranking and assistant fallback answers.
- Media pipeline: image/video pick, crop, compress, and upload.

## Recommendation System

The recommendation system is hybrid and local-first.

- Local ranking always runs first.
- Ranking uses profile signals, skills, faculty, program, searches, activity logs, recency, engagement, and opportunity fit.
- If Gemini is configured, it can rerank top results rather than replacing the local model.
- Recommendations are used in the home feed, discover experience, collaborator discovery, and lecturer applicant ranking.

## Chatbot Assistant

The in-app assistant is trained using app-specific FAQ plus curated project knowledge.

- FAQ-first matching for fast, deterministic answers.
- Project-guided knowledge for implementation-specific questions.
- Gemini fallback for broader explanation when the local knowledge is not enough.
- Feedback logging and admin analytics for benchmarking answer quality.

## Repository Structure

```text
lib/
	app/                  App bootstrap and top-level composition
	core/                 Constants, DI, router, shared services, utilities
	data/                 Local DAOs, models, remote services, repositories
	features/
		admin/              Admin dashboards and analytics
		ai/                 Recommendation and AI-facing screens
		auth/               Login, registration, onboarding, splash
		chatbot/            Assistant knowledge, repository, Cubit, UI
		discover/           Search and discovery workflows
		feed/               Home feed, post creation, project detail
		groups/             Group creation and group collaboration flows
		lecturer/           Lecturer dashboards, ranking, search, shortlist
		messaging/          Inbox and chat detail screens
		notifications/      Notification center and settings
		peers/              Collaboration and peer-oriented workflows
		profile/            Profile, editing, portfolio, achievements
assets/
	images/               App imagery
	icons/                App icons and illustrations
	fonts/                Local font assets
prototype/              Static HTML prototypes used during design exploration
test/                   Automated tests
```

## Tech Stack

- Flutter
- Dart
- Firebase Auth
- Cloud Firestore
- Firebase Storage
- Firebase Messaging
- SQLite (`sqflite`)
- Dio
- GoRouter
- flutter_bloc
- Gemini API

## Getting Started

### Prerequisites

- Flutter SDK compatible with `>=3.2.0 <4.0.0`
- Dart SDK compatible with the Flutter version above
- Firebase project configured for Android, iOS, and Web if needed
- Android Studio or VS Code with Flutter tooling

### Setup

1. Install dependencies:

```bash
flutter pub get
```

2. Configure Firebase for your project.

- Ensure `firebase_options.dart` matches your Firebase project.
- Ensure platform Firebase config files are present where required.

3. Configure environment-specific secrets and service credentials.

- Gemini API key must be available to the app configuration if AI fallback is expected to run.
- Firebase services must be enabled for Authentication, Firestore, Storage, and Messaging.

4. Run the app:

```bash
flutter run
```

## Useful Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Firebase Notes

- Firestore rules must be deployed when new collections are introduced.
- Firestore indexes may need updating for search and ranking queries.
- Messaging and notification flows depend on Firebase Messaging being configured correctly.

## Current Product Direction

The current codebase focuses on:

- project and opportunity publishing,
- discovery and collaboration,
- group-based workflows,
- lecturer applicant intelligence,
- admin moderation and analytics,
- AI-assisted user guidance and recommendation quality.

## Development Notes

- The app is designed to remain useful even when Gemini is unavailable.
- The recommender and assistant both prioritize local knowledge before AI fallback.
- The project uses explicit route constants and role-aware navigation.
- Several flows depend on Firestore security rules matching the client query shape.

## Platforms

The repository includes support for:

- Android
- iOS


## License

No open-source license is declared in this repository.
