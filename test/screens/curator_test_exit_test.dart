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
          attempts.add(Map<String, dynamic>.from(jsonDecode(request.body)));
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

  void noWrites() {
    expect(attempts, isEmpty);
    expect(ledger, isEmpty);
    expect(promotions, 0);
    expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
  }

  for (final nested in [false, true]) {
    testWidgets(
      '${nested ? 'nested Menu' : 'root'}: cancel, exit and restart twice without writes',
      (tester) async {
        await fixture.mount(
          tester,
          nested ? const AppShell() : const MenuScreen(),
        );
        if (nested) await tap(tester, 'Menu');
        await enter(tester);
        for (var run = 0; run < 2; run++) {
          expect(
            tester
                .widget<ElevatedButton>(
                  find.widgetWithText(ElevatedButton, 'Next Question'),
                )
                .onPressed,
            isNull,
          );
          await tap(tester, 'Hello');
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();
          expect(find.text('End the test?'), findsOneWidget);
          await tap(tester, 'Keep going');
          expect(find.byType(CuratorTestScreen), findsOneWidget);
          expect(
            tester
                .widget<ElevatedButton>(
                  find.widgetWithText(ElevatedButton, 'Next Question'),
                )
                .onPressed,
            isNotNull,
          );
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();
          await tap(tester, 'End test');
          expect(find.text('End the test?'), findsNothing);
          expect(find.byType(CuratorTestScreen), findsNothing);
          expect(find.text('Test Rules'), findsOneWidget);
          noWrites();
          expect(tester.takeException(), isNull);
          await start(tester);
        }
        // Leave the fresh, unanswered third run cleanly as well.
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        await tap(tester, 'End test');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Explorer'), findsOneWidget);
        noWrites();
        if (capture != null && nested) {
          await capture(tester, 'curator-exit-menu');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('system Back goes to previous question then confirms exit once', (
    tester,
  ) async {
    await fixture.mount(tester, const AppShell());
    await tap(tester, 'Menu');
    await enter(tester);
    await tap(tester, 'Hello');
    await tap(tester, 'Next Question');
    final second = tester
        .widget<Text>(find.textContaining('Greeting question').first)
        .data;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('End the test?'), findsNothing);
    expect(
      tester.widget<Text>(find.textContaining('Greeting question').first).data,
      isNot(second),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('End the test?'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('End the test?'), findsNothing);
    expect(find.byType(CuratorTestScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tap(tester, 'End test');
    expect(find.text('Test Rules'), findsOneWidget);
    noWrites();
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
    expect(find.text('End the test?'), findsOneWidget);
    await tap(tester, 'Keep going');
    expect(find.text('End the test?'), findsNothing);
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
    expect(find.text('End the test?'), findsNothing);
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
      await tap(tester, 'End test');
      expect(find.text('End the test?'), findsNothing);
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
