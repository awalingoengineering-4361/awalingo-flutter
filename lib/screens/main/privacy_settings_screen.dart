import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';

// Mirrors LEGAL_POLICY_VERSION (lib/legal.ts).
const _kLegalPolicyVersion = '2026-05-v1';

// ── Model ─────────────────────────────────────────────────────────────────────

// Mirrors ConsentPreferences (types/consent.ts). Defaults match
// createDefaultConsentPreferences (lib/consent/storage.ts): everything
// on until the user has actually saved a preference.
class _ConsentPreferences {
  final bool analytics;
  final bool errorMonitoring;
  final bool marketingEmail;
  final bool marketingPush;
  final DateTime? consentedAt;
  const _ConsentPreferences({
    this.analytics = true,
    this.errorMonitoring = true,
    this.marketingEmail = true,
    this.marketingPush = true,
    this.consentedAt,
  });

  _ConsentPreferences copyWith({
    bool? analytics, bool? errorMonitoring, bool? marketingEmail, bool? marketingPush, DateTime? consentedAt,
  }) => _ConsentPreferences(
    analytics: analytics ?? this.analytics,
    errorMonitoring: errorMonitoring ?? this.errorMonitoring,
    marketingEmail: marketingEmail ?? this.marketingEmail,
    marketingPush: marketingPush ?? this.marketingPush,
    consentedAt: consentedAt ?? this.consentedAt,
  );
}

// ── Service ───────────────────────────────────────────────────────────────────

// Mirrors getConsentPreferences/updateConsentPreferences (actions/consent.ts):
// this is stored directly on user_profile, not a separate consent table.
class _ConsentService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<_ConsentPreferences> load(String userId) async {
    final row = await _db
        .from('user_profile')
        .select('allowAnalytics, allowErrorMonitoring, allowMarketingEmail, allowMarketingPush, consentedAt')
        .eq('userId', userId)
        .maybeSingle();
    return _ConsentPreferences(
      analytics: (row?['allowAnalytics'] as bool?) ?? true,
      errorMonitoring: (row?['allowErrorMonitoring'] as bool?) ?? true,
      marketingEmail: (row?['allowMarketingEmail'] as bool?) ?? true,
      marketingPush: (row?['allowMarketingPush'] as bool?) ?? true,
      consentedAt: DateTime.tryParse(row?['consentedAt'] as String? ?? ''),
    );
  }

  Future<void> update(String userId, _ConsentPreferences prefs) async {
    await _db.from('user_profile').update({
      'allowAnalytics': prefs.analytics,
      'allowErrorMonitoring': prefs.errorMonitoring,
      'allowMarketingEmail': prefs.marketingEmail,
      'allowMarketingPush': prefs.marketingPush,
      'consentPolicyVersion': _kLegalPolicyVersion,
      'consentedAt': DateTime.now().toUtc().toIso8601String(),
      'consentSource': 'settings',
    }).eq('userId', userId);
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final _service = _ConsentService();
  bool _loading = true;
  bool _saving = false;
  _ConsentPreferences _prefs = const _ConsentPreferences();
  String? _userId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _userId = Supabase.instance.client.auth.currentUser?.id;
    if (_loading) _load();
  }

  Future<void> _load() async {
    if (_userId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final prefs = await _service.load(_userId!);
      if (mounted) setState(() { _prefs = prefs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply(_ConsentPreferences next) async {
    if (_userId == null) return;
    setState(() { _prefs = next; _saving = true; });
    try {
      await _service.update(_userId!, next);
      if (mounted) {
        setState(() => _prefs = next.copyWith(consentedAt: DateTime.now()));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Privacy preferences updated', style: TextStyle(fontFamily: 'Metropolis')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('PrivacySettings update: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Mirrors withdrawNonEssential (ConsentContext.tsx).
  Future<void> _withdrawNonEssential() async {
    await _apply(const _ConsentPreferences(
      analytics: false, errorMonitoring: false, marketingEmail: false, marketingPush: false,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Non-essential consent withdrawn', style: TextStyle(fontFamily: 'Metropolis')),
        behavior: SnackBarBehavior.floating,
      ));
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
        title: Text('Privacy Settings',
            style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.border)),
      ),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: c.primary, strokeWidth: 2))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Policy version: $_kLegalPolicyVersion',
                            style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
                        const SizedBox(height: 2),
                        Text(
                          'Last consent update: ${_prefs.consentedAt?.toLocal().toString().split('.').first ?? 'Not set'}',
                          style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground),
                        ),
                        const SizedBox(height: 16),
                        _ConsentRow(label: 'Essential processing', value: true, enabled: false, c: c, onChanged: (_) {}),
                        _ConsentRow(
                          label: 'Analytics',
                          value: _prefs.analytics,
                          enabled: !_saving,
                          c: c,
                          onChanged: (v) => _apply(_prefs.copyWith(analytics: v)),
                        ),
                        _ConsentRow(
                          label: 'Error monitoring diagnostics',
                          value: _prefs.errorMonitoring,
                          enabled: !_saving,
                          c: c,
                          onChanged: (v) => _apply(_prefs.copyWith(errorMonitoring: v)),
                        ),
                        _ConsentRow(
                          label: 'Marketing email',
                          value: _prefs.marketingEmail,
                          enabled: !_saving,
                          c: c,
                          onChanged: (v) => _apply(_prefs.copyWith(marketingEmail: v)),
                        ),
                        _ConsentRow(
                          label: 'Marketing push alerts',
                          value: _prefs.marketingPush,
                          enabled: !_saving,
                          c: c,
                          onChanged: (v) => _apply(_prefs.copyWith(marketingPush: v)),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _saving ? null : _withdrawNonEssential,
                          style: OutlinedButton.styleFrom(
                            shape: const StadiumBorder(),
                            foregroundColor: c.foreground,
                            side: BorderSide(color: c.border),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          ),
                          child: const Text('Withdraw all non-essential',
                              style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  final String label;
  final bool value;
  final bool enabled;
  final AppColorScheme c;
  final ValueChanged<bool> onChanged;
  const _ConsentRow({required this.label, required this.value, required this.enabled, required this.c, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.foreground)),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: c.primary,
          ),
        ],
      ),
    );
  }
}
