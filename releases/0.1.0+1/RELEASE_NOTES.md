# Ai Companion 0.1.0 (1) — internal test

Package: `com.aipersonalcompanion`. First testing candidate, 3 November 2026.
This is an internal-testing handoff, not a production launch or a completed
Play Console rollout. The app continues to use the existing Firebase/Supabase
projects. No guest bypass, mock AI success, billing activation or new AI calls
are introduced by this release build.

The signed bundle is **ai-companion-0.1.0-1-internal.aab**, 58,034,194 bytes
(55.3 MiB), minimum API 24 and target API 36. Google's bundletool validation,
JAR signature verification, upload-certificate matching, 16 KB native packaging
and 64-bit ELF load-segment alignment checks passed for the delivered artifact.
The owner confirmed this is the first Play Store upload. The signature uses
the securely generated, designated upload key; retain it for future releases.
Nothing has been registered or uploaded to Play Console by this handoff.

## Available for testing

- Required account sign-in, email account creation, Google sign-in integration,
  unique username and preferred-name greetings.
- Adult introduction, language and automatic/manual IANA timezone.
- Contextual streamed conversations, persisted history and retry protection.
- Grounded cross-conversation memory and automatic personalisation, with clear
  companion-mode consent and secondary correction/export/erasure controls.
- Recorded messages up to one minute, original replay, transcript editing and
  confirmation before sending; optional spoken replies retain the complete text.
- Home activity, reminder preferences and quieter settings.
- Conversation refresh keeps existing messages visible. Independent reads reduce
  waiting without changing models, token limits or AI request counts.

## Limits testers must know

- **Adults 18+ only. Use fictional preferred names and chat details for now.**
  Paid Gemini API setup remains deferred; current synthetic verification does
  not authorize use of customer personal information on the unpaid API.
- Real-time calling in Talk is Coming Soon.
- Automatic check-in delivery and scheduled cleanup are not activated. Do not
  depend on push/reminders for time-critical events.
- Physical microphone/speaker/Bluetooth/background behavior, Google sign-in on
  Play-signed installs, reset-email delivery and multi-day memory quality need
  real-device testing.
- OpenAI activation is pending. The working server path uses Gemini Flash-Lite
  with real transcription and speech; consumer subscriptions are not API access.
- Store declarations, public privacy/deletion information, AI-output reporting
  and release moderation review remain part of the launch work.

## Evidence

Clean Flutter analysis; 84 Flutter tests and 51 backend tests pass. Six Edge
entry points type-check. Existing deployed synthetic checks cover streaming,
idempotent saves, memory extraction/recall, voice transcription/speech and
isolated account erasure. Hardware and Play-review outcomes are not inferred
from these automated checks. Bundle signing/build checks are recorded alongside
the generated artifact in `artifact-verification.json`.

Paste `play-release-notes.txt` into the internal-track release notes. Follow
[internal testing](../../docs/internal-testing.md) before sharing an opt-in link.
