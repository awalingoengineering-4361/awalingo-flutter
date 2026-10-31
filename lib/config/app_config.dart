import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// A single environment for every backend consumer in this build.
class AppConfig {
  const AppConfig._({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.webBaseUrl,
    required this.pushApiOrigin,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String? webBaseUrl;
  final String? pushApiOrigin;

  static late final AppConfig current;

  static const _buildValues = {
    if (bool.hasEnvironment('SUPABASE_URL'))
      'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
    if (bool.hasEnvironment('SUPABASE_ANON_KEY'))
      'SUPABASE_ANON_KEY': String.fromEnvironment('SUPABASE_ANON_KEY'),
    if (bool.hasEnvironment('WEB_BASE_URL'))
      'WEB_BASE_URL': String.fromEnvironment('WEB_BASE_URL'),
    if (bool.hasEnvironment('ANDROID_PUSH_API_ORIGIN'))
      'ANDROID_PUSH_API_ORIGIN': String.fromEnvironment(
        'ANDROID_PUSH_API_ORIGIN',
      ),
  };

  static Future<void> initialize() async {
    var legacyValues = <String, String>{};
    if (_buildValues.isEmpty && !kReleaseMode) {
      await dotenv.load(fileName: '.env');
      legacyValues = dotenv.env;
    }
    current = resolve(
      buildValues: _buildValues,
      legacyValues: legacyValues,
      releaseMode: kReleaseMode,
      allowLocalHttp: kDebugMode,
    );
  }

  static AppConfig resolve({
    Map<String, String> buildValues = const {},
    Map<String, String> legacyValues = const {},
    bool releaseMode = false,
    bool allowLocalHttp = true,
  }) {
    final selected = buildValues.isNotEmpty;
    if (releaseMode && !selected) {
      throw const FormatException(
        'Release startup requires --dart-define-from-file=config/production.json.',
      );
    }
    final values = selected ? buildValues : legacyValues;
    for (final field in ['SUPABASE_URL', 'SUPABASE_ANON_KEY']) {
      if ((values[field] ?? '').trim().isEmpty) {
        throw FormatException('Missing $field in the selected configuration.');
      }
    }
    if (selected &&
        (!values.containsKey('ANDROID_PUSH_API_ORIGIN') ||
            (values['WEB_BASE_URL'] ?? '').trim().isEmpty)) {
      throw const FormatException(
        'Selected config must include WEB_BASE_URL and ANDROID_PUSH_API_ORIGIN. '
        'Use an empty push origin to disable push in development.',
      );
    }

    final allowLocal = allowLocalHttp && !releaseMode;
    final supabaseUrl = _origin(values['SUPABASE_URL']!, allowLocal)!;
    final webBaseUrl = _origin(values['WEB_BASE_URL'] ?? '', allowLocal);
    final pushApiOrigin = _origin(
      values['ANDROID_PUSH_API_ORIGIN'] ?? '',
      allowLocal,
    );
    final key = values['SUPABASE_ANON_KEY']!.trim();
    _validatePublicKey(key);

    if (releaseMode &&
        (supabaseUrl != 'https://auth.awalingo.org' ||
            webBaseUrl != 'https://www.awalingo.org' ||
            pushApiOrigin != 'https://awalingo-push-production.vercel.app')) {
      throw const FormatException(
        'Release startup requires the production Supabase, website, and push origins.',
      );
    }

    return AppConfig._(
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: key,
      webBaseUrl: webBaseUrl,
      pushApiOrigin: pushApiOrigin,
    );
  }

  static String? _origin(String value, bool allowLocalHttp) {
    if (value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    const localHosts = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !(uri.scheme == 'https' ||
            (allowLocalHttp &&
                uri.scheme == 'http' &&
                localHosts.contains(uri.host)))) {
      throw const FormatException(
        'Backend settings must be HTTPS origins; local HTTP is allowed in debug.',
      );
    }
    return uri.origin;
  }

  static void _validatePublicKey(String key) {
    const message =
        'SUPABASE_ANON_KEY must be a public anon or publishable key.';
    if (key.startsWith('sb_secret_')) throw const FormatException(message);
    final parts = key.split('.');
    if (parts.length == 3) {
      try {
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        if (claims is! Map || claims['role'] != 'anon') {
          throw const FormatException(message);
        }
      } catch (_) {
        throw const FormatException(message);
      }
    }
  }
}
