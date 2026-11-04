import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../auth/firebase_session.dart';
import '../core/app_failure.dart';
import 'companion_api.dart';

abstract interface class WorkspaceStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> remove();
}

class SecureWorkspaceStorage implements WorkspaceStorage {
  SecureWorkspaceStorage({this.key = 'morrow.device-workspace.v1'});
  final String key;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: key);
  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);
  @override
  Future<void> remove() => _storage.delete(key: key);
}

/// A separate, explicitly labelled device workspace. It stores real user input
/// and never generates a substitute AI response or signs in as a Firebase user.
class DeviceSession implements SessionGateway {
  final _events = StreamController<String?>.broadcast(sync: true);
  String? _uid = 'device-workspace';
  @override
  String? get userId => _uid;
  @override
  Stream<String?> get changes => _events.stream;
  @override
  Future<void> start() async {
    _uid = 'device-workspace';
    _events.add(_uid);
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _events.add(null);
  }

  @override
  Future<String> token({bool refresh = false}) async => 'device-only';
  Future<void> dispose() => _events.close();
}

class DeviceWorkspaceApi implements CompanionApi {
  DeviceWorkspaceApi(this.storage);
  final WorkspaceStorage storage;
  final _uuid = const Uuid();
  Map<String, dynamic> _data = {};
  Future<void> _queue = Future.value();
  bool _closed = false;
  Future<void> open() async {
    final saved = await storage.read();
    if (saved != null) {
      // Corrupt or inaccessible storage is surfaced; never overwrite it with an
      // empty workspace after a read failure.
      final decoded = jsonDecode(saved);
      if (decoded is! Map || decoded['version'] != 1) {
        throw const AppFailure(
          'workspace_unavailable',
          'Your device workspace could not be opened.',
        );
      }
      _data = Map<String, dynamic>.from(decoded);
    } else {
      _data = {
        'version': 1,
        'companion': null,
        'conversations': [],
        'messages': [],
        'memories': [],
        'notifications': null,
      };
    }
  }

  List<Map<String, dynamic>> _rows(String key) => (_data[key] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  Future<void> flush() => _queue;

  void _expire(Map<String, dynamic> state) {
    final now = DateTime.now().toUtc();
    state['memories'] = (state['memories'] as List)
        .where(
          (e) =>
              e['expires_at'] == null ||
              DateTime.parse(e['expires_at']).isAfter(now),
        )
        .toList();
    final days =
        (state['companion'] as Map?)?['conversation_retention_days'] as int?;
    if (days != null) {
      final cutoff = now.subtract(Duration(days: days));
      state['conversations'] = (state['conversations'] as List)
          .where((e) => DateTime.parse(e['updated_at']).isAfter(cutoff))
          .toList();
      final retained = (state['conversations'] as List)
          .map((e) => e['id'])
          .toSet();
      state['messages'] = (state['messages'] as List)
          .where((e) => retained.contains(e['conversation_id']))
          .toList();
    }
  }

  Future<Map<String, dynamic>> _transaction(
    Map<String, dynamic> Function(Map<String, dynamic>) work,
  ) {
    final result = Completer<Map<String, dynamic>>();
    _queue = _queue
        .then((_) async {
          if (_closed) {
            throw const AppFailure(
              'workspace_closed',
              'Please open your workspace again.',
            );
          }
          final next = jsonDecode(jsonEncode(_data)) as Map<String, dynamic>;
          _expire(next);
          final response = work(next);
          final encoded = jsonEncode(next);
          if (utf8.encode(encoded).length > 1024 * 1024) {
            throw const AppFailure(
              'workspace_full',
              'This device workspace is full. Export your story and remove older moments before saving more.',
            );
          }
          await storage.write(encoded);
          _data = next;
          result.complete(response);
        })
        .catchError((Object error, StackTrace stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        });
    return result.future;
  }

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    await _queue;
    switch (action) {
      case 'bootstrap':
        return _transaction(
          (state) => {
            'profile': state['profile'] ?? {},
            'companion': state['companion'],
          },
        );
      case 'save_personal_profile':
        return _transaction((state) {
          state['profile'] = Map<String, dynamic>.from(body);
          return {'profile': state['profile']};
        });
      case 'save_companion':
        return _transaction((state) {
          final old = (state['companion'] as Map?) ?? {};
          final name = (body['name'] as String).trim();
          if (name.isEmpty || name.length > 24) {
            throw const AppFailure(
              'invalid_name',
              'Choose a name of 1–24 characters.',
            );
          }
          state['companion'] = {
            ...old,
            ...body,
            'id': old['id'] ?? _uuid.v4(),
            'name': name,
            'communication_style': body['style'],
            'learning_enabled': old['learning_enabled'] ?? false,
            'voice_enabled': old['voice_enabled'] ?? false,
          };
          return {'companion': state['companion']};
        });
      case 'save_friend_preferences':
        return _transaction((state) {
          final old = state['companion'] as Map?;
          if (old == null || old['id'] != body['companion_id']) {
            throw const AppFailure(
              'not_found',
              'That companion is not available.',
            );
          }
          final name = (body['name'] as String).trim();
          if (name.isEmpty ||
              name.length > 24 ||
              (body['personality_keys'] as List).length > 2 ||
              (body['support_preferences'] as List).length > 4) {
            throw const AppFailure(
              'invalid_input',
              'Please check your companion preferences.',
            );
          }
          state['companion'] = {...old, ...body, 'name': name};
          return {'companion': state['companion']};
        });
      case 'list_conversations':
        return {'conversations': _rows('conversations').reversed.toList()};
      case 'create_conversation':
        return _transaction((state) {
          final rows = List<dynamic>.from(state['conversations']);
          final id = body['conversation_id'] as String? ?? _uuid.v4();
          final existing = rows.where((e) => e['id'] == id).firstOrNull;
          final row =
              existing ??
              {
                'id': id,
                'title': 'A little moment',
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              };
          if (existing == null) rows.add(row);
          state['conversations'] = rows;
          return {'conversation': row};
        });
      case 'messages':
        final before = body['before'] as int?;
        final rows = _rows('messages')
            .where(
              (e) =>
                  e['conversation_id'] == body['conversation_id'] &&
                  (before == null || (e['seq'] as int) < before),
            )
            .toList();
        return {
          'messages': rows
              .skip(rows.length > 50 ? rows.length - 50 : 0)
              .toList(),
        };
      case 'rename_conversation':
      case 'delete_conversation':
        return _transaction((state) {
          final rows = List<dynamic>.from(state['conversations']);
          if (action == 'delete_conversation') {
            rows.removeWhere((e) => e['id'] == body['conversation_id']);
            (state['messages'] as List).removeWhere(
              (e) => e['conversation_id'] == body['conversation_id'],
            );
          } else {
            for (final row in rows) {
              if (row['id'] == body['conversation_id']) {
                row['title'] = body['title'];
              }
            }
          }
          state['conversations'] = rows;
          return {'ok': true};
        });
      case 'list_memories':
        return _transaction(
          (state) => {'memories': state['memories'], 'pending_count': 0},
        );
      case 'save_memory':
        return _transaction((state) {
          final rows = List<dynamic>.from(state['memories']);
          final id = body['id'] as String? ?? _uuid.v4();
          rows.removeWhere((e) => e['id'] == id);
          if (rows.length >= 100) {
            throw const AppFailure(
              'memory_limit',
              'This workspace can hold up to 100 memories. Export or remove some first.',
            );
          }
          final title = (body['title'] as String).trim(),
              content = (body['content'] as String).trim();
          if (title.isEmpty ||
              title.length > 100 ||
              content.isEmpty ||
              content.length > 2000) {
            throw const AppFailure(
              'invalid_memory',
              'Add a title and a memory of up to 2,000 characters.',
            );
          }
          final retention =
              (state['companion'] as Map?)?['retention_days'] as int?;
          final expiry =
              body['expires_at'] as String? ??
              (retention == null
                  ? null
                  : DateTime.now()
                        .toUtc()
                        .add(Duration(days: retention))
                        .toIso8601String());
          rows.insert(0, {
            'id': id,
            'category': body['category'],
            'memory_key': id,
            'title': title,
            'content': content,
            'attributes': body['attributes'] ?? {},
            'verification': 'user_confirmed',
            'expires_at': expiry,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
          state['memories'] = rows;
          return {'ok': true};
        });
      case 'forget_memory':
      case 'forget_all_memories':
        return _transaction((state) {
          if (action == 'forget_all_memories') {
            state['memories'] = [];
          } else {
            (state['memories'] as List).removeWhere(
              (e) => e['id'] == body['id'],
            );
          }
          return {'ok': true};
        });
      case 'set_learning':
      case 'set_voice':
      case 'set_conversation_retention':
        if (action == 'set_voice' && body['enabled'] == true) {
          throw const AppFailure(
            'cloud_required',
            'Connect your cloud account to use AI voice.',
          );
        }
        return _transaction((state) {
          final field = switch (action) {
            'set_learning' => 'learning_enabled',
            'set_voice' => 'voice_enabled',
            _ => 'conversation_retention_days',
          };
          (state['companion']
              as Map)[field] = action == 'set_conversation_retention'
              ? body['days']
              : body['enabled'];
          _expire(state);
          return {'companion': state['companion']};
        });
      case 'notification_preferences':
        return {'preferences': _data['notifications']};
      case 'save_notification_preferences':
        return _transaction((state) {
          state['notifications'] = body;
          return {'preferences': body};
        });
      case 'export_data':
        return _transaction((state) {
          final section = body['section'] as String;
          final value = switch (section) {
            'profile' => <dynamic>[
              if (state['profile'] != null) state['profile'],
            ],
            'companion' =>
              state['companion'] == null ? [] : [state['companion']],
            'notifications' =>
              state['notifications'] == null ? [] : [state['notifications']],
            'conversations' || 'messages' || 'memories' => state[section],
            _ => <dynamic>[],
          };
          return {'rows': value, 'next_cursor': null};
        });
      case 'request_account_erasure':
        if (body['confirmation'] != 'DELETE_MY_ACCOUNT') {
          throw const AppFailure(
            'confirmation_required',
            'Confirm workspace removal.',
          );
        }
        await _queue;
        await storage.remove();
        _data = {
          'version': 1,
          'companion': null,
          'conversations': [],
          'messages': [],
          'memories': [],
          'notifications': null,
        };
        return {'status': 'complete'};
      case 'erasure_status':
        return {'status': 'complete'};
      default:
        throw const AppFailure(
          'cloud_required',
          'This feature needs a connected cloud account.',
        );
    }
  }

  /// Device-only mode is a journal: save the user's thought, with no fabricated
  /// assistant entry. Cloud conversations use the real streaming API instead.
  @override
  Stream<Map<String, dynamic>> turn(Map<String, dynamic> body) async* {
    await _transaction((state) {
      final rows = List<dynamic>.from(state['messages']);
      if (!rows.any((e) => e['request_id'] == body['request_id'])) {
        if (rows.length >= 2000) {
          throw const AppFailure(
            'journal_limit',
            'Export or remove older moments before saving more.',
          );
        }
        rows.add({
          'id': _uuid.v4(),
          'request_id': body['request_id'],
          'conversation_id': body['conversation_id'],
          'seq':
              rows.fold<int>(
                0,
                (value, row) =>
                    (row['seq'] as int) > value ? row['seq'] as int : value,
              ) +
              1,
          'role': 'user',
          'content': body['content'],
          'status': 'completed',
        });
      }
      state['messages'] = rows;
      for (final row in state['conversations'] as List) {
        if (row['id'] == body['conversation_id']) {
          if (row['title'] == 'A little moment') {
            row['title'] = (body['content'] as String)
                .split('\n')
                .first
                .substring(
                  0,
                  (body['content'] as String)
                      .split('\n')
                      .first
                      .length
                      .clamp(0, 60),
                );
          }
          row['updated_at'] = DateTime.now().toUtc().toIso8601String();
        }
      }
      return {'ok': true};
    });
    yield {'type': 'done'};
  }

  @override
  void close() {
    _closed = true;
  }
}
