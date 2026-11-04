import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/data/models.dart';

import 'support/test_services.dart';

class DelayedRefreshApi extends TestApi {
  final pending = <String, Completer<Map<String, dynamic>>>{};
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) {
    calls.add(action);
    return pending[action]?.future ?? super.call(action, body);
  }
}

void main() {
  test('saved reply refresh keeps messages visible and does not wait for sidebar or memories', () async {
    final session = TestSession(), api = DelayedRefreshApi();
    final c = CompanionController(session: session, api: api);
    await c.restore();
    final saved = Completer<Map<String, dynamic>>(),
        sidebar = Completer<Map<String, dynamic>>(),
        memories = Completer<Map<String, dynamic>>();
    api.pending.addAll({
      'messages': saved,
      'list_conversations': sidebar,
      'list_memories': memories,
    });
    var hadMessages = false, flashedEmpty = false, completed = false;
    c.addListener(() {
      if (c.messages.isNotEmpty) hadMessages = true;
      if (hadMessages && c.messages.isEmpty) flashedEmpty = true;
    });
    final sending = c.send('I enjoy cycling.').then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(c.loadingConversation, true);
    expect(c.messages.last.content, 'What do you enjoy about cycling?');
    expect(flashedEmpty, false);
    await c.ensureGreeting();
    expect(api.greetingIds, isEmpty);
    saved.complete({'messages': List<Map<String, dynamic>>.from(api.records)});
    await Future<void>.delayed(Duration.zero);
    expect(completed, true);
    expect(c.sending, false);
    expect(c.loadingConversation, false);
    expect(c.messages.last.id, 'assistant');
    expect(api.calls, containsAll(['list_conversations', 'list_memories']));
    expect(api.turnIds, hasLength(1));
    expect(flashedEmpty, false);
    sidebar.complete({
      'conversations': [
        {'id': api.conversationId, 'title': 'Cycling'},
      ],
    });
    memories.complete({'memories': []});
    await sending;
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    await session.events.close();
  });

  test('loading another conversation cannot generate a new greeting or leak an old read', () async {
    final session = TestSession(), api = DelayedRefreshApi();
    final c = CompanionController(session: session, api: api);
    await c.restore();
    final saved = Completer<Map<String, dynamic>>();
    api.pending['messages'] = saved;
    final loading = c.openConversation(
      Conversation(id: api.conversationId, title: 'Stored conversation'),
    );
    expect(c.loadingConversation, true);
    await c.ensureGreeting();
    await c.send('Do not send during loading');
    expect(api.greetingIds, isEmpty);
    expect(api.turnIds, isEmpty);
    session.switchUser(null);
    saved.complete({
      'messages': [
        {
          'id': 'old',
          'role': 'user',
          'content': 'Old account words',
          'status': 'completed',
        },
      ],
    });
    await loading;
    expect(c.messages, isEmpty);
    expect(c.loadingConversation, false);
    c.dispose();
    await session.events.close();
  });
  test('opening an empty cloud conversation persists only a welcome and does not repeat it', () async {
    final session = TestSession(), api = TestApi();
    final controller = CompanionController(session: session, api: api);
    await controller.restore();
    await controller.ensureGreeting();
    expect(api.greetingIds, hasLength(1));
    expect(api.turnIds, isEmpty);
    expect(controller.messages.map((m) => m.role), ['assistant']);
    expect(
      controller.messages.single.content,
      contains('What should I call you?'),
    );
    await controller.ensureGreeting();
    expect(api.greetingIds, hasLength(1));
    api.records.single['status'] = 'failed';
    await controller.openConversation(controller.activeConversation!);
    await controller.retrySend();
    expect(api.greetingIds, hasLength(2));
    expect(api.greetingIds.first, api.greetingIds.last);
    expect(controller.messages.single.role, 'assistant');
    expect(controller.messages.single.failed, isFalse);
    controller.dispose();
    await session.events.close();
  });
  test('personal details save under the current identity and restore separately from the companion name', () async {
    final session = TestSession(), api = TestApi();
    final controller = CompanionController(session: session, api: api);
    await controller.restore();
    await controller.savePersonalProfile(
      const PersonalProfile(
        preferredName: 'Marvin',
        timezone: 'Africa/Kampala',
      ),
    );
    expect(controller.personalProfile.preferredName, 'Marvin');
    expect(controller.companion!.name, 'Nova');
    await controller.restore();
    expect(controller.personalProfile.timezone, 'Africa/Kampala');
    session.switchUser(null);
    expect(controller.personalProfile.preferredName, isNull);
    controller.dispose();
    await session.events.close();
  });
  test(
    'first anonymous session creates one persistent companion and restores it',
    () async {
      final session = TestSession()..uid = null;
      final api = TestApi()..companion = null;
      final bootstrap = Completer<Map<String, dynamic>>();
      api.bootstrap = bootstrap;
      final controller = CompanionController(session: session, api: api);
      Future<bool> create() => controller.create(
        name: 'Lumi',
        style: 'Reflective',
        interests: ['Books'],
        memoryEnabled: false,
      );
      final creating = create();
      await Future<void>.delayed(Duration.zero);
      expect(controller.busy, isTrue);
      expect(await create(), isFalse);
      bootstrap.complete({'profile': {}, 'companion': null});
      expect(await creating, isTrue);
      expect(api.saved, hasLength(1));
      expect(controller.companion!.memoryEnabled, isFalse);
      final id = controller.companion!.id;
      controller.dispose();
      final restored = CompanionController(session: session, api: api);
      await restored.restore();
      expect(restored.companion!.id, id);
      expect(restored.companion!.style, 'Reflective');
      expect(restored.companion!.interests, ['Books']);
      expect(restored.companion!.memoryEnabled, isFalse);
      restored.dispose();
      await session.events.close();
    },
  );
  test(
    'a failed consent/settings save prevents sending with stale preferences',
    () async {
      final session = TestSession(), api = TestApi();
      final controller = CompanionController(session: session, api: api);
      await controller.restore();
      api.failSettings = true;
      await controller.saveSettings(
        controller.companion!.copyWith(memoryEnabled: false),
      );
      await controller.send('I enjoy cycling.');
      expect(api.turnIds, isEmpty);
      expect(controller.error?.code, 'settings_not_saved');
      controller.dispose();
      await session.events.close();
    },
  );
  test('interrupted sends retry with the same request ID and replace the partial reply', () async {
    final session = TestSession(), api = TestApi()..failFirstTurn = true;
    final controller = CompanionController(session: session, api: api);
    await controller.restore();
    await controller.send('I enjoy cycling.');
    expect(controller.error, isNotNull);
    expect(controller.messages.last.failed, isTrue);
    await controller.retrySend();
    expect(api.turnIds.length, 2);
    expect(api.turnIds[0], api.turnIds[1]);
    expect(controller.messages.length, 2);
    expect(
      controller.messages.last.content,
      'What do you enjoy about cycling?',
    );
    expect(controller.messages.last.pending, isFalse);
    expect(controller.error, isNull);
    controller.dispose();
    await session.events.close();
  });
  test('old account responses cannot populate a new account session', () async {
    final session = TestSession(), api = TestApi();
    final pending = Completer<Map<String, dynamic>>();
    api.bootstrap = pending;
    final controller = CompanionController(session: session, api: api);
    final restore = controller.restore();
    final oldCompanion = api.companion;
    api.companion = null;
    api.profileName = 'Bob';
    session.switchUser('bob');
    pending.complete({
      'profile': {'display_name': 'Old account'},
      'companion': oldCompanion,
    });
    await restore;
    await Future<void>.delayed(Duration.zero);
    expect(controller.companion, isNull);
    expect(controller.displayName, 'Bob');
    expect(controller.messages, isEmpty);
    expect(controller.busy, isFalse);
    controller.dispose();
    await session.events.close();
  });
  test(
    'settings saves are serialized and restore the most recent selection',
    () async {
      final session = TestSession(), api = TestApi();
      final controller = CompanionController(session: session, api: api);
      await controller.restore();
      final first = controller.saveSettings(
        controller.companion!.copyWith(style: 'Reflective'),
      );
      final second = controller.saveSettings(
        controller.companion!.copyWith(
          style: 'Gentle & warm',
          memoryEnabled: false,
        ),
      );
      await Future.wait([first, second]);
      expect(api.saved.map((s) => s['style']), ['Reflective', 'Gentle & warm']);
      expect(controller.companion!.style, 'Gentle & warm');
      expect(controller.companion!.memoryEnabled, isFalse);
      expect(controller.settingsSaved, isTrue);
      controller.dispose();
      await session.events.close();
    },
  );
}
