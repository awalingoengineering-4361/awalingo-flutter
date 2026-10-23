import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PushRegistration {
  final bool configured, accountEnabled, deviceEnabled;
  final String environment;
  const PushRegistration({
    required this.configured,
    required this.accountEnabled,
    required this.deviceEnabled,
    required this.environment,
  });
}

class PushApiException implements Exception {
  final String message;
  const PushApiException(this.message);
  @override
  String toString() => message;
}

abstract interface class AndroidPushApi {
  bool get configured;
  Future<PushRegistration> status(String installationId, String bearer);
  Future<PushRegistration> enable(
    String installationId,
    String token,
    String bearer,
  );
  Future<PushRegistration> disable(String installationId, String bearer);
  Future<void> unregister(String installationId, String bearer);
}

class HttpAndroidPushApi implements AndroidPushApi {
  final String environment;
  final http.Client _client;
  final Uri? _origin;
  HttpAndroidPushApi({
    required String? origin,
    required this.environment,
    http.Client? client,
    bool allowLocal = kDebugMode,
  }) : _client = client ?? http.Client(),
       _origin = _validateOrigin(origin, allowLocal);
  static Uri? _validateOrigin(String? value, bool allowLocal) {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    final local = [
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
      '::1',
    ].contains(uri.host);
    return uri.scheme == 'https' ||
            (allowLocal && local && uri.scheme == 'http')
        ? uri
        : null;
  }

  @override
  bool get configured => _origin != null && environment.isNotEmpty;
  Future<PushRegistration?> _request(
    String method,
    String installationId,
    String bearer, {
    String? token,
  }) async {
    if (!configured) {
      throw const PushApiException(
        'Push notifications are not configured for this app yet.',
      );
    }
    final base = _origin!.resolve('/api/push/android');
    final uri = method == 'GET'
        ? base.replace(queryParameters: {'installationId': installationId})
        : base;
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $bearer',
        'Content-Type': 'application/json',
      });
    if (method != 'GET') {
      request.body = jsonEncode({
        'installationId': installationId,
        'token': ?token,
      });
    }
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 401) {
        throw const PushApiException(
          'Sign in again to manage push notifications.',
        );
      }
      if (response.statusCode == 503) {
        throw const PushApiException(
          'Push service is unavailable. Please try again later.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const PushApiException(
          'Unable to save push notifications. Please retry.',
        );
      }
      if (method == 'DELETE') return null;
      final value = jsonDecode(response.body) as Map<String, dynamic>;
      if (value['environment'] != environment) {
        throw const PushApiException(
          'Push server does not match this app environment.',
        );
      }
      if ([
        value['configured'],
        value['accountEnabled'],
        value['deviceEnabled'],
      ].any((value) => value is! bool)) {
        throw const FormatException();
      }
      return PushRegistration(
        configured: value['configured'],
        accountEnabled: value['accountEnabled'],
        deviceEnabled: value['deviceEnabled'],
        environment: environment,
      );
    } on PushApiException {
      rethrow;
    } catch (_) {
      throw const PushApiException(
        'Network unavailable. Check your connection and retry.',
      );
    }
  }

  @override
  Future<PushRegistration> status(String installationId, String bearer) async =>
      (await _request('GET', installationId, bearer))!;
  @override
  Future<PushRegistration> enable(
    String installationId,
    String token,
    String bearer,
  ) async => (await _request('PUT', installationId, bearer, token: token))!;
  @override
  Future<PushRegistration> disable(
    String installationId,
    String bearer,
  ) async => (await _request('PATCH', installationId, bearer))!;
  @override
  Future<void> unregister(String installationId, String bearer) async {
    await _request('DELETE', installationId, bearer);
  }
}
