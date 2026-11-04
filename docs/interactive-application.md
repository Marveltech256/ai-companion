# Interactive application

Updated 3 November 2026 following the request to treat the Figma screens as inspiration and implement a working application.

The production entry point requires a registered Firebase account and an explicit adult (18+) introduction before companion use. Cancelling sign-in stays at the gate; sign-out closes protected overlays. Home, Chat and Talk are the three primary destinations. Talk is Coming Soon; memory review/correction and privacy remain in Settings. Device journals remain separate development previews. Branding, logo, colours and fonts are preserved.

## Runtime interface

`lib/main.dart` launches `MorrowApplication` from `lib/application/`. It does not load the Figma `DesignLibrary`, scene JSON, a screenshot, or a frame painter. Native Flutter widgets implement onboarding, home, conversation/journal, voice, memory management, and settings. The same Inter/Lora fonts and Figma colour values provide visual continuity. Figma's setup node `2:6619` was also inspected through the newly available connector during this work.

The interface includes companion naming/style/interests, personal preferred name/details, response length, automatic-memory consent, independent learning consent, voice consent, conversation history/rename/deletion, searchable editable structured memories/routines/events with individual expiry, global forgetting, timezone/day/times/frequency/quiet-hour scheduling, confirmed reminders and notification history/cancellation, separate memory/conversation retention, export, email sign-in/linking/reauthentication, sign-out, and account-erasure confirmation/status. These additions reuse the existing screens/dialogs and styling; see the [companion audit](companion-direction-audit.md).

Small-screen conversation layout adapts when the keyboard is open. Lists and forms scroll normally; complete Figma frames are not scaled into the viewport. The voice microphone starts only on explicit Unmute, and its existing turn cancellation and account/conversation fences remain in use.

## Device workspace

A new workspace is empty and persists real companion preferences, user-authored journal entries, and manually added memories. It contains no Figma example conversations or invented memories. It never adds an assistant reply or typing indicator. The composer is labelled **Save thought** and the screen explains that it is a journal until cloud AI is connected.

`DeviceWorkspaceApi` serializes mutations and commits in-memory state only after storage writes succeed. Failed writes preserve the last saved workspace; retry request IDs avoid duplicate journal entries. Memory expiry and conversation retention are applied to device data. Exports include actual records. Confirmed device erasure removes the application's storage key, not other applications' data. Corrupt/inaccessible saved data is surfaced rather than silently reset.

Storage uses [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage), with platform-specific storage and encryption. Android app backups are disabled; iOS includes the documented Keychain entitlement. Browser storage depends on WebCrypto and requires localhost or HTTPS; it stays in that browser/origin and is not an authenticated cloud account. Platform storage, deployment headers, backup behavior, and hardware security still require release review. No password, OpenAI key, or Supabase service key is stored in the device workspace.

The device workspace is capped at 1 MiB, 100 memories, and 2,000 journal entries. It is deliberately separate from each cloud account. Switching to a cloud workspace does not silently upload device notes. Explicit synchronization/import is not implemented.

## Cloud behavior

The supplied public Firebase mobile/Supabase values remain in the ignored development configuration. The VS Code **Ai Companion** launch configuration includes those values. **Connect cloud account** switches to the Firebase-verified Supabase API; cloud conversations retain the original OpenAI streaming, memory, voice, and privacy services. Repeated workspace changes reuse Firebase initialization while creating a fresh HTTP transport.

Gemini 3.1 Flash-Lite now passes live synthetic adult-account streaming, saved/idempotent history, grounded memory extraction, recall after fresh password login, French preference and truthful Home activity. Firebase signup/login/profile saving, account isolation and erasure also pass. All 16 application tables have RLS; all 85 SQL functions have expected privileges. The owner deferred paid Gemini API setup; customer personal-data use is not activated. OpenAI connection/key, interactive Google consent, audio, scheduler activation and closed-app notification delivery remain pending.

The subsequent account update adds direct email signup, Google login, password recovery, guest linking, a unique username and required preferred name. Registered users with an incomplete profile finish it on the existing setup surface; the home greets them with “Hi, Marvin.” See [account authentication](account-authentication.md) for activation requirements. Authentication is independent of OpenAI configuration.

## Reference and verification

`lib/main_preview.dart` now launches the interactive device application. The old scene renderer is isolated behind `lib/main_design_reference.dart`. Its sample data is only a design reference.

Interaction tests exercise actual Flutter widgets/controllers with isolated doubles. The analyzer is clean, 74 Flutter tests and 47 backend tests pass, all six Edge entry points type-check, and Android debug/web release builds succeed. Live synthetic checks are reported separately. Renders are in build/application-review. Physical microphone/playback/push, iOS, interactive Google consent and multi-day quality still require runtime verification. See the personal friend delivery report for the ten updated stages.
