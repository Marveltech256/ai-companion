# Personal friend product update — 3 November 2026

This continues the existing Flutter/Firebase/Supabase application. The supplied
Master Product Retraining brief replaces earlier navigation and Talk decisions.
Brand assets, colours, typography, authentication, owned data and working
backend capabilities are retained.

## Latest refinement — automatic preferences and Chat voice messages

The subsequent screenshot request is implemented and deployed. Timezone uses
the OS/browser IANA zone, with a searchable city dropdown and manual override;
no IP lookup or location permission is needed. Automatic mode updates on app
resume, while manual choices are preserved. The two large companion/style and
memory settings panels are removed. Explicit companion-mode acceptance enables
memory and personalisation together; migration does not convert prior opt-outs.
Saved-detail correction and account export/erasure remain secondary privacy tools.

Chat now records up to 60 seconds, keeps the original locally for replay, and
shows an editable transcript before Send. Retry/discard and recording cancellation
are supported. Text/Voice reply selection persists; complete saved assistant
messages can be spoken and replayed. Text remains visible. Leaving Chat stops
capture, and identity changes discard unsent audio. Talk is still Coming Soon
for real-time calling. Tone and reply length adapt to current words and requests;
mood is tentative context, never a diagnosis or a permanent personality claim.

Final checks: clean analysis, **84 Flutter tests** (one browser-specific VM skip),
**51 backend tests**, all six entry points type-check, Android debug and web
release builds succeed. Migration 016 and four changed functions are deployed.
All **16 tables have RLS**, all **90 RPCs** retain expected privileges; the fresh
installer contains **16 migrations**. Do not rerun it on this installed project.

The older Gemini 3.1 model passed initially, then returned repeated provider 503s.
After direct streaming/extraction/transcription tests, the configured low-cost
model was changed to **gemini-3.5-flash-lite**; speech uses
**gemini-3.8-flash-lite-tts**, voice Kore. Final deployed synthetic checks pass:
name/time/negation transcription, confirmed-text persistence, real WAV speech,
foreign-message denial, chat idempotency, grounded extraction and recall after a
fresh login. Every temporary account was erased. Published standard 3.5 rates are
$0.30 input / $2.50 output per million tokens ([Google pricing](https://aistudio.google.com/docs/pricing#gemini-3.5-flash-lite)).
Google billing remains disabled and unchanged; paid API setup is still required
before customer personal-data use. OpenAI activation remains pending.

The compiled PC browser app is served at **http://localhost:52100** using
`node tools/serve_pc.mjs`. HTTP/assets were verified. Browser control was stopped
by the user's physical Escape key, so no further browser actions were taken.
Interactive Google sign-in and physical microphone/speaker testing remain for
the user. No Windows native executable or Mac/iOS build was claimed.

The conversation responsiveness follow-up keeps streamed messages visible while
persisted IDs reload. The empty-chat introduction appears only after a genuinely
empty conversation has finished loading; loading cannot initiate an extra AI
greeting. Conversation-list and memory refreshes no longer hold up the next turn,
and existing context/personalisation database reads run in parallel before one
generation request. Model, prompts, token budget, provider routing and memory
extraction policy are unchanged. This reduces application/network waiting; it
does not claim a guaranteed change to model generation time. Desktop Enter and
numpad Enter send once, Shift+Enter retains newline behavior, and composing text
is not submitted. Regression tests hold network responses to verify no empty
screen flash, no extra generation and no loss of a pending voice draft.

The following audit and stage table record the earlier baseline delivery; this
latest refinement supersedes its counts, manual settings and audio status.

## Stage 1: audit

| Area | Current evidence and gap |
| --- | --- |
| Navigation | Four primary items expose Memories and Our rhythm. Chat is labelled Talk, while a separate voice page implies a call. Replace with Home, Chat and an honest Talk preview; keep privacy/memory controls in Settings. |
| Home | Uses the preferred name, but repeats one greeting, shows generic interest suggestions and a memory count. It lacks actual conversation/reminder activity. |
| Registration | Firebase email/Google and required account gate work. Unique usernames/preferred names persist. Age groups and a short personal first meeting are absent; language/timezone are optional free-text settings. |
| Identity/context | Profiles already hold explicit names, language and timezone. The context RPC retrieves owned identity, routines, events and previous discussions. Reuse it rather than rebuilding memory. |
| Personality | Warmth, honesty, personal boundaries, source grounding and continuity already exist. Make selected-language adherence and gradual discovery explicit. Never fabricate a relationship, memory or reminder. |
| Memory/routines | Seven structured memory kinds, source quotes, corrections, tombstones, consent, retention and cross-conversation retrieval already exist. Live extraction still needs a successful deployed provider test. |
| AI access | Gemini restricted server key exists. 3.8 Flash returned high-demand 503; 3.1 Flash-Lite passed a direct real request and is now configured. Deployed streaming/history/memory verification is running. OpenAI Developers currently reports disconnected; secure OpenAI key creation remains authorized. |
| Notifications | Owned queue, leases, quiet hours/timezones, daily limits, routine guards, consent and received/opened acknowledgements exist. No scheduler is activated and closed-app device delivery is unverified. Add configurable inactivity without repeated unanswered prompts. |
| Voice | Existing capture/transcription/speech infrastructure is preserved. It is not a completed real-time calling service. Talk must be Coming Soon. Optional welcome audio must be user initiated and use a real speech service. |
| Privacy/subscriptions | RLS, account isolation and erasure have live evidence. Preserve memory inspection/deletion and consent in Settings. Subscriptions remain a later phase; do not invent entitlements or convert consumer subscriptions into API credentials. |

The immediate reason there are no real companion replies was provider activation
and availability, not a missing chat screen. Consumer app subscriptions do not
serve as reusable backend API keys. Billing changes and paid-service activation
remain separate decisions.

## Ordered implementation

1. Simplify navigation and Home; retain existing memory and settings controls.
2. Add concise age/language/timezone introduction and a once-only personal
   welcome. Keep registration short and return existing users to their space.
3. Strengthen language/continuity instructions and verify the existing grounded
   memory and routine correction paths rather than adding parallel systems.
4. Add inactivity preferences to the existing notification machinery and expose
   actual upcoming reminders/recent discussions on Home.
5. Present Talk as Coming Soon, preserving the future voice architecture.
6. Test the major paths, build Android/web, and record provider, scheduler,
   audio and physical-device limits without claiming unobserved delivery.

The owner first requested 15+, then explicitly changed this release to **18+**
after reviewing Google's API age requirements. Adult age ranges are self
reported; this is not verified identity/age assurance. No birth date is collected.
Paid Gemini API setup is explicitly deferred. No private key is placed in
Flutter, public configuration, source or chat.

## Delivery and stage verification

| Stage | Changed and tested | Remaining |
| --- | --- | --- |
| 1 Audit | Reviewed existing screens, auth, schema/context, memory, proactivity, voice and provider access. Found and corrected the FCM `fid` payload bug to the documented `token` field. | Physical platform checks. |
| 2 Simplicity | Home/Chat/Talk navigation, Settings icon, memory inspection/correction in Settings; responsive widget tests and rendered Android-sized/desktop screens pass. | Device accessibility/performance review. |
| 3 Introduction | Required adult age range, language and IANA timezone; optional companion preferences; once-only personal welcome followed by first chat. Existing users keep their companion/history and confirm the introduction once. API rejects under-18/unconfirmed inputs before model access. | Welcome audio is wired to real saved-message speech, muted by default and replayable when the server advertises audio; OpenAI speech configuration/device playback remain pending. |
| 4 Personality | Explicit selected-language adherence, first-meeting/returning context, gradual discovery and truthful boundaries on offline activity. | Longitudinal quality evaluation. |
| 5 Memory | Real Gemini streaming, saved/idempotent replies, grounded extraction and hobby recall after fresh Firebase password login in a new conversation pass. | Multi-day real-user quality/retention testing. |
| 6 Routines | Existing structured routines, source-grounded updates, exceptions, tombstones and routine notification guards retained; PostgreSQL continuity/proactivity tests pass. | Real-user schedule quality. |
| 7 Check-ins | Configurable 1–14-day inactivity gap or explicit scheduled cadence. One unanswered inactivity check-in per absence; a new user reply resets the gap. Consent, quiet hours, timezones and explicit reminders remain independent. FCM serialization and cancellation tests pass. | Scheduler secret, Cron/pg_net activation and closed-app device delivery. `prepare_schedulers.sql` prepares inactive jobs after secure prerequisites; it has not been executed. |
| 8 Home | Actual recent conversations, verified profile-local clock/return context, queued reminders and confirmed upcoming event facts; empty sections are omitted. Live Home check has no invented reminders/events. | Physical-device presentation. |
| 9 Talk | Coming Soon preview has no call/microphone controls; original capture/transcription/speech services are retained for future real-time calling. Widget test confirms zero microphone requests. | Real-time calling is intentionally not released. |
| 10 Refinement | Clean Flutter analyzer, 74 Flutter tests, 47 backend tests, all six Edge entry points type-check, Android debug and web release builds succeed. Screens rendered and visually reviewed. Migrations 014/015 and four changed API functions deployed. | Interactive Google sign-in, Mac/iOS build, audio/hardware, notification delivery and provider billing activation. |

Live schema verification: all 16 application tables retain RLS; all 85 SQL
functions have expected privileges. Fresh installation includes 15 migrations;
do not rerun the installer on the existing project. Temporary live-verification
identities and their owned data were erased through the privacy API.

Gemini `gemini-3.1-flash-lite` passes real synthetic adult-account tests. The
earlier 3.8 model returned 503 high demand. Standard published paid rates for
3.1 Flash-Lite are $0.25 input / $1.50 output per million text tokens. OpenAI
`gpt-6-luna` is the proposed low-cost current-family model at $0.10 / $0.50;
its project access is unverified and no OpenAI secret/model was installed.
OpenAI Developers still reports disconnected/not installed in the latest lookup.
New-key creation remains authorized; do not ask the owner to approve it again.

Google AI Plus is a consumer subscription, not the API project's quota/billing.
The Google project's billing remains disabled. Google's unpaid API terms prohibit
personal information, so successful synthetic tests do **not** authorize a
customer launch or real personal conversations before paid API setup. The owner
chose to handle that separately. Nothing changed billing or charged a card.

An attempted provider pause/model switch was rejected by automatic approval
review because no working OpenAI key was confirmed and replies could stop.
The safe continuation kept the existing Gemini routing/model settings intact;
the owner's subsequent 18+ choice preserves that provider path. No rejection
was bypassed. OpenAI activation remains blocked by the missing connection.

Sources: [Google API terms](https://ai.google.dev/gemini-api/terms),
[Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing#gemini-3.1-flash-lite),
[OpenAI pricing](https://developers.openai.com/api/docs/pricing),
[FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api),
[Supabase scheduling](https://supabase.com/docs/guides/functions/schedule-functions).
