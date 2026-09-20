import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/auth_provider.dart';
import '../services/theme_notifier.dart';
import '../services/notification_router.dart';
import '../screens/main/notifications_screen.dart';

// Matches neolingo's NOTIFICATION_REFETCH_INTERVAL_MS (queryKeys.ts).
const _kNotificationPollInterval = Duration(seconds: 30);
const _kNotificationPreviewLimit = 5;

class AppMobileHeader extends StatefulWidget implements PreferredSizeWidget {
  const AppMobileHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  State<AppMobileHeader> createState() => _AppMobileHeaderState();
}

class _AppMobileHeaderState extends State<AppMobileHeader> with WidgetsBindingObserver {
  final _notificationService = NotificationService();
  final GlobalKey _bellKey = GlobalKey();

  int _unread = 0;
  String? _communityShort;
  String? _communityFlagCode;
  bool _communityLoaded = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pollTimer = Timer.periodic(_kNotificationPollInterval, (_) => _loadUnread());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Mobile equivalent of NotificationBell.tsx's refetchOnWindowFocus.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadUnread();
  }

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
      final count = await _notificationService.unreadCount(userId);
      if (mounted) setState(() => _unread = count);
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
    final url = (meta?['avatar_url'] as String?) ?? (meta?['picture'] as String?);
    return (url != null && url.isNotEmpty) ? url : null;
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

  // Mirrors NotificationBell.tsx's DropdownMenu: a preview of the latest
  // notifications with mark-as-read / mark-all-as-read and a "View all"
  // footer, refreshed each time the menu opens (onOpenChange).
  Future<void> _showNotificationsMenu() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;

    final renderBox = _bellKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) return;
    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + renderBox.size.height + 8,
      overlay.size.width - topLeft.dx - renderBox.size.width,
      0,
    );

    List<AppNotification> preview = [];
    bool loading = true;

    final fetch = Future.wait([
      _notificationService.load(userId, limit: _kNotificationPreviewLimit),
      _notificationService.unreadCount(userId),
    ]);

    final c = AppColorScheme.of(context);

    await showMenu<void>(
      context: context,
      position: position,
      color: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 320),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: StatefulBuilder(
            builder: (menuContext, setMenuState) {
              if (loading) {
                fetch.then((results) {
                  preview = results[0] as List<AppNotification>;
                  final count = results[1] as int;
                  loading = false;
                  if (mounted) setState(() => _unread = count);
                  setMenuState(() {});
                }).catchError((_) {
                  loading = false;
                  setMenuState(() {});
                });
              }

              Future<void> markAllRead() async {
                setMenuState(() {
                  preview = preview.map((n) => n.copyWith(isRead: true)).toList();
                });
                setState(() => _unread = 0);
                await _notificationService.markAllRead(userId);
              }

              Future<void> handleTap(AppNotification n) async {
                if (!n.isRead) {
                  setMenuState(() {
                    preview = preview.map((x) => x.id == n.id ? x.copyWith(isRead: true) : x).toList();
                  });
                  setState(() => _unread = _unread > 0 ? _unread - 1 : 0);
                  _notificationService.markRead(userId, n.id);
                }
                Navigator.of(menuContext).pop();
                await openNotificationLink(context, userId, n.link);
              }

              final hasUnread = preview.any((n) => !n.isRead);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Notifications',
                            style: TextStyle(
                              fontFamily: 'Parkinsans',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.foreground,
                            ),
                          ),
                        ),
                        if (hasUnread)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: markAllRead,
                            child: Text(
                              'Mark all as read',
                              style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.primary),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: c.border),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (preview.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No notifications',
                        style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (var i = 0; i < preview.length; i++)
                              _NotificationPreviewTile(
                                notification: preview[i],
                                c: c,
                                isLast: i == preview.length - 1,
                                onTap: () => handleTap(preview[i]),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (preview.isNotEmpty) ...[
                    Divider(height: 1, color: c.border),
                    InkWell(
                      onTap: () {
                        Navigator.of(menuContext).pop();
                        Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const NotificationsScreen()))
                            .then((_) => _loadUnread());
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'View all notifications',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
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
              // Wordmark — not tappable: this header is AppShell's persistent
              // appBar, so a tap would pushReplacementNamed('/home') over
              // the whole shell, discarding the Menu tab's nested navigator
              // and resetting the selected bottom-nav tab.
              Image.asset(
                isDark
                    ? 'assets/branding/logo-wordmark-dark.png'
                    : 'assets/branding/logo-wordmark-light.png',
                height: 36,
                fit: BoxFit.contain,
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
                // Notification bell — matches NotificationBell.tsx's plain
                // presence dot (no count) and dropdown preview.
                GestureDetector(
                  onTap: _showNotificationsMenu,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        key: _bellKey,
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
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
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
                Builder(builder: (context) {
                  final avatarUrl = _avatarUrl(auth.user);
                  final fallbackIcon = Icon(Icons.person_outline, size: 18, color: c.mutedForeground);
                  return GestureDetector(
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
                      child: avatarUrl != null
                          ? Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => fallbackIcon,
                              loadingBuilder: (_, child, progress) =>
                                  progress == null ? child : fallbackIcon,
                            )
                          : fallbackIcon,
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Preview row inside the notification dropdown — mirrors the item markup
// in NotificationBell.tsx (title + unread dot, 2-line message, relative time).
class _NotificationPreviewTile extends StatelessWidget {
  final AppNotification notification;
  final AppColorScheme c;
  final bool isLast;
  final VoidCallback onTap;

  const _NotificationPreviewTile({
    required this.notification,
    required this.c,
    required this.isLast,
    required this.onTap,
  });

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUnread ? c.primary.withValues(alpha: 0.06) : Colors.transparent,
          border: isLast ? null : Border(bottom: BorderSide(color: c.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    notification.title,
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 13,
                      fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                      color: c.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isUnread)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(left: 6, top: 2),
                    decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              notification.message,
              style: TextStyle(fontFamily: 'Metropolis', fontSize: 11.5, color: c.mutedForeground),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              _timeAgo(notification.createdAt),
              style: TextStyle(fontFamily: 'Metropolis', fontSize: 10.5, color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
