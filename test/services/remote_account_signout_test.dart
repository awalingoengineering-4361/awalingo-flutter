import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:awalingo/services/auth_provider.dart';

class _SessionStorage extends GotrueAsyncStorage {
  Completer<void>? removal;
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {
    await removal?.future;
  }
}

Map<String, dynamic> fixtureUser(String id) => {
  'id': id,
  'aud': 'authenticated',
  'app_metadata': {},
  'user_metadata': {},
  'created_at': '2026-11-07T10:00:00Z',
};
Future<void> installSession(String owner, String token) async {
  await Supabase.instance.client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'user': fixtureUser(owner),
    }),
  );
  await Future<void>.delayed(Duration.zero);
}

void main() => remoteAccountSignoutTests();
void remoteAccountSignoutTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthNotifier notifier;
  late _SessionStorage storage;
  late Future<http.Response> Function(http.Request) respond;
  var userChecks = 0;
  var cleanups = 0;
  var failCleanup = false;
  Completer<http.Response>? pendingLogout;
  setUp(() async {
    userChecks = cleanups = 0;
    failCleanup = false;
    pendingLogout = null;
    storage = _SessionStorage();
    SharedPreferences.setMockInitialValues({});
    respond = (_) async =>
        http.Response('{"code":"user_not_found","msg":"User not found"}', 403);
    await Supabase.initialize(
      url: 'https://remote-signout.test',
      publishableKey: 'fixture-key',
      authOptions: FlutterAuthClientOptions(
        pkceAsyncStorage: storage,
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/user')) {
          userChecks++;
          return respond(request);
        }
        if (request.url.path.endsWith('/token')) return respond(request);
        if (request.url.path.endsWith('/logout')) {
          return pendingLogout?.future ?? http.Response('{}', 200);
        }
        throw StateError('Unexpected request: ${request.url.path}');
      }),
    );
    await installSession('deleted-owner', 'fixture-token');
    notifier = AuthNotifier(
      beforeSignOut: () async {
        cleanups++;
        if (failCleanup) throw StateError('Push cleanup unavailable');
      },
    );
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    notifier.dispose();
    await Supabase.instance.dispose();
  });

  test(
    'remote deletion clears cached auth even when push cleanup fails',
    () async {
      failCleanup = true;
      expect(notifier.isAuthenticated, isTrue);
      await notifier.revalidateSession();
      expect(notifier.isAuthenticated, isFalse);
      expect(Supabase.instance.client.auth.currentSession, isNull);
      expect(cleanups, 1);
    },
  );
  test('an active remote account remains signed in', () async {
    respond = (_) async =>
        http.Response(jsonEncode(fixtureUser('deleted-owner')), 200);
    await notifier.revalidateSession();
    expect(notifier.isAuthenticated, isTrue);
    expect(cleanups, 0);
  });
  test(
    'offline validation preserves state, then reconnect clears deleted account',
    () async {
      respond = (_) async => throw http.ClientException('offline');
      await notifier.revalidateSession();
      expect(notifier.isAuthenticated, isTrue);
      respond = (_) async =>
          http.Response('{"code":"user_not_found","msg":"Gone"}', 403);
      await notifier.revalidateSession();
      expect(notifier.isAuthenticated, isFalse);
    },
  );
  test('server outage preserves the local session', () async {
    respond = (_) async => http.Response('{"msg":"Unavailable"}', 503);
    await notifier.revalidateSession();
    expect(notifier.isAuthenticated, isTrue);
    expect(cleanups, 0);
  });
  test('a delayed rejection cannot sign out another account', () async {
    final pending = Completer<http.Response>();
    respond = (_) => pending.future;
    final checking = notifier.revalidateSession();
    await Future<void>.delayed(Duration.zero);
    await installSession('next-owner', 'next-token');
    pending.complete(
      http.Response('{"code":"user_not_found","msg":"Gone"}', 403),
    );
    await checking;
    expect(notifier.user?.id, 'next-owner');
    expect(
      Supabase.instance.client.auth.currentSession?.accessToken,
      'next-token',
    );
    expect(cleanups, 0);
  });
  test(
    'a delayed rejection cannot sign out a fresh session for the same account',
    () async {
      final pending = Completer<http.Response>();
      respond = (_) => pending.future;
      final checking = notifier.revalidateSession();
      await Future<void>.delayed(Duration.zero);
      await installSession('deleted-owner', 'new-token');
      pending.complete(
        http.Response('{"code":"session_not_found","msg":"Gone"}', 403),
      );
      await checking;
      expect(notifier.isAuthenticated, isTrue);
      expect(
        Supabase.instance.client.auth.currentSession?.accessToken,
        'new-token',
      );
      expect(cleanups, 0);
    },
  );
  test('expired tokens refresh before validating an active account', () async {
    final refreshCalls = <String>[];
    respond = (request) async {
      refreshCalls.add(request.url.path);
      if (request.url.path.endsWith('/token')) {
        return http.Response(
          jsonEncode({
            'access_token': 'refreshed-token',
            'refresh_token': 'next-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            'user': fixtureUser('deleted-owner'),
          }),
          200,
        );
      }
      return http.Response(jsonEncode(fixtureUser('deleted-owner')), 200);
    };
    await Supabase.instance.client.auth.setInitialSession(
      jsonEncode({
        'access_token':
            'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': 1})))}.fixture',
        'refresh_token': 'fixture-refresh',
        'token_type': 'bearer',
        'expires_in': -3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600,
        'user': fixtureUser('deleted-owner'),
      }),
    );
    await notifier.revalidateSession();
    expect(notifier.isAuthenticated, isTrue);
    expect(
      Supabase.instance.client.auth.currentSession?.accessToken,
      'refreshed-token',
    );
    expect(refreshCalls, contains('/auth/v1/token'));
    expect(refreshCalls, contains('/auth/v1/user'));
    expect(cleanups, 0);
  });

  test(
    'a delayed logout cannot clear a new session for the same account',
    () async {
      pendingLogout = Completer<http.Response>();
      final checking = notifier.revalidateSession();
      for (var i = 0; i < 10 && cleanups == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await installSession('deleted-owner', 'next-login-token');
      pendingLogout!.complete(http.Response('{}', 200));
      await checking;
      expect(
        Supabase.instance.client.auth.currentSession?.accessToken,
        'next-login-token',
      );
      expect(notifier.isAuthenticated, isTrue);
    },
  );

  test(
    'refresh followed by authoritative user rejection clears the refreshed session',
    () async {
      respond = (request) async {
        if (request.url.path.endsWith('/token')) {
          return http.Response(
            jsonEncode({
              'access_token': 'refreshed-invalid-token',
              'refresh_token': 'next-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': fixtureUser('deleted-owner'),
            }),
            200,
          );
        }
        return http.Response('{"code":"user_not_found","msg":"Gone"}', 403);
      };
      await Supabase.instance.client.auth.setInitialSession(
        jsonEncode({
          'access_token':
              'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': 1})))}.fixture',
          'refresh_token': 'fixture-refresh',
          'token_type': 'bearer',
          'user': fixtureUser('deleted-owner'),
        }),
      );
      await notifier.revalidateSession();
      expect(notifier.isAuthenticated, isFalse);
      expect(Supabase.instance.client.auth.currentSession, isNull);
    },
  );

  for (final nextOwner in ['deleted-owner', 'another-owner']) {
    test(
      'delayed signedOut event preserves newer session for $nextOwner',
      () async {
        storage.removal = Completer<void>();
        final checking = notifier.revalidateSession();
        for (
          var i = 0;
          i < 20 && Supabase.instance.client.auth.currentSession != null;
          i++
        ) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(Supabase.instance.client.auth.currentSession, isNull);
        await installSession(nextOwner, 'new-login-during-storage');
        storage.removal!.complete();
        await checking;
        await Future<void>.delayed(Duration.zero);
        expect(notifier.user?.id, nextOwner);
        expect(
          Supabase.instance.client.auth.currentSession?.accessToken,
          'new-login-during-storage',
        );
      },
    );
  }

  test('duplicate foreground checks share the same request', () async {
    final pending = Completer<http.Response>();
    respond = (_) => pending.future;
    final first = notifier.revalidateSession();
    final second = notifier.revalidateSession();
    await Future<void>.delayed(Duration.zero);
    expect(userChecks, 1);
    pending.complete(
      http.Response('{"code":"user_not_found","msg":"Gone"}', 403),
    );
    await Future.wait([first, second]);
    expect(notifier.isAuthenticated, isFalse);
    expect(cleanups, 1);
  });
}
