import 'package:awalingo/services/load_failure.dart';
import 'package:awalingo/widgets/load_failure_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('offline Retry works in $brightness', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: LoadFailureView(
              failure: LoadFailure.fromError(
                http.ClientException('secret details'),
              ),
              onRetry: () => retries++,
            ),
          ),
        ),
      );
      expect(find.text('You are offline'), findsOneWidget);
      expect(find.textContaining('secret details'), findsNothing);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact failure fits a narrow scrolling list', (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              LoadFailureView(
                compact: true,
                failure: LoadFailure.fromError(
                  http.ClientException('connection failed'),
                ),
                onRetry: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Retry'));
    expect(tester.takeException(), isNull);
  });
}
