import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awalingo/screens/main/account_deletion_screen.dart';
import 'package:awalingo/theme/app_theme.dart';

void main() => accountDeletionScreenTests();

void accountDeletionScreenTests({
  Future<void> Function(WidgetTester tester, String name)? capture,
}) {
  testWidgets(
    'requires confirmation, prevents duplicate taps, and reports request receipt',
    (tester) async {
      if (capture == null) {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      var calls = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AccountDeletionScreen(
            submit: () {
              calls++;
              return pending.future;
            },
            onAccepted: () async {},
          ),
        ),
      );
      await reveal(tester, find.byKey(const Key('request-deletion')), 200);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('request-deletion')))
            .onPressed,
        isNull,
      );
      await reveal(tester, find.byType(TextField), 200);
      await tester.enterText(find.byType(TextField), 'DELETE');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('request-deletion')));
      if (capture != null) {
        await capture(tester, 'account-deletion-confirmation');
      }
      await tester.tap(find.byKey(const Key('request-deletion')));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('request-deletion')))
            .onPressed,
        isNull,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Deletion requested'), findsOneWidget);
      expect(
        tester.getRect(find.text('Deletion requested')).left,
        greaterThanOrEqualTo(0),
      );
      if (capture != null) await capture(tester, 'account-deletion-requested');
      expect(find.textContaining('already deleted'), findsNothing);
    },
  );
  testWidgets('waits for local cleanup before allowing return to sign in', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cleanup = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AccountDeletionScreen(
          submit: () async {},
          onAccepted: () => cleanup.future,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('request-deletion')));
    await tester.tap(find.byKey(const Key('request-deletion')));
    await tester.pumpAndSettle();
    final returnButton = find.widgetWithText(FilledButton, 'Return to sign in');
    expect(tester.widget<FilledButton>(returnButton).onPressed, isNull);
    cleanup.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(returnButton).onPressed, isNotNull);
  });
  testWidgets('a failed request keeps confirmation available for retry', (
    tester,
  ) async {
    if (capture == null) {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AccountDeletionScreen(
          submit: () async {
            attempts++;
            if (attempts == 1) throw Exception('offline');
          },
          onAccepted: () async {},
        ),
      ),
    );
    await reveal(tester, find.byType(TextField), 200);
    await tester.enterText(find.byType(TextField), 'DELETE');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('request-deletion')));
    await tester.tap(find.byKey(const Key('request-deletion')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Please retry'), findsOneWidget);
    if (capture != null) await capture(tester, 'account-deletion-retry');
    await tester.tap(find.byKey(const Key('request-deletion')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Deletion requested'), findsOneWidget);
  });
}

Future<void> reveal(WidgetTester tester, Finder target, double delta) =>
    tester.scrollUntilVisible(
      target,
      delta,
      scrollable: find.byType(Scrollable).first,
    );
