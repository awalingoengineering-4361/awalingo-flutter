import 'package:awalingo/screens/main/curator_test_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/offline_fixture.dart';

void main() {
  late OfflineFixture fixture;

  setUp(() async {
    fixture = OfflineFixture();
    await fixture.initialize();
    fixture.offline = false;
    // More than the 10 a test uses, so there are spares to swap in.
    fixture.questions = List.generate(
      12,
      (i) => {
        'id': i + 1,
        'text': 'Greeting question ${i + 1}',
        'options': [
          {'label': 'A', 'value': 'hello'},
          {'label': 'B', 'value': 'goodbye'},
        ],
        'correctAnswer': 'hello',
      },
    );
  });
  tearDown(() => fixture.dispose());

  String currentQuestion(WidgetTester tester) => tester
      .widget<Text>(find.textContaining('Greeting question').first)
      .data!;

  ButtonStyleButton nextButton(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Next Question'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );

  Future<void> leaveAndReturn(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('leaving the app replaces the current question', (tester) async {
    await fixture.mount(tester, const CuratorTestScreen());
    final before = currentQuestion(tester);
    await tester.tap(find.text('hello'));
    await tester.pumpAndSettle();
    expect(nextButton(tester).onPressed, isNotNull);

    await leaveAndReturn(tester);

    expect(currentQuestion(tester), isNot(before));
    // The previous answer doesn't carry over to the new question.
    expect(nextButton(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a brief inactive overlay keeps the question', (tester) async {
    await fixture.mount(tester, const CuratorTestScreen());
    final before = currentQuestion(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(currentQuestion(tester), before);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
