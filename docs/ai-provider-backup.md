# OpenAI primary and Gemini backup

Text generation uses `createTextAi` in `supabase/functions/_shared/text_ai.ts`.
The shared provider implementation powers conversation replies, assistant greetings,
memory extraction/recovery and proactive message writing. Optional semantic
memory ranking also supports backup through `createMemoryReranker`.

OpenAI remains primary. Gemini is available only when `GEMINI_API_KEY` and
`GEMINI_MODEL` are configured on the server. Setting
`GEMINI_BACKUP_ENABLED=false` explicitly disables it. Keys never enter Flutter
configuration. The model values are plain model IDs enabled for the owner's
provider account; no model or API key is invented by the application.

Server variables:

| Variable | Purpose |
| --- | --- |
| `OPENAI_API_KEY`, `OPENAI_MODEL` | Primary credentials and text model |
| `OPENAI_MEMORY_MODEL` | Primary extraction model; defaults to primary text model |
| `GEMINI_API_KEY`, `GEMINI_MODEL` | Backup credentials and text model |
| `GEMINI_MEMORY_MODEL` | Backup extraction model; defaults to Gemini text model |
| `OPENAI_RETRIEVAL_MODEL`, `GEMINI_RETRIEVAL_MODEL` | Optional semantic ranking; neither configured means no ranking request |
| `GEMINI_BACKUP_ENABLED` | Optional `false` to disable backup |

Store these in Supabase **Edge Functions → Secrets** for project
`rvokidwyzwygpzzkpqck`. The shared factory is deployed with the six existing
functions; a schema migration is not needed for provider routing.

Failover happens once, only before any nonempty primary reply text is emitted.
HTTP 408/429/5xx, transport failures, missing primary configuration and a
15-second first-text timeout can use Gemini. Caller cancellation, an expired
overall deadline, invalid/auth/permission requests, provider refusals and visible
partial replies do not trigger a provider switch. A partial reply is marked
interrupted and can use the existing idempotent retry flow. There is no canned
success response when both providers fail.

Extraction gives the primary 12 seconds within the existing 30-second job
deadline; ranking gives it two seconds within the five-second retrieval budget.
The same extraction instructions/schema, source quote/time/timezone and
application grounding checks are used on both providers. Ranking accepts only
already-owned candidate IDs. Normal messages still persist once under the same
request ID and lease. Logs contain only the backup operation name.

Gemini uses Google's native server-side GenerateContent REST endpoints, SSE
streaming and JSON-schema output. Thought parts are excluded. Safety blocks,
truncation and streams without successful completion are surfaced as errors.
The existing account, ownership, memory-consent and erasure checks run before
provider access. Settings disclose text processing by the backup provider.

Audio chooses a configured OpenAI operation first, otherwise Gemini. Gemini transcription uses `gemini-3.5-flash-lite`; speech uses `gemini-3.8-flash-lite-tts`, voice Kore. Real deployed synthetic tests pass editable-transcript persistence, owned-message speech and WAV output. No provider key enters Flutter.

Verification: **50 backend tests**, **81 Flutter tests**, clean Flutter analysis and all six Edge entry points type-check. Android debug and web release builds succeed. Updated Home/welcome/Talk renders were inspected. Migrations 014/015/016 are deployed; all 16 tables retain RLS and all 90 functions have expected privileges.

The authorized **Ai Companion Gemini Server** key is restricted to `generativelanguage.googleapis.com`. Supabase holds the private key, `gemini-3.5-flash-lite` text/memory models and backup enabled. Private upload files were removed. The earlier 3.8 model returned 503 high demand; 3.1 Flash-Lite later became overloaded; 3.5 Flash-Lite passes real direct and deployed requests.

Real synthetic adult-account tests pass streaming, saved/idempotent replies, grounded extraction, recall after fresh password login, French preference and truthful Home activity. All temporary identities/data were erased. These checks do not establish multi-day relationship quality or device audio/push delivery.

The owner explicitly chose **18+**. Google billing remains unchanged and disabled. Paid Gemini API setup is required before customer personal-data use; the owner explicitly deferred it. Google's unpaid API terms prohibit personal information; consumer Google AI Plus benefits do not replace API project quota/billing. Standard paid 3.5 Flash-Lite rates are $0.30 input / $2.50 output per million text tokens.

OpenAI `gpt-6-luna` is the proposed low-cost current-family model at $0.10 input / $0.50 output per million tokens, pending project access and real verification. It is in the server example only; no unverified OpenAI key/model was installed remotely.

Local verification tools:

- `node tools/check_gemini_project.cjs`: reads API enablement, key restriction
  metadata and billing status without retrieving the key string.
- `node tools/check_gemini_access.cjs`: makes a minimal real generation request
  with bounded retries and sanitized status output. The key stays in memory.
- `node --experimental-transform-types --import ./backend/register.mjs tools/live_conversation_smoke_test.mjs`:
  checks the deployed greeting, reply, idempotent history and grounded memory,
  then erases only its own test identity. A failed greeting stops later checks.

Ignored reports are in `.cache/gemini-server-provisioning.json`,
`.cache/gemini-project-preflight.json`, `.cache/gemini-live-provider-access.json`
and `.cache/live-conversation-verification.json`. They contain status metadata,
not credentials. All generated examples use fictional test data.

The user approved creating a new OpenAI project key on 3 November 2026. The latest plugin lookup reports OpenAI Developers not installed/connected, and no Platform key tools are exposed here. No OpenAI key/private local file was created. Connect it through Apps, then resume secure key provisioning without asking again whether a new key is wanted. An attempted provider pause/model switch was rejected by automatic approval review because it could stop replies without a confirmed OpenAI key. Existing Gemini routing was retained, consistent with the owner's subsequent 18+ choice.

References: [Google GenerateContent REST](https://ai.google.dev/api/generate-content),
[structured output](https://ai.google.dev/gemini-api/docs/structured-output),
[OpenAI Developers setup](https://developers.openai.com/learn/developers-codex-plugin).
