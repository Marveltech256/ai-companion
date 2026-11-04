import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/application/friend_preferences.dart';
import 'package:ai_companion/application/theme.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/data/models.dart';

import 'support/test_services.dart';
import 'support/account_services.dart';

import 'package:ai_companion/application/setup_page.dart';

import 'application_test.dart' as capture_helpers;

void main() {
  setUpAll(capture_helpers.loadFonts);
  testWidgets(
    'three-step introduction keeps drafts on Back and saves the named companion with preferences',
    (tester) async {
      capture_helpers.viewport(tester, const Size(402, 900));
      final session = AccountTestSession()..isAnonymous = false;
      final api = AccountTestApi(session)..companion = null;
      api.profiles['alice'] = {
        'username': 'marvin_test',
        'preferred_name': 'Marvin',
      };
      final c = CompanionController(session: session, api: api);
      await c.restore();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('application-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: morrowTheme(),
            home: SetupPage(controller: c, deviceOnly: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('companion-name')),
        'Alex',
      );
      final age = find.byKey(const ValueKey('introduction-age'));
      await tester.ensureVisible(age);
      await tester.tap(age);
      await tester.pumpAndSettle();
      await tester.tap(find.text('25–34').last);
      await tester.pumpAndSettle();
      final zone = find.byKey(const ValueKey('introduction-timezone'));
      await tester.ensureVisible(zone);
      await tester.enterText(zone, 'Africa/Kampala');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Africa/Kampala').last);
      await tester.pumpAndSettle();
      Future<void> next() async {
        final button = find.widgetWithText(FilledButton, 'Continue');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await next();
      expect(find.text('Your kind of friend.'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Step 2 of 3')).dy, greaterThan(0));
      await capture_helpers.capture(tester, 'friend-personality-mobile');
      final funny = find.byKey(const ValueKey('personality-funny_playful'));
      await tester.ensureVisible(funny);
      await tester.tap(funny);
      await tester.pumpAndSettle();
      final learning = find.byKey(const ValueKey('support-learning'));
      await tester.ensureVisible(learning);
      await tester.tap(learning);
      await tester.pumpAndSettle();
      await next();
      await capture_helpers.capture(tester, 'friend-goals-mobile');
      final practice = find.byKey(const ValueKey('friend-learning'));
      await tester.ensureVisible(practice);
      await tester.enterText(practice, 'Practise German');
      final goals = find.byKey(const ValueKey('friend-goals'));
      await tester.ensureVisible(goals);
      await tester.enterText(goals, 'Speak more confidently');
      await tester.ensureVisible(find.text('Back'));
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('personality-funny_playful')),
            )
            .selected,
        true,
      );
      await next();
      expect(
        tester.widget<TextFormField>(practice).controller!.text,
        'Practise German',
      );
      final meet = find.widgetWithText(FilledButton, 'Meet Alex');
      await tester.ensureVisible(meet);
      await tester.tap(meet);
      await tester.pumpAndSettle();
      expect(c.companion!.name, 'Alex');
      expect(c.companion!.preferences.support, ['learning']);
      expect(c.companion!.preferences.personalities, [
        'warm_caring',
        'funny_playful',
      ]);
      expect(c.companion!.preferences.learning, 'Practise German');
      expect(c.personalProfile.preferredName, 'Marvin');
      expect(c.personalProfile.ageGroup, '25_34');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await session.events.close();
    },
  );
  testWidgets(
    'support selection is capped at four, can be removed, and personality blends retain a choice',
    (tester) async {
      final draft = FriendPreferencesDraft();
      await tester.pumpWidget(
        MaterialApp(
          theme: morrowTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: FriendPreferenceFields(draft: draft, step: 1),
            ),
          ),
        ),
      );
      for (final key in [
        'learning',
        'daily_companionship',
        'motivation',
        'language_practice',
      ]) {
        final option = find.byKey(ValueKey('support-$key'));
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
      }
      expect(draft.support.length, 4);
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('support-creativity')),
            )
            .onSelected,
        isNull,
      );
      final remove = find.byKey(const ValueKey('support-learning'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('support-creativity')),
            )
            .onSelected,
        isNotNull,
      );
      final funny = find.byKey(const ValueKey('personality-funny_playful'));
      await tester.ensureVisible(funny);
      await tester.tap(funny);
      await tester.pumpAndSettle();
      expect(draft.personalities, {'warm_caring', 'funny_playful'});
      final warm = find.byKey(const ValueKey('personality-warm_caring'));
      await tester.ensureVisible(warm);
      await tester.tap(warm);
      await tester.pumpAndSettle();
      await tester.tap(funny);
      await tester.pumpAndSettle();
      expect(draft.personalities, {'funny_playful'});
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    },
  );

  test('preference changes survive controller restoration and preserve existing memory consent', () async {
    final session = TestSession(), api = TestApi();
    final first = CompanionController(session: session, api: api);
    await first.restore();
    final before = first.companion!;
    const preferences = CompanionPreferences(
      personalities: ['curious_intellectual'],
      support: ['learning'],
      communication: 'direct',
      learning: 'Practise German',
      goals: 'Speak confidently',
    );
    await first.saveFriendPreferences('Alex', preferences);
    expect(first.companion!.preferences.learning, 'Practise German');
    expect(first.companion!.memoryEnabled, before.memoryEnabled);
    final restored = CompanionController(session: session, api: api);
    await restored.restore();
    expect(restored.companion!.name, 'Alex');
    expect(restored.companion!.preferences.personalities, [
      'curious_intellectual',
    ]);
    expect(restored.companion!.preferences.support, ['learning']);
    expect(restored.companion!.preferences.communication, 'direct');
    first.dispose();
    restored.dispose();
    await session.events.close();
  });
}
