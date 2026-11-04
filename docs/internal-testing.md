# Ai Companion — Android internal testing

Release: **0.1.4 (version code 5)**, package `com.aipersonalcompanion`.
Start with the **Internal testing track** in Play Console. Preparing these files
does not upload an app, create testers, send invitations or publish a release.
A private-code guest entry is available for app review; see review-guest-access.md. There is no switch to production rollout.

European AI testing and launch remain pending paid API setup, as confirmed by
the owner. Internal testing ignores Play country targeting: do not invite EEA,
UK or Swiss users to AI testing until that setup is verified. See
[geographic access and the release gate](geo-blocking-readiness.md). This is an
invitation/release hold, not a new IP or nationality filter in the app.

## Bundle and signing

The candidate is `releases/0.1.4+5/ai-companion-0.1.4-5-internal.aab`.
The original version 1 artifact is preserved. The new candidate is verified with
Google's bundletool, signature/certificate checks and 16 KB native packaging/load
alignment checks. Physical-device runtime remains unverified. An AAB is uploaded
to Play; it is not directly installed
like an APK. `artifact-verification.json` records its hash, signing and manifest
checks. Its existence does not establish a successful Play review.

Debug signing has been removed from release configuration. A confirmed first
upload can create a dedicated local RSA upload key using
`node tools/create_android_upload_key.cjs --first-upload`. An existing Play app
must use its registered upload key instead; do not create a replacement merely
because the file is missing. Configure existing keys using
`android/key.properties.example`, then keep actual passwords in the private
`android/key.properties` only. Never put them in chat.

The owner has confirmed this is Ai Companion's **first Play Store upload**.
The securely generated local key is now the designated upload key for this
bundle. It has not been registered with Play yet; keep and reuse it for future
uploads. No replacement key or rebuild is needed. The Play distribution/app
signing certificate will be obtained separately when setting up Play App Signing.

Back up **both** `android/key.properties` and
`android/keystores/ai-companion-upload.jks` in private encrypted storage outside
this PC. They are ignored source files with restricted local permissions. Do not
include them in a tester handoff, public repository or release zip. The exported
`upload-certificate.pem` and its fingerprints are public certificate information,
not the private upload key. Play App Signing supplies the distribution key.
See [Flutter signing](https://docs.flutter.dev/deployment/android) and
[Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en).

Build from this workspace, preserving its existing public service configuration:

```powershell
flutter build appbundle --release --build-name=0.1.4 --build-number=5 --dart-define-from-file=config/development.json
```

For subsequent Play uploads increment the version code in `pubspec.yaml` or the
build command. Do not replace `com.aipersonalcompanion` or its Firebase project.

## Set up the internal track

1. In Play Console create/select **Ai Companion**, default language English,
   application type App. Complete the account and app tasks shown there; declare
   the intended adult audience accurately. Do not declare a final IARC rating
   from the app's self-reported 18+ onboarding alone.
2. Open **Test and release → Testing → Internal testing → Create new release**.
   Use Play App Signing, upload the signed AAB and inspect Play's validation.
   Name this release `0.1.4 (5) — Internal test update`.
3. Paste `releases/0.1.4+5/play-release-notes.txt` into release notes. Its English
   body is below Play's 500-character per-language limit. Resolve any Console
   errors before rollout. Leave Production untouched.
4. Under the internal track's **Testers** tab add the intended tester list or
   group, save it, then review and roll out **only the internal release**. Share
   the resulting opt-in URL with those testers. No list or invitations have
   been created by this local preparation.
5. Register the **Play app-signing certificate SHA-1 and SHA-256** from Play
   Console's App integrity/App signing page in this Firebase Android app.
   These differ from the local upload certificate. Re-sync Firebase public
   configuration if it changes, rebuild with the next version code, and verify
   Google sign-in on an app installed through Play. Local upload-signed APKs need
   their upload fingerprints too. Do not assume debug fingerprints cover either.

Internal testing supports up to 100 chosen testers and is separate from public
availability. A test opt-in link may take time to become available. Follow
[Google's internal-testing guide](https://support.google.com/googleplay/android-developer/answer/9845334?hl=en-en).

New personal developer accounts created after 13 November 2023 generally need
a **closed test with at least 12 opted-in testers for 14 continuous days** before
applying for production access. Internal testing does not satisfy that closed
test requirement. Check the actual account's dashboard; see
[Google's account testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en).

## Test scope and release gates

For this early round use adults, fictional preferred names and fictional chat
details. Paid Gemini API setup is still deferred. Do not collect real personal
conversations until it is completed. This does not change the working provider
or enable any billing. Real-time calling and automatic check-in delivery remain
unavailable; label them honestly in test expectations.

Before a wider launch complete the public privacy policy/deletion-request URL,
Play Data safety and audience/content declarations, app-access review
instructions, AI-output reporting/moderation, signed-device Google login, paid
AI setup and the device checks below. The app's AI chat falls within Google's
[AI-generated content policy](https://support.google.com/googleplay/android-developer/answer/13985936?hl=en),
which requires in-app reporting of offensive generated content. That reporting
flow is not implemented yet. Do not advertise this candidate as policy-approved.
The Android target is API 36, matching the
[current Play submission requirement](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en-en).

| Test | Pass condition |
| --- | --- |
| Clean install and access | Sign-in is required; Back/cancel/error never exposes private screens. |
| Email and Google | Create/login/relaunch/sign-out work; a Play-installed build completes Google sign-in. |
| Personal identity | Preferred name, adult introduction and language persist; no repeated introduction after completion. |
| Conversation | Reply streams, persists and reloads; no empty-chat flash; retry does not duplicate a turn. |
| Memory | A fictional fact is recalled in another conversation; correction/erasure takes effect; accounts stay isolated. |
| Audio | Grant/deny permission, record, stop, replay, edit/discard/send transcript; text/voice choice and spoken playback work on hardware. |
| Lifecycle/network | App backgrounding, keyboard, Bluetooth interruptions, offline/reconnect and provider failure preserve a safe understandable state. |
| Timezone | Device detection, manual choice, travel/resume and DST-sensitive reminders behave correctly. |
| Privacy | Export and full account erasure complete; no other account's records appear after sign-out/in. |
| Android/quality | At least two Android versions/devices, font scaling, Talk Coming Soon and 16 KB page-size runtime are checked. |

Record device/OS, build number, steps, expected/actual result and severity for
each issue. Keep test transcripts and credentials out of public bug reports.
Blockers must be resolved before moving to Closed testing or Production.

Privacy and account-deletion pages are published under Marvel tech solutions, Uganda.
Use https://ai-personal-companion-privacy.web.app/privacy.html for the privacy
URL, and https://ai-personal-companion-privacy.web.app/delete-account.html for
the outside-app deletion URL. Web email sign-in and deletion were verified on
4 November 2026 with a disposable fictional identity, which was erased. The
owner confirmed that testing stays free and no Play upload has occurred.
