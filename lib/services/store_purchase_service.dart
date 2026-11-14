import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../widgets/cowry_checkout_webview.dart' show CowryCheckoutResult;

/// Which store sells cowries in this build. Apple and Google require their
/// own billing for virtual currency, so the iOS and Android apps sell
/// cowries as consumable in-app products instead of through Paystack.
enum CowryStore { appStore, googlePlay }

extension CowryStoreInfo on CowryStore {
  String get label => this == CowryStore.appStore ? 'App Store' : 'Google Play';
  String get provider =>
      this == CowryStore.appStore ? 'APP_STORE' : 'GOOGLE_PLAY';
}

/// Store product ids per cowry package. Must match STORE_PRODUCT_IDS in
/// supabase/functions/_shared/cowry-packages.ts and the products created in
/// App Store Connect and the Play Console.
const Map<String, String> kCowryStoreProductIds = {
  'copper-50': 'cowries_copper_50',
  'silver-100': 'cowries_silver_100',
  'gold-500': 'cowries_gold_500',
  'diamond-1000': 'cowries_diamond_1000',
};

const List<(String, String, int)> _kStorePackages = [
  ('copper-50', 'Copper', 50),
  ('silver-100', 'Silver', 100),
  ('gold-500', 'Gold', 500),
  ('diamond-1000', 'Diamond', 1000),
];

class StoreCowryPackage {
  final String id;
  final String name;
  final int cowries;
  final ProductDetails product;
  const StoreCowryPackage({
    required this.id,
    required this.name,
    required this.cowries,
    required this.product,
  });

  /// Localized price from the store, e.g. "₦1,500.00" or "$1.99".
  String get price => product.price;
}

/// Thin seam over the in_app_purchase plugin so the purchase flow can be
/// tested without a real store.
abstract class StoreBilling {
  Stream<List<PurchaseDetails>> get purchases;
  Future<bool> isAvailable();
  Future<List<ProductDetails>> products(Set<String> ids);
  Future<void> buy(ProductDetails product, String userId);

  /// Tells the store the purchase was delivered. On Android this consumes
  /// it so the same package can be bought again.
  Future<void> finish(PurchaseDetails purchase);

  /// Re-delivers purchases that were paid for but never finished.
  Future<void> recoverUnfinished();
}

class PluginStoreBilling implements StoreBilling {
  final InAppPurchase _iap = InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchases => _iap.purchaseStream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<List<ProductDetails>> products(Set<String> ids) async {
    final response = await _iap.queryProductDetails(ids);
    if (response.error != null) throw Exception(response.error!.message);
    return response.productDetails;
  }

  @override
  Future<void> buy(ProductDetails product, String userId) async {
    // applicationUserName becomes the appAccountToken (iOS) or
    // obfuscatedAccountId (Android); the server checks it against the
    // signed-in user. Consumed manually in finish(), only after the server
    // has credited the cowries.
    await _iap.buyConsumable(
      purchaseParam: PurchaseParam(
        productDetails: product,
        applicationUserName: userId,
      ),
      autoConsume: false,
    );
  }

  @override
  Future<void> finish(PurchaseDetails purchase) async {
    if (purchase is GooglePlayPurchaseDetails) {
      await _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
          .consumePurchase(purchase);
    } else if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  @override
  Future<void> recoverUnfinished() async {
    // StoreKit re-sends unfinished transactions on its own when the purchase
    // stream is first listened to; calling restore there would prompt for
    // an Apple ID sign-in. Google Play needs to be asked.
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _iap.restorePurchases();
    }
  }
}

/// Outcome of asking the server to credit a store purchase.
enum StoreCreditOutcome { credited, pending, rejected, retryLater }

abstract class StoreCreditApi {
  Future<StoreCreditOutcome> credit(
    CowryStore store,
    PurchaseDetails purchase, {
    double? amount,
    String? currency,
  });
}

class HttpStoreCreditApi implements StoreCreditApi {
  @override
  Future<StoreCreditOutcome> credit(
    CowryStore store,
    PurchaseDetails purchase, {
    double? amount,
    String? currency,
  }) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return StoreCreditOutcome.retryLater;
    try {
      final response = await http.post(
        Uri.parse(
          '${AppConfig.current.supabaseUrl}/functions/v1/cowry-store-purchase',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'provider': store.provider,
          'productId': purchase.productID,
          if (store == CowryStore.appStore)
            'transactionId': purchase.purchaseID,
          if (store == CowryStore.googlePlay)
            'purchaseToken': purchase.verificationData.serverVerificationData,
          'amount': amount,
          'currency': currency,
        }),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true) return StoreCreditOutcome.credited;
      if (data['pending'] == true) return StoreCreditOutcome.pending;
      debugPrint(
        'cowry-store-purchase: ${response.statusCode} ${response.body}',
      );
      return data['retryable'] == false
          ? StoreCreditOutcome.rejected
          : StoreCreditOutcome.retryLater;
    } catch (e) {
      debugPrint('cowry-store-purchase failed: $e');
      return StoreCreditOutcome.retryLater;
    }
  }
}

/// Runs cowry purchases through the App Store / Google Play. Started once at
/// app launch so purchases that were paid for but not yet credited (app
/// killed mid-purchase, no network) are picked up and credited later.
class StorePurchaseService {
  StorePurchaseService({
    required this.store,
    required this._billing,
    required this._api,
    required this._currentUserId,
  });

  /// The app-wide instance, or null on platforms without a store (web,
  /// desktop), where Paystack is used instead.
  static StorePurchaseService? instance;

  final CowryStore store;
  final StoreBilling _billing;
  final StoreCreditApi _api;
  final String? Function() _currentUserId;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final Map<String, ProductDetails> _products = {};
  final Map<String, PurchaseDetails> _uncredited = {};
  final Map<String, Completer<CowryCheckoutResult>> _waiting = {};

  void start() {
    _subscription ??= _billing.purchases.listen((purchases) {
      for (final purchase in purchases) {
        unawaited(_handle(purchase));
      }
    }, onError: (Object e) => debugPrint('Store purchase stream error: $e'));
    if (_currentUserId() != null) unawaited(_recover());
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<List<StoreCowryPackage>> loadPackages() async {
    if (!await _billing.isAvailable()) {
      throw Exception('${store.label} is not available on this device.');
    }
    final products = await _billing.products(
      kCowryStoreProductIds.values.toSet(),
    );
    for (final p in products) {
      _products[p.id] = p;
    }
    // Opening the top-up modal is a good moment to retry anything that
    // couldn't be credited earlier (e.g. bought while signed out/offline).
    unawaited(_recover());
    return [
      for (final (id, name, cowries) in _kStorePackages)
        if (_products[kCowryStoreProductIds[id]] case final product?)
          StoreCowryPackage(
            id: id,
            name: name,
            cowries: cowries,
            product: product,
          ),
    ];
  }

  /// Opens the store's payment sheet and completes once the purchase has
  /// been credited, cancelled, failed or left pending.
  Future<CowryCheckoutResult> buy(StoreCowryPackage pkg) async {
    final userId = _currentUserId();
    if (userId == null) return CowryCheckoutResult.failed;
    final productId = pkg.product.id;
    _waiting[productId]?.complete(CowryCheckoutResult.cancelled);
    final completer = _waiting[productId] = Completer<CowryCheckoutResult>();
    try {
      await _billing.buy(pkg.product, userId);
    } catch (e) {
      debugPrint('Store buy failed: $e');
      _waiting.remove(productId);
      return CowryCheckoutResult.failed;
    }
    return completer.future;
  }

  Future<void> _recover() async {
    for (final purchase in List.of(_uncredited.values)) {
      await _credit(purchase);
    }
    try {
      await _billing.recoverUnfinished();
    } catch (e) {
      debugPrint('Store recovery failed: $e');
    }
  }

  void _resolve(String productId, CowryCheckoutResult result) {
    final completer = _waiting.remove(productId);
    if (completer != null && !completer.isCompleted) completer.complete(result);
  }

  Future<void> _handle(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        // Waiting on the buyer (e.g. Ask to Buy, cash payment); the store
        // sends another update once it settles.
        _resolve(purchase.productID, CowryCheckoutResult.pending);
      case PurchaseStatus.canceled:
        if (purchase.pendingCompletePurchase) await _billing.finish(purchase);
        _resolve(purchase.productID, CowryCheckoutResult.cancelled);
      case PurchaseStatus.error:
        debugPrint('Store purchase error: ${purchase.error}');
        if (purchase.pendingCompletePurchase) await _billing.finish(purchase);
        _resolve(purchase.productID, CowryCheckoutResult.failed);
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        await _credit(purchase);
    }
  }

  String _key(PurchaseDetails p) =>
      p.purchaseID ?? p.verificationData.serverVerificationData;

  Future<void> _credit(PurchaseDetails purchase) async {
    final key = _key(purchase);
    _uncredited[key] = purchase;
    if (_currentUserId() == null) return;
    final product = _products[purchase.productID];
    final outcome = await _api.credit(
      store,
      purchase,
      amount: product?.rawPrice,
      currency: product?.currencyCode,
    );
    switch (outcome) {
      case StoreCreditOutcome.credited:
      case StoreCreditOutcome.rejected:
        // Only finished once the server has either credited it or said it
        // never will; anything else stays with the store to retry later.
        _uncredited.remove(key);
        try {
          await _billing.finish(purchase);
        } catch (e) {
          debugPrint('Store finish failed: $e');
        }
        _resolve(
          purchase.productID,
          outcome == StoreCreditOutcome.credited
              ? CowryCheckoutResult.success
              : CowryCheckoutResult.failed,
        );
      case StoreCreditOutcome.pending:
        _resolve(purchase.productID, CowryCheckoutResult.pending);
      case StoreCreditOutcome.retryLater:
        _resolve(purchase.productID, CowryCheckoutResult.pending);
    }
  }
}
