import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum NavTab { quiz, vote, translate, menu }

class AppBottomNav extends StatelessWidget {
  final NavTab current;
  final ValueChanged<NavTab> onTap;
  final bool isJuror;

  const AppBottomNav({
    super.key,
    required this.current,
    required this.onTap,
    this.isJuror = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    // Add viewPadding.bottom so nav items sit above the gesture/button nav bar
    // on edge-to-edge Android (the system bar would otherwise overlap the row).
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 12 + bottomPad),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(label: 'AwaQuiz',  icon: Icons.extension_outlined,    activeIcon: Icons.extension,      active: current == NavTab.quiz,       onTap: () => onTap(NavTab.quiz)),
          _NavItem(label: isJuror ? 'Jury' : 'Vote', icon: Icons.how_to_vote_outlined, activeIcon: Icons.how_to_vote, active: current == NavTab.vote, onTap: () => onTap(NavTab.vote)),
          _NavItem(label: 'Translate',icon: Icons.lightbulb_outline,     activeIcon: Icons.lightbulb,      active: current == NavTab.translate,  onTap: () => onTap(NavTab.translate)),
          _NavItem(label: 'Menu',     icon: Icons.grid_view_outlined,    activeIcon: Icons.grid_view,      active: current == NavTab.menu,       onTap: () => onTap(NavTab.menu)),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: active ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(active ? activeIcon : icon, size: 22, color: c.primary),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                fontFamily: 'Metropolis',
                color: c.primary,
              )),
            ],
          ),
        ),
      ),
    );
  }
}
