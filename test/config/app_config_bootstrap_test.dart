import 'package:awalingo/config/app_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bootstrap uses compiled production settings instead of loaded staging env',
    () async {
      dotenv.testLoad(
        fileInput: '''
SUPABASE_URL=https://staging-project.supabase.co
SUPABASE_ANON_KEY=staging-fixture-key
WEB_BASE_URL=https://staging.awalingo.org
ANDROID_PUSH_API_ORIGIN=https://awalingo-push-staging.vercel.app
''',
      );
      await AppConfig.initialize();
      expect(AppConfig.current.supabaseUrl, 'https://auth.awalingo.org');
      expect(AppConfig.current.supabaseAnonKey, 'public-fixture-key');
      expect(AppConfig.current.webBaseUrl, 'https://www.awalingo.org');
      expect(
        AppConfig.current.pushApiOrigin,
        'https://awalingo-push-production.vercel.app',
      );
    },
    skip: const String.fromEnvironment('APP_CONFIG_TEST_FIXTURE') != 'production'
        ? 'Run with --dart-define-from-file=test/fixtures/config/production.json'
        : false,
  );
}
