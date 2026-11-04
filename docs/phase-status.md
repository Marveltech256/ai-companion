# Delivery status

Current update: [Phases 11–12 implementation and verification](remaining-phases.md).
Temporary private-code **Guest for app review** is enabled on the welcome screen;
see [review access and removal](review-guest-access.md). Guest workspaces use the
same services and remain separate from personal accounts.
The 0.1.3 (4) Android candidate includes inactive subscription infrastructure, reply
reporting, account-switch isolation and daily privacy cleanup without redesigning
the existing application. Live checks confirm 23 RLS tables and 110 functions;
the real Chrome storage probe passes. Store, paid-provider and physical device
gates remain explicit. The historical account below predates this update.

Current checks: **92 Flutter tests**, **65 backend tests**, all nine Edge entry
points type-check, and the real Chrome persistence/cleanup probe passes. The web
release and signed Android 0.1.2 (3) bundle are built and verified for internal testing.
Public privacy/terms/deletion pages now identify Marvel tech solutions, Uganda;
real web email login and account erasure pass. The app's existing privacy section
links to the published notice. No Play upload has occurred.

## Historical implementation record before Phases 11–12

The current handoff is an Android internal-test candidate, with an estimated
**80% overall completion**. See the [weighted readiness assessment](testing-release-status.md),
[internal testing steps](internal-testing.md) and [latest implementation evidence](personal-friend-update.md).
The historical details below predate the latest voice/automatic-preferences and
release-signing refinements. Current checks are 84 Flutter tests and 51 backend
tests; Gemini 3.5 Flash-Lite is the working text/memory/transcription path.

The application is now branded **Ai Companion** with the supplied purple/orange logo in its wordmark, Android/iOS launcher icons and web/PWA icons. The original image is preserved in `assets/branding/`; the Dart package is `ai_companion`. Firebase registrations, installed mobile identifiers, backend RPC names and saved-data namespaces remain stable across the rename. Original Figma scenes remain historical references.

Updated 3 November 2026. The user clarified that Figma supplies visual inspiration and requested a functioning application. The source changes survived the machine restart; one corrupt generated Flutter hook-cache JSON file was regenerated.

The subsequent personal-companion correction was audited before code changes. Persistent identity, seven structured memory kinds, temporal events/routines, bounded conversation context, assistant welcomes and contextual proactivity now extend the same application. See the [gap analysis, implementation evidence and ten live acceptance gates](companion-direction-audit.md). Existing screens, styling and working services are preserved.

## Application

The shipped entry point now launches `MorrowApplication` in `lib/application/`. Its screens use responsive Flutter widgets, editable fields, scrollable lists, independent controls, and dialogs. It does not import the exported Figma scene library or render whole frames. Inter/Lora typography and Figma colours preserve the visual direction. The original renderer is isolated behind `lib/main_design_reference.dart`; `main_preview.dart` now launches the interactive device application.

A fresh installation can create a companion, save journal entries, search/edit/delete manually added memories, change preferences and retention, export records, and delete its device workspace. Real user records persist through the platform storage plugin. Journal mode never adds assistant replies or typing indicators. The device workspace is labelled and remains separate from cloud accounts; no automatic import or synchronization is implemented.

The new UI also wires cloud conversation history/rename/deletion, learning and voice consent, notification schedule preferences, email sign-in/linking/reauthentication, export, sign-out, and account-erasure confirmation/status to the existing service controller.

Production requires a registered account before setup or any main screen. Sign-in cancellation, old workspace preferences, error screens and sign-out cannot enter a guest/journal workspace. Protected overlays close and voice stops on sign-out. Firebase anonymous signup is disabled. The shared Edge verifier and deployed migration 013 enforce registered identities. All **74 Flutter tests** and **47 backend tests** pass, including guest denial and registered account access. Separate journal entry points remain development previews.

## Phase coverage

| Phase | Implemented | Remaining activation or verification |
| --- | --- | --- |
| 0 — Audit | Source export/provenance, Flutter/backend architecture, original seven frames, current Figma setup context and installed cloud schema inspected | Reconcile manual bundle installation with CLI migration history before future pushes |
| 1 — UI | Native onboarding, home, conversation/journal, voice, memory management, settings, responsive navigation and dialogs | Real device visual/accessibility/performance QA |
| 2 — Foundation | Platform config, live Firebase providers, deployed exact-project backend verification, email signup/login/profile round trip, account isolation | Interactive Google login, reset-email delivery and device sign-in |
| 3 — Companion | Naming, styles/interests, response length, persisted settings and memory consent; live companion save/reload passes | Device interaction and quality evaluation |
| 4 — Conversation | Native composer/history, real Gemini streaming, idempotent retry and recall after fresh login | Longitudinal quality and OpenAI activation |
| 5 — Memory | Consent, manual correction/forget, grounded live extraction and cross-conversation recall, routines/events and tombstones | Longitudinal quality and scheduled cleanup |
| 6 — Personalization | Independent learning consent UI, explicit preferences, opt-in completed-turn patterns, opt-out clearing | Live conversational-quality evaluation |
| 7 — Proactivity | Editor supports timezone/days/up to three times/frequency/quiet hours, routine guards, contextual worker, reminder confirmation/cancellation/history; FCM-capable server identity and worker deployed | OpenAI, scheduler secret/cron, APNs and real closed-app delivery |
| 8 — Voice | Talk Coming Soon; services preserved; optional saved-greeting playback with explicit Play/replay/mute | OpenAI speech, real-time calling and hardware verification |
| 9 — Companionship | Selected-interest invitations and supportive reflection/activity/goal guidance | Live quality/safety evaluation |
| 10 — Privacy | Native consent/retention/export/erasure controls, verified cloud RLS/privileges, live account lookup and erasure, deployed cleanup worker, separate device storage | Scheduler activation, backup/provider retention and platform storage review |

## Cloud state

Gemini `gemini-3.1-flash-lite` is configured with an API-restricted key. Real synthetic adult-account tests pass streaming, saved/idempotent replies, grounded extraction, recall after fresh password login, French preference and truthful Home activity. OpenAI remains the intended primary, but no OpenAI key is configured and its developer connection is still missing. See [provider setup](ai-provider-backup.md).

The owner chose an **18+ release** and deferred paid Gemini setup. Google billing remains unchanged and disabled. Paid Gemini API setup is required before customer personal-data use; the owner explicitly deferred it. Navigation is Home/Chat/Talk, Talk is Coming Soon, and memory controls remain in Settings. See [all ten new stages and limits](personal-friend-update.md).

Latest live verification (3 November 2026): the owning Supabase CLI login now works. Administrative checks confirm all 16 application tables with RLS, the expected Firebase project/profile columns/unique index and all 85 function privileges. All six Edge Functions are deployed. Supabase's secret manager holds the restricted Firebase server identity, project ID and exact browser origins. Live email signup, account checks, username/preferred-name and companion saving, password login/reload, duplicate username rejection, cross-account denial and account erasure pass. Temporary test identities and their application data were removed.

Supabase public values and Firebase mobile/Web configuration remain configured. Email/password and Google are enabled; anonymous signup is disabled. Google uses **Ai Companion** and temporary support email **atalyebamarvin4@gmail.com**. Interactive Google login, OpenAI and scheduler activation remain pending.

The user initially installed the twelve-migration bundle manually. The additive sign-in policy (013) was later applied through the authorized CLI. The fresh-install bundle now includes all 15 sources; do not rerun it on this database. Reconcile migration history before a future db push. No existing user data was deleted. Unauthenticated requests return 401, and real guest tokens receive sign_in_required.

## Limits

Real synthetic adult-account tests pass streaming, saved/idempotent replies, grounded extraction, recall after fresh password login, French preference and truthful Home activity. Google billing remains unchanged and disabled. Paid Gemini API setup is required before customer personal-data use; the owner explicitly deferred it. OpenAI, audio, scheduler activation and physical-device delivery remain pending. Account persistence and erasure pass deployed checks.

The device workspace is capped at 1 MiB, 100 memories, and 2,000 journal entries. Its browser storage stays in that browser/origin. Its settings and notes are not automatically imported into cloud accounts. The existing settings and memory dialogs now confirm individual cloud reminders through the verified API; notification permissions alone do not create reminders.

Cloud conversation lists return the most recent 40 records; messages page in groups of 50, and the memory manager loads up to 100 records. The supplied logo now provides launcher/PWA artwork. Subscription work and full production validation remain Phases 11 and 12.

## Validation

The account update adds email signup, Google sign-in, unique usernames, required preferred names, guest linking and password recovery in the existing forms. See [account authentication](account-authentication.md). The analyzer is clean; 74 Flutter tests and 47 backend tests pass, and one browser-only storage test is skipped on the VM. All six Edge entry points type-check, including the predeployment check. Live Firebase email/guest tests and deployed Firebase-to-Supabase account lifecycle/isolation/erasure tests pass. Web release and Android debug builds succeeded after Google configuration; its authorization-start check returns HTTP 200 with the matching client/callback. Build artifacts are `build/web/` and `build/app/outputs/flutter-apk/app-debug.apk`; renders are in `build/application-review/`. Interactive Google consent and device runtime checks remain pending.

Database tests use isolated PGlite PostgreSQL; provider tests use deterministic doubles. These do not establish live model quality or production cloud security. The separate Chrome storage test targets the actual storage plugin, but its harness stalled during loading and did not reach the test body. Direct browser verification could not proceed because Computer Use could not determine the current Windows browser URL confidently enough to enforce policy. No browser-storage or hardware verification is claimed.

See [interactive application notes](interactive-application.md), [README](../README.md), and [backend setup](backend-setup.md).
