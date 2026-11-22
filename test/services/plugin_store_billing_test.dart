import 'package:awalingo/services/store_purchase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'store_purchase_service_test.dart'
    show FakeBilling, FakeCreditApi, product, purchase;
import 'package:awalingo/widgets/cowry_checkout_webview.dart';
import 'dart:async';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

class _AndroidAddition extends Fake
    implements InAppPurchaseAndroidPlatformAddition {
  BillingResponse response = BillingResponse.ok;
  List<GooglePlayPurchaseDetails> owned = [];
  IAPError? queryError;
  @override
  Future<BillingResultWrapper> consumePurchase(
    PurchaseDetails purchase,
  ) async => BillingResultWrapper(responseCode: response);
  @override
  Future<QueryPurchaseDetailsResponse> queryPastPurchases({
    String? applicationUserName,
  }) async =>
      QueryPurchaseDetailsResponse(pastPurchases: owned, error: queryError);
}

class _StoreSdk extends Fake implements InAppPurchase {
  bool launched = true;
  final addition = _AndroidAddition();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getPlatformAddition) return addition;
    return super.noSuchMethod(invocation);
  }

  final completed = <String?>[];
  @override
  Future<void> completePurchase(PurchaseDetails purchase) async =>
      completed.add(purchase.purchaseID);
  PurchaseParam? params;
  bool? autoConsumed;
  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    params = purchaseParam;
    autoConsumed = autoConsume;
    return launched;
  }
}

GooglePlayPurchaseDetails googlePurchase(
  PurchaseStatus status, {
  String? owner,
  int purchaseTime = 0,
}) => GooglePlayPurchaseDetails(
  productID: 'cowries_copper_50',
  purchaseID: 'order-1',
  verificationData: PurchaseVerificationData(
    localVerificationData: '{}',
    serverVerificationData: 'paid-token',
    source: 'google_play',
  ),
  transactionDate: '0',
  status: status,
  billingClientPurchase: PurchaseWrapper(
    orderId: 'order-1',
    packageName: 'org.awalingo.app',
    purchaseTime: purchaseTime,
    obfuscatedAccountId: owner,
    purchaseToken: 'paid-token',
    signature: 'fixture',
    products: ['cowries_copper_50'],
    isAutoRenewing: false,
    originalJson: '{}',
    isAcknowledged: false,
    purchaseState: PurchaseStateWrapper.purchased,
  ),
);

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'Apple checkout uses the StoreKit-compatible autoConsume argument',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final sdk = _StoreSdk();
      await PluginStoreBilling(
        iap: sdk,
      ).buy(product('cowries_copper_50', 'USD 1'), 'owner');
      expect(sdk.autoConsumed, true);
    },
  );
  test(
    'ITEM_NOT_OWNED retains the receipt if fresh inventory still owns it',
    () async {
      final sdk = _StoreSdk();
      final tx = googlePurchase(PurchaseStatus.purchased);
      sdk.addition
        ..response = BillingResponse.itemNotOwned
        ..owned = [tx];
      await expectLater(
        PluginStoreBilling(iap: sdk).finish(tx),
        throwsStateError,
      );
      sdk.addition.owned = [];
      await PluginStoreBilling(iap: sdk).finish(tx);
      sdk.addition.queryError = IAPError(
        source: 'google_play',
        code: 'offline',
        message: 'offline',
      );
      await expectLater(
        PluginStoreBilling(iap: sdk).finish(tx),
        throwsStateError,
      );
    },
  );
  test(
    'Play recovery before the original callback resolves the buyer',
    () async {
      final billing = FakeBilling();
      final service = StorePurchaseService(
        store: CowryStore.googlePlay,
        billing: billing,
        api: FakeCreditApi(),
        currentUserId: () => 'owner-uuid',
      )..start();
      addTearDown(service.dispose);
      final pkg = (await service.loadPackages()).first;
      final result = service.buy(pkg);
      await pumpEventQueue();
      billing.controller.add([
        googlePurchase(
          PurchaseStatus.restored,
          owner: 'owner-uuid',
          purchaseTime: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);
      expect(
        await result.timeout(const Duration(seconds: 2)),
        CowryCheckoutResult.success,
      );
      expect(billing.finished, ['order-1']);
    },
  );

  test(
    'a cancelled Google checkout is never consumed or acknowledged',
    () async {
      final sdk = _StoreSdk();
      // Any attempt to get the Android consumption adapter throws from Fake.
      await PluginStoreBilling(
        iap: sdk,
      ).finish(googlePurchase(PurchaseStatus.canceled));
      expect(sdk.completed, isEmpty);
    },
  );
  test('an Apple error transaction is removed from its failed queue', () async {
    final sdk = _StoreSdk();
    await PluginStoreBilling(
      iap: sdk,
    ).finish(purchase('cowries_copper_50', PurchaseStatus.error));
    expect(sdk.completed, ['tx-1']);
  });
  test(
    'store checkout binds the buyer and disables automatic consumption',
    () async {
      final sdk = _StoreSdk();
      await PluginStoreBilling(
        iap: sdk,
      ).buy(product('cowries_copper_50', 'USD 1'), 'owner-uuid');
      expect(sdk.params!.applicationUserName, 'owner-uuid');
      expect(sdk.autoConsumed, false);
    },
  );
  test(
    'a store sheet that fails to launch is reported instead of waiting forever',
    () async {
      final sdk = _StoreSdk()..launched = false;
      await expectLater(
        PluginStoreBilling(
          iap: sdk,
        ).buy(product('cowries_copper_50', 'USD 1'), 'owner-uuid'),
        throwsStateError,
      );
    },
  );
}
