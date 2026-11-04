# Public source setup

This repository contains Ai Companion's Flutter source, assets, tests, Supabase
migrations/Edge Functions and public privacy-site sources. Private server keys,
Android upload signing, reviewer access codes, developer caches, real service
configuration and compiled bundles remain local and are excluded.

For a fresh development checkout:

1. Install the Flutter/Dart and Node versions listed in README.
2. Copy `config/development.example.json` to `config/development.json` and supply
   your public Firebase/Supabase client configuration.
3. Download your own Firebase app registration files into
   `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`.
   They are intentionally excluded from the public repository.
4. Run `flutter pub get`, then the README's validation commands. Backend tests
   use isolated PostgreSQL and provider doubles rather than customer records.
5. Configure server credentials through the server secret manager, following
   `supabase/functions/.env.example`. Never put private provider keys in Dart.
6. Use the complete SQL bundle only for an empty database. Preserve and inspect
   migration state before applying changes to an existing project.

Release Android builds require a separately provisioned upload key and local
`android/key.properties`; see its example and the internal-testing guide. The
project owner's existing private upload key is not included here.

Temporary reviewer access requires an owner-provisioned private code. Its local
instructions file and plaintext code are excluded from public source. See
`review-guest-access.md` for operation and removal. Publishing source does not
enable purchases, create accounts or deploy cloud resources on a fresh checkout.

The included font licences apply to their respective font files. Public repository
visibility does not itself grant an open-source licence to the application.
