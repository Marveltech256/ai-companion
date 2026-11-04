import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/application/application.dart';
import 'package:ai_companion/application/bootstrap.dart';
import 'package:ai_companion/application/connection.dart';
import 'package:ai_companion/application/sign_in_page.dart';
import 'package:ai_companion/core/app_failure.dart';

import 'support/account_services.dart';

void main() {
  testWidgets(
    'an existing guest companion cannot bypass sign-in or cancel into the app',
    (tester) async {
      final session = AccountTestSession();
      final controller = CompanionController(
        session: session,
        api: AccountTestApi(session),
      );
      await controller.restore();
      expect(controller.companion, isNotNull);
      await tester.pumpWidget(
        MorrowApplication(
          connection: AppConnection(
            controller: controller,
            deviceOnly: false,
            closeSession: session.events.close,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SignInPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Meet Lumi'), findsNothing);
      expect(find.text('Start on this device'), findsNothing);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SignInPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'restored registered accounts enter; sign-out closes protected overlays and locks again',
    (tester) async {
      final session = AccountTestSession()..isAnonymous = false;
      final api = AccountTestApi(session);
      api.profiles['alice'] = {
        'username': 'marvin',
        'preferred_name': 'Marvin',
        'age_group': '25_34',
        'introduction_completed_at': '2026-11-03T10:00:00Z',
        'welcome_completed_at': '2026-11-03T10:00:00Z',
      };
      final controller = CompanionController(session: session, api: api);
      await controller.restore();
      await tester.pumpWidget(
        MorrowApplication(
          connection: AppConnection(
            controller: controller,
            deviceOnly: false,
            closeSession: session.events.close,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hi, Marvin.'), findsOneWidget);
      await tester.tap(find.byTooltip('Your settings'));
      await tester.pumpAndSettle();
      expect(find.text('Open device workspace'), findsNothing);
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Conversation history'));
      await tester.pumpAndSettle();
      expect(find.text('Little moments'), findsOneWidget);
      await controller.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(SignInPage), findsOneWidget);
      expect(find.text('Little moments'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'switching directly between registered users closes the previous account overlays',
    (tester) async {
      final session = AccountTestSession()..isAnonymous = false;
      final api = AccountTestApi(session);
      for (final owner in ['alice', 'bob']) {
        api.profiles[owner] = {
          'username': owner,
          'preferred_name': owner,
          'age_group': '25_34',
          'introduction_completed_at': '2026-11-03T10:00:00Z',
          'welcome_completed_at': '2026-11-03T10:00:00Z',
        };
      }
      final controller = CompanionController(session: session, api: api);
      await controller.restore();
      await tester.pumpWidget(
        MorrowApplication(
          connection: AppConnection(
            controller: controller,
            deviceOnly: false,
            closeSession: session.events.close,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Conversation history'));
      await tester.pumpAndSettle();
      expect(find.text('Little moments'), findsOneWidget);
      session.switchUser('bob');
      await tester.pumpAndSettle();
      expect(find.text('Little moments'), findsNothing);
      expect(find.text('Hi, bob.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a persisted device connection cannot enter the production app', (
    tester,
  ) async {
    final controller = CompanionController.unconfigured(null);
    await tester.pumpWidget(
      MorrowApplication(
        connection: AppConnection(controller: controller, deviceOnly: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SignInPage), findsOneWidget);
    expect(find.text('Meet Lumi'), findsNothing);
    expect(find.text('Open device journal'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('startup errors cannot expose a device-journal bypass', (
    tester,
  ) async {
    var journalOpened = false;
    await tester.pumpWidget(
      ApplicationBootstrap(
        open: () async =>
            throw const AppFailure('offline', 'Check your connection.'),
        openDevice: () async {
          journalOpened = true;
          return AppConnection(
            controller: CompanionController.unconfigured(null),
            deviceOnly: true,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Open device journal'), findsNothing);
    expect(journalOpened, false);
    await tester.pumpWidget(const SizedBox());
  });
}
