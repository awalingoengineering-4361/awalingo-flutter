import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  bool _allowAnalytics = true;
  bool _allowPublicProfile = true;
  bool _allowLeaderboard = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) { setState(() => _loading = false); return; }
    try {
      final row = await _db
          .from('user_profile')
          .select('allowAnalytics, allowPublicProfile, allowLeaderboard')
          .eq('userId', userId)
          .maybeSingle();
      if (mounted) setState(() {
        _allowAnalytics = (row?['allowAnalytics'] as bool?) ?? true;
        _allowPublicProfile = (row?['allowPublicProfile'] as bool?) ?? true;
        _allowLeaderboard = (row?['allowLeaderboard'] as bool?) ?? true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(String field, bool value) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _db.from('user_profile').update({field: value}).eq('userId', userId);
    } catch (e) {
      debugPrint('PrivacySettings update: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: BackButton(color: c.foreground),
        title: Text('Privacy Settings', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.border)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary, strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionLabel(label: 'Data & Visibility', c: c),
                const SizedBox(height: 8),
                _PrivacyTile(
                  icon: Icons.bar_chart_outlined,
                  title: 'Usage Analytics',
                  subtitle: 'Help us improve the app by sharing anonymous usage data',
                  value: _allowAnalytics,
                  c: c,
                  onChanged: (v) {
                    setState(() => _allowAnalytics = v);
                    _update('allowAnalytics', v);
                  },
                ),
                _PrivacyTile(
                  icon: Icons.person_outline,
                  title: 'Public Profile',
                  subtitle: 'Allow your contributions to appear in community leaderboards',
                  value: _allowPublicProfile,
                  c: c,
                  onChanged: (v) {
                    setState(() => _allowPublicProfile = v);
                    _update('allowPublicProfile', v);
                  },
                ),
                _PrivacyTile(
                  icon: Icons.emoji_events_outlined,
                  title: 'Leaderboard Visibility',
                  subtitle: 'Show your name on the community leaderboard',
                  value: _allowLeaderboard,
                  c: c,
                  onChanged: (v) {
                    setState(() => _allowLeaderboard = v);
                    _update('allowLeaderboard', v);
                  },
                ),
                const SizedBox(height: 24),
                _SectionLabel(label: 'Your Data', c: c),
                const SizedBox(height: 8),
                _InfoTile(
                  icon: Icons.download_outlined,
                  title: 'Download Your Data',
                  subtitle: 'Request a copy of all data associated with your account',
                  c: c,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Data export coming soon.', style: TextStyle(fontFamily: 'Metropolis')),
                    behavior: SnackBarBehavior.floating,
                  )),
                ),
                _InfoTile(
                  icon: Icons.delete_outline,
                  title: 'Delete Account',
                  subtitle: 'Permanently remove your account and all associated data',
                  c: c,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Please contact support to delete your account.', style: TextStyle(fontFamily: 'Metropolis')),
                    behavior: SnackBarBehavior.floating,
                  )),
                  isDestructive: true,
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final AppColorScheme c;
  const _SectionLabel({required this.label, required this.c});

  @override
  Widget build(BuildContext context) => Text(label,
      style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, fontWeight: FontWeight.w600, color: c.mutedForeground, letterSpacing: 0.5));
}

class _PrivacyTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final AppColorScheme c;
  final ValueChanged<bool> onChanged;
  const _PrivacyTile({required this.icon, required this.title, required this.subtitle, required this.value, required this.c, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: c.mutedForeground),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, fontWeight: FontWeight.w500, color: c.foreground)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
            ]),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged, activeThumbColor: c.primary),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final AppColorScheme c;
  final VoidCallback onTap;
  final bool isDestructive;
  const _InfoTile({required this.icon, required this.title, required this.subtitle, required this.c, required this.onTap, this.isDestructive = false});

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? const Color(0xFFEF4444) : c.foreground;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: isDestructive ? const Color(0xFFEF4444).withValues(alpha: 0.1) : c.secondary, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, fontWeight: FontWeight.w500, color: color)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
              ]),
            ),
            Icon(Icons.chevron_right, color: c.mutedForeground, size: 18),
          ],
        ),
      ),
    );
  }
}
