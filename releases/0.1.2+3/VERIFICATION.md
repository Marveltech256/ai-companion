# Verification — 0.1.2 (3)

4 November 2026. This update publishes the supplied operator identity and adds a
link to the full privacy notice within the existing app privacy section.

- Flutter analyzer: no issues. Full Flutter suite: **90 passed**; browser-only
  storage test remains skipped on the VM. Existing browser storage proof is the
  separate compiled Chrome probe recorded in the previous release.
- Public deletion-client test: **passed**. Backend implementation is unchanged;
  its last full run passed **60 tests** and eight Edge entry-point type checks on
  3 November. These counts are not presented as a fresh full backend run today.
- Public HTTPS privacy, terms and deletion pages show **Marvel tech solutions,
  Uganda** and the supplied temporary support email. Security headers and exact
  CORS origins were checked on the actual deployed site.
- A real isolated Chrome run verified Firebase email login, password-field
  clearing, disabled deletion for incomplete confirmation, and complete web account
  erasure without onboarding or payment. The disposable fictional identity was
  erased. No model request or purchase was made. Interactive Google consent was
  not automated and remains a human acceptance check.
- The mobile deletion page was visually inspected at 390 × 844 with no horizontal
  overflow. Both Firebase Hosting HTTPS domains serve the notice and pass API
  preflight. Existing project domains and the original hosting site were preserved.
- Supabase metadata and a read-only database check confirm the billing capability,
  sales and usage enforcement remain off. The monthly catalog remains unconfigured.
- The owner explicitly confirmed **no Play upload yet** and requested free testing.

The signed bundle passes bundletool validation, signature/certificate matching
and 16 KB native alignment checks. It is **58,764,051 bytes**, targets SDK 36 and
is not debuggable. SHA-256:
`b37421a362a448b554edc2cb5562afd40ddfbd5dc0c2d862edca5f82eeed26ce`.
Full manifest/certificate evidence is in `artifact-verification.json`. Earlier bundles and the existing upload
key are preserved. This is an internal-test candidate; no Play release, tester
invitation or financial activation was performed. Physical Android, Play-signed
Google login, notification delivery, audio acceptance and iOS remain unverified.

Published URLs:

- https://ai-personal-companion-privacy.web.app/privacy.html
- https://ai-personal-companion-privacy.web.app/delete-account.html
- https://ai-personal-companion-privacy.web.app/terms.html

Paid AI setup remains deferred; use fictional conversation details in testing.
The working companion models and generation budgets are unchanged.
