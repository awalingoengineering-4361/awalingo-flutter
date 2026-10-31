import 'services/android_push_taps.dart';
import 'services/notification_router.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/android_push_api.dart';
import 'services/android_push_platform.dart';
import 'services/android_push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SystemChrome / SystemUiMode
import 'config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
import 'services/route_observer.dart';
import 'widgets/auth_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opt into edge-to-edge so Flutter correctly reports viewPadding for both
  // the status bar (top) and gesture/button navigation bar (bottom).
  // Required on Android 15+ and good practice on earlier versions.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // The UI isn't designed for landscape anywhere in the app — lock to
  // portrait only (both upright and upside-down) so rotating the device
  // doesn't put the app in a broken, unusable layout.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await AppConfig.initialize();
  final config = AppConfig.current;
  final supabaseUrl = config.supabaseUrl;
  final supabaseAnonKey = config.supabaseAnonKey;

  await Supabase.initialize(
    url: supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  final push = AndroidPushService(
    platform: NativeAndroidPushPlatform(),
    api: HttpAndroidPushApi(
      origin: config.pushApiOrigin,
      environment: Uri.parse(supabaseUrl).host,
    ),
    preferences: await SharedPreferences.getInstance(),
    environment: Uri.parse(supabaseUrl).host,
    accessToken: () =>
        Supabase.instance.client.auth.currentSession?.accessToken,
  );
  runApp(AwalingoApp(pushService: push));
}

class AwalingoApp extends StatefulWidget {
  final AndroidPushService? pushService;
  const AwalingoApp({super.key, this.pushService});

  @override
  State<AwalingoApp> createState() => _AwalingoAppState();
}

class _AwalingoAppState extends State<AwalingoApp> {
  late final AuthNotifier _authNotifier = AuthNotifier(
    beforeSignOut: _prepareForSignOut,
  );
  late final ThemeNotifier _themeNotifier = ThemeNotifier();
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Map<String, dynamic>>? _pushTapSubscription;
  int _pushAuthGeneration = 0;
  String? _pushAuthOwner;
  late final AndroidPushTaps _pushTaps = AndroidPushTaps(
    environment: widget.pushService?.environment ?? '',
    navigate: (link, owner) async {
      final context = _navigatorKey.currentContext;
      final generation = _pushAuthGeneration;
      if (context != null && _authNotifier.user?.id == owner) {
        await openNotificationLink(
          context,
          owner,
          link,
          canNavigate: () =>
              mounted &&
              generation == _pushAuthGeneration &&
              _authNotifier.user?.id == owner,
        );
      }
    },
  );
  late final NavigatorObserver _pushNavigationObserver =
      _PushNavigationObserver((ready) {
        unawaited(_pushTaps.setReady(ready));
      });
  // Track the auth state at startup so we only react to transitions,
  // not to the initial session that the SplashScreen already handles.
  late bool _wasAuthenticated;

  @override
  void initState() {
    super.initState();
    _wasAuthenticated = _authNotifier.isAuthenticated;
    _pushAuthOwner = _authNotifier.user?.id;
    _authNotifier.addListener(_onAuthChange);
    _pushTaps.setOwner(_authNotifier.user?.id);
    final push = widget.pushService;
    if (push != null) {
      // Consume native launch data before reconciliation closes an old native gate.
      unawaited(_readPushTap());
      _pushTapSubscription = push.platform.events.listen((event) {
        if (event['type'] == 'tap') unawaited(_readPushTap());
      }, onError: (_) {});
      unawaited(push.reconcile(_authNotifier.user));
    }
  }

  Future<void> _readPushTap() async {
    try {
      final payload = await widget.pushService?.platform.getInitialTap();
      if (payload != null && mounted) await _pushTaps.receive(payload);
    } catch (_) {
      /* No valid pending native tap. */
    }
  }

  Future<void> _prepareForSignOut() async {
    _pushAuthGeneration++;
    _pushTaps.setOwner(null);
    await widget.pushService?.prepareForSignOut();
  }

  void _onAuthChange() {
    final owner = _authNotifier.user?.id;
    if (owner != _pushAuthOwner) {
      _pushAuthGeneration++;
      _pushAuthOwner = owner;
    }
    _pushTaps.setOwner(_authNotifier.user?.id);
    unawaited(widget.pushService?.reconcile(_authNotifier.user));
    final isAuth = _authNotifier.isAuthenticated;
    if (isAuth && !_wasAuthenticated) {
      // User just signed in (e.g. OAuth deep link returned on Android).
      // Navigate to home and clear the back-stack so they can't go back
      // to the sign-in screen.
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/home',
        (_) => false,
      );
    }
    _wasAuthenticated = isAuth;
  }

  @override
  void dispose() {
    _pushTapSubscription?.cancel();
    _authNotifier.removeListener(_onAuthChange);
    _authNotifier.dispose();
    _themeNotifier.dispose();
    widget.pushService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AuthProvider(
      notifier: _authNotifier,
      child: ThemeProvider(
        notifier: _themeNotifier,
        child: ListenableBuilder(
          listenable: _themeNotifier,
          builder: (context, _) => MaterialApp(
            navigatorKey: _navigatorKey,
            navigatorObservers: [appRouteObserver, _pushNavigationObserver],
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
    return widget.pushService == null
        ? app
        : AndroidPushScope(service: widget.pushService!, child: app);
  }
}

class _PushNavigationObserver extends NavigatorObserver {
  final void Function(bool ready) onReady;
  _PushNavigationObserver(this.onReady);
  void _update(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null) return;
    final ready = ['/home', '/profile', '/request'].contains(name);
    WidgetsBinding.instance.addPostFrameCallback((_) => onReady(ready));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _update(newRoute);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);
}
