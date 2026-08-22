import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/permissions.dart';
import '../../widgets/bottom_nav.dart';
import 'become_curator_screen.dart';
import 'become_juror_screen.dart';
import 'curator_requests_screen.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class _LeaderboardEntry {
  final int rank;
  final String name;
  final int score;
  const _LeaderboardEntry({required this.rank, required this.name, required this.score});
}

// ── Service ───────────────────────────────────────────────────────────────────

class _HomeService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<({
    String? voteWord,
    String? suggestWord,
    String communityName,
    int communityId,
    String role,
  })> load(String userId) async {
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

    // Fetch vote word (neo with enough ratings)
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

    // Fetch a suggest word (English term for curators/jurors to translate)
    String? suggestWord;
    if (role == 'CURATOR' || role == 'JUROR') {
      final suggestRows = await _db
          .from('terms')
          .select('text')
          .eq('languageId', 1)
          .limit(1);
      if (suggestRows.isNotEmpty) {
        suggestWord = suggestRows.first['text'] as String?;
      }
    }

    return (
      voteWord: voteWord,
      suggestWord: suggestWord,
      communityName: communityName,
      communityId: communityId,
      role: role,
    );
  }

  // Ports neolingo/src/actions/leaderboard.ts getLeaderboard() 1:1:
  // score = votes cast (1 pt) + neos suggested (5 pts), top 5 by score,
  // name falls back to 'Anonymous Curation' — same algorithm, same
  // fallback text, no per-user special-casing.
  Future<({
    List<_LeaderboardEntry> leaderboard,
    int votesCast,
    int wordsSuggested,
  })> loadLeaderboardData(String userId, int communityId) async {
    final neoRows = await _db
        .from('neos')
        .select('id, userId')
        .eq('languageId', communityId);

    final neoCountByUser = <String, int>{};
    final allNeoIds = <int>[];
    for (final row in neoRows) {
      final uid = row['userId'] as String;
      neoCountByUser[uid] = (neoCountByUser[uid] ?? 0) + 1;
      allNeoIds.add(row['id'] as int);
    }

    final voteCountByUser = <String, int>{};
    if (allNeoIds.isNotEmpty) {
      final voteRows = await _db
          .from('votes')
          .select('userId, neoId')
          .inFilter('neoId', allNeoIds);
      for (final row in voteRows) {
        final uid = row['userId'] as String;
        voteCountByUser[uid] = (voteCountByUser[uid] ?? 0) + 1;
      }
    }

    final allIds = {...neoCountByUser.keys, ...voteCountByUser.keys};
    final scores = {
      for (final uid in allIds)
        uid: (voteCountByUser[uid] ?? 0) + (neoCountByUser[uid] ?? 0) * 5,
    };

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();

    List<_LeaderboardEntry> leaderboard = [];
    if (top5.isNotEmpty) {
      final top5Ids = top5.map((e) => e.key).toList();
      final profiles = await _db
          .from('user_profile')
          .select('userId, name')
          .inFilter('userId', top5Ids);

      final nameMap = <String, String>{
        for (final p in profiles)
          p['userId'] as String: (p['name'] as String?)?.trim() ?? '',
      };

      leaderboard = top5.asMap().entries.map((e) {
        final uid = e.value.key;
        final name = (nameMap[uid] ?? '').isNotEmpty
            ? nameMap[uid]!
            : 'Anonymous Curation';
        return _LeaderboardEntry(
          rank: e.key + 1,
          name: name,
          score: e.value.value,
        );
      }).toList();
    }

    return (
      leaderboard: leaderboard,
      votesCast: voteCountByUser[userId] ?? 0,
      wordsSuggested: neoCountByUser[userId] ?? 0,
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
  String? _suggestWord;
  String _communityName = 'Community';
  int _communityId = 1;
  String _role = 'EXPLORER';

  // Leaderboard
  List<_LeaderboardEntry> _leaderboard = [];
  int _votesCast = 0;
  int _wordsSuggested = 0;
  bool _leaderboardLoading = false;

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
          _suggestWord = data.suggestWord;
          _communityName = data.communityName;
          _communityId = data.communityId;
          _role = data.role;
          _loading = false;
        });
        _loadLeaderboard();
      }
    } catch (e) {
      debugPrint('MenuScreen load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLeaderboard() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    setState(() => _leaderboardLoading = true);
    try {
      final data = await _service.loadLeaderboardData(userId, _communityId);
      if (mounted) {
        setState(() {
          _leaderboard = data.leaderboard;
          _votesCast = data.votesCast;
          _wordsSuggested = data.wordsSuggested;
          _leaderboardLoading = false;
        });
      }
    } catch (e) {
      debugPrint('loadLeaderboard: $e');
      if (mounted) setState(() => _leaderboardLoading = false);
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

    final isExplorer = _role == 'EXPLORER';
    final isCurator = _role == 'CURATOR';
    final isJuror   = _role == 'JUROR';
    final canReview  = hasPermission(_role, Permission.reviewRequests);
    final canApprove = hasPermission(_role, Permission.approveRequests);

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

            // ── Role description ──────────────────────────────────────────
            if (isExplorer)
              _RoleDescription(
                text:
                    "You're an Explorer — vote daily and take the Curator test to start translating words!",
                c: c,
              ),
            if (isCurator)
              _RoleDescription(
                text:
                    "You're a Curator — suggest words for your community, review pending requests, and keep building toward the JuryBoard.",
                c: c,
              ),
            if (isJuror)
              _RoleDescription(
                text:
                    "You're a Juror — rate community suggestions, guide the best words forward, and help protect translation quality.",
                c: c,
              ),

            const SizedBox(height: 4),

            // ── Become a Juror (Curator only) ─────────────────────────────
            if (isCurator) ...[
              _BecomeJurorCard(c: c, isDark: isDark, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BecomeJurorScreen()))),
              const SizedBox(height: 12),
            ],

            // ── Explorer-only cards ───────────────────────────────────────
            if (isExplorer) ...[
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
                onTap: () => widget.onNavigate?.call(NavTab.quiz),
                c: c,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _CtaCard(
                title: 'Become a Curator',
                subtitle: 'Take the test to translate words for your community',
                word: 'Level up your role',
                ctaLabel: 'Curator test',
                buttonLabel: 'Level up',
                buttonIcon: Icons.school_outlined,
                innerBg: isDark
                    ? const Color(0xFF78350F).withValues(alpha: 0.3)
                    : const Color(0xFFFFFBEB),
                innerBorder: isDark
                    ? const Color(0xFF92400E)
                    : const Color(0xFFFDE68A),
                pillBg: isDark
                    ? const Color(0xFF92400E).withValues(alpha: 0.5)
                    : const Color(0xFFFEF3C7),
                pillText: isDark
                    ? const Color(0xFFFCD34D)
                    : const Color(0xFF92400E),
                wordColor: isDark
                    ? const Color(0xFFFAFAFA)
                    : const Color(0xFF111111),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BecomeCuratorScreen())),
                c: c,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
            ],

            // ── Vote card (non-juror only) ─────────────────────────────────
            if (!isJuror) ...[
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
            ],

            // ── Jury Lounge (juror only) ───────────────────────────────────
            if (isJuror) ...[
              _CtaCard(
                title: 'Jury Lounge',
                subtitle: 'Review and manage word suggestions',
                word: 'Your jury dashboard',
                ctaLabel: 'Go to dashboard',
                buttonLabel: 'Validate',
                buttonIcon: Icons.gavel,
                innerBg: isDark
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFF0F0F0),
                innerBorder: isDark
                    ? const Color(0xFF333333)
                    : const Color(0xFFDCDCDC),
                pillBg: isDark
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFF0F0F0),
                pillText: isDark
                    ? const Color(0xFFF0F0F0)
                    : const Color(0xFF292929),
                wordColor: isDark
                    ? const Color(0xFFFAFAFA)
                    : const Color(0xFF111111),
                onTap: () => widget.onNavigate?.call(NavTab.vote),
                c: c,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
            ],

            // ── Make Your Suggestion (curator / juror) ─────────────────────
            if (isCurator || isJuror) ...[
              _CtaCard(
                title: 'Make Your Suggestion',
                subtitle:
                    'Suggest a $_communityName word for the word of the day!',
                word: _suggestWord ?? 'Awalingo',
                ctaLabel: 'Word of the day',
                buttonLabel: 'Curate',
                buttonIcon: Icons.lightbulb_outline,
                innerBg: isDark
                    ? const Color(0xFF1E3A5F).withValues(alpha: 0.4)
                    : const Color(0xFFEFF6FF),
                innerBorder: isDark
                    ? const Color(0xFF1E40AF)
                    : const Color(0xFFBFDBFE),
                pillBg: isDark
                    ? const Color(0xFF1E40AF).withValues(alpha: 0.5)
                    : const Color(0xFFDBEAFE),
                pillText: isDark
                    ? const Color(0xFF93C5FD)
                    : const Color(0xFF1E40AF),
                wordColor: isDark
                    ? const Color(0xFFFAFAFA)
                    : const Color(0xFF111111),
                onTap: () => widget.onNavigate?.call(NavTab.translate),
                c: c,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
            ],

            // ── Review / Approve Requests (MANAGER / ADMIN) ───────────────
            if (canReview) ...[
              _CtaCard(
                title: canApprove ? 'Approve Requests' : 'Review Requests',
                subtitle: 'Approve or reject new requests',
                word: 'Curate the dictionary',
                ctaLabel: canApprove ? 'Pending Approvals' : 'Pending Reviews',
                buttonLabel: canApprove ? 'Approve' : 'Review',
                buttonIcon: Icons.lightbulb_outline,
                innerBg: isDark
                    ? const Color(0xFF312E81).withValues(alpha: 0.3)
                    : const Color(0xFFEEF2FF),
                innerBorder: isDark
                    ? const Color(0xFF3730A3)
                    : const Color(0xFFC7D2FE),
                pillBg: isDark
                    ? const Color(0xFF3730A3).withValues(alpha: 0.5)
                    : const Color(0xFFE0E7FF),
                pillText: isDark
                    ? const Color(0xFFA5B4FC)
                    : const Color(0xFF3730A3),
                wordColor: isDark
                    ? const Color(0xFFFAFAFA)
                    : const Color(0xFF111111),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CuratorRequestsScreen())),
                c: c,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
            ],

            // ── Request card (always) ──────────────────────────────────────
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

            // ── Social card (always) ───────────────────────────────────────
            _SocialCard(c: c, isDark: isDark),
            const SizedBox(height: 12),

            // ── Leaderboard card (always) ──────────────────────────────────
            _LeaderboardCard(
              communityName: _communityName,
              leaderboard: _leaderboard,
              votesCast: _votesCast,
              wordsSuggested: _wordsSuggested,
              loading: _leaderboardLoading,
              onRefresh: _loadLeaderboard,
              c: c,
              isDark: isDark,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── Role description ──────────────────────────────────────────────────────────

class _RoleDescription extends StatelessWidget {
  final String text;
  final AppColorScheme c;
  const _RoleDescription({required this.text, required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Metropolis',
          fontSize: 13,
          color: c.mutedForeground,
        ),
      ),
    );
  }
}

// ── Become a Juror Card ───────────────────────────────────────────────────────

class _BecomeJurorCard extends StatelessWidget {
  final AppColorScheme c;
  final bool isDark;
  final VoidCallback onTap;

  const _BecomeJurorCard({
    required this.c,
    required this.isDark,
    required this.onTap,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
            child: Text(
              'Become a Juror',
              style: TextStyle(
                fontFamily: 'Parkinsans',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.foreground,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF064E3B).withValues(alpha: 0.3)
                    : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF065F46)
                      : const Color(0xFFA7F3D0),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Take the leap, Join the Awalingo JuryBoard for your Community',
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 13,
                        color: c.mutedForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                            Icons.rocket_launch_outlined,
                            size: 15,
                            color: isDark
                                ? const Color(0xFF0A0A0A)
                                : Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Elevate',
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
            ),
          ),
        ],
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

// Inline SVG paths sourced from Simple Icons (simpleicons.org) — MIT licence
const _kSvgYouTube =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/></svg>';
const _kSvgTikTok =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/></svg>';
const _kSvgLinkedIn =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 0 1-2.063-2.065 2.064 2.064 0 1 1 2.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z"/></svg>';
const _kSvgWhatsApp =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413Z"/></svg>';

const _socialLinks = [
  (label: 'YouTube',  href: 'https://www.youtube.com/@awalingo',                       svg: _kSvgYouTube,  brandColor: Color(0xFFFF0000)),
  (label: 'TikTok',   href: 'https://www.tiktok.com/@awalingo',                        svg: _kSvgTikTok,   brandColor: Color(0xFF000000)),
  (label: 'LinkedIn', href: 'https://linkedin.com/company/awalingo',                   svg: _kSvgLinkedIn, brandColor: Color(0xFF0A66C2)),
  (label: 'WhatsApp', href: 'https://whatsapp.com/channel/0029Vb85Lth7T8bgFEhPjt3m',  svg: _kSvgWhatsApp, brandColor: Color(0xFF25D366)),
];

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
              // rose-50 / rose-900/20 matching Next.js exactly
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF881337).withValues(alpha: 0.2)
                    : const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF9F1239)  // rose-800
                      : const Color(0xFFFECDD3), // rose-200
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < _socialLinks.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _SocialButton(
                      label:      _socialLinks[i].label,
                      href:       _socialLinks[i].href,
                      svg:        _socialLinks[i].svg,
                      brandColor: _socialLinks[i].brandColor,
                      isDark:     isDark,
                    ),
                  ],
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
  final String label;
  final String href;
  final String svg;
  final Color brandColor;
  final bool isDark;

  const _SocialButton({
    required this.label,
    required this.href,
    required this.svg,
    required this.brandColor,
    required this.isDark,
  });

  Future<void> _open() async {
    final uri = Uri.parse(href);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: _open,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF404040)
                  : Colors.white.withValues(alpha: 0.8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: SvgPicture.string(
            svg,
            colorFilter: ColorFilter.mode(brandColor, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Leaderboard Card
// ──────────────────────────────────────────────────────────────────────────────

class _LeaderboardCard extends StatelessWidget {
  final String communityName;
  final List<_LeaderboardEntry> leaderboard;
  final int votesCast;
  final int wordsSuggested;
  final bool loading;
  final VoidCallback onRefresh;
  final AppColorScheme c;
  final bool isDark;

  const _LeaderboardCard({
    required this.communityName,
    required this.leaderboard,
    required this.votesCast,
    required this.wordsSuggested,
    required this.loading,
    required this.onRefresh,
    required this.c,
    required this.isDark,
  });

  Color get _cardBg => isDark ? const Color(0xFF1C1C1E) : Colors.white;
  Color get _borderColor =>
      isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'Leaderboard',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: loading ? null : onRefresh,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 20,
                          color: isDark
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF6B7280),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Community pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF9C62D9).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              '$communityName Community',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7C3AED),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Stats grid (2 columns)
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: wordsSuggested.toString(),
                  label: 'Total Suggestions',
                  valueFg: const Color(0xFFEA580C),
                  labelFg: const Color(0xFF9A3412),
                  bg: const Color(0xFFFFF7ED),
                  border: const Color(0xFFFED7AA),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  value: votesCast.toString(),
                  label: 'Total Votes Cast',
                  valueFg: const Color(0xFF2563EB),
                  labelFg: const Color(0xFF1E40AF),
                  bg: const Color(0xFFEFF6FF),
                  border: const Color(0xFFBFDBFE),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Top Curators heading
          Text(
            'Top Curators',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),

          // Ranked list
          if (leaderboard.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No curation data yet.',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF6B7280),
                ),
              ),
            )
          else
            Column(
              children: leaderboard
                  .map((e) => _LeaderboardRow(entry: e, isDark: isDark))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color valueFg;
  final Color labelFg;
  final Color bg;
  final Color border;

  const _StatTile({
    required this.value,
    required this.label,
    required this.valueFg,
    required this.labelFg,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueFg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: labelFg,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final _LeaderboardEntry entry;
  final bool isDark;

  const _LeaderboardRow({required this.entry, required this.isDark});

  Color get _badgeBg {
    switch (entry.rank) {
      case 1:
        return const Color(0xFFFEF9C3);
      case 2:
        return const Color(0xFFE2E8F0);
      case 3:
        return const Color(0xFFFEF3C7);
      default:
        return const Color(0xFFE5E5E5);
    }
  }

  Color get _badgeFg {
    switch (entry.rank) {
      case 1:
        return const Color(0xFFA16207);
      case 2:
        return const Color(0xFF334155);
      case 3:
        return const Color(0xFFB45309);
      default:
        return const Color(0xFF525252);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _badgeBg,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '${entry.rank}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _badgeFg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Name
          Expanded(
            child: Text(
              entry.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : const Color(0xFF111827),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Score
          Text(
            '${entry.score} pts',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? const Color(0xFF9CA3AF)
                  : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}
