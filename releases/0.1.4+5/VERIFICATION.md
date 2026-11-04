# Verification — 4 November 2026

The signed `ai-companion-0.1.4-5-internal.aab` passes bundletool validation,
JAR signature verification and comparison with the original upload certificate.
It declares `com.aipersonalcompanion`, version 0.1.4/code 5, minimum SDK 24,
target SDK 36 and a non-debuggable release. Native packaging and 64-bit ELF load
segments pass the 16 KB checks. The protected reviewer code was checked privately
and is absent from the native libraries; private signing files are not packaged.
See `artifact-verification.json` for the exact hash and checks.

The analyzer is clean, 95 Flutter tests pass (one browser-only test is skipped on
the VM), 70 backend tests pass and all nine Edge entry points type-check. This
update does not rerun or replace the earlier actual-browser storage evidence.
New mobile onboarding screenshots were rendered and reviewed; web release
compilation passes and the existing PC web preview serves 0.1.4 (5).

Migration 020 and the three affected backend functions are deployed with their
existing authentication configuration preserved. Live metadata verifies 23 RLS
tables, 111 application functions, seven new preference columns, no client-role
write RPC permissions and purchases disabled. Six real synthetic adult replies
confirm selected names, restored goals/preferences and French language use.
Three disposable identities were erased. All younger-bracket submissions remain
denied before generation; that is not a working youth-release or child-safety test.

Public privacy/terms/deletion pages return HTTPS 200 and match reviewed files.
The privacy notice covers the new optional preferences. API/provider credentials
and the private reviewer code remain outside public source and artifacts.

Physical Android audio/accessibility/network checks, Play-signed Google login,
store review, paid provider setup, longitudinal response quality and the separate
younger-user provider/consent/safeguarding launch remain outstanding. No Play
upload, production track rollout or billing activation was performed.
