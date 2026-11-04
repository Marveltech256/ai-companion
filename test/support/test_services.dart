import 'dart:async';

import 'package:ai_companion/auth/firebase_session.dart';
import 'package:ai_companion/core/app_failure.dart';
import 'package:ai_companion/data/companion_api.dart';

// Test-only doubles. Production never constructs an in-memory backend.
class TestSession implements SessionGateway {
  String? uid = 'alice';
  final events = StreamController<String?>.broadcast(sync: true);
  @override
  String? get userId => uid;
  @override
  Stream<String?> get changes => events.stream;
  @override
  Future<void> start() async {
    uid ??= 'alice';
    events.add(uid);
  }

  @override
  Future<String> token({bool refresh = false}) async => 'test-token';
  @override
  Future<void> signOut() async {
    uid = null;
    events.add(null);
  }

  void switchUser(String? value) {
    uid = value;
    events.add(value);
  }
}

class TestApi implements CompanionApi {
  Map<String, dynamic>? companion = {
    'id': '1b29689a-8c86-4280-9170-f101de06f9ef',
    'name': 'Nova',
    'communication_style': 'Playful',
    'interests': ['Little adventures'],
    'response_length': .5,
    'memory_enabled': true,
    'retention_days': null,
  };
  final conversationId = '50642940-37b8-452d-85c3-adc9d4b78905';
  final List<Map<String, dynamic>> records = [];
  final List<String> turnIds = [];
  final List<String> greetingIds = [];
  Map<String, dynamic> personalProfile = {};
  final List<Map<String, dynamic>> saved = [];
  final List<Map<String, dynamic>> memoryRecords = [];
  bool failSettings = false;
  bool failFirstTurn = false;
  Completer<Map<String, dynamic>>? bootstrap;
  String profileName = 'Taylor';
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    switch (action) {
      case 'bootstrap':
        final pending = bootstrap;
        bootstrap = null;
        return pending == null
            ? {
                'profile': {'display_name': profileName, ...personalProfile},
                'companion': companion,
              }
            : pending.future;
      case 'save_companion':
        if (failSettings) {
          throw const AppFailure('offline', 'Not saved.', retryable: true);
        }
        companion = {
          ...companion ?? {},
          ...body,
          'id': companion?['id'] ?? '1b29689a-8c86-4280-9170-f101de06f9ef',
          'communication_style': body['style'],
        };
        saved.add(Map.of(body));
        return {'companion': companion};
      case 'save_personal_profile':
        personalProfile = Map.of(body);
        return {'profile': personalProfile};
      case 'save_friend_preferences':
        if (failSettings) {
          throw const AppFailure('offline', 'Not saved.', retryable: true);
        }
        companion = {...companion!, ...body};
        saved.add(Map.of(body));
        return {'companion': companion};
      case 'set_voice':
        companion = {...companion!, 'voice_enabled': body['enabled']};
        return {'companion': companion};
      case 'set_reply_mode':
        personalProfile = {...personalProfile, 'reply_mode': body['mode']};
        return {'profile': personalProfile};
      case 'list_conversations':
        return {
          'conversations': records.isEmpty
              ? []
              : [
                  {'id': conversationId, 'title': 'Cycling'},
                ],
        };
      case 'create_conversation':
        return {
          'conversation': {'id': conversationId, 'title': 'Cycling'},
        };
      case 'messages':
        return {'messages': List<Map<String, dynamic>>.from(records)};
      case 'list_memories':
        return {'memories': memoryRecords, 'total': memoryRecords.length};
      case 'notification_preferences':
        return {'preferences': null};
      case 'home_summary':
        return {'clock': {}, 'reminders': [], 'events': []};
      case 'forget_all_memories':
      case 'forget_memory':
        return {'ok': true};
      default:
        throw StateError('Unexpected test action $action');
    }
  }

  @override
  Stream<Map<String, dynamic>> turn(Map<String, dynamic> body) async* {
    final request = body['request_id'] as String;
    if (body['initiate'] == true) {
      greetingIds.add(request);
      const text = 'Hi, I am Nova. What should I call you? You can skip that.';
      yield {'type': 'delta', 'text': text};
      records.removeWhere((m) => m['id'] == 'greeting');
      records.add({
        'id': 'greeting',
        'kind': 'greeting',
        'request_id': request,
        'seq': 1,
        'role': 'assistant',
        'content': text,
        'status': 'completed',
      });
      yield {'type': 'done'};
      return;
    }
    turnIds.add(request);
    yield {'type': 'delta', 'text': 'What do you enjoy '};
    if (failFirstTurn && turnIds.length == 1) {
      throw const AppFailure('interrupted', 'Please retry.', retryable: true);
    }
    yield {'type': 'delta', 'text': 'about cycling?'};
    records
      ..clear()
      ..addAll([
        {
          'id': 'user',
          'request_id': request,
          'seq': 1,
          'role': 'user',
          'content': body['content'],
          'status': 'completed',
        },
        {
          'id': 'assistant',
          'request_id': request,
          'seq': 2,
          'role': 'assistant',
          'content': 'What do you enjoy about cycling?',
          'status': 'completed',
        },
      ]);
    yield {'type': 'done'};
  }

  @override
  void close() {}
}
