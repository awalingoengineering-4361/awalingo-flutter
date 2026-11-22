import 'dart:convert';
import 'package:awalingo/main.dart';
import 'package:awalingo/services/auth_provider.dart';
import 'package:awalingo/screens/onboarding/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/remote_account_signout_test.dart'
    show fixtureUser, installSession;

void main() => remoteAccountLifecycleTests();
void remoteAccountLifecycleTests({
  Future<void> Function(WidgetTester)? capture,
}) {
  var deleted = false;
  setUp(() async {
    deleted = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://lifecycle.test',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/user')) {
          return deleted
              ? http.Response('{"code":"user_not_found","msg":"Gone"}', 403)
              : http.Response(jsonEncode(fixtureUser('deleted-owner')), 200);
        }
        if (request.url.path.endsWith('/logout')) {
          return http.Response('{}', 200);
        }
        throw StateError('Unexpected request: ${request.url.path}');
      }),
    );
    await installSession('deleted-owner', 'cached-token');
  });
  tearDown(() async {
    await Supabase.instance.dispose();
  });

  Future<void> awaitSignIn(WidgetTester tester) async {
    // The SDK's persistent-storage cleanup completes in the real async zone.
    final auth = tester
        .widget<AuthProvider>(find.byType(AuthProvider))
        .notifier!;
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && auth.isAuthenticated; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    for (
      var i = 0;
      i < 40 && find.text('Sign into Your Account').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> clean(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> openPrivateScreen(WidgetTester tester) async {
    await tester.pumpWidget(const AwalingoApp());
    await tester.pump();
    final navigator = Navigator.of(tester.element(find.byType(SplashScreen)));
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cached private screen')),
      ),
      (_) => false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Cached private screen'), findsOneWidget);
  }

  testWidgets('startup clears an account deleted while the app was closed', (
    tester,
  ) async {
    deleted = true;
    await tester.pumpWidget(const AwalingoApp());
    await awaitSignIn(tester);
    expect(find.text('Sign into Your Account'), findsOneWidget);
    expect(Supabase.instance.client.auth.currentSession, isNull);
    await clean(tester);
  });
  testWidgets('resume after remote deletion clears private navigation', (
    tester,
  ) async {
    await openPrivateScreen(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    deleted = true;
    if (capture == null) {
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Cached private screen'), findsOneWidget);
      expect(Supabase.instance.client.auth.currentSession, isNotNull);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await awaitSignIn(tester);
    expect(find.text('Cached private screen'), findsNothing);
    expect(find.text('Sign into Your Account'), findsOneWidget);
    expect(Supabase.instance.client.auth.currentSession, isNull);
    if (capture != null) await capture(tester);
    await clean(tester);
  });
  testWidgets(
    'a foreground device detects remote deletion on its next check',
    (tester) async {
      await openPrivateScreen(tester);
      deleted = true;
      await tester.pump(const Duration(seconds: 30));
      await awaitSignIn(tester);
      expect(find.text('Sign into Your Account'), findsOneWidget);
      expect(find.text('Cached private screen'), findsNothing);
      await clean(tester);
    },
    skip: capture != null,
  );
}
