# Personalized companion enhancement

## Audit before implementation

The existing Flutter/Firebase/Supabase application already persisted a preferred
user name, companion name, adult age bracket, language, device/manual time zone,
owned conversations, grounded memories and routines. Current turn claims fetch
the companion row again for each new reply. A shared instruction builder serves
both configured text providers, welcomes and proactive entries. Voice speech
reads the saved assistant reply, so it must not invent a second personality.

Gaps: the main setup screen no longer exposed its companion-name controller;
the three legacy personality styles were not meaningfully used in the shared
instruction builder; support areas, communication preference and optional
learning/goals/additional details had no persistent onboarding fields. Existing
users needed an editing path without being forced to repeat their introduction.

## Implemented integration

The existing setup now groups its questions into three short sections: identity,
personality/support, and communication/optional goals. It reuses the existing
fonts, colours, panels, form controls, account flow, adult introduction and
welcome. Back navigation preserves the draft. Support choices may be empty and
are capped at four. Users can choose one personality or blend two, matching the
brief's warm-and-funny example. Six communication styles work with that choice.

Settings has a companion editor using the same controls. Existing accounts keep
their history, consent and preferences, and do not repeat onboarding. Legacy
styles still shape replies until the owner selects the new choices. Changing
preferences does not reset memory or silently grant voice/learning consent.

Migration 020 adds bounded preference columns to the existing `companions` row
and a service-only owner-scoped RPC. Existing RLS, erasure cascades and companion
export include the new fields. The account/profile remains the source of name,
language, age group and time zone. No exact birth date is collected. The full
setup bundle is regenerated for fresh databases; **do not rerun that bundle on
the installed project**. Apply only the additive migration there.

Each new turn claim retrieves current preferences. Shared instructions translate
personality and communication choices into actual behaviour, combine directness
with playfulness when selected, and use support/goals as optional invitations.
User free text stays bounded and explicitly untrusted. Current choices take
precedence over older learned patterns. Adult age brackets inform examples and
boundaries without assuming education, family, employment or maturity. Existing
memory/history/routines and one-generation-per-turn flow remain intact.

## Younger-user support: requested, not activated

The owner wants younger users onboarded with content appropriate to their age.
The current Gemini API contract prohibits use in clients directed towards or
likely to be accessed by under-18s. Adding a prompt, age filter, guardian checkbox
or removing the 18+ label does not resolve that restriction.
[Gemini terms](https://aistudio.google.com/docs/terms).

OpenAI documents a possible under-18 API path with additional safeguards.
Processing personal data below 13 or the applicable digital-consent age requires
Zero Data Retention first. This is an organisation/project approval, not merely
`store:false` in a request. Age-appropriate filtering, disclosures, reporting,
escalation and appropriate age assurance also need implementation and validation.
[Under-18 guidance](https://developers.openai.com/api/docs/guides/safety-checks/under-18-api-guidance),
[data controls](https://developers.openai.com/api/docs/guides/your-data).

For US under-13 users, applicable COPPA obligations include verified parental
consent and parental access/deletion rights; a child's checkbox or unverified
email is insufficient. For consent-based children's online services in the EU,
the parental-consent threshold varies from 13 to 16 by member state.
[FTC guidance](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions),
[Commission guidance](https://commission.europa.eu/law/law-topic/data-protection/information-business-and-organisations/legal-grounds-processing-data/are-there-any-specific-safeguards-data-about-children_en).

The current release therefore retains backend adult eligibility. Tests submit
`under_13`, `13_15` and `16_17`, verify rejection, and verify that forged body age
fields cannot reach generation. **This is denial evidence, not evidence of a
working younger-user companion or completed child safeguarding.** The requested
eight-bracket public onboarding and under-18 launch remain pending an eligible
provider, verified consent/age-assurance flow, privacy/store updates and
end-to-end child-safety evaluation. Do not advertise all-age availability yet.

Before any youth release, separate youth provider routing from Gemini for text,
memory extraction/ranking, transcription and speech; prohibit fallback to it;
apply input/output filtering before exposing output; verify guardian withdrawal,
data minimisation, incident escalation and reports. Onboard children through the
appropriate consent process **before** account/profile/audio collection. Keep
non-romantic boundaries, real-world support and transparent AI identity. A
teen-only first stage should be evaluated separately from under-13 support.

No financial billing activation, provider-key creation or youth access is implied
by this enhancement. European AI launch remains pending paid provider setup.

## Verification record

Isolated PostgreSQL tests pass for warm/funny, calm/intellectual and
positive/casual companions, fresh turn claims, restored settings, name/goal
updates, bounded choices, owner isolation, unchanged consent and denied younger
generation. The analyzer is clean and all nine Edge entry points type-check.

Migration 020 and the three affected functions are deployed. A read-only check
confirmed their pre-existing Firebase-verification configuration before targeted
deployment; authentication settings were preserved. Live checks reject missing
identity, foreign-owner preference writes and all three younger-age inputs.
Post-deployment metadata confirms **23 tables with RLS, 111 functions, seven new
preference columns and zero application write functions executable by client
roles**. Purchases remain disabled. Public privacy/terms/deletion pages return
HTTPS 200; the privacy notice now describes these optional fields.

`tools/live_friend_preferences.mjs` completed six real streamed responses using
three disposable fictional adult accounts. Alex (warm/playful, direct), Sam
(calm/intellectual, detailed), and Jamie (positive/relaxed, French) used their
chosen names, restored preferences after a fresh password login, and retrieved
the saved German practice goal in a new conversation. The direct reply was
shorter than the detailed example; French was preserved. These samples establish
integration and some behavioural evidence, not consistently perfect humour,
register or long-term quality. The three temporary accounts were erased. No
minor data or provider requests were used; purchases remain inactive.

All **95 Flutter tests and 70 backend tests pass**. The Flutter tests cover four-selection limits, optional fields, draft
preservation on Back, name propagation, preference restoration and existing
consent. Mobile screenshots are rendered for the new personality/goal sections.
Version 0.1.4 (5) is the new internal-test candidate. Final artifact verification
is recorded beside its signed bundle; Play upload and physical-device runtime
are separate actions.
