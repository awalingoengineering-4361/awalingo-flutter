import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show BillingResponse, PurchaseStateWrapper;
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
  PluginStoreBilling({InAppPurchase? iap})
    : _iap = iap ?? InAppPurchase.instance;
  final InAppPurchase _iap;

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
    final launched = await _iap.buyConsumable(
      purchaseParam: PurchaseParam(
        productDetails: product,
        applicationUserName: userId,
      ),
      autoConsume: defaultTargetPlatform != TargetPlatform.android,
    );
    if (!launched) throw StateError('The store checkout could not be opened.');
  }

  @override
  Future<void> finish(PurchaseDetails purchase) async {
    if (purchase is GooglePlayPurchaseDetails) {
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored)
        return;
      final android = _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final result = await android.consumePurchase(purchase);
      if (result.responseCode == BillingResponse.itemNotOwned) {
        final inventory = await android.queryPastPurchases();
        final token = purchase.verificationData.serverVerificationData;
        if (inventory.error == null &&
            !inventory.pastPurchases.any(
              (p) => p.verificationData.serverVerificationData == token,
            ))
          return;
      }
      if (result.responseCode != BillingResponse.ok) {
        throw StateError(
          'Store consumption failed: ${result.responseCode.name}',
        );
      }
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
  /// Server-side eligibility/configuration check before opening store checkout.
  Future<bool> canPurchase(CowryStore store, String productId);

  Future<StoreCreditOutcome> credit(
    CowryStore store,
    PurchaseDetails purchase, {
    double? amount,
    String? currency,
  });
}

class HttpStoreCreditApi implements StoreCreditApi {
  @override
  Future<bool> canPurchase(CowryStore store, String productId) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return false;
    try {
      final response = await http
          .post(
            Uri.parse(
              '${AppConfig.current.supabaseUrl}/functions/v1/cowry-store-purchase',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'action': 'eligibility',
              'provider': store.provider,
              'productId': productId,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return response.statusCode == 200 &&
          (jsonDecode(response.body) as Map<String, dynamic>)['eligible'] ==
              true;
    } catch (_) {
      return false;
    }
  }

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
      final response = await http
          .post(
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
                'purchaseToken':
                    purchase.verificationData.serverVerificationData,
              'amount': amount,
              'currency': currency,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true)
        return StoreCreditOutcome.credited;
      if (data['pending'] == true) return StoreCreditOutcome.pending;
      debugPrint('cowry-store-purchase: HTTP ${response.statusCode}');
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
class _StoreAttempt {
  _StoreAttempt(this.owner, this.productId);
  final String productId;
  int? launchedAt;
  bool get launched => launchedAt != null;
  String? pendingKey;
  final String owner;
  final result = Completer<CowryCheckoutResult>();
}

class _StoreReceipt {
  _StoreReceipt(this.purchase, this.owner, this.attempt);
  final _StoreAttempt? attempt;
  bool blocksCheckout = true;
  final PurchaseDetails purchase;
  String? owner;
  bool credited = false;
  Future<void>? processing;
}

class StorePurchaseService {
  StorePurchaseService({
    required this.store,
    required StoreBilling billing,
    required StoreCreditApi api,
    required String? Function() currentUserId,
  }) : _billing = billing,
       _api = api,
       _currentUserId = currentUserId;

  /// Null on platforms where Paystack is used instead.
  static StorePurchaseService? instance;
  final CowryStore store;
  final StoreBilling _billing;
  final StoreCreditApi _api;
  final String? Function() _currentUserId;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final _products = <String, ProductDetails>{};
  final _receipts = <String, _StoreReceipt>{};
  final _finished = <String>{};
  final _attempts = <String, _StoreAttempt>{};
  _StoreAttempt? _sheet;
  final _credits = StreamController<String>.broadcast();
  Future<void>? _recovery;
  bool _disposed = false;

  /// The owner whose balance should be fetched again after server fulfillment.
  Stream<String> get credits => _credits.stream;

  void start() {
    _subscription ??= _billing.purchases.listen((purchases) {
      for (final purchase in purchases) {
        unawaited(_handle(purchase));
      }
    }, onError: (Object _) => debugPrint('Store purchase stream unavailable'));
    unawaited(recover());
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    for (final attempt in _attempts.values) {
      if (!attempt.result.isCompleted)
        attempt.result.complete(CowryCheckoutResult.pending);
    }
    _attempts.clear();
    await _credits.close();
  }

  Future<List<StoreCowryPackage>> loadPackages() async {
    if (!await _billing.isAvailable()) {
      throw Exception('${store.label} is not available on this device.');
    }
    final products = await _billing.products(
      kCowryStoreProductIds.values.toSet(),
    );
    _products.clear();
    for (final p in products) {
      _products[p.id] = p;
    }
    await recover();
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

  Future<CowryCheckoutResult> buy(StoreCowryPackage pkg) async {
    final owner = _currentUserId();
    if (_disposed || owner == null) return CowryCheckoutResult.failed;
    final productId = pkg.product.id;
    // Reserve before the first await: double taps cannot open two sheets.
    if (_sheet != null ||
        _attempts.containsKey(productId) ||
        _receipts.values.any(
          (r) =>
              r.blocksCheckout &&
              r.purchase.productID == productId &&
              (r.owner == null || r.owner == owner),
        )) {
      return CowryCheckoutResult.pending;
    }
    final attempt = _attempts[productId] = _StoreAttempt(owner, productId);
    _sheet = attempt;
    try {
      if (!await _api.canPurchase(store, productId) ||
          _disposed ||
          _currentUserId() != owner ||
          attempt.result.isCompleted) {
        _resolve(productId, CowryCheckoutResult.failed, attempt: attempt);
      } else {
        attempt.launchedAt = DateTime.now().millisecondsSinceEpoch;
        await _billing.buy(pkg.product, owner);
      }
    } catch (_) {
      _resolve(productId, CowryCheckoutResult.failed, attempt: attempt);
    }
    return attempt.result.future;
  }

  /// Called on authentication changes and foreground resume as well as top-up.
  Future<void> recover() {
    if (_disposed) return Future.value();
    for (final entry in List.of(_attempts.entries)) {
      if (entry.value.owner != _currentUserId()) {
        if (!entry.value.result.isCompleted) {
          entry.value.result.complete(CowryCheckoutResult.pending);
        }
      }
    }
    if (_currentUserId() == null) return Future.value();
    return _recovery ??= _recover().whenComplete(() => _recovery = null);
  }

  Future<void> _recover() async {
    for (final receipt in List.of(_receipts.values)) {
      await _credit(receipt);
    }
    try {
      await _billing.recoverUnfinished();
    } catch (_) {
      debugPrint('Store recovery unavailable; will retry on resume');
    }
  }

  void _resolve(
    String productId,
    CowryCheckoutResult result, {
    _StoreAttempt? attempt,
  }) {
    final waiting = _attempts[productId];
    if (waiting == null || (attempt != null && !identical(attempt, waiting)))
      return;
    _attempts.remove(productId);
    if (identical(_sheet, waiting)) _sheet = null;
    if (!waiting.result.isCompleted) waiting.result.complete(result);
  }

  Future<void> _handle(PurchaseDetails purchase) async {
    if (_disposed) return;
    switch (purchase.status) {
      case PurchaseStatus.pending:
        // Keep the attempt owner until the final store event arrives.
        final attempt = _matchingAttempt(purchase);
        if (attempt != null) _markPending(attempt, purchase);
      case PurchaseStatus.canceled:
        await _clearFailedTransaction(purchase);
        _resolveStoreFailure(purchase, CowryCheckoutResult.cancelled);
      case PurchaseStatus.error:
        // PluginStoreBilling only clears Apple's failed transaction queue;
        // failed/cancelled Google payments are never consumed.
        await _clearFailedTransaction(purchase);
        _resolveStoreFailure(purchase, CowryCheckoutResult.failed);
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        if (purchase.productID.isEmpty) {
          _resolveStoreFailure(purchase, CowryCheckoutResult.failed);
          return;
        }
        final key = _key(purchase);
        if (_finished.contains(key)) return;
        final receipt = _receipts.putIfAbsent(key, () {
          final attempt = _matchingAttempt(purchase);
          return _StoreReceipt(purchase, attempt?.owner, attempt);
        });
        await _credit(receipt);
    }
  }

  _StoreAttempt? _matchingAttempt(PurchaseDetails purchase) {
    final attempt = _attempts[purchase.productID];
    if (attempt == null || !attempt.launched) return null;
    final pendingKey = attempt.pendingKey;
    if (pendingKey != null)
      return pendingKey == _key(purchase) ? attempt : null;

    if (purchase is GooglePlayPurchaseDetails) {
      final native = purchase.billingClientPurchase;
      // Play recovery can deliver the payment before the original callback.
      // Bind it only if its owner and purchase time match this checkout.
      return native.obfuscatedAccountId == attempt.owner &&
              native.purchaseTime >= attempt.launchedAt!
          ? attempt
          : null;
    }
    return purchase.status == PurchaseStatus.restored ? null : attempt;
  }

  void _markPending(_StoreAttempt attempt, PurchaseDetails purchase) {
    if (purchase.verificationData.serverVerificationData.isNotEmpty ||
        (purchase.purchaseID?.isNotEmpty ?? false)) {
      attempt.pendingKey = _key(purchase);
    }
    if (identical(_sheet, attempt)) _sheet = null;
    if (!attempt.result.isCompleted) {
      attempt.result.complete(CowryCheckoutResult.pending);
    }
  }

  void _resolveStoreFailure(
    PurchaseDetails purchase,
    CowryCheckoutResult result,
  ) {
    final attempt = purchase.productID.isEmpty
        ? _sheet
        : _attempts[purchase.productID];
    if (attempt != null && attempt.launched) {
      _resolve(attempt.productId, result, attempt: attempt);
    }
  }

  Future<void> _clearFailedTransaction(PurchaseDetails purchase) async {
    if (store != CowryStore.appStore || !purchase.pendingCompletePurchase)
      return;
    try {
      await _billing.finish(purchase);
    } catch (_) {
      debugPrint('Failed store transaction cleanup will retry on redelivery');
    }
  }

  String _key(PurchaseDetails p) =>
      store == CowryStore.appStore && p.purchaseID != null
      ? 'apple:${p.purchaseID}'
      : p.verificationData.serverVerificationData.isNotEmpty
      ? p.verificationData.serverVerificationData
      : '${p.productID}:${p.purchaseID}';

  Future<void> _credit(_StoreReceipt receipt) => receipt.processing ??=
      _process(receipt).whenComplete(() => receipt.processing = null);

  Future<void> _process(_StoreReceipt receipt) async {
    final purchase = receipt.purchase;
    final key = _key(purchase);
    final owner = _currentUserId();
    final attempt = receipt.attempt;
    void resolve(CowryCheckoutResult result) {
      if (attempt != null)
        _resolve(attempt.productId, result, attempt: attempt);
    }

    if (_disposed ||
        owner == null ||
        (receipt.owner != null && receipt.owner != owner)) {
      resolve(CowryCheckoutResult.pending);
      return;
    }
    if (purchase is GooglePlayPurchaseDetails &&
        purchase.billingClientPurchase.purchaseState ==
            PurchaseStateWrapper.pending) {
      if (attempt != null) _markPending(attempt, purchase);
      _receipts.remove(key);
      return;
    }
    if (!receipt.credited) {
      final product = _products[purchase.productID];
      StoreCreditOutcome outcome;
      try {
        outcome = await _api.credit(
          store,
          purchase,
          amount: product?.rawPrice,
          currency: product?.currencyCode,
        );
      } catch (_) {
        outcome = StoreCreditOutcome.retryLater;
      }
      if (outcome != StoreCreditOutcome.credited) {
        // A different signed-in account can retry later. Rejection never
        // authorizes consuming an unpaid/unfulfilled entitlement.
        if (outcome == StoreCreditOutcome.rejected) {
          receipt.owner = null;
          receipt.blocksCheckout = false;
        }
        resolve(
          outcome == StoreCreditOutcome.rejected
              ? CowryCheckoutResult.failed
              : CowryCheckoutResult.pending,
        );
        return;
      }
      receipt.credited = true;
      receipt.owner = owner;
      if (!_disposed) _credits.add(owner);
    }
    try {
      await _billing.finish(purchase);
      _receipts.remove(key);
      _finished.add(key);
    } catch (_) {
      // Retain credited-but-unfinished state. Retry finish without re-crediting.
      debugPrint('Store completion unavailable; will retry on resume');
    }
    resolve(
      _currentUserId() == receipt.owner
          ? CowryCheckoutResult.success
          : CowryCheckoutResult.pending,
    );
  }
}
