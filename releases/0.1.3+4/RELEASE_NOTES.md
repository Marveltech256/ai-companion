# Ai Companion 0.1.3 (4) — Temporary review guest

The welcome screen adds **Guest for app review** while review access is enabled.
The private code is supplied through Play Console App access, never embedded in
the app or published in the listing. This entry creates a separate Firebase identity
and uses the same companion, memory, conversation and voice services. Adult
onboarding and consent remain required. It does not identify reviewers automatically.

Normal email/Google sign-in and existing personal workspaces are preserved.
Purchases and commercial enforcement remain inactive. The existing upload key and
all earlier bundles are preserved; nothing is uploaded or rolled out by this build.

Private reviewer instructions/code: `config/PLAY_REVIEW_ACCESS.private.txt`.
Disable access after review with `tools/configure_review_guest.cjs --disable`
using the owning Supabase CLI. This revokes the existing review version as well.
Review workspaces are queued for deletion when disabled, version-revoked or inactive
for 30 days, through the daily privacy maintenance worker.

Use fictional conversation details while paid AI setup remains deferred. Real-time
calling is still Coming Soon. Device/Play-signed Google login, physical audio,
notification delivery and iOS remain separate acceptance checks.
