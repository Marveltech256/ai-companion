import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/application/application.dart';
import 'package:ai_companion/application/connection.dart';
import 'package:ai_companion/voice/voice_controller.dart';

import 'support/voice_services.dart';
import 'support/workspace_storage.dart';
import 'support/account_services.dart';

class VoiceAccountApi extends AccountTestApi {
  VoiceAccountApi(super.session);
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    final result = await super.call(action, body);
    if (action == 'bootstrap') {
      result['capabilities'] = {'welcome_audio': true, 'transcription': true};
    }
    return result;
  }
}

class DelayedMessageApi extends AccountTestApi {
  DelayedMessageApi(super.session);
  Completer<Map<String, dynamic>>? messageRead;
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) {
    if (action == 'messages' && messageRead != null) return messageRead!.future;
    return super.call(action, body);
  }
}

Future<void> loadFonts() async {
  for (final family in ['Inter', 'Lora']) {
    final loader = FontLoader(family)
      ..addFont(rootBundle.load('assets/fonts/$family.ttf'));
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

void viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<AppConnection> deviceApp(
  WidgetTester tester, {
  MemoryWorkspaceStorage? storage,
  bool setup = false,
}) async {
  final connection = await openDeviceWorkspace(
    storage: storage ?? MemoryWorkspaceStorage(),
  );
  if (!setup) {
    await connection.controller.create(
      name: 'Lumi',
      style: 'Gentle & warm',
      interests: ['Music'],
      memoryEnabled: false,
    );
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('application-capture'),
      child: MorrowApplication(connection: connection, requireSignIn: false),
    ),
  );
  await tester.pumpAndSettle();
  return connection;
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final context = tester.element(
      find.byKey(const ValueKey('application-capture')),
    );
    for (final picture in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(picture.image, context);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('application-capture')),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/application-review').create(recursive: true);
    await File('build/application-review/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'desktop Enter sends once; Shift Enter and IME composition do not send',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        viewport(tester, const Size(1440, 1000));
        final session = AccountTestSession()..isAnonymous = false;
        final api = DelayedMessageApi(session);
        api.profiles['alice'] = {
          'username': 'taylor',
          'preferred_name': 'Taylor',
          'age_group': '25_34',
          'introduction_completed_at': '2026-11-03T10:00:00Z',
          'welcome_completed_at': '2026-11-03T10:00:00Z',
        };
        final c = CompanionController(session: session, api: api);
        await c.restore();
        await tester.pumpWidget(
          MorrowApplication(
            connection: AppConnection(
              controller: c,
              deviceOnly: false,
              closeSession: session.events.close,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chat'));
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('message-input'));
        await tester.enterText(input, 'I enjoy cycling.');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(api.turnIds, isEmpty);
        final editor = tester.widget<TextField>(input).controller!;
        editor.value = const TextEditingValue(
          text: 'Pending composition',
          selection: TextSelection.collapsed(offset: 19),
          composing: TextRange(start: 0, end: 19),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(api.turnIds, isEmpty);
        await tester.enterText(input, 'I enjoy cycling.');
        api.messageRead = Completer<Map<String, dynamic>>();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        // The persisted-message read is deliberately held while the send spinner
        // animates; inspect that intermediate frame instead of waiting for idle.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(api.turnIds, hasLength(1));
        expect(c.loadingConversation, true);
        expect(find.text('What do you enjoy about cycling?'), findsOneWidget);
        expect(find.text('No perfect words needed.'), findsNothing);
        expect(editor.text, isEmpty);
        api.messageRead!.complete({
          'messages': List<Map<String, dynamic>>.from(api.records),
        });
        await tester.pumpAndSettle();
        expect(find.text('No perfect words needed.'), findsNothing);
        expect(c.sending, false);
        await tester.enterText(input, 'Numpad sends too.');
        // Flutter's Windows test simulator omits the numpad-enter key code.
        await tester.sendKeyEvent(
          LogicalKeyboardKey.numpadEnter,
          platform: 'linux',
        );
        await tester.pumpAndSettle();
        expect(api.turnIds, hasLength(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  testWidgets(
    'Chat voice recording is editable, replayable and only sends after confirmation',
    (tester) async {
      viewport(tester, const Size(402, 900));
      final session = AccountTestSession()..isAnonymous = false;
      final api = VoiceAccountApi(session);
      api.profiles['alice'] = {
        'username': 'taylor',
        'preferred_name': 'Taylor',
        'age_group': '25_34',
        'introduction_completed_at': '2026-11-03T10:00:00Z',
        'welcome_completed_at': '2026-11-03T10:00:00Z',
      };
      final c = CompanionController(session: session, api: api);
      await c.restore();
      final hardware = TestVoiceHardware(), speech = TestSpeechGateway();
      final voice = VoiceController(
        companion: c,
        hardware: hardware,
        gateway: speech,
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('application-capture'),
          child: MorrowApplication(
            connection: AppConnection(
              controller: c,
              deviceOnly: false,
              voice: voice,
              closeSession: session.events.close,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Record a voice message'));
      await tester.pump();
      hardware.chunks.add(Uint8List(6400));
      await tester.pump();
      await tester.tap(find.byTooltip('Stop voice recording'));
      await tester.runAsync(() async {
        for (var i = 0; i < 50 && voice.stage == VoiceStage.transcribing; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(
        voice.stage,
        VoiceStage.review,
        reason: '${voice.error?.code}: ${voice.error?.message}',
      );
      expect(api.turnIds, isEmpty);
      expect(find.text('Review before sending'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'New conversation',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('voice-transcript-review')),
        'I enjoy cycling, not running.',
      );
      await tester.tap(find.text('Replay recording'));
      await tester.pumpAndSettle();
      expect(hardware.plays, 1);
      await capture(tester, 'voice-message-review');
      await tester.ensureVisible(find.text('Send voice message'));
      await tester.tap(find.text('Send voice message'));
      await tester.pumpAndSettle();
      expect(api.turnIds, hasLength(1));
      expect(
        c.messages.firstWhere((m) => m.role == 'user').content,
        'I enjoy cycling, not running.',
      );
      expect(speech.spoken, isEmpty);
      await tester.tap(find.byTooltip('Play voice reply'));
      await tester.pumpAndSettle();
      expect(speech.spoken.last, c.messages.last.id);
      expect(hardware.plays, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Home continues the latest stored conversation after a fresh restore',
    (tester) async {
      viewport(tester, const Size(402, 900));
      final session = AccountTestSession()..isAnonymous = false;
      final api = AccountTestApi(session);
      api.profiles['alice'] = {
        'username': 'taylor',
        'preferred_name': 'Taylor',
        'age_group': '25_34',
        'introduction_completed_at': '2026-11-03T10:00:00Z',
        'welcome_completed_at': '2026-11-03T10:00:00Z',
      };
      api.records.add({
        'id': 'owned-saved-message',
        'request_id': 'owned-saved-request',
        'seq': 1,
        'role': 'user',
        'content': 'I finished my sketch yesterday.',
        'status': 'completed',
      });
      final c = CompanionController(session: session, api: api);
      await c.restore();
      expect(c.activeConversation!.id, api.conversationId);
      await tester.pumpWidget(
        MorrowApplication(
          connection: AppConnection(
            controller: c,
            deviceOnly: false,
            closeSession: session.events.close,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue chatting'));
      await tester.pumpAndSettle();
      expect(c.activeConversation!.id, api.conversationId);
      expect(find.text('I finished my sketch yesterday.'), findsOneWidget);
      expect(api.greetingIds, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'an existing account confirms 18+ and language once without replacing its companion',
    (tester) async {
      viewport(tester, const Size(402, 900));
      final session = AccountTestSession()..isAnonymous = false;
      final api = AccountTestApi(session);
      api.profiles['alice'] = {
        'username': 'marvin',
        'preferred_name': 'Marvin',
        'welcome_completed_at': '2026-11-01T09:00:00Z',
      };
      final c = CompanionController(session: session, api: api);
      await c.restore();
      await tester.pumpWidget(
        MorrowApplication(
          connection: AppConnection(
            controller: c,
            deviceOnly: false,
            closeSession: session.events.close,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Choose your age range.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('introduction-age')));
      await tester.pumpAndSettle();
      expect(find.text('15–17'), findsNothing);
      await tester.tap(find.text('18–24').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('introduction-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Français').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('introduction-timezone')),
        'Africa/Kampala',
      );
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(c.personalProfile.ageGroup, '18_24');
      expect(c.personalProfile.language, 'fr');
      expect(c.companion!.name, 'Nova');
      expect(api.saved, isEmpty);
      expect(find.text('Salut, Marvin.'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
        hasLength(3),
      );
      expect(find.text('Coming up'), findsNothing);
      expect(find.text('Things you mentioned'), findsNothing);
      await c.restore();
      await tester.pumpAndSettle();
      expect(find.text('Before we catch up.'), findsNothing);
      expect(find.text('Nice to meet you, Marvin!'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'email signup collects account names, validates confirmation and greets the saved preferred name',
    (tester) async {
      viewport(tester, const Size(402, 900));
      final session = AccountTestSession()..uid = null;
      final api = AccountTestApi(session)..companion = null;
      final c = CompanionController(session: session, api: api);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('application-capture'),
          child: MorrowApplication(
            connection: AppConnection(
              controller: c,
              deviceOnly: false,
              closeSession: session.events.close,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'sign-in');
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('account-username')),
        'Marvin_20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-preferred-name')),
        'Marvin',
      );
      await tester.pumpAndSettle();
      await capture(tester, 'create-account');
      await tester.enterText(
        find.byKey(const ValueKey('account-email')),
        'marvin@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password')),
        'test-password',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('account-password-confirm')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password-confirm')),
        'different-password',
      );
      final submit = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Create account'),
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(session.creates, 0);
      await tester.enterText(
        find.byKey(const ValueKey('account-password-confirm')),
        'test-password',
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(c.personalProfile.username, 'marvin_20');
      expect(c.personalProfile.preferredName, 'Marvin');
      expect(session.creates, 1);
      await tester.tap(find.byKey(const ValueKey('introduction-age')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25–34').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('introduction-timezone')),
        'Africa/Kampala',
      );
      for (var step = 0; step < 2; step++) {
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Continue'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Meet Lumi'));
      await tester.tap(find.text('Meet Lumi'));
      await tester.pumpAndSettle();
      expect(find.text('Nice to meet you, Marvin!'), findsOneWidget);
      expect(c.personalProfile.ageGroup, '25_34');
      expect(c.personalProfile.language, 'en');
      await capture(tester, 'welcome');
      await tester.tap(find.text('Let’s get to know each other'));
      await tester.pumpAndSettle();
      expect(c.needsWelcome, false);
      expect(find.byKey(const ValueKey('message-input')), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Hi, Marvin.'), findsOneWidget);
      expect(find.text('With Lumi'), findsOneWidget);
      await capture(tester, 'cloud-home');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Google login asks a new account for its own name without requiring an email password',
    (tester) async {
      viewport(tester, const Size(402, 900));
      final session = AccountTestSession()..uid = null;
      final api = AccountTestApi(session)..companion = null;
      final c = CompanionController(session: session, api: api);
      await tester.pumpWidget(
        MorrowApplication(
          connection: AppConnection(
            controller: c,
            deviceOnly: false,
            closeSession: session.events.close,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.text('Make this space yours'), findsOneWidget);
      expect(session.googleLogins, 1);
      expect(session.creates, 0);
      await tester.enterText(
        find.byKey(const ValueKey('account-username')),
        'google_marvin',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-preferred-name')),
        'Marvin',
      );
      final save = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save my name'),
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(c.needsAccountDetails, false);
      expect(api.profiles['google-user']!['preferred_name'], 'Marvin');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'personal details use the existing account dialog and update the home greeting',
    (tester) async {
      viewport(tester, const Size(402, 900));
      final connection = await deviceApp(tester);
      await tester.tap(find.byTooltip('Your settings'));
      await tester.pumpAndSettle();
      final details = find.text('My name & personal details');
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'What should I call you?'),
        'Marvin',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Time zone'),
        'Africa/Kampala',
      );
      await tester.pumpAndSettle();
      await capture(tester, 'personal-details');
      await tester.tap(find.text('Save my details'));
      await tester.pumpAndSettle();
      expect(connection.controller.personalProfile.preferredName, 'Marvin');
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Hi, Marvin.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'narrow conversation remains usable with a keyboard and larger text',
    (tester) async {
      viewport(tester, const Size(320, 680));
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetViewInsets);
      await deviceApp(tester);
      await tester.tap(find.text('Chat'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('message-input')),
        'One small thought.\nAnd another line.\nRoom to keep writing.',
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Save thought'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'automatic companion settings remove manual style and memory panels',
    (tester) async {
      viewport(tester, const Size(402, 900));
      final storage = MemoryWorkspaceStorage();
      final connection = await deviceApp(tester, storage: storage);
      await tester.tap(find.byTooltip('Your settings'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-companion-name')),
        findsNothing,
      );
      expect(find.byType(Slider), findsNothing);
      expect(find.text('Save companion'), findsNothing);
      expect(find.text('Let your story grow'), findsNothing);
      expect(find.text('Learn our rhythm'), findsNothing);
      expect(connection.controller.companion!.name, 'Lumi');
      await capture(tester, 'settings');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'native privacy dialog requires exact confirmation before device erasure',
    (tester) async {
      viewport(tester, const Size(402, 900));
      final storage = MemoryWorkspaceStorage();
      final connection = await deviceApp(tester, storage: storage);
      await tester.tap(find.byTooltip('Your settings'));
      await tester.pumpAndSettle();
      final remove = find.text('Delete device workspace');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(connection.controller.companion, isNotNull);
      expect(storage.value, isNotNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirmation'),
        'DELETE_MY_ACCOUNT',
      );
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(connection.controller.erasureStatus, 'complete');
      expect(storage.value, isNull);
      expect(find.text('Your space has been removed.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'native onboarding, journal, and memory editor persist actual user input',
    (tester) async {
      viewport(tester, const Size(402, 900));
      final storage = MemoryWorkspaceStorage();
      final connection = await deviceApp(tester, storage: storage, setup: true);
      await capture(tester, 'setup');
      final meet = find.widgetWithText(FilledButton, 'Meet Lumi');
      await tester.ensureVisible(meet);
      await tester.tap(meet);
      await tester.pumpAndSettle();
      expect(connection.controller.companion!.name, 'Lumi');
      expect(connection.controller.companion!.memoryEnabled, true);
      await capture(tester, 'home');
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('message-input')),
        'Today I finished my first sketch.',
      );
      await tester.tap(find.byTooltip('Save thought'));
      await tester.pumpAndSettle();
      expect(connection.controller.messages.single.role, 'user');
      expect(find.text('Today I finished my first sketch.'), findsOneWidget);
      await capture(tester, 'conversation');
      await tester.tap(find.byTooltip('Your settings'));
      await tester.pumpAndSettle();
      final savedMemories = find.text('My saved details');
      await tester.ensureVisible(savedMemories);
      await tester.tap(savedMemories);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add memory'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Sketching');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'I enjoy sketching by the lake.',
      );
      await tester.tap(find.text('Save memory'));
      await tester.pumpAndSettle();
      expect(
        connection.controller.memories.single.content,
        'I enjoy sketching by the lake.',
      );
      await capture(tester, 'memories');
      await tester.tap(find.byTooltip('Manage Sketching'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit memory'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Morning sketching',
      );
      await tester.tap(find.text('Save memory'));
      await tester.pumpAndSettle();
      expect(connection.controller.memories.single.title, 'Morning sketching');
      expect(storage.value, contains('Morning sketching'));
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .every(
              (widget) =>
                  widget.image is AssetImage &&
                  (widget.image as AssetImage).assetName ==
                      'assets/branding/logo-mark.png',
            ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'native cloud composer sends through the actual controller and shows streamed records',
    (tester) async {
      viewport(tester, const Size(402, 900));
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
      await tester.enterText(
        find.byKey(const ValueKey('message-input')),
        'I enjoy cycling.',
      );
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(api.turnIds, hasLength(1));
      expect(find.text('What do you enjoy about cycling?'), findsOneWidget);
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .every(
              (widget) =>
                  widget.image is AssetImage &&
                  (widget.image as AssetImage).assetName ==
                      'assets/branding/logo-mark.png',
            ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Talk is a Coming Soon preview and never starts microphone capture',
    (tester) async {
      viewport(tester, const Size(402, 900));
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
      final hardware = TestVoiceHardware()..allowed = false;
      final voice = VoiceController(
        companion: controller,
        hardware: hardware,
        gateway: TestSpeechGateway(),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('application-capture'),
          child: MorrowApplication(
            connection: AppConnection(
              controller: controller,
              deviceOnly: false,
              voice: voice,
              closeSession: session.events.close,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Talk'));
      await tester.pumpAndSettle();
      expect(hardware.permissionRequests, 0);
      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.byTooltip('Unmute'), findsNothing);
      expect(find.byTooltip('End'), findsNothing);
      await capture(tester, 'voice');
      await tester.tap(find.text('Back to chat'));
      await tester.pumpAndSettle();
      expect(hardware.permissionRequests, 0);
      expect(find.byKey(const ValueKey('message-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'desktop and narrow screens use flowing layout rather than scaled frames',
    (tester) async {
      viewport(tester, const Size(1440, 1000));
      await deviceApp(tester);
      expect(find.byType(NavigationBar), findsNothing);
      await capture(tester, 'desktop-home');
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      await capture(tester, 'desktop-conversation');
      tester.view.physicalSize = const Size(320, 680);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
