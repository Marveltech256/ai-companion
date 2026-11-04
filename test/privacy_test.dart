import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/core/app_failure.dart';

import 'support/test_services.dart';

class PrivacyApi extends TestApi {
  bool failErasure = false;
  String deletionStatus = 'requested';
  Completer<Map<String, dynamic>>? exportPage;
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    if (action == 'request_account_erasure') {
      if (failErasure) {
        throw const AppFailure('unavailable', 'Please try again.');
      }
      return {'status': 'requested', 'blocked': true};
    }
    if (action == 'erasure_status') return {'status': deletionStatus};
    if (action == 'export_data') {
      final pending = exportPage;
      exportPage = null;
      if (pending != null) return pending.future;
      if (body['section'] == 'messages') {
        return body['after'] == null
            ? {
                'rows': [
                  {'content': 'First saved message'},
                ],
                'next_cursor': 'page-two',
              }
            : {
                'rows': [
                  {'content': 'Second saved message'},
                ],
                'next_cursor': null,
              };
      }
      return {'rows': [], 'next_cursor': null};
    }
    return super.call(action, body);
  }
}

void main() {
  test('export follows message pagination and discards results after an account change', () async {
    final session = TestSession(), api = PrivacyApi();
    final controller = CompanionController(session: session, api: api);
    await controller.restore();
    final data = jsonDecode((await controller.exportData())!) as Map;
    expect((data['messages'] as List).length, 2);
    final pending = Completer<Map<String, dynamic>>();
    api.exportPage = pending;
    final exporting = controller.exportData();
    session.switchUser('bob');
    pending.complete({
      'rows': [
        {'private': 'Old account'},
      ],
      'next_cursor': null,
    });
    expect(await exporting, isNull);
    controller.dispose();
    await session.events.close();
  });
  test('failed erasure preserves local data; accepted erasure hides it without claiming completion', () async {
    final session = TestSession(), api = PrivacyApi();
    final controller = CompanionController(session: session, api: api);
    await controller.restore();
    api.failErasure = true;
    await expectLater(
      controller.requestAccountErasure('DELETE_MY_ACCOUNT'),
      throwsA(isA<AppFailure>()),
    );
    expect(controller.companion, isNotNull);
    api.failErasure = false;
    await controller.requestAccountErasure('DELETE_MY_ACCOUNT');
    expect(controller.companion, isNull);
    expect(controller.erasureStatus, 'requested');
    expect(session.userId, 'alice');
    api.deletionStatus = 'complete';
    await controller.refreshErasureStatus();
    expect(session.userId, isNull);
    controller.dispose();
    await session.events.close();
  });
}
