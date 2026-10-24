import 'dart:convert';
import 'package:awalingo/screens/main/request_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../support/offline_fixture.dart';

void main() {
  late OfflineFixture fixture;

  setUp(() async {
    fixture = OfflineFixture();
    await fixture.initialize();
    fixture.offline = false;
    fixture.intercept = (request) async {
      final query = request.url.queryParameters;
      // The pre-insert duplicate check (word + meaning match) finds a row.
      if (request.url.pathSegments.last == 'translation_requests' &&
          query.containsKey('word')) {
        return http.Response(
          jsonEncode([
            {'id': 1},
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      return fixture.respond(request);
    };
  });
  tearDown(() => fixture.dispose());

  testWidgets('duplicate request is flagged with a red error', (tester) async {
    await fixture.mount(tester, const RequestScreen());

    await tester.enterText(find.byType(TextFormField).at(0), 'Hello');
    await tester.enterText(find.byType(TextFormField).at(1), 'A greeting');
    await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Noun').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit Request'));
    await tester.tap(find.text('Submit Request'));
    await tester.pumpAndSettle();

    const message =
        'This word with the same meaning has already been requested. Please be patient.';
    expect(find.text(message), findsOneWidget);
    final text = tester.widget<Text>(find.text(message));
    expect(text.style?.color, const Color(0xFFDC2626));
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.backgroundColor, const Color(0xFFFEF2F2));
    expect(
      fixture.requests.where((r) => r.method != 'GET'),
      isEmpty,
      reason: 'a duplicate must not be inserted',
    );
    expect(tester.takeException(), isNull);
  });
}
