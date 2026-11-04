# Accounts and preferred names

Implemented in the existing application on 3 November 2026. Firebase owns credentials/identity; Supabase owns profiles, companions, memories and conversations under the verified Firebase UID. Passwords and Google tokens are not saved in application profiles or the device journal. Device workspaces are not uploaded automatically.

## Account flow

The production app requires sign-in before companion setup or any main screen. **Sign in** and **Create account** open the email/Google account dialog. Cancelling or pressing Back cannot enter the app. There are no guest, skip or device-journal controls in production. Valid registered sessions restore normally; sign-out closes protected overlays, stops voice and returns to sign-in. Signup requires a case-insensitive unique username (3–30 letters, numbers or underscores) and a preferred name. The home greets that saved preferred name, for example **Hi, Marvin.**

Email signup uses Firebase account creation. Upgrading a cloud guest links credentials to the same UID, preserving its data. Google uses a Firebase popup on web and the official native Google plugin plus Firebase credential on mobile. New Google users finish their profile; returning users keep their saved names. Conflicting accounts are not merged automatically. If profile saving fails after Firebase signup, users retry their name without creating a second identity. Registered accounts finish both names before entering their companion. Existing settings allow name edits, password reset, and Google/email reauthentication.

Migration `202611030012_account_names.sql` adds the username/index and a service-only atomic profile-save function. Existing profiles start with a null username and finish it on their next registered-account session. Updates preserve owner RLS, export and erasure. Usernames are display handles; security ownership remains the Firebase UID.

## Firebase activation

Email/password and Google are enabled in Firebase project `ai-personal-companion`; **anonymous signup is disabled**. Session startup refuses guest identities. The deployed shared verifier denies anonymous or missing-provider identities before accessing data, and migration `202611030013_require_sign_in.sql` also denies guest RLS reads. Existing guest data is retained for credential linking. Real tests confirm guest-token rejection on all four user APIs, blocked anonymous signup and successful registered signup/login/profile saving/erasure. Google uses **Ai Companion** and temporary support address **atalyebamarvin4@gmail.com**. Native/Web public configuration and debug fingerprints remain configured.

1. Firebase provider activation is complete. Its repeatable configuration is in `firebase.json`. See [Firebase password authentication](https://firebase.google.com/docs/auth/flutter/password-auth) and [Google authentication](https://firebase.google.com/docs/auth/flutter/federated-auth).
2. Add this workspace’s **public debug signing fingerprints** to the existing Android app’s Firebase registration:

   ```text
   SHA-1:   0E:89:64:9F:EC:10:18:E4:FC:22:88:64:C5:46:86:4C:56:A3:8F:7E
   SHA-256: 72:0F:FF:A0:13:A1:A3:01:A2:F3:98:97:52:09:8D:C4:5D:83:7B:34:A4:6C:DD:D6:2C:73:56:E1:70:C4:90:EF
   ```

   These came from `:app:signingReport` for the debug APK. Register a production certificate separately when preparing a signed release.
3. Updated native registration files have been fetched. The Android web OAuth client matches the enabled Google provider and is saved as `GOOGLE_SERVER_CLIENT_ID` in the ignored `config/development.json`. This is a public audience identifier. See [Android plugin setup](https://pub.dev/packages/google_sign_in_android).
4. The actual iOS registration now supplies `GOOGLE_IOS_CLIENT_ID`. `ios/Runner/Info.plist` contains its `GIDClientID`, server client ID and matching reversed-client-ID URL scheme, so `GOOGLE_IOS_CONFIGURED` is true locally. See [iOS plugin setup](https://pub.dev/packages/google_sign_in_ios). Apple runtime/build testing still needs a Mac/device.
5. Browser builds also need the separate Firebase Web configuration and the website/local origin registered in Firebase authorized domains. The Google popup starts directly from the button press.
6. The user installed the [complete SQL bundle](database-installation.md) in Supabase SQL Editor. Administrative read-only checks now confirm all 16 tables/RLS, the Firebase project, profile columns, unique username index and all 77 function privileges. All six Edge Functions and the restricted Firebase server identity are configured. Do not rerun the fresh installer over these tables.

Authentication does not require the OpenAI key. The activated Supabase API now passes real profile persistence/reload tests. AI conversations separately need the server OpenAI configuration. Keep private credentials out of Flutter configuration and chat.

## Validation

71 Flutter tests and 44 backend tests pass; one separate browser-only storage test remains skipped on the VM. Coverage includes Firebase method selection, web popup/native Google credential paths, UID preservation, identity-change/cancellation fences, profile retry, username uniqueness/atomic rollback/RLS, signup and Google widget interactions, the greeting and the supplied full SQL installer. All six Edge entry points type-check, including the predeployment check. Web release and Android debug builds succeeded after Google activation; the live Google authorization-start API returned HTTP 200 with the expected client ID and Firebase callback. The sync helper checks native app IDs, package/bundle IDs and the iOS callback. `tools/backend_account_smoke_test.mjs` passes live email signup → account lookup → owned Supabase profile/companion save → password login/reload, case-insensitive username collision and cross-account conversation denial. Temporary test identities/data were erased through the deployed privacy API. Reset-email delivery, interactive Google consent and on-device sign-in remain unverified.
