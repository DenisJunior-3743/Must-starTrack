# MUST StarTrack Chatbot Training Playbook

This playbook defines how to continuously train the in-app assistant and improve recommendation accuracy using real project usage.

## What Is Already Wired

- Local-first answer flow: FAQ -> project docs -> learned memory -> OpenAI -> safe fallback.
- Chat feedback in UI: users can mark assistant replies as `Helpful` or `Not Helpful`.
- Chat interaction logging in Firestore collection: `chatbot_interactions`.
- Recommendation logs in Firestore collection: `recommendation_logs`.

## How Learning Now Works

The chatbot periodically loads recent helpful interactions and turns them into reusable learned examples.

In simple terms:

1. User asks a question.
2. Assistant answers.
3. User marks answer as helpful.
4. That Q/A becomes part of learning memory.
5. Similar future questions can reuse this proven answer pattern.

## Training Routine (Recommended)

Run this loop each week:

1. Open admin chatbot analytics and review low-confidence or not-helpful traces.
2. Add or refine FAQ entries for repeated gaps.
3. Ask 30-50 realistic student, lecturer, and admin questions in the chatbot.
4. Mark strong answers as helpful.
5. Re-test key scenarios:
   - Guest limitations
   - Project/opportunity posting flows
   - Group and collaboration flows
   - Lecturer applicant ranking flows
   - Admin moderation and analytics flows

## Recommendation Accuracy Loop

To keep recommendations accurate:

1. Ensure users have complete profiles (skills, faculty, program, bio).
2. Encourage feed interactions (views, likes, comments, searches).
3. Monitor `recommendation_logs` for dominant weak signals.
4. Tune ranking weights in:
   - `lib/data/remote/recommender_service.dart`
5. Compare before/after using recommendation web lab screens.

## Quality Targets

Use these practical targets:

- Helpful ratio on chatbot feedback: >= 80%
- Fallback-only answers: <= 15%
- AI rerank used only when local match is weak
- Recommendation top results include clear skill/faculty/program relevance

## Important Principle

OpenAI should stay a support layer, not the only intelligence layer.
The app remains reliable because local logic, local docs, and learned memory stay active even without external AI.
