import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/theme_notifier.dart';

class _ProfileData {
  final String? name;
  final int cowryBalance;
  final bool allowInAppNotifications;
  final String? communityName;
  final int neoCount;

  const _ProfileData({
    this.name,
    this.cowryBalance = 0,
    this.allowInAppNotifications = true,
    this.communityName,
    this.neoCount = 0,
  });

  _ProfileData copyWith({bool? allowInAppNotifications}) => _ProfileData(
        name: name,
        cowryBalance: cowryBalance,
        allowInAppNotifications:
            allowInAppNotifications ?? this.allowInAppNotifications,
        communityName: communityName,
        neoCount: neoCount,
      );
}

class _ProfileService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<_ProfileData> loadProfile(String userId) async {
    final profile = await _db
        .from('user_profile')
        .select('name, cowryBalance, allowInAppNotifications')
        .eq('userId', userId)
        .maybeSingle();

    final utl = await _db
        .from('user_target_languages')
        .select('language:languages!languageId(id, name)')
        .eq('userId', userId)
        .maybeSingle();

    final neoRows = await _db.from('neos').select('id').eq('userId', userId);
    final lang = utl?['language'] as Map<String, dynamic>?;

    return _ProfileData(
      name: profile?['name'] as String?,
      cowryBalance: (profile?['cowryBalance'] as int?) ?? 0,
      allowInAppNotifications:
          (profile?['allowInAppNotifications'] as bool?) ?? true,
      communityName: lang?['name'] as String?,
      neoCount: neoRows.length,
    );
  }

  Future<void> updateNotifications(String userId, bool value) async {
    await _db
        .from('user_profile')
        .update({'allowInAppNotifications': value}).eq('userId', userId);
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _service = _ProfileService();
  bool _loading = true;
  _ProfileData? _data;
  bool _loadDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadDone) {
      _loadDone = true;
      _load();
    }
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await _service.loadProfile(userId);
      if (mounted) setState(() { _data = data; _loading = false; });
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Could not update preference',
              style: TextStyle(fontFamily: 'Metropolis')),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary, strokeWidth: 2))
          : _buildBody(context, c, isDark),
    );
  }

  Widget _buildBody(BuildContext context, AppColorScheme c, bool isDark) {
    final user = AuthProvider.of(context).user;
    final theme = ThemeProvider.of(context);
    final email = user?.email ?? '';
    final displayName = _data?.name?.isNotEmpty == true
        ? _data!.name!
        : email.split('@').first;
    final initials = _initials(displayName);
    final joinedAt =
        user?.createdAt != null ? DateTime.tryParse(user!.createdAt) : null;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() { _loadDone = false; _loading = true; });
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
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.07),
                    blurRadius: 15,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
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
                    child: Center(
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
                  const SizedBox(height: 14),
                  Text(
                    displayName,
                    style: TextStyle(
                      fontFamily: 'Parkinsans',
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

            // ── Stats row ─────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    iconWidget: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFDE68A), width: 3),
                      ),
                      child: const Icon(Icons.emoji_events, color: Color(0xFF1A1A1A), size: 22),
                    ),
                    value: '${_data?.cowryBalance ?? 0} 🐚',
                    label: 'Cowries',
                    c: c,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    iconWidget: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF9C62D9).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(child: Text('✍️', style: TextStyle(fontSize: 22))),
                    ),
                    value: '${_data?.neoCount ?? 0}',
                    label: 'Words',
                    c: c,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Settings card ─────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: c.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.07),
                    blurRadius: 15,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
                          child: Icon(Icons.settings_outlined, size: 20, color: c.mutedForeground),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Settings',
                          style: TextStyle(
                            fontFamily: 'Parkinsans',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: c.foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: c.border),

                  _GroupLabel('PREFERENCES', c: c),
                  _SettingsTile(
                    iconBg: c.secondary,
                    iconColor: c.mutedForeground,
                    icon: Icons.notifications_outlined,
                    label: 'In-App Notifications',
                    trailing: Switch(
                      value: _data?.allowInAppNotifications ?? true,
                      onChanged: _toggleNotifications,
                      activeThumbColor: const Color(0xFF9C62D9),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    c: c,
                  ),
                  _SettingsTile(
                    iconBg: c.secondary,
                    iconColor: theme.isDark ? const Color(0xFFF59E0B) : c.mutedForeground,
                    icon: theme.isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_outlined,
                    label: 'Dark Mode',
                    trailing: Switch(
                      value: theme.isDark,
                      onChanged: (_) => theme.toggle(),
                      activeThumbColor: const Color(0xFF9C62D9),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    c: c,
                  ),

                  Divider(height: 1, color: c.border),

                  _GroupLabel('COMMUNITY', c: c),
                  _SettingsTile(
                    iconBg: isDark
                        ? const Color(0xFF1E3A8A).withValues(alpha: 0.3)
                        : const Color(0xFFEFF6FF),
                    iconColor: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                    icon: Icons.language,
                    label: 'Change Community',
                    subtitle: _data?.communityName,
                    onTap: () => Navigator.of(context).pushNamed('/language-setup'),
                    c: c,
                  ),
                  _SettingsTile(
                    iconBg: isDark
                        ? const Color(0xFF581C87).withValues(alpha: 0.3)
                        : const Color(0xFFFAF5FF),
                    iconColor: isDark ? const Color(0xFFA855F7) : const Color(0xFF9333EA),
                    icon: Icons.menu_book_outlined,
                    label: 'Community Guidelines',
                    onTap: () {},
                    c: c,
                  ),

                  Divider(height: 1, color: c.border),

                  _GroupLabel('MORE', c: c),
                  _SettingsTile(
                    iconBg: c.secondary,
                    iconColor: c.mutedForeground,
                    icon: Icons.lock_outline,
                    label: 'Privacy Settings',
                    onTap: () {},
                    c: c,
                  ),
                  _SettingsTile(
                    iconBg: c.secondary,
                    iconColor: c.mutedForeground,
                    icon: Icons.gavel_outlined,
                    label: 'Legal Hub',
                    onTap: () {},
                    c: c,
                  ),

                  Divider(height: 1, color: c.border),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: InkWell(
                      onTap: () async {
                        await AuthProvider.of(context).logout();
                        if (context.mounted) {
                          Navigator.of(context)
                              .pushNamedAndRemoveUntil('/signin', (route) => false);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.logout, size: 20, color: Colors.red),
                            ),
                            const SizedBox(width: 14),
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
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

class _StatCard extends StatelessWidget {
  final Widget iconWidget;
  final String value;
  final String label;
  final AppColorScheme c;

  const _StatCard({required this.iconWidget, required this.value, required this.label, required this.c});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06), blurRadius: 15, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          iconWidget,
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
              Text(label, style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, color: c.mutedForeground)),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  final AppColorScheme c;
  const _GroupLabel(this.text, {required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(text, style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, fontWeight: FontWeight.w600, color: c.mutedForeground, letterSpacing: 0.8)),
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
                width: 40, height: 40,
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, fontWeight: FontWeight.w500, color: c.foreground)),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
                  ],
                ),
              ),
              if (trailing != null) trailing!
              else if (onTap != null)
                Icon(Icons.chevron_right, size: 18, color: c.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
