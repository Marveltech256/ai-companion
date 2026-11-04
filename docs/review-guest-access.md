# Temporary guest entry for Play review

Updated 4 November 2026. The welcome screen shows **Guest for app review** while
the server enables it. The entry requires a private code; it does not identify
Google reviewers by device, email, IP address or geography. Anyone holding the
code can enter. The current design and normal email/Google sign-in are preserved.

Open `config/PLAY_REVIEW_ACCESS.private.txt` locally and copy its English
instructions/code into Play Console → App content → App access. The code is not
included in the app, public pages, release notes or store listing. The file is
ignored and restricted to the Windows owner. Do not include it in a public zip.
No Play Console entry or rollout has been submitted by these tools.

Each entry creates a separate Firebase custom-token identity and owned workspace.
Anonymous Firebase identities remain rejected. Guest chat, memory, recorded voice,
history and privacy use the normal services and model configuration. Reviewers see
the same features and responses as other users. Identity defaults to Reviewer;
the same explicit adult age/language/timezone and companion/consent steps apply.
Billing remains inactive for everyone.

The current guest restores on the same installation. After **Exit guest**, entering
the code starts a fresh workspace. Reconfirming the code before account deletion
reauthenticates the same guest; it cannot select another owner. Settings requires
DELETE_MY_ACCOUNT before erasure. The verified owner can still poll its erasure
receipt after the guest registry and Firebase account are removed.

## Disable after review

Use the owning Supabase CLI and run:

```powershell
$env:AI_COMPANION_SUPABASE_CLI = Join-Path (Get-Location).Path '.cache/npm/_npx/aa8e5c70f9d8d161/node_modules/@supabase/cli-windows-x64/bin/supabase.exe'
node tools/configure_review_guest.cjs --disable
```

This disables entry, rotates the review version to invalidate existing guests, and
queues their erasure. Alternatively trusted SQL can set
`public.review_configuration.enabled=false`; that immediately blocks review API
access and owned RLS reads. Fresh app loads hide the entry. An old guest session
receives an ended-access error and signs out. Re-enabling is an explicit owner
operation; the provisioning script never replaces an existing unknown code.

The daily privacy worker queues/deletes guests when disabled, version-revoked or
inactive for 30 days. It processes bounded batches through normal leased erasure
jobs. Regular user profiles are excluded. Keep reviewer access enabled until the
review finishes; the code has no automatic expiry while access remains enabled.

## Verification

92 Flutter tests, 65 backend tests and nine Edge type checks pass. Deployed tests
verify wrong-code rejection, Firebase custom-token exchange/refresh, separate
ownership, renewed access to saved history, individual revocation, normal email
account regression and complete guest erasure. A synthetic saved reply verifies
normal streaming replay; it is not a new model-quality test. These checks generate
no AI reply or purchase. All disposable identities were erased.

The 19-source fresh SQL installer includes two private review tables. Live checks
expect 23 RLS tables and 110 application functions. Do not rerun the complete
installer on the existing project; migration 019 was applied additively.

Paid API setup remains deferred, so reviewer instructions request fictional names
and conversation details. Physical Android audio, Play-installed Google login,
notifications and iOS acceptance remain separate checks. The candidate reuses the
existing upload key; preparing it does not publish a Play release.

References: [Google Play review access requirements](https://support.google.com/googleplay/android-developer/answer/15748846?hl=en),
[Firebase custom tokens](https://firebase.google.com/docs/auth/admin/create-custom-tokens).
