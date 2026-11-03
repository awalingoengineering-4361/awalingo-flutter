import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:awalingo/services/account_deletion_service.dart';

void main() {
  test(
    'sends only confirmation and bearer to the configured backend',
    () async {
      final service = AccountDeletionService(
        origin: 'https://www.awalingo.org',
        accessToken: () => 'test-token',
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://www.awalingo.org/api/account/deletion',
          );
          expect(request.headers['authorization'], 'Bearer test-token');
          expect(jsonDecode(request.body), {'confirmation': 'DELETE'});
          return http.Response(
            '{"requestId":"receipt","status":"requested"}',
            202,
          );
        }),
      );
      await service.requestDeletion();
    },
  );
  test('does not report completion when the request failed', () async {
    final service = AccountDeletionService(
      origin: 'https://www.awalingo.org',
      accessToken: () => 'token',
      client: MockClient(
        (_) async => http.Response('{"error":"Sign in again."}', 403),
      ),
    );
    await expectLater(
      service.requestDeletion(),
      throwsA(isA<AccountDeletionException>()),
    );
  });
  test('does not send a request without authentication', () async {
    final service = AccountDeletionService(
      origin: 'https://www.awalingo.org',
      accessToken: () => null,
      client: MockClient((_) async => throw StateError('must not send')),
    );
    await expectLater(
      service.requestDeletion(),
      throwsA(isA<AccountDeletionException>()),
    );
  });
  test(
    'retries a lost response using the same authenticated account',
    () async {
      var attempts = 0;
      final service = AccountDeletionService(
        origin: 'https://www.awalingo.org',
        accessToken: () => 'token',
        client: MockClient((_) async {
          attempts++;
          if (attempts == 1) throw http.ClientException('network lost');
          return http.Response(
            '{"requestId":"same-receipt","status":"requested"}',
            202,
          );
        }),
      );
      await expectLater(
        service.requestDeletion(),
        throwsA(isA<AccountDeletionException>()),
      );
      await service.requestDeletion();
      expect(attempts, 2);
    },
  );
}
