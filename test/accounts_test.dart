import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/core/app_failure.dart';

import 'support/account_services.dart';

void main() {
  test('new email account saves its username and preferred name to its own profile', () async {
    final session = AccountTestSession()..uid = null;
    final api = AccountTestApi(session);
    final c = CompanionController(session: session, api: api);
    await c.createAccount(
      'marvin@example.com',
      'test-password',
      username: 'Marvin_20',
      preferredName: 'Marvin',
    );
    expect(session.creates, 1);
    expect(session.links, 0);
    expect(c.userId, 'email-user');
    expect(c.needsAccountDetails, false);
    expect(api.profiles['email-user']!['username'], 'marvin_20');
    expect(c.displayName, 'Marvin');
    expect(api.bootstraps, 1);
    c.dispose();
    await session.events.close();
  });
  test('upgrading a guest links credentials to the same UID without losing the companion', () async {
    final session = AccountTestSession();
    final api = AccountTestApi(session);
    final c = CompanionController(session: session, api: api);
    await c.restore();
    final id = c.companion!.id;
    await c.createAccount(
      'marvin@example.com',
      'test-password',
      username: 'marvin',
      preferredName: 'Marvin',
    );
    expect(session.links, 1);
    expect(session.creates, 0);
    expect(c.userId, 'alice');
    expect(c.companion!.id, id);
    c.dispose();
    await session.events.close();
  });
  test('profile failure keeps the created account and retries names without creating a second identity', () async {
    final session = AccountTestSession()..uid = null;
    final api = AccountTestApi(session)..failProfile = true;
    final c = CompanionController(session: session, api: api);
    await expectLater(
      c.createAccount(
        'marvin@example.com',
        'test-password',
        username: 'taken',
        preferredName: 'Marvin',
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(c.registeredAccount, true);
    expect(c.needsAccountDetails, true);
    expect(session.creates, 1);
    api.failProfile = false;
    await c.completeAccountDetails('marvin_20', 'Marvin');
    expect(c.needsAccountDetails, false);
    expect(session.creates, 1);
    c.dispose();
    await session.events.close();
  });
  test('Google login restores the selected account names; new users must finish their profile', () async {
    final session = AccountTestSession()..uid = null;
    final api = AccountTestApi(session);
    final c = CompanionController(session: session, api: api);
    await c.authenticateGoogle();
    expect(c.needsAccountDetails, true);
    await c.completeAccountDetails('marvin', 'Marvin');
    await c.signOut();
    await c.authenticateGoogle();
    expect(c.personalProfile.preferredName, 'Marvin');
    expect(c.needsAccountDetails, false);
    expect(session.googleLogins, 2);
    expect(api.profiles.keys, ['google-user']);
    c.dispose();
    await session.events.close();
  });
  test(
    'cancelled Google sign-in preserves the guest identity and its data',
    () async {
      final session = AccountTestSession()..cancelGoogle = true;
      final api = AccountTestApi(session);
      final c = CompanionController(session: session, api: api);
      await c.restore();
      final companion = c.companion!.id;
      await expectLater(
        c.authenticateGoogle(link: true),
        throwsA(isA<AppFailure>()),
      );
      expect(c.userId, 'alice');
      expect(c.companion!.id, companion);
      expect(c.anonymousAccount, true);
      expect(c.authenticating, false);
      c.dispose();
      await session.events.close();
    },
  );
}
