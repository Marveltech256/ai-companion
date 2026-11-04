import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/app/morrow_app.dart';
import 'package:ai_companion/core/app_failure.dart';
import 'package:ai_companion/design/scene.dart';
import 'package:ai_companion/design/scene_view.dart';

import 'support/test_services.dart';
import 'support/voice_services.dart';

import 'package:ai_companion/voice/voice_controller.dart';

void main() {
  late DesignLibrary library;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final family in ['Inter', 'Lora']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
    library = await DesignLibrary.load();
  });
  testWidgets(
    'live memories render stored content using the supplied card styling',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = TestSession(), api = TestApi();
      api.records.add({
        'id': 'saved-user-message',
        'request_id': 'saved-request',
        'seq': 1,
        'role': 'user',
        'content': 'I enjoy cycling.',
        'status': 'completed',
      });
      api.memoryRecords.add({
        'id': 'memory',
        'memory_key': 'preferences.cycling',
        'category': 'preferences',
        'title': 'Cycling',
        'content': 'I enjoy cycling.',
        'updated_at': '2026-11-02T10:00:00Z',
      });
      final controller = CompanionController(session: session, api: api);
      await controller.restore();
      await tester.pumpWidget(
        MorrowApp(library: library, controller: controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is DesignButton && w.label == 'Memories',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cycling'), findsNWidgets(2));
      expect(find.text('LITTLE JOYS'), findsOneWidget);
      // The two alternatives must exclude the persisted selected style.
      expect(
        find.byWidgetPredicate(
          (w) => w is DesignButton && w.label == 'Gentle & warm',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is DesignButton && w.label == 'Playful',
        ),
        findsNothing,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is DesignButton && w.label == 'Gentle & warm',
        ),
      );
      await tester.pumpAndSettle();
      expect(api.saved.last['style'], 'Gentle & warm');
      // History retains its Figma row positions and opens from Memories.
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is DesignButton && w.label == 'Cycling',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('viewport-desktop_conversation')),
        findsOneWidget,
      );
      expect(controller.messages.single.content, 'I enjoy cycling.');
      expect(
        find.byWidgetPredicate(
          (w) => w is DesignText && (w.node.text ?? '').contains('Maya'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await session.events.close();
    },
  );
  testWidgets(
    'supplied voice screen waits for an explicit microphone action and contains no sample transcript',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = TestSession(), api = TestApi();
      final controller = CompanionController(session: session, api: api);
      await controller.restore();
      final hardware = TestVoiceHardware()..allowed = false;
      final voice = VoiceController(
        companion: controller,
        hardware: hardware,
        gateway: TestSpeechGateway(),
      );
      await tester.pumpWidget(
        MorrowApp(library: library, controller: controller, voice: voice),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is DesignButton && w.label == 'Or, let’s talk out loud',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('viewport-voice')), findsOneWidget);
      expect(hardware.permissionRequests, 0);
      expect(find.text('Unmute when you are ready to talk.'), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate((w) => w is DesignButton && w.label == 'Unmute'),
      );
      await tester.pumpAndSettle();
      expect(hardware.permissionRequests, 1);
      expect(voice.error?.code, 'microphone_denied');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await session.events.close();
    },
  );
  testWidgets(
    'unconfigured live mode remains on setup instead of fabricating a session',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CompanionController.unconfigured(
        const AppFailure('configuration_required', 'Configuration required.'),
      );
      await tester.pumpWidget(
        MorrowApp(library: library, controller: controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is DesignButton && w.label == 'Meet Lumi',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('viewport-setup')), findsOneWidget);
      expect(controller.companion, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'live conversation renders real records and removes Figma example transcript',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = TestSession(), api = TestApi();
      final controller = CompanionController(session: session, api: api);
      await controller.restore();
      await tester.pumpWidget(
        MorrowApp(library: library, controller: controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((w) => w is DesignButton && w.label == 'Talk'),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is DesignText && (w.node.text ?? '').contains('Maya'),
        ),
        findsNothing,
      );
      await tester.enterText(find.byType(TextField), 'I enjoy cycling.');
      await tester.tap(
        find
            .byWidgetPredicate((w) => w is DesignButton && w.label.isEmpty)
            .last,
      );
      await tester.pumpAndSettle();
      expect(controller.messages.length, 2);
      expect(
        controller.messages.last.content,
        'What do you enjoy about cycling?',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await session.events.close();
    },
  );
}
