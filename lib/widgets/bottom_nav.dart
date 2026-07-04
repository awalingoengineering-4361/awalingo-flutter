import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum NavTab { dictionary, vote, translate, menu }

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
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(label: 'AwaDiko',  icon: Icons.menu_book_outlined,   activeIcon: Icons.menu_book,      active: current == NavTab.dictionary, onTap: () => onTap(NavTab.dictionary)),
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
