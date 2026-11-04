# Phase 0 audit — Morrow

Audit date: 2 November 2026. This document preserves the initial audit. The user subsequently authorized work through Phase 5; see [current delivery status](phase-status.md). Cloud projects remain unavailable for inspection.

## Existing project

The workspace was empty, including hidden files. No existing application, dependencies, assets, Git repository, Firebase configuration, Supabase configuration, or tests were present. No cloud database or cloud authentication configuration has been verified.

Flutter 3.47.7 stable and Dart 3.13.5 are installed. Android Studio, its bundled Java, and an Android SDK directory exist; actual Android build readiness remains unverified. Git and Node.js are available. Native iOS verification requires a Mac/Xcode environment.

## Design authority and screen inventory

File: https://www.figma.com/design/ZR1ovxn0yC9WzkPjQYI7ZL/Untitled

| Frame | Node | Platform |
| --- | --- | --- |
| Meet your companion | 2:6619 | Mobile |
| A little company today | 2:6688 | Mobile |
| In conversation with Lumi | 2:6754 | Mobile |
| A voice, a little closer | 2:6816 | Mobile |
| The little things that stay | 2:6870 | Mobile |
| Morrow — Conversation | 2:6939 | Desktop |
| Morrow — Memories and personalization | 2:7076 | Desktop |

All seven frames were inspected visually in the prototype and confirmed in the source layer inventory. Onboarding is 402 × 900; the desktop conversation frame is 1440 × 1000. The onboarding source background is #F9F7F2. Its title uses Lora Regular at 28 px; supporting text uses Inter Regular at 13 px with 150% line height. These are inspected examples, not a complete token inventory.

Mobile navigation exposes Home, Talk, and Memories. Home exposes text and voice entry points. Desktop navigation exposes Today, Conversation, Memories, and Our rhythm, plus conversation history. The Continue group inspected in setup has no configured interaction; all destinations must be checked rather than inferred from presentation order.

The seven frames do not include the other onboarding steps, authentication, billing, memory-editing dialogs, or every error/loading/empty state. Do not invent those layouts. Design dates, names, chat messages, memory records, and prices are reference content, not production records or finalized commercial requirements.

## Asset and implementation prerequisites

Inspect all dimensions, fonts, colours, radii, iconography, and component states before implementing. Obtain original exports for the Lumi artwork and icons, and package the exact font files. Do not redraw or substitute the artwork. Do not embed screenshots as the application UI.

The Figma plugin is installed but its detailed tools are not exposed in this session. The user explicitly approved browser inspection and original exports as the alternate design-reading workflow. Preserve the UI exactly.

## Proposed architecture

Use Flutter and Dart for mobile and web. Extract reusable components from the design and keep screen presentation separate from application data and services. Firebase Authentication owns sign-in; Firebase Storage holds files where required. Supabase/PostgreSQL owns application data, RLS, relevant Realtime subscriptions, and backend functions. AI, voice, scheduling, and billing verification run through backend services. No provider secrets belong in the client.

Provisional logical entities are profiles, companions, companion_settings, conversations, messages, memories, user_preferences, interaction_patterns, notification_preferences, scheduled_checkins, subscriptions, and usage_records. Finalize the schema only after cloud-project and feature inspection. Ownership policies must validate the Firebase identity and prevent cross-user relations. Do not create tables during Phase 1.

Core service packages expected in later phases are firebase_core, firebase_auth, supabase_flutter, and firebase_storage if needed. Add only dependencies required by implemented work; do not pre-install voice, payment, or notification packages before choosing their providers.

## Ordered delivery plan

0. Audit the existing project, tools, design, navigation, assets, and cloud configuration.
1. Reproduce the seven supplied UI frames, extract reusable components, wire approved navigation, and compare renders against Figma.
2. Add initialization, authentication, sessions, backend integration, secure configuration, and approved loading/error states.
3. Implement persistent companion creation and preferences.
4. Add secure conversational requests, history, streaming, and retries.
5. Add structured memory retrieval, provenance, relevance, retention, and deletion.
6. Add interaction-based, user-controlled personalization.
7. Add opt-in check-ins with frequency, timezone, and quiet-hour controls.
8. Connect voice to the same conversation and memory infrastructure.
9. Add the approved companionship and wellbeing features.
10. Complete privacy, security, data deletion, and isolation verification; maintain secure access throughout earlier integration work.
11. Add server-verified subscription entitlements and usage limits.
12. Complete visual, functional, privacy, performance, and platform validation before production.

Report evidence and remaining issues at each phase. The later authorization through Phase 5 covers the local implementation sequence; it does not authorize deployment or backend provisioning.
