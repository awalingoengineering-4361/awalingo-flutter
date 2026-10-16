import 'package:awalingo/screens/main/awaquiz_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../support/offline_fixture.dart';

void main() => awaQuizLayoutTests();

void awaQuizLayoutTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineFixture fixture;
  setUpAll(() async {
    for (final family in ['Metropolis', 'Parkinsans']) {
      final extension = family == 'Metropolis' ? 'otf' : 'ttf';
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(
          rootBundle.load('assets/fonts/$family-$weight.$extension'),
        );
      }
      await loader.load();
    }
  });
  setUp(() async {
    fixture = OfflineFixture()..offline = false;
    await fixture.initialize();
    fixture.intercept = (request) async {
      final table = request.url.pathSegments.last;
      if (table == 'community_quiz_sets') {
        return http.Response(
          '[{"id":11,"difficulty":"BEGINNER","questionCount":10},'
          '{"id":22,"difficulty":"INTERMEDIATE","questionCount":10},'
          '{"id":33,"difficulty":"ADVANCED","questionCount":10}]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      if (table == 'community_quiz_questions') {
        return http.Response(
          '[{"setId":11},{"setId":22},{"setId":33}]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      return fixture.respond(request);
    };
  });
  tearDown(() => fixture.dispose());

  for (final width in [320.0, 360.0, 430.0, 800.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('quiz cards fit width $width with text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await fixture.mount(
          tester,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: AwaQuizScreen(languageId: 2, communityName: 'Yoruba'),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final previous in [
          'JJC',
          'Sabi Player',
          'Shugaba',
          'Odogwu',
          'Idan',
        ]) {
          final prerequisite = find.text('Score 100% on $previous');
          await tester.scrollUntilVisible(prerequisite, 250);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final content = find
              .ancestor(of: prerequisite, matching: find.byType(Column))
              .first;
          final locked = find.descendant(
            of: content,
            matching: find.widgetWithText(ElevatedButton, 'Locked'),
          );
          expect(locked, findsOneWidget);
          expect(tester.widget<ElevatedButton>(locked).onPressed, isNull);
          expect(tester.getRect(prerequisite).right, lessThanOrEqualTo(width));
          expect(tester.getRect(locked).right, lessThanOrEqualTo(width));
          if (previous == 'Sabi Player' && width == 360 && scale == 1) {
            expect(
              tester.getRect(locked).top,
              greaterThanOrEqualTo(tester.getRect(prerequisite).bottom),
            );
          }
        }
        expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
      });
    }
  }
}
