import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:awalingo/services/auth_provider.dart';
import 'package:awalingo/services/theme_notifier.dart';
import 'package:awalingo/screens/main/awaquiz_screen.dart';
import 'package:awalingo/screens/main/curator_test_screen.dart';
import 'package:awalingo/screens/main/dictionary_screen.dart';
import 'package:awalingo/screens/main/my_word_requests_screen.dart';
import 'package:awalingo/screens/main/request_screen.dart';
import 'package:awalingo/screens/main/translate_screen.dart';
import 'package:awalingo/screens/main/vote_screen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import '../support/offline_fixture.dart';

void main() => offlineRecoveryTests();

void offlineRecoveryTests({
  Future<void> Function(WidgetTester, String)? capture,
  bool screenshotsOnly = false,
}) {
  void runCase(String name, WidgetTesterCallback body) {
    testWidgets(name, body, skip: screenshotsOnly && !(
      name == 'AwaQuiz: offline → retry → recover twice' ||
      name == 'Voting Lounge: offline → retry → recover twice'));
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineFixture fixture;
  setUp(() async {
    fixture = OfflineFixture();
    await fixture.initialize();
  });
  tearDown(() => fixture.dispose());
  runCase('AwaQuiz: disconnect during parallel overview reads', (
    tester,
  ) async {
    fixture.offline = false;
    fixture.intercept = (request) async {
      if (request.url.pathSegments.last == 'user_profile') {
        throw http.ClientException('connection lost');
      }
      return fixture.respond(request);
    };
    await fixture.mount(tester, const AwaQuizScreen(languageId: 2));
    expect(find.text('You are offline'), findsOneWidget);
    fixture.intercept = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('You are offline'), findsNothing);
    expect(find.text('Unable to load'), findsNothing);
  });
  for (final entry in <String, Widget Function()>{
    'AwaDiko': () => const DictionaryScreen(),
    'Voting': () => const VoteScreen(),
    'Translation': () => const TranslateScreen(),
  }.entries) {
    runCase('${entry.key}: disconnect during language switch and recover', (
      tester,
    ) async {
      fixture.offline = false;
      await fixture.mount(tester, entry.value());
      fixture.offline = true;
      await tester.tap(
        find.text(entry.key == 'Translation' ? 'YR' : 'EN').first,
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();
      expect(find.text('You are offline'), findsOneWidget);
      expect(find.text('Word Not Found'), findsNothing);
      fixture.offline = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('You are offline'), findsNothing);
      expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
    });
  }
  runCase(
    'AwaDiko: failed next page preserves words and retries same offset',
    (tester) async {
      fixture.offline = false;
      fixture.terms = List.generate(
        25,
        (i) => {
          'id': i + 1,
          'text': 'Apple${i.toString().padLeft(2, '0')}',
          'meaning': 'A fruit',
          'neos': <Object>[],
        },
      );
      await fixture.mount(tester, const DictionaryScreen());
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      fixture.offline = true;
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('You are offline'), findsOneWidget);
      expect(find.text('Apple19'), findsOneWidget);
      fixture.offline = false;
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('You are offline'), findsNothing);
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Apple24'), findsOneWidget);
      final offsets = fixture.requests
          .where(
            (r) =>
                r.url.queryParameters['select'] != 'text' &&
                r.url.pathSegments.last == 'terms',
          )
          .map((r) => r.url.queryParameters['offset']);
      expect(offsets.first, '0');
      expect(offsets.skip(1), everyElement('20'));
      expect(tester.takeException(), isNull);
    },
  );
  runCase(
    'Request: failed explicit submit preserves entered text without writes',
    (tester) async {
      fixture.offline = false;
      await fixture.mount(tester, const RequestScreen());
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Preserved word',
      );
      await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Noun').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Preserved meaning',
      );
      fixture.offline = true;
      await tester.ensureVisible(find.text('Submit Request'));
      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();
      expect(find.textContaining('You are offline.'), findsOneWidget);
      expect(find.text('Preserved word'), findsOneWidget);
      expect(find.text('Preserved meaning'), findsOneWidget);
      final count = fixture.requests.length;
      fixture.offline = false;
      await tester.pump(const Duration(seconds: 20));
      expect(fixture.requests.length, count);
      expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  runCase('AwaDiko: latest search wins over delayed earlier results', (
    tester,
  ) async {
    fixture.offline = false;
    fixture.terms = [
      {'id': 1, 'text': 'Apple', 'meaning': 'fruit'},
    ];
    await fixture.mount(tester, const DictionaryScreen());
    final delayed = Completer<http.Response>();
    fixture.intercept = (request) async {
      final filter = request.url.queryParameters['or'] ?? '';
      if (filter.contains('older')) return delayed.future;
      if (filter.contains('newer')) {
        return http.Response(
          '[{"id":2,"text":"Newer result","meaning":"new"}]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      return fixture.respond(request);
    };
    await tester.enterText(find.byType(TextField), 'older');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'newer');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Newer result'), findsOneWidget);
    delayed.complete(
      http.Response(
        '[{"id":3,"text":"Stale result","meaning":"old"}]',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stale result'), findsNothing);
    expect(find.text('Newer result'), findsOneWidget);
  });
  runCase(
    'Curator: repeated failed retries start only one timer after recovery',
    (tester) async {
      await fixture.mount(tester, const CuratorTestScreen());
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('You are offline'), findsOneWidget);
      fixture.offline = false;
      fixture.questions = [
        {
          'id': 1,
          'text': 'Fixture question',
          'options': [
            {'label': 'A', 'value': 'yes'},
            {'label': 'B', 'value': 'no'},
          ],
          'correctAnswer': 'yes',
        },
      ];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Fixture question'), findsOneWidget);
      final timers = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => RegExp(r'^\d\d:\d\d$').hasMatch(s))
          .toList();
      expect(timers, hasLength(1));
      final before = timers.single.split(':').map(int.parse).toList();
      await tester.pump(const Duration(seconds: 1));
      final remaining = before[0] * 60 + before[1] - 1;
      expect(
        find.text(
          '${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}',
        ),
        findsOneWidget,
      );
      expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
  for (final screen in <Widget>[
    const AwaQuizScreen(),
    const CuratorTestScreen(),
    const DictionaryScreen(),
    const VoteScreen(),
    const TranslateScreen(),
    const RequestScreen(),
    const MyWordRequestsScreen(),
  ]) {
    runCase('${screen.runtimeType}: late load after disposal is ignored', (
      tester,
    ) async {
      fixture.offline = false;
      final delayed = Completer<http.Response>();
      http.Request? pending;
      fixture.intercept = (request) {
        pending = request;
        return delayed.future;
      };
      await tester.pumpWidget(
        AuthProvider(
          notifier: fixture.auth,
          child: ThemeProvider(
            notifier: fixture.theme,
            child: MaterialApp(home: screen),
          ),
        ),
      );
      await tester.pump();
      expect(pending, isNotNull);
      await tester.pumpWidget(const SizedBox());
      delayed.complete(fixture.respond(pending!));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  runCase('Voting: populated recovery and repeat failure on same mounted screen', (tester) async {
    expect(Supabase.instance.client.auth.currentUser?.id, 'offline-user');
    fixture.offline = false;
    var failCandidates = true;
    fixture.intercept = (request) async {
      if (request.url.pathSegments.last == 'neos' && failCandidates) {
        throw http.ClientException('candidate connection lost');
      }
      if (!fixture.offline && request.url.pathSegments.last == 'neos') {
        return http.Response('[{"id":1,"termId":1,"ratingCount":2,"rejectCount":0,"createdAt":"2026-10-16T00:00:00Z"}]', 200,
          headers: {'content-type': 'application/json'}, request: request);
      }
      return fixture.respond(request);
    };
    fixture.terms = [{'id': 1, 'text': 'Populated voting term', 'meaning': 'Fixture meaning', 'partOfSpeech': {'name': 'Noun'}}];
    await fixture.mount(tester, const VoteScreen());
    expect(find.text('You are offline'), findsOneWidget);
    failCandidates = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Populated voting term'), findsOneWidget);
    fixture.offline = true;
    // The English switch reloads bootstrap, then the real authenticated reads.
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    expect(find.text('You are offline'), findsOneWidget);
    fixture.offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Populated voting term'), findsOneWidget);
    expect(fixture.requests.any((r) => r.url.pathSegments.last == 'neo_rating'), isTrue);
    expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
  });
  final cases = <String, Widget Function()>{
    'AwaQuiz': () => const AwaQuizScreen(),
    'Curator Test': () => const CuratorTestScreen(),
    'AwaDiko': () => const DictionaryScreen(),
    'Voting Lounge': () => const VoteScreen(),
    'Jury Lounge': () => const VoteScreen(isJuror: true),
    'Translation Lounge': () => const TranslateScreen(),
    'Request a Word': () => const RequestScreen(),
    'Word Requests': () => const MyWordRequestsScreen(),
  };
  for (final entry in cases.entries) {
    runCase('${entry.key}: offline → retry → recover twice', (
      tester,
    ) async {
      for (var run = 0; run < 2; run++) {
        fixture.offline = true;
        await fixture.mount(tester, entry.value());
        expect(
          find.text('You are offline'),
          findsOneWidget,
          reason:
              '${entry.key} run $run: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
        );
        expect(find.textContaining('private.host'), findsNothing);
        expect(find.text('COM'), findsNothing);
        expect(find.text('NEO'), findsNothing);
        expect(find.text('No word requests yet'), findsNothing);
        expect(find.text('Word Not Found'), findsNothing);
        expect(find.byType(TextFormField), findsNothing);
        if (run == 0 &&
            capture != null &&
            ['AwaQuiz', 'Voting Lounge'].contains(entry.key)) {
          await capture(tester, '${entry.key}-offline');
        }
        fixture.offline = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('You are offline'), findsNothing);
        expect(find.text('Unable to load'), findsNothing);
        if (entry.key == 'Request a Word')
          expect(find.byType(TextFormField), findsNWidgets(2));
        if (entry.key == 'AwaDiko')
          expect(find.text('Word Not Found'), findsOneWidget);
        if (entry.key == 'Word Requests')
          expect(find.text('No word requests yet'), findsOneWidget);
        if (entry.key == 'Curator Test') {
          expect(
            find.textContaining('No questions are currently available'),
            findsOneWidget,
          );
        }
        if (entry.key.contains('Lounge'))
          expect(find.text('YR'), findsOneWidget);
        if (run == 0 && capture != null && entry.key == 'Voting Lounge') {
          await capture(tester, 'Voting Lounge-recovered');
        }
        expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });
    runCase('${entry.key}: server errors are distinct from offline', (
      tester,
    ) async {
      fixture.offline = false;
      fixture.serverError = true;
      await fixture.mount(tester, entry.value());
      expect(find.text('Unable to load'), findsOneWidget);
      expect(find.text('You are offline'), findsNothing);
      expect(find.textContaining('private permission'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
