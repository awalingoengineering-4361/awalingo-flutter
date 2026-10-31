import 'package:flutter_test/flutter_test.dart';
import 'package:awalingo/config/app_config.dart';

void main() {
  const staging = {
    'SUPABASE_URL': 'https://staging-project.supabase.co',
    'SUPABASE_ANON_KEY': 'public-fixture-key',
    'WEB_BASE_URL': 'https://staging.awalingo.org',
    'ANDROID_PUSH_API_ORIGIN': 'https://awalingo-push-staging.vercel.app',
  };
  const production = {
    'SUPABASE_URL': 'https://auth.awalingo.org',
    'SUPABASE_ANON_KEY': 'public-fixture-key',
    'WEB_BASE_URL': 'https://www.awalingo.org',
    'ANDROID_PUSH_API_ORIGIN': 'https://awalingo-push-production.vercel.app',
  };

  test('selected build config replaces every legacy endpoint', () {
    final config = AppConfig.resolve(
      buildValues: production,
      legacyValues: staging,
    );
    expect(config.supabaseUrl, 'https://auth.awalingo.org');
    expect(config.webBaseUrl, 'https://www.awalingo.org');
    expect(config.pushApiOrigin, 'https://awalingo-push-production.vercel.app');
    expect(config.supabaseAnonKey, 'public-fixture-key');
  });

  test('partial build config cannot inherit legacy settings', () {
    expect(
      () => AppConfig.resolve(
        buildValues: const {'SUPABASE_URL': 'https://auth.awalingo.org'},
        legacyValues: staging,
      ),
      throwsFormatException,
    );
  });

  test('debug without build settings keeps legacy development working', () {
    final config = AppConfig.resolve(legacyValues: staging);
    expect(config.supabaseUrl, 'https://staging-project.supabase.co');
  });

  test('release cannot silently use the legacy env asset', () {
    expect(
      () => AppConfig.resolve(legacyValues: production, releaseMode: true),
      throwsFormatException,
    );
  });

  test('release accepts the explicit production endpoint set', () {
    expect(
      AppConfig.resolve(buildValues: production, releaseMode: true).webBaseUrl,
      'https://www.awalingo.org',
    );
  });

  test('release rejects staging and individually mixed endpoints', () {
    for (final field in [
      'SUPABASE_URL',
      'WEB_BASE_URL',
      'ANDROID_PUSH_API_ORIGIN',
    ]) {
      expect(
        () => AppConfig.resolve(
          buildValues: {...production, field: staging[field]!},
          releaseMode: true,
        ),
        throwsFormatException,
        reason: field,
      );
    }
  });

  test(
    'selected config requires web and push fields even when push is off',
    () {
      for (final field in ['WEB_BASE_URL', 'ANDROID_PUSH_API_ORIGIN']) {
        final values = {...staging}..remove(field);
        expect(
          () => AppConfig.resolve(buildValues: values),
          throwsFormatException,
        );
      }
      expect(
        AppConfig.resolve(
          buildValues: {...staging, 'ANDROID_PUSH_API_ORIGIN': ''},
        ).pushApiOrigin,
        isNull,
      );
    },
  );

  test('invalid origins fail without exposing their input in errors', () {
    for (final bad in [
      'not-a-url',
      'http://staging.awalingo.org',
      'https://user:password@example.com',
      'https://example.com/api/push',
      'https://example.com?secret=hidden',
      'https://example.com#fragment',
    ]) {
      expect(
        () => AppConfig.resolve(
          buildValues: {...staging, 'ANDROID_PUSH_API_ORIGIN': bad},
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.toString().contains(bad),
            'redacts input',
            isFalse,
          ),
        ),
      );
    }
  });

  test('local HTTP origins work only in debug', () {
    final config = AppConfig.resolve(
      buildValues: {
        ...staging,
        'SUPABASE_URL': 'http://10.0.2.2:54321',
        'WEB_BASE_URL': 'http://localhost:3000',
        'ANDROID_PUSH_API_ORIGIN': 'http://127.0.0.1:3000',
      },
    );
    expect(config.supabaseUrl, 'http://10.0.2.2:54321');
  });

  test('profile rejects local HTTP just like the push client', () {
    expect(
      () => AppConfig.resolve(
        buildValues: {...staging, 'SUPABASE_URL': 'http://10.0.2.2:54321'},
        allowLocalHttp: false,
      ),
      throwsFormatException,
    );
  });

  test('server-only Supabase keys are rejected', () {
    for (final key in [
      'sb_secret_do-not-bundle',
      'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature',
    ]) {
      expect(
        () => AppConfig.resolve(
          buildValues: {...staging, 'SUPABASE_ANON_KEY': key},
        ),
        throwsFormatException,
      );
    }
  });
}
