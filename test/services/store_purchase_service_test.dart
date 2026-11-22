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
  transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
  status: status,
)..pendingCompletePurchase = true;

class FakeBilling implements StoreBilling {
  final controller = StreamController<List<PurchaseDetails>>.broadcast(
    sync: true,
  );
  final finished = <String?>[];
  final bought = <(String, String)>[];
  int recoveries = 0;
  int finishFailures = 0;
  int finishAttempts = 0;
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
  Future<void> finish(PurchaseDetails purchase) async {
    finishAttempts++;
    if (finishFailures > 0) {
      finishFailures--;
      throw StateError('store unavailable');
    }
    finished.add(purchase.purchaseID);
  }

  @override
  Future<void> recoverUnfinished() async => recoveries++;
}

class FakeCreditApi implements StoreCreditApi {
  bool eligible = true;
  Completer<bool>? eligibilityGate;
  Completer<StoreCreditOutcome>? creditGate;
  Future<bool> canPurchase(CowryStore store, String productId) async =>
      eligibilityGate == null ? eligible : eligibilityGate!.future;
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
    if (creditGate != null) return creditGate!.future;
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
    'a rejected purchase remains unconsumed and is reported as failed',
    () async {
      final pkg = (await service.loadPackages()).first;
      api.outcomes.add(StoreCreditOutcome.rejected);
      billing.onBuy = [purchase('cowries_copper_50', PurchaseStatus.purchased)];

      expect(await service.buy(pkg), CowryCheckoutResult.failed);
      expect(billing.finished, isEmpty);
    },
  );

  test(
    'failed completion retries after credit without crediting again',
    () async {
      final pkg = (await service.loadPackages()).first;
      billing.finishFailures = 1;
      billing.onBuy = [purchase(pkg.product.id, PurchaseStatus.purchased)];
      expect(await service.buy(pkg), CowryCheckoutResult.success);
      expect(billing.finished, isEmpty);
      await service.loadPackages();
      await pumpEventQueue();
      expect(billing.finished, ['tx-1']);
      expect(api.calls, hasLength(1));
    },
  );

  test('duplicate callbacks serialize credit and consume once', () async {
    final pkg = (await service.loadPackages()).first;
    api.creditGate = Completer<StoreCreditOutcome>();
    final tx = purchase(pkg.product.id, PurchaseStatus.purchased);
    billing.onBuy = [tx, tx];
    final result = service.buy(pkg);
    await pumpEventQueue();
    expect(api.calls, hasLength(1));
    api.creditGate!.complete(StoreCreditOutcome.credited);
    expect(await result, CowryCheckoutResult.success);
    billing.controller.add([tx]);
    await pumpEventQueue();
    expect(api.calls, hasLength(1));
    expect(billing.finished, ['tx-1']);
  });

  test('eligibility denial does not open a chargeable store sheet', () async {
    final pkg = (await service.loadPackages()).first;
    api.eligible = false;
    billing.onBuy = [purchase(pkg.product.id, PurchaseStatus.purchased)];
    expect(await service.buy(pkg), CowryCheckoutResult.failed);
    expect(billing.bought, isEmpty);
    expect(billing.finished, isEmpty);
  });

  test(
    'account change during eligibility never charges the old user',
    () async {
      final pkg = (await service.loadPackages()).first;
      api.eligibilityGate = Completer<bool>();
      billing.onBuy = [purchase(pkg.product.id, PurchaseStatus.purchased)];
      final result = service.buy(pkg);
      await pumpEventQueue();
      userId = 'user-2';
      api.eligibilityGate!.complete(true);
      expect(await result, CowryCheckoutResult.failed);
      expect(billing.bought, isEmpty);
    },
  );

  test(
    'switching accounts before delivery preserves the buyer receipt',
    () async {
      final pkg = (await service.loadPackages()).first;
      final result = service.buy(pkg);
      await pumpEventQueue();
      userId = 'user-2';
      billing.controller.add([
        purchase(pkg.product.id, PurchaseStatus.purchased),
      ]);
      expect(await result, CowryCheckoutResult.pending);
      expect(api.calls, isEmpty);
      expect(billing.finished, isEmpty);
      userId = 'user-1';
      await service.loadPackages();
      await pumpEventQueue();
      expect(api.calls, hasLength(1));
      expect(billing.finished, ['tx-1']);
    },
  );

  test('same buyer can immediately purchase the same package again', () async {
    final pkg = (await service.loadPackages()).first;
    billing.onBuy = [purchase(pkg.product.id, PurchaseStatus.purchased)];
    expect(await service.buy(pkg), CowryCheckoutResult.success);
    billing.onBuy = [
      purchase(pkg.product.id, PurchaseStatus.purchased, id: 'tx-2'),
    ];
    expect(await service.buy(pkg), CowryCheckoutResult.success);
    expect(api.calls, hasLength(2));
    expect(billing.finished, ['tx-1', 'tx-2']);
  });

  test(
    'background recovery publishes a balance refresh only for the credited owner',
    () async {
      final owners = <String>[];
      final subscription = service.credits.listen(owners.add);
      addTearDown(subscription.cancel);
      api.outcomes.add(StoreCreditOutcome.retryLater);
      billing.controller.add([
        purchase('cowries_copper_50', PurchaseStatus.restored),
      ]);
      await pumpEventQueue();
      expect(owners, isEmpty);
      await service.recover();
      await pumpEventQueue();
      expect(owners, ['user-1']);
      await service.recover();
      expect(owners, ['user-1']);
    },
  );

  test('sign-out recovery keeps the in-flight buyer identity', () async {
    final pkg = (await service.loadPackages()).first;
    final result = service.buy(pkg);
    await pumpEventQueue();
    userId = null;
    await service.recover();
    expect(await result, CowryCheckoutResult.pending);
    userId = 'user-2';
    await service.recover();
    billing.controller.add([
      purchase(pkg.product.id, PurchaseStatus.purchased),
    ]);
    await pumpEventQueue();
    expect(api.calls, isEmpty);
    expect(billing.finished, isEmpty);
    userId = 'user-1';
    await service.recover();
    expect(billing.finished, ['tx-1']);
  });

  test(
    'Apple transactions sharing an app receipt still credit independently',
    () async {
      final pkg = (await service.loadPackages()).first;
      PurchaseDetails apple(String id) => PurchaseDetails(
        purchaseID: id,
        productID: pkg.product.id,
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: 'shared-app-receipt',
          source: 'app_store',
        ),
        transactionDate: '0',
        status: PurchaseStatus.purchased,
      )..pendingCompletePurchase = true;
      billing.onBuy = [apple('apple-1')];
      expect(await service.buy(pkg), CowryCheckoutResult.success);
      billing.onBuy = [apple('apple-2')];
      CowryCheckoutResult? second;
      unawaited(service.buy(pkg).then((result) => second = result));
      await pumpEventQueue();
      expect(api.calls, hasLength(2));
      expect(second, CowryCheckoutResult.success);
      expect(billing.finished, ['apple-1', 'apple-2']);
    },
  );

  test(
    'anonymous Google cancellation releases the active sheet and allows another purchase',
    () async {
      await service.dispose();
      service = StorePurchaseService(
        store: CowryStore.googlePlay,
        billing: billing,
        api: api,
        currentUserId: () => userId,
      )..start();
      final packages = await service.loadPackages();
      CowryCheckoutResult? first;
      unawaited(service.buy(packages.first).then((r) => first = r));
      await pumpEventQueue();
      CowryCheckoutResult? overlapping;
      unawaited(service.buy(packages.last).then((r) => overlapping = r));
      await pumpEventQueue();
      expect(overlapping, CowryCheckoutResult.pending);
      expect(billing.bought, hasLength(1));
      billing.controller.add([purchase('', PurchaseStatus.canceled, id: '')]);
      await pumpEventQueue();
      expect(first, CowryCheckoutResult.cancelled);
      billing.onBuy = [
        purchase(
          packages.last.product.id,
          PurchaseStatus.purchased,
          id: 'next',
        ),
      ];
      expect(await service.buy(packages.last), CowryCheckoutResult.success);
    },
  );

  test(
    'a rejected old receipt does not block a new purchase or resolve its attempt',
    () async {
      final pkg = (await service.loadPackages()).first;
      api.outcomes.add(StoreCreditOutcome.rejected);
      billing.onBuy = [purchase(pkg.product.id, PurchaseStatus.purchased)];
      expect(await service.buy(pkg), CowryCheckoutResult.failed);
      api.eligibilityGate = Completer<bool>();
      CowryCheckoutResult? next;
      billing.onBuy = [
        purchase(pkg.product.id, PurchaseStatus.purchased, id: 'tx-2'),
      ];
      unawaited(service.buy(pkg).then((r) => next = r));
      await pumpEventQueue();
      api.outcomes.add(StoreCreditOutcome.rejected);
      await service
          .recover(); // Old receipt must not fail the new buyer's attempt.
      expect(next, isNull);
      api.eligibilityGate!.complete(true);
      await pumpEventQueue();
      expect(next, CowryCheckoutResult.success);
      expect(billing.bought, hasLength(2));
    },
  );

  test('a pending purchase can settle through restoration alone', () async {
    final pkg = (await service.loadPackages()).first;
    billing.onBuy = [purchase(pkg.product.id, PurchaseStatus.pending)];
    expect(await service.buy(pkg), CowryCheckoutResult.pending);

    billing.controller.add([purchase(pkg.product.id, PurchaseStatus.restored)]);
    await pumpEventQueue();
    expect(billing.finished, ['tx-1']);

    billing.onBuy = [
      purchase(pkg.product.id, PurchaseStatus.purchased, id: 'tx-2'),
    ];
    expect(
      await service.buy(pkg).timeout(const Duration(seconds: 2)),
      CowryCheckoutResult.success,
    );
  });

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
void modalTests({
  CowryStore store = CowryStore.appStore,
  Future<void> Function(WidgetTester)? capture,
}) {
  testWidgets('Top Up modal sells store products in store builds', (
    tester,
  ) async {
    final billing = FakeBilling();
    final service = StorePurchaseService(
      store: store,
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

    expect(find.text('Pay with ${store.label}'), findsOneWidget);
    if (capture != null) await capture(tester);
    expect(find.text('Paystack'), findsNothing);
    expect(find.text(r'$7.99'), findsOneWidget);

    await tester.tap(find.text('Gold'));
    await tester.pumpAndSettle();
    expect(result, CowryCheckoutResult.success);
    expect(billing.bought.single.$1, 'cowries_gold_500');

    billing.onBuy = [
      purchase('cowries_gold_500', PurchaseStatus.purchased, id: 'tx-2'),
    ];
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gold'));
    await tester.pumpAndSettle();
    expect(result, CowryCheckoutResult.success);
    expect(billing.bought, hasLength(2));
    expect(billing.finished, ['tx-1', 'tx-2']);
  });
}
