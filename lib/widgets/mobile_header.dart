import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/auth_provider.dart';
import '../services/theme_notifier.dart';
import '../screens/main/notifications_screen.dart';

class AppMobileHeader extends StatefulWidget implements PreferredSizeWidget {
  const AppMobileHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  State<AppMobileHeader> createState() => _AppMobileHeaderState();
}

class _AppMobileHeaderState extends State<AppMobileHeader> {
  int _unread = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('userId', userId)
          .eq('isRead', false);
      if (mounted) setState(() => _unread = rows.length);
    } catch (_) {}
  }

  void _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    _loadUnread();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.of(context);
    final theme = ThemeProvider.of(context);
    final c = AppColorScheme.of(context);
    final isDark = theme.isDark;

    // Scaffold constrains appBar to preferredSize.height + viewPadding.top.
    // Without an explicit height the Container fills that full space, so the
    // card background extends behind the status bar. viewPadding.top is added
    // as top padding so the Row content sits below the status bar.
    final topPad = MediaQuery.of(context).viewPadding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        padding: EdgeInsets.fromLTRB(16, topPad, 16, 0),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              // Wordmark — matches the Next.js web header exactly
              GestureDetector(
                onTap: () => Navigator.of(context).pushReplacementNamed('/home'),
                child: Image.asset(
                  isDark
                      ? 'assets/branding/logo-wordmark-dark.png'
                      : 'assets/branding/logo-wordmark-light.png',
                  height: 36,
                  fit: BoxFit.contain,
                ),
              ),

              const Spacer(),

              // Theme toggle
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
                // Notification bell with unread badge
                GestureDetector(
                  onTap: _openNotifications,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c.secondary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.notifications_outlined,
                          color: c.foreground,
                          size: 18,
                        ),
                      ),
                      if (_unread > 0)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              _unread > 99 ? '99+' : '$_unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontFamily: 'Metropolis',
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
        ),
      ),
    );
  }
}
