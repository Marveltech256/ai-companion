# Geographic access and European launch readiness

Reviewed 4 November 2026 for Ai Companion, operated by Marvel tech solutions,
Uganda. Owner decision: **internal testing only; European AI testing and launch
remain pending paid API setup.** This is a technical audit and release record,
not a legal certification or a declaration that every market is ready.

## Relevant requirements

Regulation (EU) 2018/302 addresses unjustified nationality/residence-based
restrictions. Article 3 covers interface blocking and forced regional redirects;
its legal-requirement exception needs a specific applicable legal basis and a
clear explanation. Article 4 addresses access conditions in covered situations.
Its copyright-content provision is not a blanket exemption for every app.
Article 5 concerns accepted payment arrangements, including same-brand/category,
authentication and accepted-currency conditions. Recital 17 includes traders
outside the EU when operating within it. The exact service classification and
applicable exceptions must be assessed before launch.
[Regulation text](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32018R0302).

Different advertised regional prices are not categorically prohibited. Do not
confuse access to covered offers on equal terms with requiring a single global
price or support for every currency/payment method.
[Council explanation](https://www.consilium.europa.eu/en/policies/geo-blocking/).
See also the [Commission overview](https://digital-strategy.ec.europa.eu/en/policies/geoblocking).
This EU regulation does not by itself establish US privacy, consumer or AI-law compliance.

## Application audit and safeguards

| Area | Current behaviour and evidence |
| --- | --- |
| Interface and API access | No nationality, residence, IP-country allowlist, regional redirect or residence proof is used by the app handlers. Firebase identity, ownership, adult onboarding and consent apply uniformly. CORS allows our application origins; it is not a country check. |
| Language and time zone | User choices are retained. Device-zone detection is local OS/browser functionality, with manual override. General location is optional personalisation input. It is not eligibility evidence. |
| Chat and memory | Authenticated owners receive the same functions. Geographic headers cannot change identity, waive onboarding or read another account's records. No AI model or request-count changes were made for this audit. |
| Review access | Same temporary private-code requirement globally; no Google-reviewer detection or region-specific fake responses. |
| Prices and payments | Free testing; sales and enforcement remain disabled. No app-level country surcharge. Prepared Android billing displays Google Play's local formatted price and verifies the exact server-configured product/base plan. Merchant offers and cross-border payment acceptance require separate review before activation. |
| Public information | HTTPS privacy, terms and deletion pages have no app login requirement to read them, country rules or geographic redirects. Deletion itself requires identity verification. The old privacy route redirects to the canonical policy for everyone. |

`backend/tests/market_access.test.ts` exercises the actual Firebase JWT verifier,
companion/billing handlers, Postgres API error mapping and all migrations in an
isolated PGlite database. Synthetic French, German and US profiles keep their
language/time-zone choices while country headers change. The test verifies equal
free access, no redirect, ownership isolation, required onboarding and denied
unauthenticated access. It sends **zero AI or payment requests**. Synthetic
headers and profile fields are regression inputs, not proof of real-world global
network availability. External platform rules and outages are outside that test.

Verification on 4 November: all **67 backend tests passed**, including both new
market-access tests. The fresh read-only Google metadata check confirmed unpaid
billing; the European gate returned the expected exit 2. No provider requests,
purchases, billing activation, runtime access changes or Play rollout were made.

## Paid Gemini gate

Current Gemini terms require paid services for clients available to EEA, UK or
Swiss users. Google's project billing check currently reports disabled. This
applies even when the app itself is free and conversations are fictional.
[Gemini terms](https://aistudio.google.com/docs/terms).

The owner has deferred those AI invitations and launch until enabling paid API
access. This is a provider-readiness issue, **not** an assertion that a provider
contract supplies the regulation's legal-requirement exception. No country/IP
filter was added. Holding a release or recording a pending decision does not
technically revoke an already shared installation, invitation or reviewer code.
Do not circulate AI test invitations to these users yet. If access has already
been shared, pause that testing and resolve the provider setup before resuming.
Do not use nationality as a proxy for a tester's current service location.

Read-only preflight, without an AI call or billing change:

```powershell
node tools/release_market_gate.mjs --refresh --european-ai-users
```

It checks the existing project's billing and Gemini service metadata. Missing,
wrong-project, future-dated, failed or older-than-24-hour evidence fails closed.
Exit 2 means the European paid-provider gate is not met; exit 1 means the check
could not complete. A pass verifies only paid-project metadata, not model access,
privacy contracts, legal scope, real-device operation or store approval.

The same gate runs before other checks with:

```powershell
./tools/validate_release.ps1 -EuropeanAiUsers
```

Ordinary internal checks do not run this opt-in market gate or claim European
readiness. No cloud billing, deployment or Play setting is changed by either gate.

## Distribution and remaining decisions

Google Play **internal testing does not apply country targeting**; an invited
tester can receive it regardless of production/open/closed country settings.
Those settings are based on the Play account's registered country, not current
physical location. Therefore they cannot substitute for provider readiness or
invitation management.
[Play distribution guidance](https://support.google.com/googleplay/android-developer/answer/7550024?hl=en).

Before inviting European AI testers or advancing release tracks:

1. Enable appropriate paid AI API access in the same Google project, then rerun
   the fresh gate. Review provider data-processing arrangements and update the
   unpaid-testing notices to match the verified configuration. This has not
   been authorised or activated by this audit.
2. Review the service's legal classification and covered access conditions; do
   not rely on a generic software/copyright exemption. Record any genuinely
   applicable legal restriction and its explanation before implementing it.
3. In Play Console review the actual production/open/closed Countries/regions
   and any product/base-plan availability for the intended offers. The Console
   has not been inspected or changed by this audit. Country targeting is not a
   geo-blocking compliance certificate.
4. Keep purchases inactive until price transparency, accepted cross-border
   payment conditions, refunds, taxes and consumer disclosures are reviewed
   with the store configuration. No live payment acceptance was tested here.
5. Test real EU and US devices/networks, travellers retaining their choices,
   Play-signed Google login, export/deletion and accessibility. Separately
   resolve GDPR and applicable US obligations; this audit does not certify them.

The published access terms are at
[Terms of use](https://ai-personal-companion-privacy.web.app/terms.html#equal-access).
The existing signed version 0.1.3 (4) and its UI remain unchanged; these changes
concern release validation, regression evidence and the public notices.
