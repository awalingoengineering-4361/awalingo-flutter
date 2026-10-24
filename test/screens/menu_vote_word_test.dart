import 'dart:convert';
import 'package:awalingo/screens/main/menu_screen.dart';
import 'package:awalingo/screens/main/vote_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../support/offline_fixture.dart';

void main() {
  late OfflineFixture fixture;
  late List<Map<String, dynamic>> votes;

  const terms = [
    {'id': 10, 'text': 'Alpha', 'meaning': '', 'partOfSpeech': null},
    {'id': 11, 'text': 'Bravo', 'meaning': '', 'partOfSpeech': null},
  ];

  int? eqInt(http.Request request, String column) {
    final value = request.url.queryParameters[column];
    return value != null && value.startsWith('eq.')
        ? int.tryParse(value.substring(3))
        : null;
  }

  setUp(() async {
    fixture = OfflineFixture();
    await fixture.initialize();
    fixture.offline = false;
    votes = [];
    fixture.intercept = (request) async {
      final table = request.url.pathSegments.last;
      final select = request.url.queryParameters['select'] ?? '';
      Object? data = <Object>[];
      switch (table) {
        case 'terms':
          final id = eqInt(request, 'id');
          data = id == null ? terms : terms.where((t) => t['id'] == id).toList();
        case 'neos':
          if (select == 'termId') {
            data = terms.map((t) => {'termId': t['id']}).toList();
          } else if (select.contains('text')) {
            final termId = eqInt(request, 'termId');
            data = [
              {
                'id': 100 + termId!,
                'text': 'neo-$termId',
                'type': 'POPULAR',
                'audioUrl': null,
                'ratingScore': 1,
                'ratingCount': 2,
                'rejectCount': 0,
              },
            ];
          }
        case 'votes':
          final termId = eqInt(request, 'termId');
          if (request.method == 'POST') {
            votes.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          } else if (request.method == 'DELETE') {
            votes.removeWhere((v) => v['termId'] == termId);
          } else {
            data = termId == null
                ? votes
                : votes.where((v) => v['termId'] == termId).toList();
          }
        case 'user_profile':
          data = request.method == 'GET'
              ? [
                  {'cowryBalance': 10},
                ]
              : null;
        case 'record_streak_activity':
          data = null;
        default:
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

  testWidgets('voting on the word of the day changes the Menu vote word', (
    tester,
  ) async {
    await fixture.mount(tester, const MenuScreen());

    final first = find.text('Alpha').evaluate().isNotEmpty ? 'Alpha' : 'Bravo';
    final second = first == 'Alpha' ? 'Bravo' : 'Alpha';
    expect(find.text(first), findsOneWidget);
    expect(find.text(second), findsNothing);

    // Vote opens the word of the day itself, not the Voting Lounge.
    final voteButton = find.text('Vote');
    await tester.ensureVisible(voteButton);
    await tester.tap(voteButton);
    await tester.pumpAndSettle();
    expect(find.byType(VoteDetailScreen), findsOneWidget);
    expect(find.text('Word of the Day'), findsOneWidget);
    expect(find.text(first), findsOneWidget);

    await tester.tap(find.text('Vote').first);
    await tester.pumpAndSettle();
    expect(votes.single['termId'], first == 'Alpha' ? 10 : 11);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(VoteDetailScreen), findsNothing);
    expect(find.text(second), findsOneWidget);
    expect(find.text(first), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
