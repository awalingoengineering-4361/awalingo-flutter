import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../widgets/bottom_nav.dart';

// ── Service ───────────────────────────────────────────────────────────────────

class _HomeService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<({String? voteWord, String communityName, int communityId, String role})>
      load(String userId) async {
    // Run community, role, and neo queries in parallel
    final results = await Future.wait([
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
    ]);

    final utl = results[0];
    final userRoleRow = results[1];

    final lang = utl?['language'] as Map<String, dynamic>?;
    final communityId = (lang?['id'] as int?) ?? 1;
    final communityName = (lang?['name'] as String?) ?? 'Community';

    final roleMap = userRoleRow?['role'] as Map<String, dynamic>?;
    final role = (roleMap?['name'] as String?) ?? 'EXPLORER';

    final neoRows = await _db
        .from('neos')
        .select('termId, ratingCount, rejectCount')
        .eq('languageId', communityId)
        .gt('ratingCount', 0)
        .limit(20);

    final validTermIds = neoRows
        .where((n) =>
            (n['rejectCount'] as int? ?? 0) < (n['ratingCount'] as int? ?? 0))
        .map((n) => n['termId'] as int)
        .toSet()
        .toList();

    String? voteWord;
    if (validTermIds.isNotEmpty) {
      final term = await _db
          .from('terms')
          .select('text')
          .eq('id', validTermIds.first)
          .maybeSingle();
      voteWord = term?['text'] as String?;
    }

    return (
      voteWord: voteWord,
      communityName: communityName,
      communityId: communityId,
      role: role,
    );
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class MenuScreen extends StatefulWidget {
  final void Function(NavTab)? onNavigate;
  const MenuScreen({super.key, this.onNavigate});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final _service = _HomeService();
  bool _loading = true;
  bool _loadDone = false;
  String? _voteWord;
  String _role = 'EXPLORER';

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
      final data = await _service.load(userId);
      if (mounted) {
        setState(() {
          _voteWord = data.voteWord;
          _role = data.role;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('MenuScreen load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final user = AuthProvider.of(context).user;
    final name = user?.userMetadata?['name'] as String? ??
        user?.userMetadata?['display_name'] as String? ??
        user?.email?.split('@').first ??
        'User';
    final firstName = name.split(' ').first;

    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: c.primary, strokeWidth: 2));
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() { _loadDone = false; _loading = true; });
        await _load();
      },
      color: c.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Greeting ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  Text(
                    'Hi, $firstName',
                    style: TextStyle(
                      fontFamily: 'Parkinsans',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9C62D9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _role[0] + _role.substring(1).toLowerCase(),
                      style: const TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Vote card ─────────────────────────────────────────────────
            _CtaCard(
              title: 'Vote for today\'s best word',
              subtitle: 'Vote for the top ranked suggested words',
              word: _voteWord ?? 'Awalingo',
              ctaLabel: 'Word of the day',
              buttonLabel: 'Vote',
              buttonIcon: Icons.how_to_vote_outlined,
              innerBg: isDark
                  ? const Color(0xFF14532D).withValues(alpha: 0.35)
                  : const Color(0xFFE4FDE4),
              innerBorder: isDark
                  ? const Color(0xFF166534)
                  : const Color(0xFFC8FAC9),
              pillBg: isDark
                  ? const Color(0xFF166534).withValues(alpha: 0.5)
                  : const Color(0xFFE4FDE4),
              pillText: isDark
                  ? const Color(0xFF86EFAC)
                  : const Color(0xFF50954D),
              wordColor: isDark
                  ? const Color(0xFFFAFAFA)
                  : const Color(0xFF111111),
              onTap: () => widget.onNavigate?.call(NavTab.vote),
              c: c,
              isDark: isDark,
            ),
            const SizedBox(height: 12),

            // ── Explore card ──────────────────────────────────────────────
            _CtaCard(
              title: 'Explore Awadiko',
              subtitle: 'Browse words and their community translations',
              word: 'The community dictionary',
              ctaLabel: 'Awadiko',
              buttonLabel: 'Explore',
              buttonIcon: Icons.menu_book_outlined,
              innerBg: isDark
                  ? const Color(0xFF164E63).withValues(alpha: 0.35)
                  : const Color(0xFFECFEFF),
              innerBorder: isDark
                  ? const Color(0xFF155E75)
                  : const Color(0xFFA5F3FC),
              pillBg: isDark
                  ? const Color(0xFF155E75).withValues(alpha: 0.5)
                  : const Color(0xFFCFFAFE),
              pillText: isDark
                  ? const Color(0xFF67E8F9)
                  : const Color(0xFF0E7490),
              wordColor: isDark
                  ? const Color(0xFFFAFAFA)
                  : const Color(0xFF111111),
              onTap: () => widget.onNavigate?.call(NavTab.dictionary),
              c: c,
              isDark: isDark,
            ),
            const SizedBox(height: 12),

            // ── Request card ──────────────────────────────────────────────
            _CtaCard(
              title: 'Request A Word',
              subtitle: 'Got a word in your mind?',
              word: 'Ask the community to mine Words',
              ctaLabel: 'Word on your mind',
              buttonLabel: 'Request',
              buttonIcon: Icons.book_outlined,
              innerBg: isDark
                  ? const Color(0xFF3B0764).withValues(alpha: 0.35)
                  : const Color(0xFFF8F3FD),
              innerBorder: isDark
                  ? const Color(0xFF4C1D95)
                  : const Color(0xFFEADDF7),
              pillBg: isDark
                  ? const Color(0xFF4C1D95).withValues(alpha: 0.5)
                  : const Color(0xFFF8F3FD),
              pillText: isDark
                  ? const Color(0xFFD8B4FE)
                  : const Color(0xFF292929),
              wordColor: isDark
                  ? const Color(0xFFD8B4FE)
                  : const Color(0xFF6826AF),
              onTap: () => Navigator.of(context).pushNamed('/request'),
              c: c,
              isDark: isDark,
            ),
            const SizedBox(height: 12),

            // ── Social card ───────────────────────────────────────────────
            _SocialCard(c: c, isDark: isDark),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── CTA Card ──────────────────────────────────────────────────────────────────

class _CtaCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String word;
  final String ctaLabel;
  final String buttonLabel;
  final IconData buttonIcon;
  final Color innerBg;
  final Color innerBorder;
  final Color pillBg;
  final Color pillText;
  final Color wordColor;
  final VoidCallback onTap;
  final AppColorScheme c;
  final bool isDark;

  const _CtaCard({
    required this.title,
    required this.subtitle,
    required this.word,
    required this.ctaLabel,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.innerBg,
    required this.innerBorder,
    required this.pillBg,
    required this.pillText,
    required this.wordColor,
    required this.onTap,
    required this.c,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Parkinsans',
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 13,
                    color: c.mutedForeground,
                  ),
                ),
              ],
            ),
          ),

          // Tinted inner box
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: innerBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: innerBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Pill label
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: pillBg,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          ctaLabel,
                          style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: pillText,
                          ),
                        ),
                      ),
                      // Action button
                      GestureDetector(
                        onTap: onTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFFFAFAFA)
                                : const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                buttonIcon,
                                size: 15,
                                color: isDark
                                    ? const Color(0xFF0A0A0A)
                                    : Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                buttonLabel,
                                style: TextStyle(
                                  fontFamily: 'Metropolis',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFF0A0A0A)
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    word,
                    style: TextStyle(
                      fontFamily: 'Parkinsans',
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                      color: wordColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Social Card ───────────────────────────────────────────────────────────────

class _SocialCard extends StatelessWidget {
  final AppColorScheme c;
  final bool isDark;

  const _SocialCard({required this.c, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We Are Social',
                  style: TextStyle(
                    fontFamily: 'Parkinsans',
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Join us on social media and don't miss any updates.",
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 13,
                    color: c.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF4C0519).withValues(alpha: 0.2)
                    : const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isDark
                        ? const Color(0xFF9F1239)
                        : const Color(0xFFFECDD3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SocialButton(
                    icon: Icons.smart_display_outlined,
                    label: 'YouTube',
                    isDark: isDark,
                    c: c,
                  ),
                  const SizedBox(width: 12),
                  _SocialButton(
                    icon: Icons.music_note_outlined,
                    label: 'TikTok',
                    isDark: isDark,
                    c: c,
                  ),
                  const SizedBox(width: 12),
                  _SocialButton(
                    icon: Icons.business_center_outlined,
                    label: 'LinkedIn',
                    isDark: isDark,
                    c: c,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final AppColorScheme c;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF262626) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark
                  ? const Color(0xFF404040)
                  : Colors.white.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon,
            size: 24,
            color: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF404040)),
      ),
    );
  }
}
