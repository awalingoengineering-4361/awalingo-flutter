import 'dart:async';
import 'package:awalingo/services/load_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final error in [
    http.ClientException('private.host: SocketException, connection refused'),
    TimeoutException('private endpoint timed out'),
  ]) {
    test('$error gets friendly offline feedback', () {
      final failure = LoadFailure.fromError(error);
      expect(failure.isOffline, isTrue);
      expect(failure.title, 'You are offline');
      expect(failure.message, contains('internet connection'));
      expect(failure.message, isNot(contains('private')));
    });
  }

  for (final error in [
    const PostgrestException(message: 'permission denied', code: '42501'),
    const PostgrestException(message: 'server unavailable', code: '503'),
    const FormatException('private invalid response'),
    Exception('SocketException as arbitrary text'),
  ]) {
    test('$error does not falsely report a disconnected device', () {
      final failure = LoadFailure.fromError(error);
      expect(failure.isOffline, isFalse);
      expect(failure.title, 'Unable to load');
      expect(failure.message, 'Please try again.');
    });
  }
}
