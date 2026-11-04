import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/core/app_config.dart';
import 'package:ai_companion/core/app_failure.dart';
import 'package:ai_companion/data/companion_api.dart';

void main() {
  AppConfig config({
    String url = 'https://example.supabase.co',
    String key = 'sb_publishable_test',
  }) => AppConfig(
    supabaseUrl: url,
    supabaseKey: key,
    firebaseProjectId: 'test-project',
    firebaseApiKey: 'public-config',
    firebaseSenderId: '123',
    firebaseAppId: 'app',
  );
  test(
    'rejects private keys, incomplete config, and insecure destinations',
    () {
      expect(
        () => config(key: 'sb_secret_private').validate(),
        throwsA(isA<AppFailure>()),
      );
      expect(() => config(key: '').validate(), throwsA(isA<AppFailure>()));
      expect(
        () => config(url: 'http://example.com').validate(),
        throwsA(isA<AppFailure>()),
      );
      expect(() => config().validate(), returnsNormally);
    },
  );
  test('SSE survives arbitrary UTF-8 fragmentation and CRLF', () async {
    final wire = utf8.encode(
      'event: delta\r\ndata: {"type":"delta","text":"café"}\r\n\r\n'
      ': keepalive\n\ndata: {"type":"done"}\n\n',
    );
    final events = await decodeServerEvents(
      Stream.fromIterable(wire.map((b) => [b])),
    ).toList();
    expect(events, [
      {'type': 'delta', 'text': 'café'},
      {'type': 'done'},
    ]);
  });
}
