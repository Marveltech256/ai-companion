# Ai Companion

Temporary protected **Guest for app review** is available on the welcome screen
in the 0.1.3 (4) candidate. Use the private code/instructions in
`config/PLAY_REVIEW_ACCESS.private.txt` for Play Console App access. Each guest
uses an isolated Firebase workspace and the same app services. See
[review access and remote removal](docs/review-guest-access.md).

The supplied Supabase project is installed and verified: 23 tables have RLS, nine Edge Functions are deployed, and live account lifecycle, reply reporting, isolation and erasure checks pass. Daily privacy cleanup is active; purchases and AI check-ins remain inactive. See [Phases 11–12 and remaining gates](docs/remaining-phases.md). The [complete SQL setup](supabase/setup/ai_companion_complete_setup.sql) is for a fresh database only; do not rerun it on this project.

Flutter personal companion application, implementing the supplied [Figma design](https://www.figma.com/design/ZR1ovxn0yC9WzkPjQYI7ZL/Untitled). Firebase owns authentication; Supabase owns application data and the Edge API; OpenAI and Gemini integrations run behind the backend.

Gemini's restricted server key and `gemini-3.5-flash-lite` chat/memory/transcription model are configured in Supabase, with `gemini-3.8-flash-lite-tts` for spoken replies. Real synthetic adult-account tests pass transcription, saved/spoken replies, grounded extraction, recall after fresh password login and French preference. The older 3.1 model became overloaded and was replaced after direct and deployed checks. Google billing remains unchanged and disabled. Paid API setup is required before customer personal-data use; the owner explicitly deferred it. See the [delivery report](docs/personal-friend-update.md).

The app is branded **Ai Companion** using the supplied purple/orange logo. The original PNG is preserved in `assets/branding/logo-original.png`; platform icons are derived from that image. The Dart package is `ai_companion`. Existing Firebase app identifiers, backend RPC names and persisted storage keys retain their identities for continuity.

The current Android testing handoff is **0.1.3 (4)**; both earlier artifacts are preserved. See [internal testing and signing](docs/internal-testing.md), [release notes](releases/0.1.3+4/RELEASE_NOTES.md) and the [readiness assessment](docs/testing-release-status.md). The signed bundle reuses the existing upload key. The owner confirmed no Play upload yet; preparing this candidate does not publish a store release.

Public [privacy](https://ai-personal-companion-privacy.web.app/privacy.html), [account deletion](https://ai-personal-companion-privacy.web.app/delete-account.html) and [terms](https://ai-personal-companion-privacy.web.app/terms.html) identify the operator as **Marvel tech solutions, Uganda**. The web email-login/deletion flow passes a real fictional-account test. Testing remains free, and purchases remain inactive.

The application now uses responsive Flutter forms, lists, cards, navigation, and dialogs. The Figma file supplies the visual direction, colours, Inter/Lora typography, and companion motif. The shipped UI does not render exported Figma frames or screenshots. Settings, conversation management, memory editing, scheduling, and privacy controls are wired to the application controller.

Clients must sign in or create an account before companion setup or main screens. The release is **18+**. Adult age range and language are confirmed once; timezone detects the device and offers a searchable city dropdown. Memory/personalisation are part of the explicitly accepted companion experience; existing opt-outs require acceptance before AI use. Manual style, interests and response-length panels are removed. Navigation is **Home, Chat, Talk**. Chat supports recorded messages and text/voice replies; Talk remains a future real-time calling preview. Secondary saved-detail correction and account privacy controls remain. OpenAI credentials remain pending.

## Run the interactive app

```powershell
flutter pub get
flutter run -d chrome --web-port=52100 --dart-define-from-file=config/development.json
```

In VS Code, select **Ai Companion — interactive app**. The browser uses port 52100. Signed-out clients see the required sign-in page; valid registered sessions restore their profile/companion. Loading/retry states expose no journal fallback. Old workspace preferences cannot bypass sign-in. Saved device data remains untouched in separate development previews.

To serve the existing compiled PC build without recompiling, run `node tools/serve_pc.mjs` and open `http://localhost:52100`. The server listens only on loopback.

Desktop Chat sends with **Enter** (including the number pad); **Shift+Enter** keeps a new line. Ctrl/Cmd+Enter still sends. Loading an existing conversation or refreshing a saved reply no longer shows the empty-chat introduction. The existing model, prompts, output budget and AI request counts are unchanged: context reads run together, and sidebar/memory refreshes finish independently after the saved reply is restored.

The archived Figma reference is available only through `flutter run -d chrome -t lib/main_design_reference.dart`. Its example records and fixed scenes are for design comparison, not the application.

## Run with live services

Follow [backend setup](docs/backend-setup.md), copy `config/development.example.json` to `config/development.json`, and fill in public Firebase app identifiers and the Supabase publishable key.

This workspace already contains the supplied mobile/Supabase values. Preserve the existing local file. Android can use `flutter run -d <android-device-id> --dart-define-from-file=config/development.json`; the browser command below also needs the Web app's Firebase configuration.

```powershell
flutter run -d chrome --web-port=52100 --dart-define-from-file=config/development.json
```

Keep provider keys and Supabase service-role credentials on the server. Production requires sign-in. Separate development previews support a device journal. Account persistence and erasure pass live checks; AI chat, voice and scheduled check-ins need their provider/scheduler availability and verification described in the setup guide.

Accounts support email signup/login, Google sign-in, guest-account linking, unique usernames and a separate preferred name used in greetings such as **Hi, Marvin.** See [account authentication and Firebase activation](docs/account-authentication.md) for the Google registration still needed in the supplied project.

The companion-direction update adds persistent preferred identity, structured routines/events, bounded cross-conversation context, assistant welcomes, contextual check-ins, reminder confirmation and notification history within the existing interface. See the [audit, prioritized plan and acceptance evidence](docs/companion-direction-audit.md). See the personal friend delivery report for completed live backend/provider checks and the remaining device, billing and release requirements.

## Validate

Validated with Flutter 3.47.7 / Dart 3.13.5 and Node 24.19.0 on Windows.

```powershell
flutter analyze
flutter test --concurrency=2
flutter build web --release
npm.cmd --prefix backend ci
npm.cmd --prefix backend test
npm.cmd --prefix backend run check
```

Backend tests apply migrations to isolated PGlite PostgreSQL with provider doubles. Widget tests write screenshots into `build/application-review/`; archived references write into `build/ui-review/`. The real Chrome storage probe passes. Run `tools/validate_release.ps1 -BrowserStorage` for it; Flutter's Windows `--platform chrome` harness has a separate CanvasKit-loading failure. The release verification report records exact counts and limits.

## Project map

| Path | Purpose |
| --- | --- |
| `lib/application/` | Responsive application screens, forms, dialogs, navigation, and theme |
| `lib/app/companion_controller.dart` | Conversation, preferences, memory, consent, and privacy state |
| `lib/data/device_workspace.dart` | Persisted device journal and manually managed memories |
| `lib/design/`, `lib/app/morrow_app.dart` | Archived Figma reference renderer; not imported by the shipped entry point |
| `lib/auth/`, `lib/core/`, `lib/data/` | Firebase session, public configuration, backend transport, models |
| `assets/design/`, `assets/fonts/` | Original scene geometry and licensed Inter/Lora fonts |
| `design/` | Original `.fig` export and provenance manifest |
| `supabase/functions/` | Firebase-verified API, OpenAI streaming, memory extraction |
| `supabase/migrations/` | SQL sources installed through the manual bundle; reconcile migration history before later CLI pushes |
| `test/`, `backend/tests/` | UI, controller, protocol, authentication, database tests |

The interface flows with the available space, keyboard, and text size. Desktop uses a sidebar; phones use bottom navigation. The companion orb is a decorative Flutter widget. Text, forms, buttons, switches, lists, and menus are independent interactive widgets. Original Figma exports remain preserved for reference, and font licences are included in the bundle.

In Chat, microphone messages are bounded to 60 seconds. The original recording stays locally available for replay while an editable transcript is reviewed; only confirmation sends the words to the conversation. Recognition errors can be corrected or retried. Text/Voice selects future replies, and saved replies have a Play button. Spoken replies retain their complete text. Leaving Chat stops capture; account changes discard unsent recordings. The deployed Gemini speech/transcription pipeline passes synthetic tests; physical microphone/speaker behavior still needs user testing. Talk remains Coming Soon for real-time calls.
