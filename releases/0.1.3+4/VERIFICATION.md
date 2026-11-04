# Verification — 0.1.3 (4)

4 November 2026. Adds temporary private-code reviewer access to the existing
welcome screen. Normal sign-in, the visual theme and companion behavior remain.

| Check | Result |
| --- | --- |
| Flutter analyzer | No issues |
| Flutter suite | 92 passed; browser-only storage test skipped on VM |
| Backend suite | 65 passed |
| Edge type checks | All nine entry points pass |
| Reviewer code | Wrong code denied; not embedded in native libraries or packaged private files |
| Real Firebase integration | Custom-token exchange and refresh preserve scoped review claims |
| Owned data / session renewal | Separate guests cannot read each other's history; reconfirmation preserves the same owner |
| Revocation | Live API denies revoked guest; SQL tests also verify immediate RLS denial |
| Erasure | Normal leased privacy flow erases guest profile, registry and Firebase identity; status remains available to its verified owner |
| Normal accounts | Real disposable email signup/profile/login/isolation/erasure regression passes |
| Visual check | Welcome button and code dialog inspected at 390 × 844 |
| New live AI calls / purchases | Zero / zero |

The streaming check replays a synthetic assistant reply seeded directly for that
test; it does not claim a fresh provider-quality evaluation. Disposable test
identities were erased, including the one empty grant left by an initial smoke
script parsing error. No ordinary customer data was deleted by the tests.

Signed bundle: **58,819,378 bytes**. Package `com.aipersonalcompanion`, version code
4, minimum SDK 24, target SDK 36, non-debuggable. Existing upload certificate
matches. Bundletool/JAR signature and 16 KB packaging/64-bit ELF checks pass.

SHA-256:
`7ada992dde030c94045bea2d6f1fd1ff524dc96968f14cf0dd513e3654e9a26c`

The private code/instructions remain outside the release folder at
`config/PLAY_REVIEW_ACCESS.private.txt`, ignored and owner-restricted. Use them only
in Play Console App access. The app does not automatically identify Google
reviewers. Access can be disabled/revoked remotely; see
[reviewer access](../../docs/review-guest-access.md).

Purchases remain inactive. Paid AI setup, physical device/audio/notification
acceptance, Play-installed Google login and iOS remain pending. No Play upload,
tester invitation or production rollout was performed. Earlier bundles and their
upload key remain preserved.
