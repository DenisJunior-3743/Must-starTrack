## MUST StarTrack Architecture

MUST StarTrack is a Flutter application built around a local-first, offline-aware architecture for academic networking, collaboration, discovery, and AI-assisted workflows.

## High-Level Structure

- `lib/app/`: app bootstrap and root app composition
- `lib/core/`: constants, dependency injection, routing, shared services, and utilities
- `lib/data/`: local DAOs, shared models, repositories, and remote services
- `lib/features/`: feature-specific presentation and business logic

## Core Architectural Decisions

### UI And State

- Flutter Material UI with feature-based screen organization
- `flutter_bloc` for Cubit and BLoC state management
- `go_router` for guarded, role-aware navigation
- `get_it` for dependency injection

### Data Flow

- Local-first reads and writes through SQLite-backed DAOs
- Remote sync through Firebase services and service/repository abstractions
- Firestore used for shared platform data and cross-device sync
- Firebase Auth used for identity and role-aware access

### Offline-First Behavior

- The app is designed to remain functional when network availability is limited
- Local persistence allows core workflows to remain responsive
- Remote synchronization fills in when connectivity becomes available

### AI Layer

- Recommendation workflows are hybrid and local-first
- Local ranking runs first using skills, profile data, search history, engagement, and activity signals
- Gemini is used as an optional reranking layer and as fallback reasoning for the assistant
- The assistant prefers local FAQ and project knowledge before Gemini fallback

## Main Product Modules

### Feed

- Home feed for projects and opportunities
- Post creation, project detail, engagement, and sharing

### Discover

- Search by skills, faculty, category, and relevance
- Recommendation-assisted exploration of people and posts

### Peers And Collaboration

- Peer discovery and collaboration requests
- Group creation and group-attributed project organization

### Messaging And Notifications

- Real-time chat and inbox flows
- Notification center and notification preferences

### Profile

- Skills, portfolio, achievements, endorsements, and academic identity

### Lecturer Tools

- Opportunity management
- Applicant ranking, advanced search, and shortlisting

### Admin Tools

- Moderation
- User and academic management
- Analytics and assistant benchmarking

## Backend Services

- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Firebase Messaging
- Gemini API integration

## Notes For Assistant Training

This file is useful as a stable source for the assistant when answering:

- what the app does
- how the app is structured
- whether Gemini is used
- how recommendations work at a high level
- what lecturers and admins can do
