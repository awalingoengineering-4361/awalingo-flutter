import 'dart:async';
import 'package:awalingo/services/store_purchase_service.dart';
import 'package:awalingo/widgets/cowry_checkout_webview.dart';
import 'package:awalingo/widgets/top_up_cowries_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

ProductDetails product(String id, String price) => ProductDetails(
  id: id,
  title: id,
  description: id,
  price: price,
  rawPrice: 1.99,
  currencyCode: 'USD',
);

PurchaseDetails purchase(
  String productId,
  PurchaseStatus status, {
  String id = 'tx-1',
}) => PurchaseDetails(
  purchaseID: id,
  productID: productId,
  verificationData: PurchaseVerificationData(
    localVerificationData: '',
    serverVerificationData: 'token-$id',
    source: 'test',
  ),
  transactionDate: '0',
  status: status,
)..pendingCompletePurchase = true;

class FakeBilling implements StoreBilling {
  final controller = StreamController<List<PurchaseDetails>>.broadcast(
    sync: true,
  );
  final finished = <String?>[];
  final bought = <(String, String)>[];
  int recoveries = 0;
  List<PurchaseDetails> onBuy = [];

  @override
  Stream<List<PurchaseDetails>> get purchases => controller.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<ProductDetails>> products(Set<String> ids) async => [
    product('cowries_copper_50', r'$0.99'),
    product('cowries_gold_500', r'$7.99'),
  ];
  @override
  Future<void> buy(ProductDetails product, String userId) async {
    bought.add((product.id, userId));
    if (onBuy.isNotEmpty) scheduleMicrotask(() => controller.add(onBuy));
  }

  @override
  Future<void> finish(PurchaseDetails purchase) async =>
      finished.add(purchase.purchaseID);
  @override
  Future<void> recoverUnfinished() async => recoveries++;
}

class FakeCreditApi implements StoreCreditApi {
  final outcomes = <StoreCreditOutcome>[];
  final calls = <String>[];
  @override
  Future<StoreCreditOutcome> credit(
    CowryStore store,
    PurchaseDetails purchase, {
    double? amount,
    String? currency,
  }) async {
    calls.add('${store.provider}:${purchase.productID}:$amount:$currency');
    return outcomes.isEmpty
        ? StoreCreditOutcome.credited
        : outcomes.removeAt(0);
  }
}

void main() {
  modalTests();
  late FakeBilling billing;
  late FakeCreditApi api;
  String? userId;
  late StorePurchaseService service;

  setUp(() {
    billing = FakeBilling();
    api = FakeCreditApi();
    userId = 'user-1';
    service = StorePurchaseService(
      store: CowryStore.appStore,
      billing: billing,
      api: api,
      currentUserId: () => userId,
    )..start();
  });

  tearDown(() => service.dispose());

  test('lists only packages the store returned, with store prices', () async {
    final packages = await service.loadPackages();
    expect(packages.map((p) => (p.name, p.cowries, p.price)), [
      ('Copper', 50, r'$0.99'),
      ('Gold', 500, r'$7.99'),
    ]);
  });

  test('a purchase is credited before it is finished with the store', () async {
    final pkg = (await service.loadPackages()).first;
    billing.onBuy = [purchase('cowries_copper_50', PurchaseStatus.purchased)];

    expect(await service.buy(pkg), CowryCheckoutResult.success);
    expect(billing.bought, [('cowries_copper_50', 'user-1')]);
    expect(api.calls, ['APP_STORE:cowries_copper_50:1.99:USD']);
    expect(billing.finished, ['tx-1']);
  });

  test(
    'a purchase the server could not credit stays unfinished and is retried',
    () async {
      final pkg = (await service.loadPackages()).first;
      api.outcomes.add(StoreCreditOutcome.retryLater);
      billing.onBuy = [purchase('cowries_copper_50', PurchaseStatus.purchased)];

      expect(await service.buy(pkg), CowryCheckoutResult.pending);
      expect(billing.finished, isEmpty);

      await service.loadPackages();
      await pumpEventQueue();
      expect(api.calls, hasLength(2));
      expect(billing.finished, ['tx-1']);
    },
  );

  test(
    'a purchase the server rejects is finished and reported as failed',
    () async {
      final pkg = (await service.loadPackages()).first;
      api.outcomes.add(StoreCreditOutcome.rejected);
      billing.onBuy = [purchase('cowries_copper_50', PurchaseStatus.purchased)];

      expect(await service.buy(pkg), CowryCheckoutResult.failed);
      expect(billing.finished, ['tx-1']);
    },
  );

  test('cancelling the store sheet credits nothing', () async {
    final pkg = (await service.loadPackages()).first;
    billing.onBuy = [purchase('cowries_copper_50', PurchaseStatus.canceled)];

    expect(await service.buy(pkg), CowryCheckoutResult.cancelled);
    expect(api.calls, isEmpty);
  });

  test(
    'a purchase delivered while signed out is credited after sign-in',
    () async {
      await service.loadPackages();
      userId = null;
      billing.controller.add([
        purchase('cowries_gold_500', PurchaseStatus.restored),
      ]);
      await pumpEventQueue();
      expect(api.calls, isEmpty);
      expect(billing.finished, isEmpty);

      userId = 'user-1';
      await service.loadPackages();
      await pumpEventQueue();
      expect(api.calls, hasLength(1));
      expect(billing.finished, ['tx-1']);
    },
  );
}

// Kept outside main()'s setUp so the service is created inside the widget
// tester's fake-async zone, where its stream callbacks get pumped.
void modalTests() {
  testWidgets('Top Up modal sells store products in store builds', (
    tester,
  ) async {
    final billing = FakeBilling();
    final service = StorePurchaseService(
      store: CowryStore.appStore,
      billing: billing,
      api: FakeCreditApi(),
      currentUserId: () => 'user-1',
    )..start();
    addTearDown(service.dispose);
    billing.onBuy = [purchase('cowries_gold_500', PurchaseStatus.purchased)];
    CowryCheckoutResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<CowryCheckoutResult>(
                context: context,
                builder: (_) => TopUpCowriesModal(
                  returnTo: 'profile',
                  storePurchases: service,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Pay with App Store'), findsOneWidget);
    expect(find.text('Paystack'), findsNothing);
    expect(find.text(r'$7.99'), findsOneWidget);

    await tester.tap(find.text('Gold'));
    await tester.pumpAndSettle();
    expect(result, CowryCheckoutResult.success);
    expect(billing.bought.single.$1, 'cowries_gold_500');
  });
}
