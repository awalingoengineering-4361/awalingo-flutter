import 'dart:convert';
import 'dart:async';
import 'package:awalingo/screens/main/menu_screen.dart';
import 'package:awalingo/screens/app_shell.dart';
import 'package:awalingo/screens/main/translate_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../support/offline_fixture.dart';

void main() => curatorMenuRefreshTests();

void curatorMenuRefreshTests({
  Future<void> Function(WidgetTester, String)? capture,
}) {
  late OfflineFixture fixture;
  late String role;
  late List<Map<String, dynamic>> attempts;
  late List<Map<String, dynamic>> ledger;
  late int promotions;
  late bool rejectPromotion;

  setUp(() async {
    fixture = OfflineFixture();
    await fixture.initialize();
    fixture.offline = false;
    role = 'EXPLORER';
    attempts = [];
    ledger = [];
    promotions = 0;
    rejectPromotion = false;
    fixture.questions = [
      {
        'id': 1,
        'text': 'Choose the greeting',
        'options': [
          {'label': 'Hello', 'value': 'hello'},
          {'label': 'Goodbye', 'value': 'goodbye'},
        ],
        'correctAnswer': 'hello',
      },
    ];
    fixture.intercept = (request) async {
      final table = request.url.pathSegments.last;
      Object? data;
      if (table == 'user_roles') {
        data = {
          'role': {'name': role},
        };
      } else if (table == 'quiz_attempts') {
        if (request.method == 'POST') {
          attempts.add(Map<String, dynamic>.from(jsonDecode(request.body)));
        }
      } else if (table == 'promote_user_to_curator') {
        promotions++;
        if (rejectPromotion) {
          return http.Response(
            '{"message":"promotion rejected","code":"42501","details":"fixture","hint":"fixture"}',
            403,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        role = 'CURATOR';
      } else if (table == 'cowry_ledger') {
        if (request.method == 'POST') {
          ledger.add(Map<String, dynamic>.from(jsonDecode(request.body)));
        } else {
          data = ledger;
        }
      } else if (table == 'user_profile' && request.method == 'PATCH') {
        // The real screen reconciles the balance after writing the ledger.
      } else {
        return fixture.respond(request);
      }
      return http.Response(
        jsonEncode(data),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    };
  });
  tearDown(() => fixture.dispose());

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> enterTest(WidgetTester tester, {bool inShell = false}) async {
    await fixture.mount(
      tester,
      inShell ? const AppShell() : const MenuScreen(),
    );
    if (inShell) await tap(tester, 'Menu');
    expect(find.text('Explorer'), findsOneWidget);
    await tap(tester, 'Level up');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tap(tester, 'Take the Test');
    expect(find.text('Choose the greeting'), findsOneWidget);
  }

  testWidgets(
    'pass updates cached Menu immediately and stays correct on reopen',
    (tester) async {
      await enterTest(tester);
      await tap(tester, 'Hello');
      await tap(tester, 'Submit Test');
      expect(find.text('You passed!!'), findsOneWidget);
      await tap(tester, 'Go Home');
      expect(find.text('Curator'), findsOneWidget);
      expect(find.text('Become a Curator'), findsNothing);
      expect(find.text('Make Your Suggestion'), findsOneWidget);
      expect(role, 'CURATOR');
      expect(attempts.single['passed'], true);
      expect(attempts.single['userId'], 'offline-user');
      expect(ledger.single['cowry_changed'], 10);
      expect(promotions, 1);
      if (capture != null) {
        await tester.ensureVisible(find.text('Curator'));
        await tester.pumpAndSettle();
        await capture(tester, 'curator-menu-after-pass');
      }

      // The same user returns immediately: eligibility must prohibit another
      // test, and returning/reopening Menu must not repeat promotion or rewards.
      final menuContext = tester.element(find.byType(MenuScreen));
      Navigator.of(menuContext).push(
        MaterialPageRoute<void>(
          builder: (_) => const Material(child: MenuScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Curator'), findsOneWidget);
      expect(find.text('Become a Curator'), findsNothing);
      Navigator.of(tester.element(find.byType(MenuScreen).last)).pop();
      await tester.pumpAndSettle();
      expect(find.text('Curator'), findsOneWidget);
      expect(attempts, hasLength(1));
      expect(ledger, hasLength(1));
      expect(promotions, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nested Menu refreshes after pass and Translate accepts new role',
    (tester) async {
      await enterTest(tester, inShell: true);
      await tap(tester, 'Hello');
      await tap(tester, 'Submit Test');
      await tap(tester, 'Go Home');
      expect(find.text('Curator'), findsOneWidget);
      expect(find.text('Become a Curator'), findsNothing);
      await tap(tester, 'Translate');
      expect(find.byType(TranslateScreen), findsOneWidget);
      expect(find.byType(MenuScreen), findsNothing);
      await tap(tester, 'Menu');
      expect(find.text('Curator'), findsOneWidget);
      expect(promotions, 1);
      expect(attempts, hasLength(1));
      expect(ledger, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('pass via Translate guard updates already-mounted Menu', (
    tester,
  ) async {
    await fixture.mount(tester, const AppShell());
    await tap(tester, 'Menu');
    expect(find.text('Explorer'), findsOneWidget);
    await tap(tester, 'Translate');
    await tap(tester, 'Take Test');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tap(tester, 'Take the Test');
    await tap(tester, 'Hello');
    await tap(tester, 'Submit Test');
    await tap(tester, 'Go Home');
    expect(find.text('Curator'), findsOneWidget);
    expect(find.text('Become a Curator'), findsNothing);
    expect(find.text('Make Your Suggestion'), findsOneWidget);
    expect(promotions, 1);
    expect(attempts, hasLength(1));
    expect(ledger, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Back from guard-launched passed test updates Menu', (
    tester,
  ) async {
    await fixture.mount(tester, const AppShell());
    await tap(tester, 'Menu');
    expect(find.text('Explorer'), findsOneWidget);
    await tap(tester, 'Translate');
    await tap(tester, 'Take Test');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tap(tester, 'Take the Test');
    await tap(tester, 'Hello');
    await tap(tester, 'Submit Test');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Curator'), findsOneWidget);
    expect(find.text('Become a Curator'), findsNothing);
    expect(find.text('Make Your Suggestion'), findsOneWidget);
    expect(promotions, 1);
    expect(attempts, hasLength(1));
    expect(ledger, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final rejected in [false, true]) {
    testWidgets(
      rejected
          ? 'rejected promotion does not grant curator access'
          : 'failed test keeps Menu explorer access',
      (tester) async {
        rejectPromotion = rejected;
        await enterTest(tester);
        await tap(tester, rejected ? 'Hello' : 'Goodbye');
        await tap(tester, 'Submit Test');
        await tap(tester, 'Go Home');
        expect(role, 'EXPLORER');
        expect(find.text('Explorer'), findsOneWidget);
        expect(find.text('Become a Curator'), findsOneWidget);
        expect(find.text('Make Your Suggestion'), findsNothing);
        expect(attempts, hasLength(1));
        expect(ledger, hasLength(1));
        expect(promotions, rejected ? 1 : 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'late Explorer response cannot overwrite refreshed curator state',
    (tester) async {
      final roleSignal = ValueNotifier<String?>('EXPLORER');
      await fixture.mount(
        tester,
        ValueListenableBuilder<String?>(
          valueListenable: roleSignal,
          builder: (_, value, _) => MenuScreen(role: value),
        ),
      );
      final original = fixture.intercept!;
      final pending = Completer<http.Response>();
      late http.Request pendingRequest;
      var holdNext = true;
      fixture.intercept = (request) async {
        if (request.url.pathSegments.last == 'user_roles' && holdNext) {
          holdNext = false;
          pendingRequest = request;
          return pending.future;
        }
        return original(request);
      };
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      role = 'CURATOR';
      roleSignal.value = role;
      await tester.pumpAndSettle();
      expect(find.text('Curator'), findsOneWidget);
      pending.complete(
        http.Response(
          '{"role":{"name":"EXPLORER"}}',
          200,
          request: pendingRequest,
          headers: {'content-type': 'application/json'},
        ),
      );
      await refresh;
      await tester.pumpAndSettle();
      expect(find.text('Curator'), findsOneWidget);
      expect(find.text('Become a Curator'), findsNothing);
      expect(attempts, isEmpty);
      expect(ledger, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      roleSignal.dispose();
    },
  );

  testWidgets('leaving eligibility twice refreshes without submitting', (
    tester,
  ) async {
    await fixture.mount(tester, const MenuScreen());
    for (var run = 0; run < 2; run++) {
      await tap(tester, 'Level up');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Explorer'), findsOneWidget);
      expect(find.text('Become a Curator'), findsOneWidget);
    }
    expect(attempts, isEmpty);
    expect(ledger, isEmpty);
    expect(promotions, 0);
    expect(tester.takeException(), isNull);
  });
}
