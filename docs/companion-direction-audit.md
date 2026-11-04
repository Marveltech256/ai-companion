# Personal companion audit and implementation plan

Recorded 3 November 2026, before code changes for the critical direction update. This supersedes the assumption that adding a working chat interface alone establishes the intended companion behaviour.

## Findings from the existing implementation

| Area | What works | Gap or correction needed |
| --- | --- | --- |
| Application | Responsive Flutter screens, editable companion settings, memory editor, conversation history, privacy/account controls, explicit voice turns | Preserve these screens and controls. The setup name belongs to the companion, not the person. There is no editable preferred-name/routine profile wired into AI context. |
| Persistence | Supabase `memories` stores owner/companion, source message/quote, confidence, importance, timestamps, expiry and user edits. Consent epochs, extraction jobs, tombstones and recovery exist. | This is real persistent memory, not merely a conversation buffer. However, the extractor accepts only durable facts from one message, has no routine category or temporal event representation, and lacks first-meeting context for answers such as “Marvin.” |
| Retrieval | `morrow_search_memories` combines full-text relevance, importance and recency, capped at eight facts | A short greeting can crowd out identity/routine/event facts. Stable identity, current routines, upcoming/recent events and relevant older discussions need dedicated bounded retrieval. Preserve full-text search; do not send the entire archive. |
| Reply context | The Responses API receives companion style/interests, optional interaction counts, eight memories and up to 18 recent messages from the current conversation | `profiles.display_name` is not passed to the model. User-local date/time, preferred language, first-meeting state, routine windows, event dates and previous-conversation continuity are absent. |
| First meeting | Companion creation and ordinary chat work | No assistant-initiated welcome, persisted introduction state, skip handling or controlled discovery sequence. Starting a new conversation can feel like starting over. |
| Personalization | Explicit style/length/interests and separately consented turn-count/message-length observations | Counts are not a routine or personality model. Learn only grounded preferences and user-supplied schedules; never infer diagnoses or personal traits from usage. |
| Proactivity | Server-side queue/leases, one-time follow-up API, IANA timezone, days, quiet hours, registration/cancellation, duplicate cap, expiry and generic FCM push exist | Scheduling is not deployed. One time/day is the only schedule. Jobs have no personal reason/topic/source or meaningful conversation route. Worker copy is generic. History is not exposed to the app. FCM acceptance is labelled `sent`, which must not be presented as proven device delivery. |
| Reminders | Backend can schedule/cancel a UTC follow-up | No user-facing event/reminder management or confirmation tied to the actual event. The model has no scheduling tool and correctly must not promise a reminder. |
| Voice | Transcription uses the same saved text turn, history and extraction path; microphone/cancellation fences exist | The improved context must be assembled in that shared path, not in a separate voice personality/memory system. |
| Privacy | Exact Firebase-project ownership/RLS, server verification/revocation, owner-bound services, export, retention and resumable erasure | Extend the same rules to every new record. Correcting/deleting a fact must remove it from future identity/context/follow-ups. Preserve manual corrections and consent/reset fences. |
| Device workspace | A separately labelled, persisted user journal and manually managed memories | It is not an AI companion and must remain honestly labelled. Never add synthetic assistant replies or claim cloud synchronization. Preserve it; do not substitute it for live AI acceptance. |

## Prioritized incremental plan

1. **Identity and bounded context.** Add an additive migration and a single owner-scoped context assembler. Retrieve explicit profile/preferred name, language/timezone, relevant structured memories, current routine, upcoming/recent events, recent discussion anchors and current user-local time. Newer confirmed corrections take precedence over older facts. Keep historical messages bounded. Preserve the Responses streaming API and existing conversation leases.
2. **Grounded memory and continuity.** Add the requested identity, routine, preference, relationship, event, discussion and development classifications without discarding legacy categories/data. Preserve provenance, confidence, verification, temporal validity and user edits. Give extraction bounded prior-question context for first-meeting answers; keep source quotations mandatory. Temporary states and date-specific events must not become permanent routine facts. Add optional semantic reranking only over already owner-scoped candidates, with a strict budget and a deterministic retrieval fallback.
3. **First meeting and personality.** Initiate a real assistant welcome through the existing conversation surface and persist its state/idempotency. Ask one relevant question at a time, allow skipping, and stop repeating introductions or declined questions. Use known names naturally without forcing them into every reply. All transparency and healthy-boundary rules remain.
4. **Routine/event-aware proactivity.** Extend the existing queue rather than replacing it. Store explicit per-user routine windows, exceptions and events; give each check-in a reason, consent/preference revision, source and target conversation. Support user-selected frequency, one-time reminders, cancellation and bounded notification history. Respect timezone/day changes, quiet hours and known sleep/work blocks. Distinguish queued, provider-accepted, uncertain, received and opened outcomes. Do not claim delivery from an FCM acknowledgement alone.
5. **Existing controls only.** Reuse Our rhythm, the memory editor, current conversation controls and the existing notification panel for profile/routine/reminder/history operations. Preserve the visual design and routes. A genuinely new application screen requires a separate design check and approval; none is assumed in this plan.
6. **Acceptance evidence.** Add database/API/context and client integration regressions for the ten requested scenarios, then run live provider/device checks once services are active. Test doubles establish contracts, not natural model behaviour or closed-app push delivery. Record each scenario's local and live outcome separately.

## Non-negotiable implementation rules

- Never invent identity, schedules, dates, interests, diagnoses or remembered conversations. Missing information remains missing.
- Automatic memory follows consent. Explicitly edited profile/preferences are distinct from inferred memory; the UI must explain that distinction. No age collection unless volunteered and needed.
- Resolve relative dates using the source message's timestamp and an explicitly supplied user timezone. If either is insufficient, preserve uncertainty and ask; do not invent a reminder time. “Tomorrow” is not already “yesterday” on the next morning.
- A reminder is created only through a confirmed scheduling operation. A model statement alone is not a schedule or proof of delivery.
- Notification previews remain generic by default to avoid exposing names or private life events on a lock screen. Personalized content belongs to the verified, owned conversation after opening it.
- No new backend/project, UI redesign, replacement authentication, or removal of working features.

## Acceptance gates and current blockers

| Requested scenario | Required local evidence | Required live evidence |
| --- | --- | --- |
| 1. Name recognition | Saved preferred identity retrieved in a fresh conversation after reopening | Live model naturally uses the correct name |
| 2. Memory continuity | Work-week routine persists and is retrieved under the correct local date | Next-day live reply references the real schedule |
| 3. Event follow-up | Relative event date anchored to source time; recent event retrieved at the correct time | Live follow-up is chronologically correct |
| 4. Routine personalization | Explicit sleep/work windows and exceptions respected in local-time context/scheduler | Real-device schedule and user review |
| 5. Closed-app proactive message | Scheduler claim/dispatch/route/receipt contracts pass | Backend cron plus FCM/APNs delivery with app closed |
| 6. Independent personalization | Different owners receive only their own preferences/context | Two real test accounts receive distinct live responses |
| 7. Name correction | Updated profile/canonical memory wins; stale names excluded | Live reply stops using the old name |
| 8. Quiet hours | Boundary, timezone and DST tests; dispatch-time recheck | Real delivery timing/expiry on devices |
| 9. Voice continuity | Voice transcript enters the same context/memory pipeline | Microphone/transcription/speech round trip |
| 10. Isolation | RLS/RPC/API tests reject cross-owner reads and writes | Verify policies and two accounts in the target project |

The OpenAI server key was explicitly confirmed unconfigured in this conversation. Firebase server credentials/provider checks, Web registration, target Supabase schema inspection/migration deployment, cron activation and real push/audio testing remain outstanding. No real-world acceptance scenario is marked passed merely because a local test double passes. This work cannot be declared fully complete until the live gates above are actually verified.

## Provider references

The existing stateless Responses usage can be preserved by assembling bounded application-owned context, following [OpenAI conversation-state guidance](https://developers.openai.com/api/docs/guides/conversation-state). Extraction/reranking outputs must be validated even when their shape follows [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses). No provider-side conversation archive is required for the proposed changes.

## Local implementation evidence — 3 November 2026

Priorities 1–5 above are now implemented in the existing project, using additive candidate migrations 010/011, the shared Responses/memory pipeline, existing leased scheduler and existing Flutter screens/dialogs. No new application screen or design replacement was introduced. The device journal remains separate and never produces a substitute AI reply.

Implemented: explicit personal profile; all seven memory kinds; source-clock snapshots; temporary/dated/annual facts; calendar-correct leap birthdays; weekday/overnight routines and date-specific overrides; bounded identity/event/routine/history context; optional owned-candidate semantic ranking; persisted assistant welcomes; reminder confirmation/idempotency; up to three daily slots/cap; quiet/routine/day-boundary checks; contextual source/version invalidation; generic previews; persisted target conversation; cancellation and receipt/open history. Text and voice retain the same turn/extraction pipeline.

Local database/provider-contract suite: **34 passing tests**, covering fresh-conversation name retrieval/correction/isolation, original-date resolution/unknown timezone, routines/exceptions/overnight windows, annual dates, memory opt-out, greeting idempotency, context bounds, DST/quiet windows/frequency, source correction, reminder retries, timezone cancellation, proactive persistence, provider-acceptance semantics, owner-scoped receipts, and cancellation during preparation. Provider responses and push transport in this suite are doubles, not live OpenAI/FCM results.

Client suite: **51 passing tests**, with the separate browser-only storage test skipped on the VM. Includes real widget interactions, personal-details editing/home greeting, assistant-only greeting, persisted device profile/routine/export and verified notification routing. Flutter analysis and all six Deno Edge entry points pass. Live acceptance for all ten requested scenarios remains **pending**; these local checks do not close the live gates or establish natural model quality, closed-app delivery or hardware audio.
