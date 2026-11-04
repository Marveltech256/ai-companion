import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/application/connection.dart';
import 'package:ai_companion/data/device_workspace.dart';
import 'package:ai_companion/data/models.dart';

import 'support/workspace_storage.dart';

Future<void> create(AppConnection connection) async {
  expect(
    await connection.controller.create(
      name: 'Lumi',
      style: 'Gentle & warm',
      interests: ['Books'],
      memoryEnabled: false,
    ),
    isTrue,
  );
}

void main() {
  test('personal details and structured routines survive device workspace reopening and export', () async {
    final storage = MemoryWorkspaceStorage();
    var connection = await openDeviceWorkspace(storage: storage);
    await create(connection);
    await connection.controller.savePersonalProfile(
      const PersonalProfile(
        preferredName: 'Marvin',
        language: 'English',
        timezone: 'Africa/Kampala',
      ),
    );
    await connection.controller.saveMemory(
      category: 'routines',
      title: 'My work week',
      content: 'I work weekdays, 9 AM to 5 PM.',
      attributes: {
        'routine_kind': 'work',
        'weekdays': [1, 2, 3, 4, 5],
        'start_minute': 540,
        'end_minute': 1020,
      },
    );
    await connection.dispose();
    connection = await openDeviceWorkspace(storage: storage);
    await connection.controller.loadMemories();
    expect(connection.controller.personalProfile.preferredName, 'Marvin');
    expect(
      connection.controller.memories.single.attributes['end_minute'],
      1020,
    );
    expect(await connection.controller.exportData(), contains('Marvin'));
    await connection.dispose();
  });
  test('device workspace restores real journal input and memories without generating AI replies', () async {
    final storage = MemoryWorkspaceStorage();
    var connection = await openDeviceWorkspace(storage: storage);
    await create(connection);
    final observedRoles = <String>[];
    connection.controller.addListener(
      () => observedRoles.addAll(
        connection.controller.messages.map((message) => message.role),
      ),
    );
    await connection.controller.send('A quiet walk beside the lake.');
    await connection.controller.saveMemory(
      category: 'preferences',
      title: 'A favourite place',
      content: 'I enjoy walking beside the lake.',
    );
    expect(connection.controller.messages.map((message) => message.role), [
      'user',
    ]);
    expect(observedRoles, isNot(contains('assistant')));
    expect(
      connection.controller.messages.single.content,
      'A quiet walk beside the lake.',
    );
    final id = connection.controller.companion!.id;
    await connection.dispose();
    connection = await openDeviceWorkspace(storage: storage);
    await connection.controller.loadMemories();
    expect(connection.controller.companion!.id, id);
    expect(
      connection.controller.messages.single.content,
      'A quiet walk beside the lake.',
    );
    expect(connection.controller.memories.single.title, 'A favourite place');
    await connection.dispose();
  });

  test(
    'failed persistence does not overwrite the last saved workspace',
    () async {
      final storage = MemoryWorkspaceStorage();
      final connection = await openDeviceWorkspace(storage: storage);
      await create(connection);
      final saved = storage.value;
      storage.failWrites = true;
      await connection.controller.saveSettings(
        connection.controller.companion!.copyWith(name: 'Changed'),
      );
      expect(connection.controller.settingsSaved, isFalse);
      expect(storage.value, saved);
      await connection.controller.send('Do not lose this thought.');
      expect(connection.controller.error!.code, 'settings_not_saved');
      storage.failWrites = false;
      await connection.dispose();
      final restored = await openDeviceWorkspace(storage: storage);
      expect(restored.controller.companion!.name, 'Lumi');
      expect(restored.controller.messages, isEmpty);
      await restored.dispose();
    },
  );

  test(
    'concurrent mutations are serialized and journal retries remain idempotent',
    () async {
      final storage = MemoryWorkspaceStorage();
      final api = DeviceWorkspaceApi(storage);
      await api.open();
      await api.call('save_companion', {
        'name': 'Lumi',
        'style': 'Playful',
        'interests': [],
        'response_length': .5,
        'memory_enabled': false,
        'retention_days': null,
      });
      final conversation =
          (await api.call('create_conversation'))['conversation'] as Map;
      await Future.wait([
        for (final title in ['One', 'Two'])
          api.call('save_memory', {
            'category': 'preferences',
            'title': title,
            'content': 'My own note.',
          }),
      ]);
      final input = {
        'conversation_id': conversation['id'],
        'request_id': 'stable-request',
        'content': 'An ordinary, good day.',
      };
      await api.turn(input).drain<void>();
      await api.turn(input).drain<void>();
      expect(((await api.call('list_memories'))['memories'] as List).length, 2);
      expect(
        ((await api.call('messages', {
                  'conversation_id': conversation['id'],
                }))['messages']
                as List)
            .length,
        1,
      );
      api.close();
    },
  );

  test('expiry and account deletion remove saved device data', () async {
    final storage = MemoryWorkspaceStorage();
    final connection = await openDeviceWorkspace(storage: storage);
    await create(connection);
    await connection.controller.saveMemory(
      category: 'preferences',
      title: 'Temporary',
      content: 'A passing note.',
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    await connection.controller.loadMemories();
    expect(connection.controller.memories, isEmpty);
    await connection.controller.send('Keep until I choose otherwise.');
    final exported =
        jsonDecode((await connection.controller.exportData())!) as Map;
    expect(
      (exported['messages'] as List).single['content'],
      'Keep until I choose otherwise.',
    );
    await connection.controller.requestAccountErasure('DELETE_MY_ACCOUNT');
    expect(storage.value, isNull);
    expect(connection.controller.erasureStatus, 'complete');
    expect(connection.controller.companion, isNull);
    await connection.dispose();
  });

  test('unreadable saved data is surfaced without being reset', () async {
    final storage = MemoryWorkspaceStorage()..value = 'not-valid-json';
    await expectLater(
      openDeviceWorkspace(storage: storage),
      throwsA(isA<FormatException>()),
    );
    expect(storage.value, 'not-valid-json');
  });
}
