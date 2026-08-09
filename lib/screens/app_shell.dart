import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/auth_provider.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/mobile_header.dart';
import 'main/dictionary_screen.dart';
import 'main/vote_screen.dart';
import 'main/translate_screen.dart';
import 'main/menu_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  NavTab _currentTab = NavTab.dictionary;
  bool _isJuror = false;
  bool _roleLoaded = false;
  // Nested navigator for the Menu tab so sub-pages (AwaQuiz level picker, etc.)
  // remain inside the shell and keep the top/bottom nav visible.
  final _menuNavKey = GlobalKey<NavigatorState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_roleLoaded) {
      _roleLoaded = true;
      _fetchRole();
    }
  }

  Future<void> _fetchRole() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    try {
      final row = await Supabase.instance.client
          .from('user_roles')
          .select('role:roles!roleId(name)')
          .eq('userId', userId)
          .limit(1)
          .maybeSingle();
      final name =
          (row?['role'] as Map<String, dynamic>?)?['name'] as String?;
      if (mounted) setState(() => _isJuror = name == 'JUROR');
    } catch (e) {
      debugPrint('AppShell role fetch: $e');
    }
  }

  Widget get _currentScreen {
    switch (_currentTab) {
      case NavTab.dictionary:
        return const DictionaryScreen();
      case NavTab.vote:
        return VoteScreen(isJuror: _isJuror);
      case NavTab.translate:
        return const TranslateScreen();
      case NavTab.menu:
        // Nested Navigator: sub-pages pushed here stay within the shell so the
        // top/bottom nav remains visible. The active quiz uses rootNavigator:true
        // to go full-screen on top of the shell.
        return Navigator(
          key: _menuNavKey,
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => MenuScreen(
              onNavigate: (tab) => setState(() => _currentTab = tab),
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
          onTap: (tab) => setState(() => _currentTab = tab),
          isJuror: _isJuror,
        ),
      ),
    );
  }
}
