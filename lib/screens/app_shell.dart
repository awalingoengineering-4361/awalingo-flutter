import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
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

  Widget get _currentScreen {
    switch (_currentTab) {
      case NavTab.dictionary:
        return const DictionaryScreen();
      case NavTab.vote:
        return const VoteScreen();
      case NavTab.translate:
        return const TranslateScreen();
      case NavTab.menu:
        return const MenuScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      ),
    );
  }
}
