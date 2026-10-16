import 'dart:convert';
import 'package:awalingo/services/auth_provider.dart';
import 'package:awalingo/services/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FixtureAuth extends AuthNotifier {
  @override
  User get user => User(
    id: 'offline-user',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-10-16',
  );
}

class OfflineFixture {
  bool offline = true;
  bool serverError = false;
  final requests = <http.Request>[];
  List<Map<String, dynamic>> terms = [];
  List<Map<String, dynamic>> questions = [];
  Future<http.Response> Function(http.Request)? intercept;
  late FixtureAuth auth;
  late ThemeNotifier theme;

  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://offline.test',
      publishableKey: 'fixture-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (intercept != null) return intercept!(request);
        return respond(request);
      }),
    );
    // Local-only fixture session: no authentication request or real credentials.
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token': 'fixture-token', 'token_type': 'bearer',
      'user': {'id': 'offline-user', 'aud': 'authenticated',
        'app_metadata': {}, 'user_metadata': {}, 'created_at': '2026-10-16'},
    }));
    auth = FixtureAuth();
    theme = ThemeNotifier();
  }

  http.Response respond(http.Request request) {
    if (offline)
      throw http.ClientException(
        'SocketException: private.host:54321',
        request.url,
      );
    if (serverError)
      return http.Response(
        '{"code":"42501","message":"private permission failure"}',
        403,
        request: request,
      );
    if (request.method != 'GET')
      throw StateError('Unexpected mutation: ${request.method} ${request.url}');
    final table = request.url.pathSegments.last;
    final select = request.url.queryParameters['select'] ?? '';
    Object? data;
    switch (table) {
      case 'languages':
        data = {'id': 1};
      case 'user_target_languages':
        data = select == 'languageId'
            ? {'languageId': 2}
            : {
                'language': {'id': 2, 'name': 'Yoruba', 'short': 'YR'},
              };
      case 'part_of_speech':
        data = [
          {'id': 1, 'name': 'Noun'},
        ];
      case 'user_roles':
        data = {
          'role': {'name': 'EXPLORER'},
        };
      case 'user_profile':
        data = {'cowryBalance': 10};
      case 'terms':
        final start = int.parse(request.url.queryParameters['offset'] ?? '0');
        final limit = int.parse(request.url.queryParameters['limit'] ?? '1000');
        var result = terms;
        final filter = request.url.queryParameters['text'];
        if (filter != null && filter.startsWith('ilike.')) {
          final prefix = filter.substring(6).replaceAll('%', '').toLowerCase();
          result = result
              .where(
                (t) => (t['text'] as String).toLowerCase().startsWith(prefix),
              )
              .toList();
        }
        data = select == 'text'
            ? result
                  .skip(start)
                  .take(limit)
                  .map((t) => {'text': t['text']})
                  .toList()
            : result.skip(start).take(limit).toList();
      case 'quiz_questions':
        data = questions;
      case 'community_quiz_sets':
      case 'community_quiz_questions':
      case 'community_quiz_attempts':
      case 'translation_requests':
      case 'neos':
      case 'neo_rating':
      case 'defered_term':
      case 'votes':
        data = <Object>[];
      default:
        throw StateError('Unexpected read: ${request.url}');
    }
    return http.Response(
      jsonEncode(data),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }

  Future<void> mount(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      AuthProvider(
        notifier: auth,
        child: ThemeProvider(
          notifier: theme,
          child: MaterialApp(home: Material(child: screen)),
        ),
      ),
    );
    // AwaQuiz has a static loading label, so settle alone can return while
    // PostgREST is waiting between its bounded transport retries.
    for (var i = 0; i < 100 && find.text('Loading quiz...').evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    auth.dispose();
    theme.dispose();
    await Supabase.instance.dispose();
  }
}
