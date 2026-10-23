import 'dart:async';
import 'dart:convert';
import 'package:awalingo/services/notification_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RouteCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void main() {
  for (final lookupResult in [
    <String, Object>{'languageId': 2},
    null,
  ]) {
    testWidgets(
      'auth change during vote lookup cancels ${lookupResult == null ? 'fallback' : 'detail'} navigation',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final queryStarted = Completer<void>(),
            response = Completer<http.Response>();
        late http.Request query;
        await Supabase.initialize(
          url: 'https://routing.test',
          publishableKey: 'fixture',
          authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            localStorage: EmptyLocalStorage(),
          ),
          httpClient: MockClient((request) async {
            query = request;
            queryStarted.complete();
            return response.future;
          }),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await Supabase.instance.dispose();
        });
        final observer = _RouteCounter();
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        var currentSession = true;
        final navigation = openNotificationLink(
          context,
          'A',
          '/vote?termId=7',
          canNavigate: () => currentSession,
        );
        await tester.pump();
        await queryStarted.future;
        currentSession = false;
        response.complete(
          http.Response(
            jsonEncode(lookupResult),
            200,
            request: query,
            headers: {'content-type': 'application/json'},
          ),
        );
        await navigation;
        expect(
          observer.pushes,
          1,
          reason: 'Only the initial route remains after logout/account switch',
        );
      },
    );
  }
}
