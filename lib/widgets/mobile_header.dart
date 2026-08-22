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
  String? _communityShort;
  String? _communityFlagCode;
  bool _communityLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadUnread();
    if (!_communityLoaded) {
      _communityLoaded = true;
      _loadCommunity();
    }
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

  // Mirrors neolingo's userNeoCommunity: language.short + language.icon
  // (a country code rendered as a flag) for the user's target community.
  Future<void> _loadCommunity() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    try {
      final row = await Supabase.instance.client
          .from('user_target_languages')
          .select('language:languages!languageId(short, icon)')
          .eq('userId', userId)
          .maybeSingle();
      final lang = row?['language'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _communityShort = lang?['short'] as String?;
          _communityFlagCode = lang?['icon'] as String?;
        });
      }
    } catch (_) {}
  }

  String? _avatarUrl(User? user) {
    final meta = user?.userMetadata;
    return (meta?['avatar_url'] as String?) ?? (meta?['picture'] as String?);
  }

  // Converts a 2-letter ISO country code into its flag emoji, matching
  // react-country-flag's rendering (falls back to 'NG' like the web app).
  String _flagEmoji(String? countryCode) {
    final code = (countryCode ?? 'NG').toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return '🏳️';
    const base = 0x1F1E6;
    final first = base + (code.codeUnitAt(0) - 'A'.codeUnitAt(0));
    final second = base + (code.codeUnitAt(1) - 'A'.codeUnitAt(0));
    return String.fromCharCode(first) + String.fromCharCode(second);
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
                // Community flag + short code pill — matches MyCommunityTag.tsx
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_flagEmoji(_communityFlagCode), style: const TextStyle(fontSize: 13)),
                      if ((_communityShort ?? '').isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          _communityShort!.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c.foreground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Avatar button — matches neolingo's mobile MyCommunityTag:
                // a circular photo (falls back to a generic icon), never
                // the raw email.
                GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/profile'),
                  child: Container(
                    width: 36,
                    height: 36,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: c.secondary,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border),
                    ),
                    child: _avatarUrl(auth.user) != null
                        ? Image.network(
                            _avatarUrl(auth.user)!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Icon(Icons.person_outline, size: 18, color: c.mutedForeground),
                          )
                        : Icon(Icons.person_outline, size: 18, color: c.mutedForeground),
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
