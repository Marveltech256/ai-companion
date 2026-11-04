import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/app_failure.dart';

abstract interface class PushGateway {
  Stream<String> get tokens;
  Stream<void> get opens;
  Future<bool> initialOpen();
  Future<String> installationId();
  Future<String> requestToken();
  Future<void> revoke();
}

class PushRoute {
  const PushRoute(this.checkinId);
  final String checkinId;
}

abstract interface class RoutedPushGateway {
  Stream<PushRoute> get routedOpens;
  Stream<PushRoute> get receipts;
  Future<PushRoute?> initialRoute();
}

class FirebasePushGateway implements PushGateway, RoutedPushGateway {
  PushRoute? _route(RemoteMessage message) {
    final id = message.data['checkin_id'];
    return message.data['screen'] == 'conversation' &&
            id is String &&
            RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id)
        ? PushRoute(id)
        : null;
  }

  @override
  Stream<PushRoute> get routedOpens => FirebaseMessaging.onMessageOpenedApp
      .map(_route)
      .where((r) => r != null)
      .cast<PushRoute>();
  @override
  Stream<PushRoute> get receipts => FirebaseMessaging.onMessage
      .map(_route)
      .where((r) => r != null)
      .cast<PushRoute>();
  @override
  Future<PushRoute?> initialRoute() async {
    final m = await _messaging.getInitialMessage();
    return m == null ? null : _route(m);
  }

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  Future<String>? _installation;
  @override
  Stream<String> get tokens => _messaging.onRegistered;
  @override
  Stream<void> get opens => FirebaseMessaging.onMessageOpenedApp
      .where((message) => message.data['screen'] == 'conversation')
      .map((_) {});
  @override
  Future<bool> initialOpen() async =>
      (await _messaging.getInitialMessage())?.data['screen'] == 'conversation';
  @override
  Future<String> installationId() => _installation ??= () async {
    final preferences = SharedPreferencesAsync();
    final existing = await preferences.getString('morrow_installation_id');
    if (existing != null) return existing;
    final id = const Uuid().v4();
    await preferences.setString('morrow_installation_id', id);
    return id;
  }();
  @override
  Future<String> requestToken() async {
    if (kIsWeb) {
      throw const AppFailure(
        'push_unavailable',
        'Browser notifications are not connected yet.',
      );
    }
    final permission = await _messaging.requestPermission();
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw const AppFailure(
        'permission_denied',
        'Notifications are not allowed on this device.',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await _messaging.getAPNSToken() == null) {
      throw const AppFailure(
        'push_unavailable',
        'Notifications are not connected on this device yet.',
      );
    }
    await _messaging.setAutoInitEnabled(true);
    final registration = _messaging.onRegistered.first.timeout(
      const Duration(seconds: 20),
    );
    await _messaging.register();
    return registration;
  }

  @override
  Future<void> revoke() async {
    await _messaging.setAutoInitEnabled(false);
    await _messaging.unregister();
  }
}
