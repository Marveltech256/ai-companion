# Phases 11 and 12 — implementation and verification

Updated 4 November 2026. This extends the existing application. Home, Chat, Talk,
the visual theme, logo, adult onboarding, memory, voice, models and generation
budgets are preserved. The original 0.1.0 (1) bundle and upload key are preserved.
The new candidate is 0.1.3 (4); the earlier bundles remain preserved. Temporary
private-code [guest review access](review-guest-access.md) is now available while
ordinary sign-in and existing user data stay protected. The owner
confirmed on 4 November that nothing has been uploaded to Play. Internal testing
remains free, with purchases and commercial usage enforcement inactive.

## Phase 11: subscription infrastructure

Google Play monthly billing is implemented behind an inactive server capability.
Current accounts retain free access; opening the app makes no billing query or
store connection while that capability is off. Signing up starts no paid trial
and cannot charge a user. Prices, introductory duration and commercial limits
have deliberately not been invented.

When configured, the existing account settings can open the membership dialog.
The store supplies the actual local monthly price and explicit checkout; the app
supports restore and the Google Play subscription-management link. The selected
base plan must be regular monthly recurring billing. Promotional offers and
prepaid plans are not offered by this implementation.

The server derives the Firebase owner, uses a random per-account billing reference,
verifies the token with Android Publisher, checks the catalog/account binding,
acknowledges it, then stores the result. Client premium flags never grant access.
Purchase tokens are encrypted with owner-bound AES-GCM. Store notification pushes
require Google OIDC and cause a fresh Publisher lookup; the push payload cannot
grant access. Expiry, grace, cancel, hold, pause, revocation, pending purchases,
linked-token replacement and stale updates have explicit handling. Entitlements
expire without renewal and require server verification within 24 hours. A stale
paid entitlement is refreshed against the store before a denied chat/voice claim
is retried, before any AI generation; a failed store lookup grants no access.

Optional introductory/free/premium usage limits are server-controlled. Message
and greeting claims reserve usage in the same database transaction; identical
retries do not double-count, and a quota failure rolls back the claim. Daily caps
use UTC. Voice keeps its existing service limit in addition to optional commercial
limits. These checks add no AI call and currently enforce no commercial limit.

Before any purchase test, the owner must supply/decide the monthly product and
base-plan IDs, prices/markets, introduction duration and limits. The Play app must
exist, have its subscription catalog and license testers configured, and grant a
separate Android Publisher server identity app access. Configure its server secret
and authenticated Pub/Sub audience/service account, then test pending, success,
restore, cancellation, expiry, refund/revocation and account switching through
Play. Only then deliberately enable sales; enable enforcement separately. The
Firebase server identity does not acquire Play permissions automatically.

Server variables are documented in `supabase/functions/.env.example`. Keep
`BILLING_FEATURE_ENABLED=false` and both database billing switches false for the
current test. Do not rotate the token encryption key after purchases exist without
re-encrypting stored tokens. No merchant account, product, price, credential or real
purchase has been fabricated. Apple StoreKit, web checkout and real-time calling
are not implemented by this Android billing preparation.

## Phase 12: completed work

- Additive migrations 017/018 were applied to the existing project. Live checks
  confirm 21 RLS tables, 106 application functions and restricted write RPCs.
  Existing records were preserved. The 18-source complete setup is for empty
  databases only; never rerun it on the live project.
- Eight Edge Functions are deployed, including billing and authenticated store
  notifications. Existing chat and voice keep their providers, prompts and budgets.
- Users can explicitly report a completed assistant reply using its secondary
  menu. Only the selected reply and optional note enter the private review queue.
  Ownership, request idempotency, daily submission limits, export, account erasure
  and 90-day cleanup are enforced on the server. Cancel submits nothing.
- Direct account changes close the previous account's dialogs and stop voice.
  Late billing results cannot grant the next account access; a stale restore
  cannot overwrite a newly verified purchase.
- Daily privacy maintenance is active at **02:15 UTC**. The deployed maintenance
  endpoint returned HTTP 200. The matching cron/Edge secret is private; it is not
  present in application configuration or source. AI check-ins remain inactive,
  preserving the current AI usage and deferred paid-provider decision.
- Public privacy, terms and account-deletion pages are implemented in `site/`.
  The deletion page supports email/Google sign-in with in-memory credentials,
  explicit confirmation and the same recent-authentication erasure API. It does
  not require completing app onboarding or buying a subscription. Firebase Hosting
  configuration uses a separate privacy site, preserving existing app hosting.
  The pages are now published under **Marvel tech solutions, Uganda**, using the
  previously supplied temporary support email. The existing in-app privacy section
  links to the full notice. A production build still refuses missing operator data.
- Deployed tests used two disposable fictional identities, a seeded fictional
  assistant reply and **zero model requests / zero purchases**. Reporting, private
  export, cross-account denial, disabled billing and erasure passed. Both identities
  and their owned profile/report/billing data were removed.

## Publication and device gates

Published pages:

- [Privacy notice](https://ai-personal-companion-privacy.web.app/privacy.html)
- [Delete account](https://ai-personal-companion-privacy.web.app/delete-account.html)
- [Terms](https://ai-personal-companion-privacy.web.app/terms.html)

The supplied operator identity is in ignored `config/site-operator.json`.
The dedicated site's two HTTPS domains are appended to Firebase authorized domains
and the backend allowlist; existing domains were preserved. Only this site's hosting
release was deployed. A real isolated Chrome run verified email login, exact deletion
confirmation and complete account erasure without onboarding or payment. The one
fictional identity was erased. This test made no model request or purchase. Actual
interactive Google consent remains a separate human/device acceptance check.

For future page updates run `node tools/build_public_site.mjs`, then deploy only
Hosting in the existing project. Never publish preview output. A support-email or
operator change should update the notice before the next release.

Paid Gemini API setup remains explicitly deferred, and OpenAI is not configured.
Use fictional conversation details in the current controlled test. No billing
account was activated, provider changed or additional AI generation scheduled.
Notification/device delivery, Play-distributed Google login, microphone/speaker
quality, interruptions, accessibility, slow networks and multi-day continuity need
physical acceptance. No Android device was connected during this verification.

iOS requires macOS/Xcode, Apple signing/APNs and an iPhone acceptance run. On a Mac,
install dependencies, run the same Dart tests, run `flutter build ios --release
--no-codesign --dart-define-from-file=config/development.json`, then complete signed
device/TestFlight testing. Windows does not verify an iOS build. Do not advertise
unverified Apple billing or real-time calling.

The new release folder records exact build/hash and automated-check evidence.
Automated test success does not establish paid-purchase readiness, store approval,
model quality on every topic or device reliability. Those remaining gates are not
hidden behind a “100% complete” claim.

## Private report review

Operators use trusted SQL access; there is no client administration route. A review
queue query can select `id, reason, details, message_snapshot, created_at` from
`public.content_reports where status='new' order by created_at limit 50`. Avoid
copying report contents into public logs. After reviewing a selected report, call
`public.morrow_review_report(report_uuid, 'reviewed')`, `'action_taken'` or
`'dismissed'` as appropriate. A receipt is not a promise of automatic moderation;
the operator must review the queue during testing and before public release.

Relevant implementation references: [Play Billing](https://developer.android.com/google/play/billing/integrate),
[server subscription verification](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2/get),
[authenticated Pub/Sub](https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions),
[AI-output reporting](https://support.google.com/googleplay/android-developer/answer/13985936?hl=en),
[account deletion](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en).
