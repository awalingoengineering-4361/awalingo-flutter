class AppConfig {
  const AppConfig({required this.supabaseUrl, required this.supabaseAnonKey});

  const AppConfig.fromEnvironment()
    : supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');

  final String supabaseUrl;
  final String supabaseAnonKey;

  void validate() {
    final uri = Uri.tryParse(supabaseUrl);
    if (supabaseUrl.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority) {
      throw StateError(
        'SUPABASE_URL is missing or invalid. Start the app with '
        '--dart-define-from-file=config/<environment>.json.',
      );
    }

    if (supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_ANON_KEY is missing. Start the app with '
        '--dart-define-from-file=config/<environment>.json.',
      );
    }
  }
}
