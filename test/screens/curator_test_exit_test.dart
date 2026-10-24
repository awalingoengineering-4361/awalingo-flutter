import 'dart:convert';
import 'dart:async';
import 'package:awalingo/screens/app_shell.dart';
import 'package:awalingo/screens/main/menu_screen.dart';
import 'package:awalingo/screens/main/curator_test_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../support/offline_fixture.dart';

void main() => curatorTestExitTests();

void curatorTestExitTests({
  Future<void> Function(WidgetTester, String)? capture,
  bool runClockTests = true,
}) {
  late OfflineFixture fixture;
  late List<Map<String, dynamic>> attempts;
  late List<Map<String, dynamic>> ledger;
  late int promotions;
  setUp(() async {
    fixture = OfflineFixture();
    await fixture.initialize();
    fixture.offline = false;
    attempts = [];
    ledger = [];
    promotions = 0;
    fixture.questions = List.generate(
      2,
      (i) => {
        'id': i + 1,
        'text': 'Greeting question ${i + 1}',
        'options': [
          {'label': 'Hello', 'value': 'hello'},
          {'label': 'Goodbye', 'value': 'goodbye'},
        ],
        'correctAnswer': 'hello',
      },
    );
    fixture.intercept = (request) async {
      final table = request.url.pathSegments.last;
      Object? data;
      if (table == 'quiz_attempts') {
        if (request.method == 'POST') {
          attempts.add({
            ...Map<String, dynamic>.from(jsonDecode(request.body)),
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          });
        } else {
          // Eligibility check: most recent failed attempt in the cooldown.
          data = attempts
              .where((a) => a['passed'] == false)
              .map((a) => {'createdAt': a['createdAt']})
              .take(1)
              .toList();
        }
      } else if (table == 'cowry_ledger') {
        if (request.method == 'POST') {
          ledger.add(Map<String, dynamic>.from(jsonDecode(request.body)));
        } else {
          data = ledger;
        }
      } else if (table == 'promote_user_to_curator') {
        promotions++;
      } else if (table == 'user_profile' && request.method == 'PATCH') {
      } else {
        return fixture.respond(request);
      }
      return http.Response(
        jsonEncode(data),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    };
  });
  tearDown(() => fixture.dispose());

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(Checkbox));
    if (!tester.widget<Checkbox>(find.byType(Checkbox)).value!) {
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
    }
    await tap(tester, 'Take the Test');
    expect(find.byType(CuratorTestScreen), findsOneWidget);
  }

  Future<void> enter(WidgetTester tester) async {
    await tap(tester, 'Level up');
    await start(tester);
  }

  String currentQuestion(WidgetTester tester) => tester
      .widget<Text>(find.textContaining('Greeting question').first)
      .data!;

  void noWrites() {
    expect(attempts, isEmpty);
    expect(ledger, isEmpty);
    expect(promotions, 0);
    expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
  }

  // Exiting counts as a failed attempt: one quiz_attempts row (which starts
  // the 7-day cooldown), the failure cowry penalty, and no promotion.
  void recordedExit() {
    expect(attempts, hasLength(1));
    expect(attempts.single['passed'], false);
    expect(ledger.single['eventType'], 'FAIL_CURATOR_TEST');
    expect(ledger.single['description'], 'User exited curator test');
    expect(promotions, 0);
  }

  for (final nested in [false, true]) {
    testWidgets(
      '${nested ? 'nested Menu' : 'root'}: Stay keeps the test, Exit starts the cooldown',
      (tester) async {
        await fixture.mount(
          tester,
          nested ? const AppShell() : const MenuScreen(),
        );
        if (nested) await tap(tester, 'Menu');
        await enter(tester);
        await tap(tester, 'Hello');
        await tap(tester, 'Next Question');
        final second = currentQuestion(tester);

        // Back on a later question still confirms instead of stepping back.
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.text('Exit the test?'), findsOneWidget);
        await tap(tester, 'Stay');
        expect(find.byType(CuratorTestScreen), findsOneWidget);
        expect(currentQuestion(tester), second);
        noWrites();

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        await tap(tester, 'Exit');
        expect(find.text('Exit the test?'), findsNothing);
        expect(find.byType(CuratorTestScreen), findsNothing);
        recordedExit();
        expect(find.text('Not Yet Eligible'), findsOneWidget);
        expect(find.text('Take the Test'), findsNothing);
        if (capture != null && nested) {
          await capture(tester, 'curator-exit-cooldown');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('system Back confirms exit on any question', (tester) async {
    await fixture.mount(tester, const AppShell());
    await tap(tester, 'Menu');
    await enter(tester);
    await tap(tester, 'Hello');
    await tap(tester, 'Next Question');
    final second = currentQuestion(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Exit the test?'), findsOneWidget);
    // Back again dismisses the dialog and keeps the test.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Exit the test?'), findsNothing);
    expect(currentQuestion(tester), second);
    noWrites();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tap(tester, 'Exit');
    recordedExit();
    expect(find.text('Not Yet Eligible'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('failing starts the cooldown on return', (tester) async {
    await fixture.mount(tester, const MenuScreen());
    await enter(tester);
    await tap(tester, 'Goodbye');
    await tap(tester, 'Next Question');
    await tap(tester, 'Goodbye');
    await tap(tester, 'Submit Test');
    expect(attempts.single['passed'], false);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Not Yet Eligible'), findsOneWidget);
    expect(find.text('Take the Test'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('rapid Back taps open only one exit confirmation', (
    tester,
  ) async {
    await fixture.mount(tester, const MenuScreen());
    await enter(tester);
    final back = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_back))
        .onPressed!;
    back();
    back();
    await tester.pumpAndSettle();
    expect(find.text('Exit the test?'), findsOneWidget);
    await tap(tester, 'Stay');
    expect(find.text('Exit the test?'), findsNothing);
    noWrites();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('system Back during submission cannot abandon or duplicate it', (
    tester,
  ) async {
    await fixture.mount(tester, const AppShell());
    await tap(tester, 'Menu');
    await enter(tester);
    await tap(tester, 'Hello');
    await tap(tester, 'Next Question');
    await tap(tester, 'Hello');
    final original = fixture.intercept!;
    final gate = Completer<void>();
    fixture.intercept = (request) async {
      if (request.method == 'POST' &&
          request.url.pathSegments.last == 'quiz_attempts') {
        await gate.future;
      }
      return original(request);
    };
    await tester.tap(find.text('Submit Test'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Exit the test?'), findsNothing);
    expect(find.byType(CuratorTestScreen), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('You passed!!'), findsOneWidget);
    expect(attempts, hasLength(1));
    expect(ledger, hasLength(1));
    expect(promotions, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'timeout while confirmation is open keeps the submitted result',
    (tester) async {
      await fixture.mount(tester, const MenuScreen());
      await enter(tester);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 10));
      await tester.pumpAndSettle();
      expect(attempts, hasLength(1));
      expect(attempts.single['passed'], false);
      expect(ledger, hasLength(1));
      await tap(tester, 'Exit');
      expect(find.text('Exit the test?'), findsNothing);
      expect(find.text('Go Home'), findsOneWidget);
      expect(find.byType(CuratorTestScreen), findsOneWidget);
      expect(promotions, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    skip: !runClockTests,
  );
}
