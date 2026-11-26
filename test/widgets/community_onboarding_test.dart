import 'dart:convert';

import 'package:awalingo/main.dart';
import 'package:awalingo/screens/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/remote_account_signout_test.dart'
    show fixtureUser, installSession;

void main() {
  final communities = <String, int>{};
  var failMembershipRead = false;
  var failSave = false;

  setUp(() async {
    communities.clear();
    failMembershipRead = false;
    failSave = false;
    SharedPreferences.setMockInitialValues({'has_seen_onboarding': true});
    await Supabase.initialize(
      url: 'https://community.test',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        http.Response response(Object? value, [int status = 200]) =>
            http.Response(jsonEncode(value), status, request: request);
        final owner = request.headers['authorization']!.split(' ').last;
        switch (request.url.path) {
          case '/auth/v1/user':
            return response(fixtureUser(owner));
          case '/auth/v1/logout':
            return response(null);
          case '/rest/v1/user_target_languages':
            if (failMembershipRead)
              return response({'message': 'Unavailable'}, 500);
            final language = communities[owner];
            return response([
              if (language != null)
                {
                  'languageId': language,
                  'language': {'id': language, 'name': 'Yoruba'},
                },
            ]);
          case '/rest/v1/languages':
            final rows = [
              {'id': 7, 'name': 'Yoruba', 'icon': 'NG', 'is_supported': true},
              {'id': 8, 'name': 'Akan', 'icon': 'GH', 'is_supported': true},
              {'id': 9, 'name': 'Igbo', 'icon': 'NG', 'is_supported': false},
            ];
            return response(
              request.url.queryParameters['is_supported'] == 'eq.true'
                  ? rows.where((row) => row['is_supported'] == true).toList()
                  : rows,
            );
          case '/rest/v1/rpc/complete_community_onboarding':
            if (failSave) return response({'message': 'Unavailable'}, 503);
            final data = jsonDecode(request.body) as Map<String, dynamic>;
            communities.putIfAbsent(owner, () => data['p_language_id'] as int);
            return response(null);
          default:
            return response([]);
        }
      }),
    );
  });

  tearDown(() => Supabase.instance.dispose());

  Future<void> pumpApp(WidgetTester tester, {String? owner}) async {
    if (owner != null)
      await tester.runAsync(() => installSession(owner, owner));
    await tester.pumpWidget(const AwalingoApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await pumpFrames(tester);
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('unsupported communities are visible but cannot be selected', (
    tester,
  ) async {
    await pumpApp(tester, owner: 'new-owner');

    expect(find.text('Choose Your Awalingo Community'), findsOneWidget);
    expect(find.text('Rep your mother tongue.'), findsOneWidget);
    expect(find.text('🇳🇬'), findsNWidgets(2));
    expect(find.text('🇬🇭'), findsOneWidget);

    final submit = find.widgetWithText(ElevatedButton, 'Complete Profile');
    final group = find.byType(RadioGroup<int>);
    expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);
    expect(tester.widget<RadioGroup<int>>(group).groupValue, isNull);

    final unsupported = find.widgetWithText(RadioListTile<int>, 'Igbo');
    expect(unsupported, findsOneWidget);
    expect(tester.widget<RadioListTile<int>>(unsupported).enabled, isFalse);
    await tester.tap(unsupported);
    await tester.pump();
    expect(tester.widget<RadioGroup<int>>(group).groupValue, isNull);
    expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);
    expect(communities, isEmpty);

    await tester.tap(find.text('Yoruba'));
    await tester.pump();
    expect(tester.widget<RadioGroup<int>>(group).groupValue, 7);
    expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);

    await tester.tap(find.text('Akan'));
    await tester.pump();
    expect(tester.widget<RadioGroup<int>>(group).groupValue, 8);
    await tester.tap(unsupported);
    await tester.pump();
    expect(tester.widget<RadioGroup<int>>(group).groupValue, 8);
    await tester.tap(submit);
    await pumpFrames(tester);
    expect(communities, {'new-owner': 8});
    await closeApp(tester);
  });

  testWidgets(
    'Google-style auth event checks the recreated account community',
    (tester) async {
      await pumpApp(tester);
      await tester.runAsync(() => installSession('first-owner', 'first-owner'));
      await pumpFrames(tester);
      expect(find.text('Complete Profile'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      await tester.tap(find.text('Yoruba'));
      await tester.pump();
      await tester.tap(find.text('Complete Profile'));
      await pumpFrames(tester);
      expect(communities['first-owner'], 7);
      expect(find.byType(AppShell), findsOneWidget);

      await tester.runAsync(() => installSession('new-owner', 'new-owner'));
      await pumpFrames(tester);
      expect(find.text('Complete Profile'), findsOneWidget);
      expect(communities['new-owner'], isNull);
      expect(find.byType(AppShell), findsNothing);
      await tester.tap(find.text('Yoruba'));
      await tester.pump();
      await tester.tap(find.text('Complete Profile'));
      await pumpFrames(tester);
      expect(communities, {'first-owner': 7, 'new-owner': 7});
      expect(find.byType(AppShell), findsOneWidget);
      await closeApp(tester);
    },
  );

  testWidgets('a restored account with a community goes straight to Home', (
    tester,
  ) async {
    communities['returning-owner'] = 7;
    await pumpApp(tester, owner: 'returning-owner');
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Complete Profile'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('community lookup and save failures allow retry without bypass', (
    tester,
  ) async {
    failMembershipRead = true;
    await pumpApp(tester, owner: 'new-owner');
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    failMembershipRead = false;
    await tester.tap(find.text('Retry'));
    await pumpFrames(tester);

    await tester.tap(find.text('Yoruba'));
    failSave = true;
    await tester.tap(find.text('Complete Profile'));
    await pumpFrames(tester);
    expect(communities, isEmpty);
    expect(find.byType(AppShell), findsNothing);
    failSave = false;
    await tester.tap(find.text('Complete Profile'));
    await pumpFrames(tester);
    expect(communities, {'new-owner': 7});
    expect(find.byType(AppShell), findsOneWidget);
    await closeApp(tester);
  });
}

Future<void> pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 15; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
