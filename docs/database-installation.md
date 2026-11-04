# Install Ai Companion in the empty Supabase project

Use project `rvokidwyzwygpzzkpqck`. Firebase Authentication is project `ai-personal-companion`.

Migration 019 adds protected review guests using Firebase custom tokens and two
private tables. It preserves anonymous-identity denial. There are now 23 RLS tables,
110 application functions and nine deployed Edge Functions; review access is
enabled while purchases remain inactive. See [review guest setup](review-guest-access.md).

Firebase email/password and Google are enabled; anonymous signup is disabled. Deployed user APIs reject real guest tokens. Migration 013 was applied to the installed database and rejects guest RLS reads while retaining existing data. Registered signup/login/profile saving and isolated account erasure still pass. Google uses **Ai Companion** and temporary support address **atalyebamarvin4@gmail.com**; interactive Google login still needs device/browser verification.

The user installed the SQL manually. After signing into the owning CLI account, administrative read-only checks on 3 November 2026 confirmed **all 23 application tables with RLS**, Firebase project `ai-personal-companion`, the username/preferred-name columns and valid unique username index. All **110 functions** match the expected privileges: anonymous execution is denied for every function, service-role execution is allowed, and authenticated execution is allowed only for the two ownership helpers. **Do not rerun the fresh installer on this project.**

All nine Edge Functions are deployed. The restricted Firebase server credential, project ID and exact browser origins are configured in Supabase's secret manager. Live signup/profile-save/password-login/reload, companion persistence, case-insensitive duplicate username rejection, cross-account denial and account erasure all pass. The isolated temporary identities and their application data were erased through the privacy API. Daily privacy cleanup is active. OpenAI, paid Gemini setup, Play-signed Google login and hardware checks remain pending; purchases and AI check-ins remain inactive.

## Run the supplied SQL in a fresh database only

1. Open that Supabase project → **SQL Editor → New query**.
2. Open [`ai_companion_complete_setup.sql`](../supabase/setup/ai_companion_complete_setup.sql), copy **the entire file**, paste it into the query and run it once.
3. The final result should say `installed`, show `ai-personal-companion`, and report **23 application tables**.
4. Run [`verify_installation.sql`](../supabase/setup/verify_installation.sql). Every application table should exist with row-level security enabled. The identity project must match Firebase, and `profiles` must have `username` and `preferred_name`.

The complete file contains all 19 migrations, functions, indexes, consent/memory/notification tables and ownership policies required by the current app. It runs in a transaction and stops before changes if application objects already exist. It does not erase a database, create test users or insert demo conversations. It does not recreate Supabase-managed auth roles or `auth.jwt()`.

New application tables initially have no user rows. After live signup, the verified API creates a row in `public.profiles` under the Firebase UID; companion setup creates `public.companions`. Firebase users appear in **Firebase Authentication**, not Supabase Authentication → Users. This architecture deliberately uses Firebase identity and Supabase application tables.

The fresh-install bundle is an alternative to applying the 16 migration files individually. Do not run both. Before later adopting CLI `db push` on an SQL-Editor installation, reconcile migration history with the applied source versions using the Supabase migration tools; do not rerun the initial migrations over these tables.

## Deploy the server API after SQL

SQL creates the database layer. The mobile/browser application also calls the six Edge Functions, which are now deployed in this project. The following steps document setup for a fresh environment or later redeployment.

The CLI is now signed into an account with access to the target project. If access is lost, sign into the Supabase account that owns this exact project:

```powershell
npx supabase login
npx supabase projects list
```

The following values are already configured through the server secret manager. For a new environment, configure them through **Supabase → Edge Functions → Secrets**:

| Name | Value |
| --- | --- |
| `FIREBASE_PROJECT_ID` | `ai-personal-companion` |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Private server service-account JSON for this Firebase project, with the existing account-status/deletion and FCM permissions |
| `ALLOWED_ORIGINS` | Exact browser origin(s), for example `http://localhost:52100` during local web development |

Supabase injects its managed `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` into Edge Functions. Keep server credentials in the secret manager, never Flutter/Dart defines or chat. OpenAI and scheduler variables listed in [backend setup](backend-setup.md) enable AI/voice/proactivity separately; account creation does not require an OpenAI key.

From the project folder, redeploy the six functions with the checked-in configuration:

```powershell
npx supabase functions deploy companion-api conversation-turn voice privacy checkin-dispatch privacy-maintenance --remote=rvokidwyzwygpzzkpqck --use-api --jobs 2 --yes
```

`verify_jwt=false` is intentional for this Firebase-token architecture: user functions validate Firebase signatures, project, account status and UID internally; worker functions require the scheduler secret. Do not replace those checks with an unauthenticated client write. See [Supabase function deployment](https://supabase.com/docs/guides/functions/deploy) and [server secrets](https://supabase.com/docs/guides/functions/secrets).

## Verify the complete connection

Live API checks now pass signup with Firebase, a verified Edge account lookup, owned Supabase username/preferred-name and companion saves, and password login restoring that same profile. A second isolated account cannot read the first account's conversation or take its username. The deployed privacy API removes the test profiles and Firebase identities. The repeatable check is `node tools/backend_account_smoke_test.mjs`; it creates and erases only its own temporary identities, and never logs passwords or tokens. Browser CORS was checked using `http://localhost:52100`, the fixed IDE web port.

The exact combined SQL also passed isolated PostgreSQL tests: **50 backend tests**, including empty-database installation, RLS, preferred-name persistence and safe rejection of a second installation. Separate administrative checks establish the actual remote schema state. Interactive Google sign-in, app/device behavior, OpenAI activation, physical microphone/speaker behavior and scheduled delivery still need their own checks.
