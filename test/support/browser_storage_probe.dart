// Development-only entry point for a real Chrome storage check. No cloud calls.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;
import 'package:ai_companion/application/connection.dart';
import 'package:ai_companion/data/device_workspace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = SecureWorkspaceStorage(
    key: 'morrow.browser-probe.${DateTime.now().microsecondsSinceEpoch}',
  );
  AppConnection? connection;
  String? failure;
  try {
    connection = await openDeviceWorkspace(storage: storage);
    if (!await connection.controller.create(
      name: 'Lumi',
      style: 'Reflective',
      interests: ['Books'],
      memoryEnabled: false,
    )) {
      throw StateError('Device companion creation failed.');
    }
    await connection.controller.send('A fictional browser persistence note.');
    await connection.controller.saveMemory(
      category: 'preferences',
      title: 'Disposable preference',
      content: 'Synthetic test input only.',
    );
    final id = connection.controller.companion!.id;
    await connection.dispose();
    connection = await openDeviceWorkspace(storage: storage);
    await connection.controller.loadMemories();
    if (connection.controller.companion?.id != id ||
        connection.controller.messages.single.content !=
            'A fictional browser persistence note.' ||
        connection.controller.messages.single.role != 'user' ||
        connection.controller.memories.single.title !=
            'Disposable preference') {
      throw StateError('Saved workspace did not restore correctly.');
    }
  } catch (_) {
    failure = 'Browser storage round trip failed.';
  } finally {
    await connection?.dispose();
    try {
      await storage.remove();
      if (await storage.read() != null) {
        failure = 'Disposable storage was not removed.';
      }
    } catch (_) {
      failure = 'Disposable storage cleanup failed.';
    }
  }
  final result = {
    'passed': failure == null,
    'check': 'real browser workspace persistence and cleanup',
    'error': ?failure,
  };
  web.document.body!.setAttribute('data-probe-result', jsonEncode(result));
}
