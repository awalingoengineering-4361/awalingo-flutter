import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';
import 'theme/app_theme.dart';
import 'services/auth_provider.dart';
import 'services/theme_notifier.dart';
import 'screens/onboarding/splash_screen.dart';
import 'screens/onboarding/onboarding_screens.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/auth/sign_up_screen.dart';
import 'screens/app_shell.dart';
import 'screens/main/request_screen.dart';
import 'screens/main/profile_screen.dart';
import 'widgets/auth_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig.fromEnvironment();
  config.validate();

  await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabaseAnonKey,
  );

  runApp(const AwalingoApp());
}

class AwalingoApp extends StatefulWidget {
  const AwalingoApp({super.key});

  @override
  State<AwalingoApp> createState() => _AwalingoAppState();
}

class _AwalingoAppState extends State<AwalingoApp> {
  late final AuthNotifier _authNotifier = AuthNotifier();
  late final ThemeNotifier _themeNotifier = ThemeNotifier();

  @override
  void dispose() {
    _authNotifier.dispose();
    _themeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthProvider(
      notifier: _authNotifier,
      child: ThemeProvider(
        notifier: _themeNotifier,
        child: ListenableBuilder(
          listenable: _themeNotifier,
          builder: (context, _) => MaterialApp(
            title: 'Awalingo',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: _themeNotifier.mode,
            initialRoute: '/',
            routes: {
              // ── Onboarding ─────────────────────────────────────
              '/': (_) => const SplashScreen(),
              '/onboarding1': (_) => const Onboarding1Screen(),
              '/onboarding4': (_) => const Onboarding4Screen(),
              '/onboarding5': (_) => const Onboarding5Screen(),

              // ── Auth ───────────────────────────────────────────
              // Force light theme on auth screens — they use AppColors (static
              // light palette) and should not adapt to dark mode.
              '/signin': (_) =>
                  Theme(data: AppTheme.light, child: const SignInScreen()),
              '/signup': (_) =>
                  Theme(data: AppTheme.light, child: const SignUpScreen()),

              // ── Main app ───────────────────────────────────────
              '/home': (_) => const AuthGuard(child: AppShell()),
              '/profile': (_) => const AuthGuard(child: ProfileScreen()),
              '/request': (_) => const AuthGuard(child: RequestScreen()),
            },
          ),
        ),
      ),
    );
  }
}
