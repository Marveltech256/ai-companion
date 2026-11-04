import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/companion_controller.dart';
import '../core/app_failure.dart';
import 'store_gateway.dart';

class BillingController extends ChangeNotifier {
  BillingController({required this.companion, required this.store}) {
    _owner = companion.userId;
    companion.addListener(_identityChanged);
    _identityChanged();
  }
  final CompanionController companion;
  final StoreGateway store;
  Map<String, dynamic>? status;
  StorePlan? plan;
  AppFailure? error;
  bool busy = false, pending = false, _disposed = false;
  String? _owner;
  int _epoch = 0;
  int _statusRevision = 0;
  StreamSubscription<List<StorePurchase>>? _subscription;
  final _verifying = <String>{};
  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _identityChanged() {
    if (!companion.billingAvailable || !companion.registeredAccount) {
      unawaited(_subscription?.cancel());
      _subscription = null;
    }
    if (companion.userId != _owner) {
      _owner = companion.userId;
      _epoch++;
      status = null;
      plan = null;
      error = null;
      pending = false;
      busy = false;
      _verifying.clear();
      unawaited(_subscription?.cancel());
      _subscription = null;
      _notify();
    }
    // No store connection or billing query while the feature remains off.
    if (companion.billingAvailable &&
        companion.registeredAccount &&
        store.supported &&
        _subscription == null) {
      _subscription = store.purchases.listen(
        (items) {
          for (final item in items) {
            unawaited(_purchase(item));
          }
        },
        onError: (Object _) {
          error = const AppFailure(
            'store_unavailable',
            'Purchases could not be checked.',
          );
          pending = false;
          _notify();
        },
      );
    }
  }

  Future<void> load({bool refresh = false}) async {
    if (!companion.billingAvailable ||
        !companion.registeredAccount ||
        busy ||
        pending) {
      return;
    }
    final epoch = _epoch;
    final revision = ++_statusRevision;
    busy = true;
    error = null;
    _notify();
    try {
      final result = await companion.billingAction(
        refresh ? 'billing_refresh' : 'billing_status',
      );
      if (!_current(epoch) || revision != _statusRevision) return;
      status = result;
      plan = null;
      if (result['available'] == true && store.supported) {
        final value = await store.plan(
          result['product_id'] as String,
          result['base_plan_id'] as String,
        );
        if (!_current(epoch) || revision != _statusRevision) return;
        plan = value;
      }
    } catch (e) {
      if (_current(epoch)) {
        error = e is AppFailure
            ? e
            : const AppFailure(
                'billing_unavailable',
                'Membership could not be loaded.',
              );
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> buy() async {
    if (busy || pending || plan == null || !store.supported) return;
    final epoch = _epoch, selected = plan!;
    busy = true;
    error = null;
    _notify();
    try {
      final prepared = await companion.billingAction('billing_prepare');
      if (!_current(epoch)) return;
      if (prepared['available'] != true ||
          prepared['product_id'] != selected.id ||
          prepared['base_plan_id'] != selected.basePlan) {
        throw const AppFailure(
          'plan_unavailable',
          'Please reload the available plan.',
        );
      }
      pending = true;
      _notify();
      await store.buy(selected, prepared['account_ref'] as String);
    } catch (e) {
      if (_current(epoch)) {
        pending = false;
        error = e is AppFailure
            ? e
            : const AppFailure(
                'billing_unavailable',
                'The purchase could not be started.',
              );
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> restore() async {
    if (busy || pending || !store.supported) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    _notify();
    try {
      final prepared = await companion.billingAction('billing_prepare');
      if (!_current(epoch)) return;
      if (prepared['available'] != true) {
        throw const AppFailure(
          'billing_unavailable',
          'Purchases are not enabled yet.',
        );
      }
      await store.restore(prepared['account_ref'] as String);
      if (!_current(epoch)) return;
      final revision = _statusRevision;
      final result = await companion.billingAction('billing_refresh');
      if (_current(epoch) && revision == _statusRevision) status = result;
    } catch (e) {
      if (_current(epoch)) {
        error = e is AppFailure
            ? e
            : const AppFailure(
                'billing_unavailable',
                'Purchases could not be restored.',
              );
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> _purchase(StorePurchase purchase) async {
    if (!companion.registeredAccount ||
        !companion.billingAvailable ||
        !store.supported) {
      return;
    }
    final epoch = _epoch;
    if (purchase.status == 'pending') {
      pending = true;
      _notify();
      return;
    }
    if (purchase.status != 'purchased') {
      pending = false;
      if (purchase.status == 'error') {
        error = const AppFailure(
          'purchase_failed',
          'The purchase was not completed. Please check Google Play.',
        );
      }
      _notify();
      return;
    }
    if (_verifying.contains(purchase.token)) return;
    _verifying.add(purchase.token);
    final revision = ++_statusRevision;
    pending = true;
    error = null;
    _notify();
    try {
      final verified = await companion.billingAction('billing_verify', {
        'purchase_token': purchase.token,
      });
      if (!_current(epoch) || revision != _statusRevision) return;
      status = verified;
      if (purchase.needsFinish) await store.finish(purchase);
    } catch (e) {
      if (_current(epoch)) {
        error = e is AppFailure
            ? e
            : const AppFailure(
                'billing_unavailable',
                'Purchase verification is incomplete. Use Restore purchases to retry.',
              );
      }
    } finally {
      if (_current(epoch)) {
        pending = false;
        _verifying.remove(purchase.token);
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    companion.removeListener(_identityChanged);
    unawaited(_subscription?.cancel());
    _verifying.clear();
    super.dispose();
  }
}
