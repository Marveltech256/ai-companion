import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/application/report_dialog.dart';
import 'package:ai_companion/billing/billing_controller.dart';
import 'package:ai_companion/billing/store_gateway.dart';
import 'package:ai_companion/core/app_failure.dart';
import 'package:ai_companion/data/models.dart';
import 'package:ai_companion/application/theme.dart';

import 'support/account_services.dart';
import 'application_test.dart' as review show loadFonts, viewport, capture;

class BillingApi extends AccountTestApi {
  BillingApi(super.session);
  bool enabled = false, failVerification = false;
  Completer<Map<String, dynamic>>? verification;
  Completer<Map<String, dynamic>>? refresh;
  final actions = <String>[];
  final reports = <Map<String, dynamic>>[];
  final free = <String, dynamic>{
    'mode': 'free_testing',
    'available': true,
    'premium': false,
    'product_id': 'monthly',
    'base_plan_id': 'monthly-base',
    'account_ref': 'server-account-ref',
  };
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    actions.add(action);
    if (action == 'bootstrap') {
      return {
        ...await super.call(action, body),
        'capabilities': {'billing': enabled},
      };
    }
    if (action == 'billing_refresh' && refresh != null) return refresh!.future;
    if (action == 'billing_status' ||
        action == 'billing_prepare' ||
        action == 'billing_refresh') {
      return free;
    }
    if (action == 'billing_verify') {
      if (failVerification) {
        throw const AppFailure('invalid_purchase', 'Purchase not verified.');
      }
      return verification == null
          ? {'mode': 'premium', 'premium': true}
          : verification!.future;
    }
    if (action == 'report_message') {
      reports.add(body);
      return {
        'report': {'id': 'receipt', 'status': 'new'},
      };
    }
    return super.call(action, body);
  }
}

class TestStore implements StoreGateway {
  int listeners = 0, finishes = 0, checkouts = 0;
  String? accountRef;
  late final events = StreamController<List<StorePurchase>>.broadcast(
    onListen: () => listeners++,
  );
  @override
  bool get supported => true;
  @override
  Stream<List<StorePurchase>> get purchases => events.stream;
  @override
  Future<StorePlan> plan(String product, String base) async => StorePlan(
    id: product,
    basePlan: base,
    title: 'Store monthly plan',
    price: '€4.25',
  );
  @override
  Future<void> buy(StorePlan plan, String account) async {
    checkouts++;
    accountRef = account;
  }

  @override
  Future<void> restore(String account) async {
    accountRef = account;
  }

  @override
  Future<void> finish(StorePurchase purchase) async {
    finishes++;
  }
}

void main() {
  setUpAll(review.loadFonts);
  test(
    'disabled billing creates no store connection, purchase or billing request',
    () async {
      final session = AccountTestSession()..isAnonymous = false,
          api = BillingApi(session);
      final c = CompanionController(session: session, api: api);
      await c.restore();
      final store = TestStore(),
          billing = BillingController(companion: c, store: store);
      await billing.load();
      await billing.buy();
      expect(store.listeners, 0);
      expect(store.checkouts, 0);
      expect(api.actions.where((a) => a.startsWith('billing_')), isEmpty);
      billing.dispose();
      c.dispose();
      await session.events.close();
      await store.events.close();
    },
  );
  test('store pending/purchased events grant no access before the verified server response', () async {
    final session = AccountTestSession()..isAnonymous = false,
        api = BillingApi(session)..enabled = true;
    final c = CompanionController(session: session, api: api);
    await c.restore();
    final store = TestStore(),
        billing = BillingController(companion: c, store: store);
    await billing.load();
    expect(billing.plan!.price, '€4.25');
    await billing.buy();
    expect(store.accountRef, 'server-account-ref');
    api.verification = Completer<Map<String, dynamic>>();
    store.events.add([
      const StorePurchase('monthly', 'synthetic-token', 'pending'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(billing.status!['premium'], false);
    expect(billing.pending, true);
    store.events.add([
      const StorePurchase(
        'monthly',
        'synthetic-token',
        'purchased',
        needsFinish: true,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(store.finishes, 0);
    expect(billing.status!['premium'], false);
    api.verification!.complete({'premium': true, 'mode': 'premium'});
    await Future<void>.delayed(Duration.zero);
    expect(billing.status!['premium'], true);
    expect(store.finishes, 1);
    billing.dispose();
    c.dispose();
    await session.events.close();
    await store.events.close();
  });
  test('failed verification and late responses after account switching cannot grant or finish a purchase', () async {
    final session = AccountTestSession()..isAnonymous = false,
        api = BillingApi(session)..enabled = true;
    final c = CompanionController(session: session, api: api);
    await c.restore();
    final store = TestStore(),
        billing = BillingController(companion: c, store: store);
    await billing.load();
    api.failVerification = true;
    store.events.add([
      const StorePurchase(
        'monthly',
        'bad-token',
        'purchased',
        needsFinish: true,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(billing.error!.code, 'invalid_purchase');
    expect(store.finishes, 0);
    api.failVerification = false;
    api.verification = Completer<Map<String, dynamic>>();
    store.events.add([
      const StorePurchase(
        'monthly',
        'another-token',
        'purchased',
        needsFinish: true,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    session.switchUser(null);
    api.verification!.complete({'premium': true});
    await Future<void>.delayed(Duration.zero);
    expect(billing.status, isNull);
    expect(store.finishes, 0);
    billing.dispose();
    c.dispose();
    await session.events.close();
    await store.events.close();
  });
  test(
    'a slow restore response cannot overwrite a newly verified purchase',
    () async {
      final session = AccountTestSession()..isAnonymous = false;
      final api = BillingApi(session)..enabled = true;
      final c = CompanionController(session: session, api: api);
      await c.restore();
      final store = TestStore(),
          billing = BillingController(companion: c, store: store);
      await billing.load();
      api.refresh = Completer<Map<String, dynamic>>();
      final restoring = billing.restore();
      await Future<void>.delayed(Duration.zero);
      store.events.add([
        const StorePurchase(
          'monthly',
          'new-purchase',
          'purchased',
          needsFinish: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(billing.status!['premium'], true);
      api.refresh!.complete(api.free);
      await restoring;
      expect(billing.status!['premium'], true);
      expect(store.finishes, 1);
      billing.dispose();
      c.dispose();
      await session.events.close();
      await store.events.close();
    },
  );
  testWidgets(
    'reply reporting uses the current dialog style and cancel sends nothing',
    (tester) async {
      review.viewport(tester, const Size(390, 844));
      final session = AccountTestSession()..isAnonymous = false,
          api = BillingApi(session);
      final c = CompanionController(session: session, api: api);
      await c.restore();
      const message = ChatMessage(
        id: 'owned-message',
        role: 'assistant',
        content: 'A synthetic answer.',
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('application-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: morrowTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => reportReply(context, c, message),
                  child: const Text('Report'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await review.capture(tester, 'report-reply');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.reports, isEmpty);
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'A fictional review note.',
      );
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(api.reports.single['message_id'], message.id);
      expect(api.reports.single['details'], 'A fictional review note.');
      expect(api.reports.single.containsKey('message_snapshot'), false);
      expect(api.reports.single.containsKey('owner_id'), false);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await session.events.close();
    },
  );
}
