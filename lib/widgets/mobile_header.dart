import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_provider.dart';
import '../services/theme_notifier.dart';

class AppMobileHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppMobileHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.of(context);
    final theme = ThemeProvider.of(context);
    final c = AppColorScheme.of(context);
    final isDark = theme.isDark;

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: c.card,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Logo — invert colours in dark mode
          GestureDetector(
            onTap: () => Navigator.of(context).pushReplacementNamed('/home'),
            child: isDark
                ? ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      -1, 0, 0, 0, 255,
                       0,-1, 0, 0, 255,
                       0, 0,-1, 0, 255,
                       0, 0, 0, 1,   0,
                    ]),
                    child: Image.asset(
                      'assets/branding/logo-wordmark-light.png',
                      height: 36,
                      fit: BoxFit.contain,
                    ),
                  )
                : Image.asset(
                    'assets/branding/logo-wordmark-light.png',
                    height: 36,
                    fit: BoxFit.contain,
                  ),
          ),

          const Spacer(),

          // Theme toggle — sun in dark, moon in light (matches Next.js)
          GestureDetector(
            onTap: theme.toggle,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.secondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_outlined,
                size: 18,
                color: isDark ? const Color(0xFFF59E0B) : c.mutedForeground,
              ),
            ),
          ),

          if (auth.user != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.notifications_outlined, color: c.foreground, size: 22),
              onPressed: () {},
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).pushNamed('/profile'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.secondary,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline, size: 16, color: c.foreground),
                    const SizedBox(width: 4),
                    Text(
                      auth.user!.email?.split('@').first ?? 'User',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Metropolis',
                        fontWeight: FontWeight.w500,
                        color: c.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
