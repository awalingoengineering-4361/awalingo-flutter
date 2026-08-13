import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import 'curator_test_screen.dart';

// ── Service ───────────────────────────────────────────────────────────────────

class _CuratorEligibility {
  final bool canTake;
  final String? reason;
  final DateTime? eligibleAt;
  final bool alreadyCurator;
  const _CuratorEligibility({required this.canTake, this.reason, this.eligibleAt, this.alreadyCurator = false});
}

class _BecomeCuratorService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<_CuratorEligibility> check(String userId) async {
    // Check current role
    final roleRow = await _db
        .from('user_roles')
        .select('role:roles!roleId(name)')
        .eq('userId', userId)
        .maybeSingle();
    final roleName = (roleRow?['role'] as Map<String, dynamic>?)?['name'] as String?;

    if (roleName == 'CURATOR' || roleName == 'JUROR' || roleName == 'MANAGER' || roleName == 'ADMIN') {
      return const _CuratorEligibility(canTake: false, alreadyCurator: true);
    }

    // Check recent failed attempt (7-day cooldown)
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final recentFail = await _db
        .from('quiz_attempts')
        .select('createdAt')
        .eq('userId', userId)
        .eq('passed', false)
        .gte('createdAt', cutoff.toIso8601String())
        .order('createdAt', ascending: false)
        .limit(1)
        .maybeSingle();

    if (recentFail != null) {
      final failedAt = DateTime.tryParse(recentFail['createdAt'] as String? ?? '');
      final eligibleAt = failedAt?.add(const Duration(days: 7));
      return _CuratorEligibility(
        canTake: false,
        reason: 'You recently took the test.',
        eligibleAt: eligibleAt,
      );
    }

    return const _CuratorEligibility(canTake: true);
  }

  Future<bool> hasTargetLanguage(String userId) async {
    final row = await _db.from('user_target_languages').select('languageId').eq('userId', userId).maybeSingle();
    return row != null;
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class BecomeCuratorScreen extends StatefulWidget {
  const BecomeCuratorScreen({super.key});

  @override
  State<BecomeCuratorScreen> createState() => _BecomeCuratorScreenState();
}

class _BecomeCuratorScreenState extends State<BecomeCuratorScreen> {
  final _service = _BecomeCuratorService();
  bool _loading = true;
  bool _acknowledged = false;
  _CuratorEligibility? _eligibility;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _check();
  }

  Future<void> _check() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) { setState(() => _loading = false); return; }
    try {
      final eligibility = await _service.check(userId);
      if (mounted) setState(() { _eligibility = eligibility; _loading = false; });
    } catch (e) {
      debugPrint('BecomeCurator check: $e');
      if (mounted) setState(() { _eligibility = const _CuratorEligibility(canTake: true); _loading = false; });
    }
  }

  void _startTest() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CuratorTestScreen()));
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
        title: Text('Become a Curator', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.border)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary, strokeWidth: 2))
          : _eligibility?.alreadyCurator == true
              ? _AlreadyCuratorView(c: c)
              : _eligibility?.canTake == false
                  ? _IneligibleView(eligibility: _eligibility!, c: c)
                  : _RulesView(
                      acknowledged: _acknowledged,
                      onAcknowledgeChanged: (v) => setState(() => _acknowledged = v ?? false),
                      onStart: _acknowledged ? _startTest : null,
                      c: c,
                    ),
    );
  }
}

// ── Rules View ────────────────────────────────────────────────────────────────

class _RulesView extends StatelessWidget {
  final bool acknowledged;
  final ValueChanged<bool?> onAcknowledgeChanged;
  final VoidCallback? onStart;
  final AppColorScheme c;
  const _RulesView({required this.acknowledged, required this.onAcknowledgeChanged, required this.onStart, required this.c});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.edit_outlined, color: c.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Curator Test', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
                ]),
                const SizedBox(height: 8),
                Text('Become a Curator and start translating words into your community language.',
                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text('Test Rules', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 15, fontWeight: FontWeight.w600, color: c.foreground)),
          const SizedBox(height: 12),

          for (final rule in [
            (Icons.quiz_outlined,    '10 multiple-choice questions about your community language'),
            (Icons.timer_outlined,   '10 minutes total — the test auto-submits when time runs out'),
            (Icons.bar_chart,        'Score 70% or higher to pass and earn the Curator role'),
            (Icons.repeat_outlined,  'If you don\'t pass, you can retake after 7 days'),
          ])
            _RuleItem(icon: rule.$1, text: rule.$2, c: c),

          const SizedBox(height: 24),

          // Acknowledge checkbox
          GestureDetector(
            onTap: () => onAcknowledgeChanged(!acknowledged),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(value: acknowledged, onChanged: onAcknowledgeChanged, activeColor: c.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('I have read the rules and I am ready to start.',
                        style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.foreground)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: onStart,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: c.primaryForeground,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Take the Test', style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _RuleItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final AppColorScheme c;
  const _RuleItem({required this.icon, required this.text, required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: c.mutedForeground),
          ),
          const SizedBox(width: 12),
          Expanded(child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(text, style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.foreground)),
          )),
        ],
      ),
    );
  }
}

// ── Ineligible View ───────────────────────────────────────────────────────────

class _IneligibleView extends StatelessWidget {
  final _CuratorEligibility eligibility;
  final AppColorScheme c;
  const _IneligibleView({required this.eligibility, required this.c});

  @override
  Widget build(BuildContext context) {
    final eligibleAt = eligibility.eligibleAt;
    final dateStr = eligibleAt != null
        ? '${eligibleAt.day}/${eligibleAt.month}/${eligibleAt.year}'
        : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
              child: Icon(Icons.schedule, size: 30, color: c.mutedForeground),
            ),
            const SizedBox(height: 20),
            Text('Not Yet Eligible', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
            const SizedBox(height: 8),
            Text(eligibility.reason ?? 'You are not eligible to take the test yet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground)),
            if (dateStr != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(8)),
                child: Text('Eligible again on $dateStr',
                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlreadyCuratorView extends StatelessWidget {
  final AppColorScheme c;
  const _AlreadyCuratorView({required this.c});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(Icons.check_circle, size: 30, color: c.primary),
            ),
            const SizedBox(height: 20),
            Text("You're already a Curator!", style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
            const SizedBox(height: 8),
            Text('Keep suggesting translations and help grow your community.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}
