import 'dart:async';
import 'dart:convert';
import 'package:awalingo/services/android_push_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'registration uses bearer and JSON token without leaking it in URL',
    () async {
      late http.Request sent;
      final api = HttpAndroidPushApi(
        origin: 'https://api.test',
        environment: 'test.supabase.co',
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'configured': true,
              'accountEnabled': true,
              'deviceEnabled': true,
              'environment': 'test.supabase.co',
            }),
            200,
          );
        }),
      );
      final result = await api.enable(
        'installation',
        'private-token',
        'session',
      );
      expect(result.deviceEnabled, true);
      expect(sent.headers['Authorization'], 'Bearer session');
      expect(sent.url.toString(), 'https://api.test/api/push/android');
      expect(jsonDecode(sent.body)['token'], 'private-token');
    },
  );
  test('mismatched server environment cannot enable delivery', () async {
    final api = HttpAndroidPushApi(
      origin: 'https://api.test',
      environment: 'staging.supabase.co',
      client: MockClient(
        (_) async => http.Response(
          '{"configured":true,"accountEnabled":true,"deviceEnabled":true,"environment":"production.supabase.co"}',
          200,
        ),
      ),
    );
    await expectLater(
      api.enable('installation', 'token', 'session'),
      throwsA(isA<PushApiException>()),
    );
  });
  test('unsafe origins stay unavailable; debug permits only local HTTP', () {
    for (final origin in [
      null,
      '',
      'http://api.test',
      'https://user:pass@api.test',
      'https://api.test/path',
      'https://api.test?key=1',
    ]) {
      expect(
        HttpAndroidPushApi(
          origin: origin,
          environment: 'test.supabase.co',
        ).configured,
        false,
      );
    }
    expect(
      HttpAndroidPushApi(
        origin: 'http://10.0.2.2:3000',
        environment: 'test',
        allowLocal: true,
      ).configured,
      true,
    );
    expect(
      HttpAndroidPushApi(
        origin: 'http://10.0.2.2:3000',
        environment: 'test',
        allowLocal: false,
      ).configured,
      false,
    );
  });
  testWidgets(
    'a server that never returns headers times out with retry guidance',
    (tester) async {
      final api = HttpAndroidPushApi(
        origin: 'https://api.test',
        environment: 'test.supabase.co',
        client: MockClient((_) => Completer<http.Response>().future),
      );
      Object? failure;
      unawaited(
        api
            .enable('installation', 'token', 'session')
            .then<void>(
              (_) {},
              onError: (Object error) {
                failure = error;
              },
            ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 13));
      expect(failure, isA<PushApiException>());
    },
  );
}
