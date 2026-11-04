import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/data/models.dart';
import 'package:ai_companion/notifications/push_gateway.dart';

import 'support/test_services.dart';

class TestPush implements PushGateway {
  int permissionRequests = 0, revocations = 0;
  final registrations = StreamController<String>.broadcast();
  final opened = StreamController<void>.broadcast();
  @override
  Stream<String> get tokens => registrations.stream;
  @override
  Stream<void> get opens => opened.stream;
  @override
  Future<bool> initialOpen() async => false;
  @override
  Future<String> installationId() async => 'device-id';
  @override
  Future<String> requestToken() async {
    permissionRequests++;
    return 'device-fid';
  }

  @override
  Future<void> revoke() async {
    revocations++;
  }
}

class RoutedTestPush extends TestPush implements RoutedPushGateway {
  final routes = StreamController<PushRoute>.broadcast();
  final received = StreamController<PushRoute>.broadcast();
  @override
  Stream<PushRoute> get routedOpens => routes.stream;
  @override
  Stream<PushRoute> get receipts => received.stream;
  @override
  Future<PushRoute?> initialRoute() async => null;
}

class RouteApi extends TestApi {
  final receiptCalls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    if (action == 'checkin_receipt') {
      receiptCalls.add(Map.of(body));
      return {
        'conversation': body['id'] == 'owned-checkin'
            ? {'id': conversationId, 'title': 'An owned check-in'}
            : null,
      };
    }
    return super.call(action, body);
  }
}

void main() {
  test('push opens use the server-owned conversation and separate receipt from open', () async {
    final session = TestSession(), api = RouteApi(), push = RoutedTestPush();
    final controller = CompanionController(
      session: session,
      api: api,
      push: push,
    );
    await controller.restore();
    push.routes.add(const PushRoute('foreign-checkin'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.takeNotificationOpen(), false);
    expect(controller.activeConversation, isNull);
    push.received.add(const PushRoute('owned-checkin'));
    await Future<void>.delayed(Duration.zero);
    expect(api.receiptCalls.last['opened'], false);
    expect(controller.takeNotificationOpen(), false);
    push.routes.add(const PushRoute('owned-checkin'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.activeConversation!.title, 'An owned check-in');
    expect(controller.takeNotificationOpen(), true);
    expect(api.receiptCalls.last['opened'], true);
    controller.dispose();
    await session.events.close();
    await push.routes.close();
    await push.received.close();
    await push.registrations.close();
    await push.opened.close();
  });
  test('notification controls cannot request permission without complete scheduling preferences', () async {
    final session = TestSession(), api = TestApi(), push = TestPush();
    final controller = CompanionController(
      session: session,
      api: api,
      push: push,
    );
    await controller.restore();
    await controller.saveNotificationPreferences(
      const NotificationPreferences(checkins: true),
    );
    expect(push.permissionRequests, 0);
    expect(controller.notificationPreferences.enabled, false);
    expect(controller.error?.code, 'schedule_required');
    push.opened.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(controller.takeNotificationOpen(), true);
    expect(controller.takeNotificationOpen(), false);
    controller.dispose();
    await session.events.close();
    await push.registrations.close();
    await push.opened.close();
  });
}
