# Connecting Ai Companion's services

Live verification on 3 November 2026 now passes the Firebase → Edge → Supabase account flow: email signup, username/preferred-name saving, companion persistence, password login/reload, cross-account isolation and account erasure. Temporary test identities and their application data were removed. All 16 application tables have RLS, the identity project and username index match, and all 90 SQL functions have the expected privileges. All six Edge Functions are deployed and reject unauthenticated requests. Google is enabled with app name **Ai Companion** and temporary support email **atalyebamarvin4@gmail.com**; Android/iOS OAuth configuration is synced, but interactive Google login remains untested. See [installation and connection status](database-installation.md). The OpenAI key, scheduler configuration and hardware checks remain pending.

## Public Flutter configuration

For a new checkout, copy `config/development.example.json` to the ignored `config/development.json`. This workspace already has the supplied Supabase and mobile Firebase values in that file; preserve them. Supply the Supabase HTTPS project URL and an `sb_publishable_` key, the Firebase project ID, sender ID, and registered app ID for each platform being run. Set each platform's own key in `FIREBASE_ANDROID_API_KEY`, `FIREBASE_IOS_API_KEY`, and `FIREBASE_WEB_API_KEY`. `FIREBASE_API_KEY` remains a fallback for configurations that use one shared key. For web, include the Firebase auth domain; for iOS, include the registered bundle ID. These are client configuration values, not server credentials. Do not substitute a mobile app ID for a Web app ID.

The Android application ID and Kotlin namespace now match the supplied registration, `com.aipersonalcompanion`. Its original `google-services.json` is in `android/app/`, processed by the Google Services Gradle plugin. The iOS app bundle ID is `com.ai-personal-companion`; its original `GoogleService-Info.plist` is included in the Runner resources for all build configurations. Flutter also initializes Firebase with the corresponding platform-specific options. The native identifiers and public keys agree with the supplied registration files. See [Firebase Android configuration](https://firebase.google.com/docs/android/setup).

Firebase's Web app and localhost domains are configured. **Anonymous signup is disabled**. All four user Edge APIs reject real guest Firebase tokens, and migration 013 requires a registered provider for RLS reads. Valid registered sessions restore their companions. Existing guest data is preserved for credential linking at account creation.

Email/password and Google sign-in are enabled. Legacy guest-account linking and recent-authentication dialogs remain available. Production exposes no guest or journal entry; separate development journal entry points retain device data without upload.

The OpenAI key remains unconfigured on 3 November 2026. Gemini 3.5 Flash-Lite passes real synthetic adult-account text/memory checks. The release is 18+; explicit adult introduction is checked before AI/data operations. Google billing remains unchanged and disabled. Paid Gemini API setup is required before customer personal-data use; the owner explicitly deferred it.

Use Flutter's explicit Firebase options supplied by the public configuration. Native Firebase registration and platform setup still need testing on the intended devices. See [Firebase Flutter setup](https://firebase.google.com/docs/flutter/setup).

## Server environment

Gemini text fallback is deployed for replies, greetings, memory recovery and proactive writing. The key is restricted to `generativelanguage.googleapis.com` and stored in Supabase with `gemini-3.5-flash-lite` text/memory models and backup enabled. Real synthetic adult-account tests pass streaming, saved/idempotent replies, grounded extraction, recall after fresh password login, French preference and truthful Home activity. Google billing remains unchanged and disabled. Paid Gemini API setup is required before customer personal-data use; the owner explicitly deferred it. Gemini transcription and WAV speech pass deployed synthetic checks; physical audio remains unverified. See [provider verification](ai-provider-backup.md).

The required account entry supports email signup/login and Google sign-in. Legacy guest credentials can be linked to preserve their UID, but guest sessions cannot use the app. Native registrations include the real OAuth IDs. See [account authentication](account-authentication.md).

Supabase now stores `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_JSON` and `ALLOWED_ORIGINS` in its secret manager. The dedicated server identity is `ai-companion-edge@ai-personal-companion.iam.gserviceaccount.com`, with custom role `aiCompanionEdge` containing only `firebaseauth.users.get`, `firebaseauth.users.delete` and `cloudmessaging.messages.create`. Its private key was uploaded through a temporary file restricted to the current Windows user, then that file was removed. No private server credential was added to Flutter or source files. Account lookup and deletion pass real endpoint checks. Browser origins allow localhost/127.0.0.1 on port 52100 and this project's two Firebase Hosting domains. Other website origins must be explicitly configured.

`supabase/functions/.env.example` lists the server variables. Copy it to an ignored local `.env` only when running locally; configure production values using the project's secret manager. Never put these values in Dart defines, assets, the public config JSON, or source control.

| Variable | Purpose |
| --- | --- |
| `FIREBASE_PROJECT_ID` | Set to `ai-personal-companion` so the handlers accept this project's ID tokens |
| `OPENAI_API_KEY` | Server-only OpenAI credential |
| `OPENAI_MODEL` | Model available in your account, supporting Responses streaming |
| `OPENAI_MEMORY_MODEL` | Optional structured-output extraction model; defaults to `OPENAI_MODEL` |
| `GEMINI_API_KEY` | Server-only backup key restricted to the Gemini API |
| `GEMINI_MODEL` | Backup text model; currently `gemini-3.5-flash-lite` |
| `GEMINI_MEMORY_MODEL` | Backup extraction model; defaults to `GEMINI_MODEL` |
| `GEMINI_BACKUP_ENABLED` | Set to `false` to disable backup; currently `true` |
| `OPENAI_RETRIEVAL_MODEL` | Optional semantic reranker over at most 32 owner-scoped candidates; empty disables the extra request |
| `GEMINI_TRANSCRIPTION_MODEL` | Gemini transcription; currently `gemini-3.5-flash-lite` |
| `GEMINI_SPEECH_MODEL`, `GEMINI_SPEECH_VOICE` | Speech: `gemini-3.8-flash-lite-tts`, `Kore` |
| `OPENAI_TRANSCRIPTION_MODEL` | Audio transcription model available in your account |
| `OPENAI_SPEECH_MODEL` | Speech synthesis model available in your account |
| `OPENAI_SPEECH_VOICE` | Built-in speech voice; defaults to `marin` |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Server-only credential for user status/revocation checks, account erasure, and FCM delivery |
| `SCHEDULER_SECRET` | Long random secret shared only with the scheduled workers and scheduler/Vault |
| `ALLOWED_ORIGINS` | Comma-separated exact browser origins, including scheme and port |
| `SUPABASE_URL` | Backend project's REST URL; managed Edge runtime supplies this |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-only database credential; managed Edge runtime supplies this |

The model is intentionally configurable. Verify that the selected model supports [Responses streaming](https://developers.openai.com/api/docs/guides/streaming-responses) and [strict structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs). The implementation calls the official Responses endpoint with `store: false`; this is an API option, not a claim of zero provider retention.

For a local web run, choose a fixed port, for example `flutter run -d chrome --web-port=52100 --dart-define-from-file=config/development.json`, and allow exactly `http://localhost:52100` in the local function environment. Native requests without an Origin header still require verified Firebase authentication.

## Migration inventory

| File | Change |
| --- | --- |
| `202611020001_foundation.sql` | Firebase-UID profiles, identity helpers, ownership policies, bootstrap |
| `202611020002_companions.sql` | Persistent companion/settings, consent version, retention policy |
| `202611020003_conversations.sql` | Conversations/messages, scoped history, idempotent turn leases, rate limit |
| `202611020004_memories.sql` | Categorized facts, provenance, relevance search, durable extraction jobs, edits/deletion/retention |
| `202611020005_memory_recovery.sql` | Bounded recovery of interrupted extraction jobs |
| `202611020006_personalization.sql` | Independent learning consent and completed-turn observations |
| `202611020007_proactivity.sql` | Notification preferences, device registrations, leased check-ins and delivery caps |
| `202611020008_voice.sql` | Voice consent, usage limits, owned persisted speech lookup |
| `202611020009_privacy.sql` | Exact-project RLS, consent audit, scoped exports, retention, resumable erasure |
| `202611030010_companion_continuity.sql` | Preferred identity, source-time memory, seven canonical kinds, current routines/exceptions, annual events, bounded context and idempotent assistant welcome |
| `202611030011_personal_proactivity.sql` | Frequency/slots, contextual reasons, routine guards, confirmed local reminders, delivery history/receipts, conversation routing and cancellation fences |
| `202611030013_require_sign_in.sql` | Registered provider required for client RLS |
| `202611030014_personal_introduction.sql` | Adult introduction/welcome, personal context and truthful Home |
| `202611030015_inactivity_checkins.sql` | Inactivity gap and one unanswered check-in per absence |
| `202611030012_account_names.sql` | Case-insensitive unique usernames and atomic owned username/preferred-name profile saves |

Apply them in timestamp order only after reconciling the target project. All data rows use Firebase UID ownership. Composite foreign keys prevent cross-owner relations. Client roles have owner-scoped RLS reads; write RPC execution is restricted to `service_role`. The Edge layer derives `p_owner` from the verified token rather than accepting it from the request body.

Deploy `companion-api`, `conversation-turn`, `voice`, `privacy`, `checkin-dispatch`, and `privacy-maintenance` with the checked-in `supabase/config.toml` and Deno import map. Their gateway `verify_jwt=false` settings are deliberate: user handlers cryptographically verify Firebase RS256 signatures against Google's JWKS and check issuer, audience, subject, expiration, issuance, and authentication time. The two worker routes require the server scheduler secret instead of a user token. Do not bypass these checks. See [Firebase token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens) and [Supabase function configuration](https://supabase.com/docs/guides/functions/function-configuration).

Ordinary user requests also check Firebase account existence, disabled status, and token revocation using the server credential; lookup results are cached for at most 15 seconds. Export and new erasure requests force a fresh account check. Missing server credentials fail closed. Provision only the required `firebaseauth.users.get`, `firebaseauth.users.delete`, and `cloudmessaging.messages.create` permissions for the relevant services. Confirm the `identity_configuration.firebase_project_id` database row matches `FIREBASE_PROJECT_ID` exactly. See [Firebase session revocation](https://firebase.google.com/docs/auth/admin/manage-sessions) and [account lookup](https://cloud.google.com/identity-platform/docs/reference/rest/v1/projects.accounts/lookup).

All current app operations use these verified Edge gateways. Supabase's Firebase third-party authentication integration is not needed for this path; configure it before adding direct client database/Realtime reads. Its identity mapping must remain consistent with the Firebase UID and issuer checks in the RLS helper. See [Supabase Firebase integration](https://supabase.com/docs/guides/auth/third-party/firebase-auth).

## Memory lifecycle

Replies retain the existing limit of 18 recent messages and an 18,000-character current-history budget. The continuity query retrieves at most 32 owner-scoped candidates, reserving identity, routine, event and communication-preference anchors. The assembler selects bounded facts with a 10,500-character JSON budget, up to eight current routines, six short earlier-discussion excerpts and five scheduling records. Scalar identity and the actual local clock are supplied separately. Optional semantic reranking has a five-second timeout and can only reorder these owned rows; failures fall back to structured/lexical ordering. The app does not resend the full archive.

Seven canonical kinds cover identity, routines, preferences, relationships, events, conversation continuity and personal development. Legacy categories/data remain supported. Extraction stores validated verbatim user quotes, source-message provenance, confidence/importance, verification and temporal status. A bounded previous assistant question can interpret a short answer such as a name; it cannot supply a fact. Relative dates use the original message time and its saved, explicitly known timezone. An unknown timezone leaves relative dates unresolved. Explicit annual birthdays/anniversaries retain month/day without inventing a birth year; leap-day occurrences use the next valid calendar date. Temporary facts expire after seven days; one-time events after their date plus 30 days (or source time plus 30 days if unresolved), subject to any shorter retention. Annual facts remain durable under the chosen retention. Credential/ungrounded-fact filtering is preserved; this is not a complete sensitive-data classification system.

The existing account dialog edits preferred name, optional full name, language, timezone and general location. Explicit profile identity takes priority over older automatic name facts. The existing memory editor exposes routine times/weekdays, date-specific exceptions, interruption boundaries, event status and annual dates. No age is requested. First-meeting and later greetings are real, idempotent assistant-only turns; they create no fake user message, extraction job or interaction count.

The existing notification editor supports one to three selected local times and a one-to-three-per-day cap, with days and quiet hours. Confirmed reminders use an idempotent request ID and a chosen local date/time/timezone. Ambiguous or nonexistent DST times require a different selection. Changing notification preferences invalidates queued work; changing the profile timezone also cancels pending/sending reminders for reconfirmation. Work/sleep blocks and date exceptions apply at claim and immediately before each push, with TTL capped at the next quiet/routine/day boundary. Contextual source edits, forgetting, cancellation, consent changes, deleted conversations and changed profile snapshots invalidate prepared work before dispatch.

The server worker writes the personalized assistant message to its owned conversation before contacting FCM. Push previews remain generic; payloads contain opaque check-in/conversation IDs. The client asks the verified backend for the owned destination rather than trusting a payload conversation ID. History distinguishes queued, provider-accepted, unconfirmed, received-in-app and opened states. The legacy database status `sent` means provider acceptance only. Foreground receipt or opening provides an app acknowledgement; no background delivery/display is inferred without one. FCM acceptance cannot guarantee the exact display time or recall an already accepted push. The existing settings and memory dialogs expose scheduling, cancellation and history. No production cron has been activated.

Completed replies enqueue durable extraction jobs. Jobs use leases, bounded retries, and recovery during bootstrap/memory reads. Pausing memory prevents retrieval and new extraction. Consent-version checks suppress work started before a consent change. Manual edits take precedence over automatic updates. Individual deletion records a stable-key tombstone; extraction cannot recreate that same key. Global deletion removes structured facts and suppresses older pending jobs. New conversations can create new facts while memory remains enabled.

Global retention accepts 1–3650 days or no automatic expiry. Per-record expiry is separately preserved. Expired facts are excluded from retrieval and lists and swept during relevant reads. After the target-project audit, arrange a daily server-owned invocation of `public.morrow_purge_expired_memories()` for physical cleanup even when a user never returns. No production schedule has been created.

Forgetting a memory does **not** erase conversation transcripts. Conversation deletion is a separate operation. Likewise, account-wide erasure, backup retention, and provider retention controls require the later privacy/release work.

## Activation verification

Live registered signup/login, adult introduction, profile persistence, isolation, erasure and Gemini text/memory checks pass using fictional test accounts. Guest access remains disabled. Test interactive Google consent, physical audio/push delivery and multi-day quality separately. Customer personal-data use requires the deferred paid API setup.

Local doubles alone do not prove cloud or hardware behavior. The live reports record only checks actually completed; temporary test identities/data were erased.
