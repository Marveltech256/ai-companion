import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/application/connection.dart';
import 'package:ai_companion/data/device_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real browser storage restores the saved device workspace', () async {
    final storage = SecureWorkspaceStorage(
      key:
          'morrow.browser-storage-check.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      var connection = await openDeviceWorkspace(storage: storage);
      expect(
        await connection.controller.create(
          name: 'Lumi',
          style: 'Reflective',
          interests: ['Books'],
          memoryEnabled: false,
        ),
        isTrue,
      );
      await connection.controller.send('A browser storage verification note.');
      await connection.controller.saveMemory(
        category: 'preferences',
        title: 'Verification',
        content: 'This is disposable test input.',
      );
      final id = connection.controller.companion!.id;
      await connection.dispose();
      connection = await openDeviceWorkspace(storage: storage);
      await connection.controller.loadMemories();
      expect(connection.controller.companion!.id, id);
      expect(
        connection.controller.messages.single.content,
        'A browser storage verification note.',
      );
      expect(connection.controller.messages.single.role, 'user');
      expect(connection.controller.memories.single.title, 'Verification');
      await connection.dispose();
    } finally {
      await storage.remove();
    }
  }, skip: !kIsWeb);
}
