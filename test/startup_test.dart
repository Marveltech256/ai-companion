import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/application/bootstrap.dart';
import 'package:ai_companion/application/connection.dart';
import 'package:ai_companion/core/app_failure.dart';

import 'support/account_services.dart';

void main() {
  AppConnection connection() => AppConnection(
    controller: CompanionController.unconfigured(null),
    deviceOnly: false,
  );

  test('a new installation selects the live account experience', () async {
    final cloud = connection();
    var journalOpens = 0;
    expect(
      await openInitialConnection(
        deviceOnly: false,
        openCloud: () async => cloud,
        openDevice: () async {
          journalOpens++;
          return connection();
        },
      ),
      same(cloud),
    );
    expect(journalOpens, 0);
    await cloud.dispose();
  });

  test(
    'legacy automatic journal preferences do not hide the account experience',
    () async {
      final cloud = connection();
      var journalOpened = false;
      expect(
        await openInitialConnection(
          deviceOnly: false,
          openCloud: () async => cloud,
          openDevice: () async {
            journalOpened = true;
            return connection();
          },
        ),
        same(cloud),
      );
      expect(journalOpened, false);
      await cloud.dispose();
    },
  );

  test(
    'the separate development journal entry point is available for previews',
    () async {
      for (final deviceOnly in [true]) {
        final device = connection();
        var cloudOpens = 0;
        expect(
          await openInitialConnection(
            deviceOnly: deviceOnly,
            openCloud: () async {
              cloudOpens++;
              return connection();
            },
            openDevice: () async => device,
          ),
          same(device),
        );
        expect(cloudOpens, 0);
        await device.dispose();
      }
    },
  );

  test(
    'an unavailable account never silently falls back to another workspace',
    () async {
      var deviceOpened = false;
      await expectLater(
        openInitialConnection(
          deviceOnly: false,
          openCloud: () async =>
              throw const AppFailure('offline', 'Try again.'),
          openDevice: () async {
            deviceOpened = true;
            return connection();
          },
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(deviceOpened, false);
    },
  );

  testWidgets(
    'startup shows progress, offers retry, and restores the real companion name',
    (tester) async {
      final session = AccountTestSession()..isAnonymous = false;
      final api = AccountTestApi(session);
      api.profiles['alice'] = {
        'username': 'taylor',
        'preferred_name': 'Taylor',
        'age_group': '25_34',
        'introduction_completed_at': '2026-11-03T10:00:00Z',
        'welcome_completed_at': '2026-11-03T10:00:00Z',
      };
      final controller = CompanionController(session: session, api: api);
      await controller.restore();
      final cloud = AppConnection(
        controller: controller,
        deviceOnly: false,
        closeSession: session.events.close,
      );
      final pending = Completer<AppConnection>();
      var attempts = 0;
      await tester.pumpWidget(
        ApplicationBootstrap(
          open: () {
            attempts++;
            return attempts == 1 ? pending.future : Future.value(cloud);
          },
        ),
      );
      expect(find.text('Opening your space…'), findsOneWidget);
      pending.completeError(
        const AppFailure('offline', 'Check your connection.'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check your connection.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('With Nova'), findsOneWidget);
      expect(find.text('Your cloud space'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a connection finishing after the startup widget closes is disposed',
    (tester) async {
      final pending = Completer<AppConnection>();
      var closed = false;
      await tester.pumpWidget(ApplicationBootstrap(open: () => pending.future));
      await tester.pumpWidget(const SizedBox());
      pending.complete(
        AppConnection(
          controller: CompanionController.unconfigured(null),
          deviceOnly: false,
          closeSession: () async => closed = true,
        ),
      );
      await tester.pump();
      expect(closed, true);
      expect(tester.takeException(), isNull);
    },
  );
}
