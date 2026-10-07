import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../features/awaquiz/awaquiz_progression.dart';
import '../../services/auth_provider.dart';
import '../../services/permissions.dart';
import '../../services/route_observer.dart';
import '../../services/theme_notifier.dart';
import '../../services/webview_support.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cowry_checkout_webview.dart';
import '../../widgets/dev_role_switcher.dart';
import '../../widgets/simple_webview_screen.dart';
import '../../widgets/top_up_cowries_modal.dart';
import 'daily_streak_screen.dart';
import 'notifications_screen.dart';
import 'privacy_settings_screen.dart';

class _ProfileData {
  final String? name;
  final int cowryBalance;
  final bool allowInAppNotifications;
  final String? communityName;
  final String role;
  final int currentStreak;
  final String? level; // raw difficulty, e.g. 'BEGINNER' — null if not started
  final String? levelName; // human stage name, e.g. 'Sabi Player'

  const _ProfileData({
    this.name,
    this.cowryBalance = 0,
    this.allowInAppNotifications = true,
    this.communityName,
    this.role = 'EXPLORER',
    this.currentStreak = 0,
    this.level,
    this.levelName,
  });

  _ProfileData copyWith({bool? allowInAppNotifications, int? cowryBalance}) =>
      _ProfileData(
        name: name,
        cowryBalance: cowryBalance ?? this.cowryBalance,
        allowInAppNotifications:
            allowInAppNotifications ?? this.allowInAppNotifications,
        communityName: communityName,
        role: role,
        currentStreak: currentStreak,
        level: level,
        levelName: levelName,
      );
}

class _ProfileService {
  final SupabaseClient _db = Supabase.instance.client;

  // Mirrors getHighestQuizProgress (streaks/service.ts): the highest-ranked
  // submitted AwaQuiz attempt (by difficulty, tie-broken by higher section),
  // independent of the user's current target language.
  Future<({String? level, String? levelName})> _highestQuizProgress(
    String userId,
  ) async {
    final rows = await _db
        .from('community_quiz_attempts')
        .select('difficulty, section, submittedAt')
        .eq('userId', userId);
    final submitted = rows.where((r) => r['submittedAt'] != null).toList();
    if (submitted.isEmpty) return (level: null, levelName: null);

    int rank(String d) => switch (d) {
      'ADVANCED' => 3,
      'INTERMEDIATE' => 2,
      'BEGINNER' => 1,
      _ => 0,
    };
    submitted.sort((a, b) {
      final byRank = rank(
        b['difficulty'] as String,
      ).compareTo(rank(a['difficulty'] as String));
      if (byRank != 0) return byRank;
      return (b['section'] as int).compareTo(a['section'] as int);
    });
    final top = submitted.first;
    final level = top['difficulty'] as String;
    return (
      level: level,
      levelName: stageNameForQuizProgress(level, top['section'] as int),
    );
  }

  Future<_ProfileData> loadProfile(String userId) async {
    final results = await Future.wait([
      _db
          .from('user_profile')
          .select('name, cowryBalance, allowInAppNotifications')
          .eq('userId', userId)
          .maybeSingle(),
      _db
          .from('user_target_languages')
          .select('language:languages!languageId(id, name)')
          .eq('userId', userId)
          .maybeSingle(),
      _db
          .from('user_roles')
          .select('role:roles!roleId(name)')
          .eq('userId', userId)
          .limit(1)
          .maybeSingle(),
      _db
          .from('user_streaks')
          .select('currentDays')
          .eq('userId', userId)
          .maybeSingle(),
    ]);

    final profile = results[0];
    final utl = results[1];
    final roleRow = results[2];
    final streakRow = results[3];
    final progress = await _highestQuizProgress(userId);

    final lang = utl?['language'] as Map<String, dynamic>?;
    final roleMap = roleRow?['role'] as Map<String, dynamic>?;

    return _ProfileData(
      name: profile?['name'] as String?,
      cowryBalance: (profile?['cowryBalance'] as int?) ?? 0,
      allowInAppNotifications:
          (profile?['allowInAppNotifications'] as bool?) ?? true,
      communityName: lang?['name'] as String?,
      role: (roleMap?['name'] as String?) ?? 'EXPLORER',
      currentStreak: (streakRow?['currentDays'] as int?) ?? 0,
      level: progress.level,
      levelName: progress.levelName,
    );
  }

  Future<void> updateNotifications(String userId, bool value) async {
    await _db
        .from('user_profile')
        .update({'allowInAppNotifications': value})
        .eq('userId', userId);
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with RouteAware {
  final _service = _ProfileService();
  final _notificationService = NotificationService();
  bool _loading = true;
  _ProfileData? _data;
  int _unreadCount = 0;
  bool _loadDone = false;
  bool _moreExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadDone) {
      _loadDone = true;
      _load();
    }
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  // Refetch whenever this screen becomes visible again (e.g. returning from
  // Daily Streak, Vote, or AwaQuiz after an action that changed the streak,
  // cowry balance, etc.) instead of only on first load — mirrors the same
  // fix applied to Daily Streak itself (see _DailyStreakScreenState).
  @override
  void didPopNext() => _load();

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        _service.loadProfile(userId),
        _notificationService.unreadCount(userId),
      ]);
      if (mounted) {
        setState(() {
          _data = results[0] as _ProfileData;
          _unreadCount = results[1] as int;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Profile load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    setState(() => _data = _data?.copyWith(allowInAppNotifications: value));
    try {
      await _service.updateNotifications(userId, value);
    } catch (e) {
      setState(() => _data = _data?.copyWith(allowInAppNotifications: !value));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Could not update preference',
              style: TextStyle(fontFamily: 'Metropolis'),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  // Mirrors getPaymentNotice (profile/page.tsx) verbatim.
  Future<void> _showTopUpModal() async {
    final result = await showDialog<CowryCheckoutResult>(
      context: context,
      builder: (_) => const TopUpCowriesModal(returnTo: 'profile'),
    );
    if (!mounted) return;
    switch (result) {
      case CowryCheckoutResult.success:
        setState(() {
          _loadDone = false;
          _loading = true;
        });
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cowries topped up successfully.', style: TextStyle(fontFamily: 'Metropolis')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        break;
      case CowryCheckoutResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment could not be completed. Please try again.', style: TextStyle(fontFamily: 'Metropolis')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        break;
      case CowryCheckoutResult.missing:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment returned without enough details to confirm it.', style: TextStyle(fontFamily: 'Metropolis')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        break;
      case CowryCheckoutResult.cancelled:
      case null:
        break;
    }
  }

  // Shown in-app (like the cowry checkout WebView) instead of handing off to
  // the system browser — except on platforms webview_flutter doesn't
  // support (desktop, web), where it falls back to the external browser
  // instead of crashing.
  Future<void> _openWebPage(BuildContext context, String path, String title) async {
    final webBaseUrl = dotenv.env['WEB_BASE_URL'] ?? '';
    final url = '$webBaseUrl$path';
    if (supportsInAppWebView) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SimpleWebViewScreen(url: url, title: title),
      ));
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open page.', style: TextStyle(fontFamily: 'Metropolis')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String? _avatarUrl(User? user) {
    final meta = user?.userMetadata;
    final url = (meta?['avatar_url'] as String?) ?? (meta?['picture'] as String?);
    return (url != null && url.isNotEmpty) ? url : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.secondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.arrow_back, size: 20, color: c.foreground),
          ),
        ),
        title: Text(
          'Profile',
          style: TextStyle(
            fontFamily: 'Parkinsans',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: c.foreground,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: c.border),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? Center(
                child: CircularProgressIndicator(
                  color: c.primary,
                  strokeWidth: 2,
                ),
              )
            : _buildBody(context, c),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppColorScheme c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = ThemeProvider.of(context);
    final user = AuthProvider.of(context).user;
    final email = user?.email ?? '';
    final displayName = _data?.name?.isNotEmpty == true
        ? _data!.name!
        : email.split('@').first;
    final initials = _initials(displayName);
    final avatarUrl = _avatarUrl(user);
    final joinedAt = user?.createdAt != null
        ? DateTime.tryParse(user!.createdAt)
        : null;
    final role = _data?.role ?? 'EXPLORER';

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _loadDone = false;
          _loading = true;
        });
        await _load();
      },
      color: c.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(
          children: [
            // ── Profile card ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: c.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 15,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Avatar
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF9C62D9),
                      border: Border.all(color: c.card, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: avatarUrl != null
                          ? Image.network(
                              avatarUrl,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    fontFamily: 'Parkinsans',
                                    fontSize: 28,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  fontFamily: 'Parkinsans',
                                  fontSize: 28,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    displayName,
                    style: TextStyle(
                      fontFamily: 'Parkinsans',
                      fontFamilyFallback: kContentFontFallback,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 13,
                      color: c.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(color: c.border, height: 1),
                  const SizedBox(height: 14),
                  if (joinedAt != null)
                    Text(
                      'Member since ${_formatDate(joinedAt)}',
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 12,
                        color: c.mutedForeground,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Overview stats grid ─────────────────────────────────────────
            // Mirrors ProfileStatsGrid.tsx.
            _StatsGrid(
              cowries: _data?.cowryBalance ?? 0,
              currentStreak: _data?.currentStreak ?? 0,
              levelName: _data?.levelName,
              role: role,
              c: c,
            ),
            const SizedBox(height: 12),

            // ── Buy Cowries ───────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _showTopUpModal,
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18, color: Color(0xFF1A1A1A)),
                label: const Text(
                  'Buy Cowries',
                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFBBF24),
                  shape: const StadiumBorder(),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // TEMPORARY dev tool — see lib/widgets/dev_role_switcher.dart.
            if (kDebugMode) const DevRoleSwitcher(),

            // ── Settings card ─────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: c.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 15,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Settings header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c.secondary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.settings_outlined,
                            size: 20,
                            color: c.mutedForeground,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Settings',
                              style: TextStyle(
                                fontFamily: 'Parkinsans',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: c.foreground,
                              ),
                            ),
                            Text(
                              'Manage preferences and notifications',
                              style: TextStyle(
                                fontFamily: 'Metropolis',
                                fontSize: 12,
                                color: c.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: c.border),

                  // PREFERENCES
                  _GroupLabel('PREFERENCES', c: c),
                  _SettingsTile(
                    icon: Icons.description_outlined,
                    iconBg: c.secondary,
                    iconColor: c.mutedForeground,
                    label: 'View all notifications',
                    trailing: _unreadCount > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.secondary,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '$_unreadCount',
                              style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, fontWeight: FontWeight.w600, color: c.mutedForeground),
                            ),
                          )
                        : null,
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const NotificationsScreen()))
                        .then((_) => _load()),
                    c: c,
                  ),
                  _SettingsTile(
                    icon: Icons.notifications_outlined,
                    iconBg: c.secondary,
                    iconColor: c.mutedForeground,
                    label: 'Allow In-App Notifications',
                    subtitle: 'Receive updates about your contributions',
                    trailing: Switch(
                      value: _data?.allowInAppNotifications ?? true,
                      onChanged: _toggleNotifications,
                      activeThumbColor: const Color(0xFF9C62D9),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    c: c,
                  ),
                  // Mirrors PushNotificationsToggle.tsx: that's browser Web
                  // Push (Service Worker + VAPID), which has no native mobile
                  // equivalent built yet — shown disabled with an inline
                  // reason (matching the web component's own
                  // disables-with-reason pattern when unsupported) rather
                  // than silently hidden.
                  _SettingsTile(
                    icon: Icons.notifications_active_outlined,
                    iconBg: c.secondary,
                    iconColor: c.mutedForeground,
                    label: 'Allow Push Notifications',
                    subtitle: 'Not available on this device yet',
                    trailing: Switch(
                      value: false,
                      onChanged: null,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    c: c,
                  ),
                  _SettingsTile(
                    icon: theme.isDark
                        ? Icons.wb_sunny_rounded
                        : Icons.dark_mode_outlined,
                    iconBg: c.secondary,
                    iconColor: theme.isDark
                        ? const Color(0xFFF59E0B)
                        : c.mutedForeground,
                    label: 'Switch to Dark Mode',
                    subtitle: 'Switch between light and dark themes',
                    trailing: Switch(
                      value: theme.isDark,
                      onChanged: (_) => theme.toggle(),
                      activeThumbColor: const Color(0xFF9C62D9),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    c: c,
                  ),

                  Divider(height: 1, color: c.border),

                  // COMMUNITY
                  _GroupLabel('COMMUNITY', c: c),
                  _CommunityTile(
                    communityName: _data?.communityName,
                    c: c,
                    isDark: isDark,
                  ),
                  _SettingsTile(
                    icon: Icons.menu_book_outlined,
                    iconBg: isDark
                        ? const Color(0xFF581C87).withValues(alpha: 0.3)
                        : const Color(0xFFFAF5FF),
                    iconColor: isDark
                        ? const Color(0xFFA855F7)
                        : const Color(0xFF9333EA),
                    label: 'Community Guidelines & Notes',
                    onTap: () {},
                    c: c,
                  ),

                  Divider(height: 1, color: c.border),

                  // MORE (collapsible)
                  _MoreToggle(
                    expanded: _moreExpanded,
                    onToggle: () =>
                        setState(() => _moreExpanded = !_moreExpanded),
                    c: c,
                  ),
                  if (_moreExpanded) ...[
                    _SettingsTile(
                      icon: Icons.lock_outline,
                      iconBg: c.secondary,
                      iconColor: c.mutedForeground,
                      label: 'Privacy Settings',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PrivacySettingsScreen(),
                        ),
                      ),
                      c: c,
                    ),
                    _SettingsTile(
                      icon: Icons.description_outlined,
                      iconBg: c.secondary,
                      iconColor: c.mutedForeground,
                      label: 'Privacy Policy',
                      onTap: () => _openWebPage(context, '/privacy-policy', 'Privacy Policy'),
                      c: c,
                    ),
                  ],

                  // Administration — visible to admins only.
                  if (hasPermission(role, Permission.viewAdmin)) ...[
                    Divider(height: 1, color: c.border),
                    _GroupLabel('ADMINISTRATION', c: c),
                    _SettingsTile(
                      icon: Icons.shield_outlined,
                      iconBg: isDark ? const Color(0xFF881337).withValues(alpha: 0.3) : const Color(0xFFFFF1F2),
                      iconColor: isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48),
                      label: 'Admin Dashboard',
                      onTap: () => _openWebPage(context, '/admin', 'Admin Dashboard'),
                      c: c,
                    ),
                  ],

                  // Management — visible to managers only.
                  if (hasPermission(role, Permission.viewManager)) ...[
                    Divider(height: 1, color: c.border),
                    _GroupLabel('MANAGEMENT', c: c),
                    _SettingsTile(
                      icon: Icons.shield_outlined,
                      iconBg: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.3) : const Color(0xFFECFDF5),
                      iconColor: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                      label: 'Manager Board',
                      onTap: () => _openWebPage(context, '/manager', 'Manager Board'),
                      c: c,
                    ),
                  ],

                  Divider(height: 1, color: c.border),

                  // Log Out
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: InkWell(
                      onTap: () async {
                        await AuthProvider.of(context).logout();
                        if (context.mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            '/signin',
                            (route) => false,
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(
                                  alpha: isDark ? 0.2 : 0.08,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.logout,
                                size: 18,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Log Out',
                              style: TextStyle(
                                fontFamily: 'Metropolis',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

// ── Overview stats grid ──────────────────────────────────────────────────────
// Mirrors ProfileStatsGrid.tsx: a 2x2 grid of Streak / Cowries / Level /
// User type, each a small icon + stacked label/value.

String _formatEnumValue(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1).toLowerCase();

class _StatsGrid extends StatelessWidget {
  final int cowries;
  final int currentStreak;
  final String? levelName;
  final String role;
  final AppColorScheme c;

  const _StatsGrid({
    required this.cowries,
    required this.currentStreak,
    required this.levelName,
    required this.role,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overview',
            style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  iconAsset: 'assets/profile/streak-flame.svg',
                  label: 'Streak',
                  value: '$currentStreak ${currentStreak == 1 ? 'day' : 'days'} streak',
                  c: c,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DailyStreakScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatItem(
                  iconAsset: 'assets/profile/streak-cowry.png',
                  label: 'Cowries',
                  value: '$cowries ${cowries == 1 ? 'Cowry' : 'Cowries'}',
                  c: c,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  iconAsset: 'assets/profile/streak-level.svg',
                  label: 'Level',
                  value: levelName ?? 'Not started',
                  c: c,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatItem(
                  iconAsset: 'assets/profile/streak-user-type.svg',
                  label: 'User type',
                  value: _formatEnumValue(role),
                  c: c,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  // Mirrors ProfileStatsGrid.tsx's per-row `/assets/profile/*` image —
  // streak-flame.svg, streak-level.svg (a Twemoji brain, not a school icon),
  // streak-cowry.png (the only raster asset), streak-user-type.svg (a flat
  // purple Boxicons robot, not a person icon) — all rendered at 24x24
  // regardless of role/value, matching web's fixed `h-6 w-6` sizing.
  final String iconAsset;
  final String label;
  final String value;
  final AppColorScheme c;
  final VoidCallback? onTap;

  const _StatItem({
    required this.iconAsset,
    required this.label,
    required this.value,
    required this.c,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = iconAsset.endsWith('.svg')
        ? SvgPicture.asset(iconAsset, width: 24, height: 24, fit: BoxFit.contain)
        : Image.asset(iconAsset, width: 24, height: 24, fit: BoxFit.contain);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon,
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, fontWeight: FontWeight.w700, color: c.foreground),
              ),
            ],
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: row,
    );
  }
}

// ── Community tile ─────────────────────────────────────────────────────────────
// Display-only, matching profile/page.tsx:399-425 exactly: that tile has no
// onClick at all (just hover styling) — the community/target language is a
// one-time onboarding choice in neolingo, never re-editable from Settings.

class _CommunityTile extends StatelessWidget {
  final String? communityName;
  final AppColorScheme c;
  final bool isDark;

  const _CommunityTile({
    required this.communityName,
    required this.c,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E3A8A).withValues(alpha: 0.3)
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.campaign_outlined,
                size: 16,
                color: isDark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Awalingo Community',
                style: TextStyle(
                  fontFamily: 'Metropolis',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.foreground,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.secondary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                communityName ?? 'No Community',
                style: TextStyle(
                  fontFamily: 'Metropolis',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: c.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Collapsible More toggle ────────────────────────────────────────────────────

class _MoreToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final AppColorScheme c;

  const _MoreToggle({
    required this.expanded,
    required this.onToggle,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'More',
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.foreground,
                  ),
                ),
              ),
              Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 18,
                color: c.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Settings tile ──────────────────────────────────────────────────────────────

class _GroupLabel extends StatelessWidget {
  final String text;
  final AppColorScheme c;
  const _GroupLabel(this.text, {required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Metropolis',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c.mutedForeground,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final AppColorScheme c;

  const _SettingsTile({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: c.foreground,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: 'Metropolis',
                          fontSize: 12,
                          color: c.mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Icon(Icons.chevron_right, size: 18, color: c.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
