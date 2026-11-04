# Verification — 0.1.1 (2)

3 November 2026; Flutter 3.47.7, Dart 3.13.5, Node 24.19.0 on Windows.

| Check | Result |
| --- | --- |
| Flutter analyzer | No issues |
| Flutter regression suite | 90 passed; browser-only test skipped on the VM |
| Backend PostgreSQL/provider/security suite | 60 passed |
| Eight Deno Edge entry points | Type-check passed |
| Real Chrome persistence and cleanup | Passed, isolated compiled probe, zero cloud calls |
| Web release | Built, self-hosted CanvasKit; PC server reports version 0.1.1 / build 2 |
| Android release bundle | Built, signed with existing upload key |
| Bundletool / JAR signature / certificate | Passed / verified / matches existing public certificate |
| Native page alignment | 16 KB packaging and 64-bit ELF load alignment passed |
| Release manifest | com.aipersonalcompanion, code 2, SDK 24 minimum / 36 target, not debuggable |
| Live schema | 21 RLS tables, 106 functions; no unsafe anon/authenticated write RPC grants |
| Deployed synthetic safeguards | Owned reports, retry, private exports, foreign-account denial, free billing and erasure passed |
| Scheduled privacy maintenance | Endpoint HTTP 200; daily 02:15 UTC job active, AI check-in job inactive |
| Purchases / additional AI requests in new live tests | Zero / zero |

Bundle: `ai-companion-0.1.1-2-internal.aab`, **58,766,166 bytes**.

SHA-256:
`aa2d57a84d1778e526467e25ff293c608ff47b019856d288cb4e3b0fe49c32b7`

The original version 1 artifact is preserved. Existing Home/setup/theme/model and
prompt source files remain unchanged; updated mobile settings and the report
dialog were visually inspected. Reporting uses the existing secondary-menu/dialog
style. Billing remains hidden and free access is preserved while disabled.

The legacy Windows `flutter test --platform chrome` harness still stalls before
the test body because its CanvasKit request returns 404. Its logs/Chrome errors
were inspected; no application behavior is inferred from that failed harness.
The separate release-compiled storage probe passed with the actual browser plugin,
restoring the saved companion, journal entry and memory, then removing its test key.

No physical Android device was connected. Play installation/sign-in, real purchase
lifecycle, microphone/speaker/background behavior, notification delivery,
accessibility, longitudinal AI quality and iOS remain unverified. The bundle is
prepared for internal testing, not uploaded or approved by Play. Public pages are
drafts awaiting operator identity and publication; paid AI setup remains deferred.

See [remaining gates](../../docs/remaining-phases.md) and
[internal test procedure](../../docs/internal-testing.md).
