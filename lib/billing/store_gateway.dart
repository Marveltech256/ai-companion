import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

import '../core/app_failure.dart';

class StorePlan {
  const StorePlan({
    required this.id,
    required this.basePlan,
    required this.title,
    required this.price,
    this.native,
  });
  final String id, basePlan, title, price;
  final Object? native;
}

class StorePurchase {
  const StorePurchase(
    this.product,
    this.token,
    this.status, {
    this.needsFinish = false,
    this.native,
  });
  final String product, token, status;
  final bool needsFinish;
  final Object? native;
}

abstract interface class StoreGateway {
  bool get supported;
  Stream<List<StorePurchase>> get purchases;
  Future<StorePlan> plan(String product, String basePlan);
  Future<void> buy(StorePlan plan, String accountRef);
  Future<void> restore(String accountRef);
  Future<void> finish(StorePurchase purchase);
}

class GooglePlayStoreGateway implements StoreGateway {
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  InAppPurchase get _store => InAppPurchase.instance;
  @override
  Stream<List<StorePurchase>> get purchases => _store.purchaseStream.map(
    (items) => [
      for (final p in items)
        StorePurchase(
          p.productID,
          p.verificationData.serverVerificationData,
          switch (p.status) {
            PurchaseStatus.pending => 'pending',
            PurchaseStatus.purchased || PurchaseStatus.restored => 'purchased',
            PurchaseStatus.canceled => 'canceled',
            PurchaseStatus.error => 'error',
          },
          needsFinish: p.pendingCompletePurchase,
          native: p,
        ),
    ],
  );
  @override
  Future<StorePlan> plan(String product, String basePlan) async {
    if (!supported || !await _store.isAvailable()) {
      throw const AppFailure(
        'store_unavailable',
        'Google Play is not available on this device.',
      );
    }
    final response = await _store.queryProductDetails({product});
    if (response.error != null) {
      throw const AppFailure(
        'store_unavailable',
        'The plan could not be loaded. Please try again.',
      );
    }
    for (final p
        in response.productDetails.whereType<GooglePlayProductDetails>()) {
      final index = p.subscriptionIndex,
          offers = p.productDetails.subscriptionOfferDetails;
      if (index == null || offers == null) continue;
      final offer = offers[index];
      if (offer.basePlanId != basePlan ||
          offer.offerId != null ||
          offer.pricingPhases.length != 1) {
        continue;
      }
      final phase = offer.pricingPhases.single;
      if (phase.billingPeriod != 'P1M' ||
          phase.recurrenceMode != RecurrenceMode.infiniteRecurring) {
        continue;
      }
      return StorePlan(
        id: p.id,
        basePlan: basePlan,
        title: p.title,
        price: phase.formattedPrice,
        native: p,
      );
    }
    throw const AppFailure(
      'plan_unavailable',
      'The monthly plan is not available in Google Play yet.',
    );
  }

  @override
  Future<void> buy(StorePlan plan, String accountRef) async {
    final p = plan.native as GooglePlayProductDetails;
    final offer =
        p.productDetails.subscriptionOfferDetails![p.subscriptionIndex!];
    final started = await _store.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: p,
        applicationUserName: accountRef,
        offerToken: offer.offerIdToken,
      ),
    );
    if (!started) {
      throw const AppFailure(
        'purchase_not_started',
        'The purchase was not started.',
      );
    }
  }

  @override
  Future<void> restore(String accountRef) =>
      _store.restorePurchases(applicationUserName: accountRef);
  @override
  Future<void> finish(StorePurchase purchase) =>
      _store.completePurchase(purchase.native as PurchaseDetails);
}
