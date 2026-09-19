import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/auth_provider.dart';
import '../services/permissions.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/curate_guard_modal.dart';
import '../widgets/mobile_header.dart';
import 'main/awaquiz_screen.dart';
import 'main/vote_screen.dart';
import 'main/translate_screen.dart';
import 'main/menu_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  NavTab _currentTab = NavTab.quiz;
  bool _isJuror = false;
  String? _role;
  bool _roleLoaded = false;
  Future<void>? _roleFuture;
  // Nested navigator for the Menu tab so sub-pages (AwaQuiz level picker, etc.)
  // remain inside the shell and keep the top/bottom nav visible.
  final _menuNavKey = GlobalKey<NavigatorState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_roleLoaded) {
      _roleLoaded = true;
      _roleFuture = _fetchRole();
    }
  }

  Future<void> _fetchRole() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    try {
      final role = await fetchUserRole(Supabase.instance.client, userId);
      if (mounted) setState(() { _role = role; _isJuror = role == 'JUROR'; });
    } catch (e) {
      debugPrint('AppShell role fetch: $e');
    }
  }

  // Mirrors BottomNavigation.tsx's Translate nav item: without create:neos
  // permission, tapping it never reaches the terms list — it shows the
  // Curator-in-waiting guard (or, in the unreachable edge case where the
  // user also lacks take:quiz, just falls back to the Menu tab). The nav
  // bar is tappable before the role fetch resolves, so this awaits it
  // first — otherwise a curator tapping Translate right at launch could
  // briefly see the guard meant for explorers.
  Future<void> _onNavTap(NavTab tab) async {
    if (tab == NavTab.translate) {
      if (!_roleLoaded || _role == null) await _roleFuture;
      if (!mounted) return;
      if (!hasPermission(_role, Permission.createNeos)) {
        if (!hasPermission(_role, Permission.takeQuiz)) {
          setState(() => _currentTab = NavTab.menu);
        } else {
          showCurateGuardModal(context);
        }
        return;
      }
    }
    // The Menu tab has its own nested Navigator (see _menuNavKey below) so
    // sub-pages like AwaDiko stay within the shell — _currentTab never
    // actually leaves NavTab.menu while one of those is open, so tapping
    // "Menu" again was just a same-value setState that did nothing. Pop
    // that nested stack back to MenuScreen instead, matching the standard
    // "tap the active tab to return to its root" behavior.
    if (tab == NavTab.menu && _currentTab == NavTab.menu) {
      _menuNavKey.currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _currentTab = tab);
  }

  Widget get _currentScreen {
    switch (_currentTab) {
      case NavTab.quiz:
        return AwaQuizScreen(onBack: () => _onNavTap(NavTab.menu));
      case NavTab.vote:
        return VoteScreen(isJuror: _isJuror, onBack: () => _onNavTap(NavTab.menu));
      case NavTab.translate:
        return TranslateScreen(onBack: () => _onNavTap(NavTab.menu));
      case NavTab.menu:
        // Nested Navigator: sub-pages pushed here stay within the shell so the
        // top/bottom nav remains visible. The active quiz uses rootNavigator:true
        // to go full-screen on top of the shell.
        return Navigator(
          key: _menuNavKey,
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => MenuScreen(
              onNavigate: _onNavTap,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Let the menu's nested navigator handle back before the shell does.
        final menuNav = _menuNavKey.currentState;
        if (menuNav != null && menuNav.canPop()) menuNav.pop();
      },
      child: Scaffold(
        backgroundColor: AppColorScheme.of(context).background,
        appBar: const AppMobileHeader(),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(
            key: ValueKey(_currentTab),
            child: _currentScreen,
          ),
        ),
        bottomNavigationBar: AppBottomNav(
          current: _currentTab,
          onTap: _onNavTap,
          isJuror: _isJuror,
        ),
      ),
    );
  }
}
