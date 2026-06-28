import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';

// ─── Shared data model (used by translate_screen.dart) ────────────────────────
class TermWithNeoCount {
  final int id;
  final String text;
  final String meaning;
  final String partOfSpeech;
  final int neoCount;
  final int languageId;

  const TermWithNeoCount({
    required this.id,
    required this.text,
    required this.meaning,
    required this.partOfSpeech,
    required this.neoCount,
    required this.languageId,
  });
}

// ─── Internal models ──────────────────────────────────────────────────────────
class _VotingTerm {
  final int id;
  final String text;
  final String meaning;
  final String partOfSpeech;
  const _VotingTerm({
    required this.id,
    required this.text,
    required this.meaning,
    required this.partOfSpeech,
  });
}

class _NeoOption {
  final int id;
  final String text;
  final String type;
  const _NeoOption({required this.id, required this.text, required this.type});
}

// ─── Services ─────────────────────────────────────────────────────────────────
class _VoteService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<({int engId, int communityId, String communityName, String communityShort})>
      bootstrap(String userId) async {
    final engRow = await _db
        .from('languages')
        .select('id')
        .eq('code', 'eng')
        .maybeSingle();
    final engId = (engRow?['id'] as int?) ?? 1;

    final utl = await _db
        .from('user_target_languages')
        .select('language:languages!languageId(id, name, short)')
        .eq('userId', userId)
        .maybeSingle();
    final lang = utl?['language'] as Map<String, dynamic>?;

    return (
      engId: engId,
      communityId: (lang?['id'] as int?) ?? engId,
      communityName: (lang?['name'] as String?) ?? 'Community',
      communityShort: (lang?['short'] as String?) ?? 'COM',
    );
  }

  Future<List<_VotingTerm>> loadTerms(int communityLangId) async {
    final neoRows = await _db
        .from('neos')
        .select('termId, ratingCount, rejectCount')
        .eq('languageId', communityLangId)
        .gt('ratingCount', 0);

    final validTermIds = neoRows
        .where((n) =>
            (n['rejectCount'] as int? ?? 0) < (n['ratingCount'] as int? ?? 0))
        .map((n) => n['termId'] as int)
        .toSet()
        .toList();

    if (validTermIds.isEmpty) return [];

    final termRows = await _db
        .from('terms')
        .select('id, text, meaning, partOfSpeech:part_of_speech!partOfSpeechId(name)')
        .inFilter('id', validTermIds);

    return termRows.map((r) {
      final pos = r['partOfSpeech'] as Map<String, dynamic>?;
      return _VotingTerm(
        id: r['id'] as int,
        text: r['text'] as String,
        meaning: r['meaning'] as String? ?? '',
        partOfSpeech: pos?['name'] as String? ?? '',
      );
    }).toList();
  }
}

class _VoteDetailService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<_NeoOption>> loadNeos(int termId, int communityLangId) async {
    final rows = await _db
        .from('neos')
        .select('id, text, type, ratingScore, ratingCount, rejectCount')
        .eq('termId', termId)
        .eq('languageId', communityLangId)
        .gt('ratingCount', 0)
        .order('ratingScore', ascending: false)
        .limit(10);

    return rows
        .where((r) =>
            (r['rejectCount'] as int? ?? 0) < (r['ratingCount'] as int? ?? 1))
        .map((r) => _NeoOption(
              id: r['id'] as int,
              text: r['text'] as String,
              type: r['type'] as String? ?? 'POPULAR',
            ))
        .toList();
  }

  Future<int?> getExistingVote(String userId, int termId) async {
    final row = await _db
        .from('votes')
        .select('neoId')
        .eq('userId', userId)
        .eq('termId', termId)
        .maybeSingle();
    return row?['neoId'] as int?;
  }

  Future<void> castVote(String userId, int termId, int neoId) async {
    await _db.from('votes').delete().eq('userId', userId).eq('termId', termId);
    await _db.from('votes').insert({
      'userId': userId,
      'termId': termId,
      'neoId': neoId,
      'value': 1,
    });
    final profile = await _db
        .from('user_profile')
        .select('cowryBalance')
        .eq('userId', userId)
        .maybeSingle();
    if (profile != null) {
      final current = (profile['cowryBalance'] as int?) ?? 0;
      await _db
          .from('user_profile')
          .update({'cowryBalance': current + 1}).eq('userId', userId);
    }
  }
}

// ─── Voting Lounge Screen ─────────────────────────────────────────────────────
class VoteScreen extends StatefulWidget {
  const VoteScreen({super.key});

  @override
  State<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends State<VoteScreen> {
  final _service = _VoteService();

  bool _loading = true;
  bool _loadDone = false;
  List<_VotingTerm> _terms = [];
  int _communityId = 1;
  int _engId = 1;
  String _communityShort = 'COM';
  bool _showEnglish = false;

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
    setState(() => _loading = true);
    try {
      final boot = await _service.bootstrap(userId);
      _communityId = boot.communityId;
      _engId = boot.engId;
      _communityShort = boot.communityShort;

      final terms = await _service.loadTerms(_showEnglish ? _engId : _communityId);
      if (mounted) setState(() { _terms = terms; _loading = false; });
    } catch (e) {
      debugPrint('VoteScreen load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchLanguage(bool showEnglish) async {
    if (_showEnglish == showEnglish) return;
    setState(() { _showEnglish = showEnglish; _loading = true; });
    try {
      final terms = await _service.loadTerms(showEnglish ? _engId : _communityId);
      if (mounted) setState(() { _terms = terms; _loading = false; });
    } catch (e) {
      debugPrint('VoteScreen switch error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Voting Lounge',
                      style: TextStyle(
                        fontFamily: 'Parkinsans',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: c.foreground,
                      ),
                    ),
                  ),
                  // Language switch tag
                  Container(
                    decoration: BoxDecoration(
                      color: c.secondary,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LangPill(
                          label: _communityShort.toUpperCase(),
                          active: !_showEnglish,
                          onTap: () => _switchLanguage(false),
                          c: c,
                        ),
                        _LangPill(
                          label: 'EN',
                          active: _showEnglish,
                          onTap: () => _switchLanguage(true),
                          c: c,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),

            // ── Content ───────────────────────────────────────────────────
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(() { _loadDone = false; });
                  await _load();
                },
                color: c.primary,
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: c.primary, strokeWidth: 2))
                    : SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Terms card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: c.card,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: c.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: isDark ? 0.3 : 0.06),
                                    blurRadius: 20,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: _terms.isEmpty
                                  ? Column(
                                      children: [
                                        Icon(Icons.how_to_vote_outlined,
                                            size: 48,
                                            color: c.primary
                                                .withValues(alpha: 0.15)),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No terms to vote on right now.',
                                          style: TextStyle(
                                            fontFamily: 'Metropolis',
                                            fontSize: 14,
                                            color: c.mutedForeground,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    )
                                  : Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _terms
                                          .map((t) => _TermPill(
                                                term: t,
                                                communityLangId: _communityId,
                                              ))
                                          .toList(),
                                    ),
                            ),
                            const SizedBox(height: 20),

                            // Refresh button
                            Center(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  setState(() { _loadDone = false; });
                                  await _load();
                                },
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Refresh',
                                    style: TextStyle(
                                        fontFamily: 'Metropolis',
                                        fontWeight: FontWeight.w500)),
                                style: OutlinedButton.styleFrom(
                                  shape: const StadiumBorder(),
                                  foregroundColor: c.foreground,
                                  side: BorderSide(color: c.border),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Term pill ────────────────────────────────────────────────────────────────
class _TermPill extends StatelessWidget {
  final _VotingTerm term;
  final int communityLangId;

  const _TermPill({required this.term, required this.communityLangId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _VoteDetailScreen(
          term: term,
          communityLangId: communityLangId,
        ),
      )),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF420FBD),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          term.text,
          style: const TextStyle(
            fontFamily: 'Metropolis',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─── Language switch pill ─────────────────────────────────────────────────────
class _LangPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final AppColorScheme c;

  const _LangPill(
      {required this.label,
      required this.active,
      required this.onTap,
      required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF9C62D9) : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Metropolis',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : c.mutedForeground,
          ),
        ),
      ),
    );
  }
}

// ─── Vote Detail Screen ───────────────────────────────────────────────────────
class _VoteDetailScreen extends StatefulWidget {
  final _VotingTerm term;
  final int communityLangId;

  const _VoteDetailScreen(
      {required this.term, required this.communityLangId});

  @override
  State<_VoteDetailScreen> createState() => _VoteDetailScreenState();
}

class _VoteDetailScreenState extends State<_VoteDetailScreen> {
  final _service = _VoteDetailService();

  bool _loading = true;
  bool _submitting = false;
  List<_NeoOption> _neos = [];
  int? _votedNeoId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    try {
      final results = await Future.wait([
        _service.loadNeos(widget.term.id, widget.communityLangId),
        if (userId != null)
          _service.getExistingVote(userId, widget.term.id)
        else
          Future.value(null),
      ]);
      if (mounted) {
        setState(() {
          _neos = results[0] as List<_NeoOption>;
          _votedNeoId = results[1] as int?;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('VoteDetail load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _castVote(int neoId) async {
    if (_submitting || _votedNeoId == neoId) return;
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;

    final prev = _votedNeoId;
    setState(() { _votedNeoId = neoId; _submitting = true; });

    try {
      await _service.castVote(userId, widget.term.id, neoId);
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Voted! You earned 🐚 1 cowry.',
              style: TextStyle(fontFamily: 'Metropolis')),
          backgroundColor: const Color(0xFF2da529),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      debugPrint('castVote error: $e');
      if (mounted) {
        setState(() { _votedNeoId = prev; _submitting = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Failed to cast vote. Please try again.',
              style: TextStyle(fontFamily: 'Metropolis')),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: c.secondary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.arrow_back,
                            size: 20, color: c.foreground),
                      ),
                    ),
                  ),
                  Text(
                    widget.term.text,
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

            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: c.primary, strokeWidth: 2))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                      child: Column(
                        children: [
                          // ── Word card ──────────────────────────────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: c.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                      alpha: isDark ? 0.3 : 0.06),
                                  blurRadius: 15,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.auto_awesome,
                                        size: 14,
                                        color: Color(0xFFEAAB0B)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Word to Vote On',
                                      style: TextStyle(
                                        fontFamily: 'Metropolis',
                                        fontSize: 12,
                                        color: c.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.term.text,
                                  style: TextStyle(
                                    fontFamily: 'Parkinsans',
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    color: c.foreground,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (widget.term.partOfSpeech.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: c.secondary,
                                      borderRadius:
                                          BorderRadius.circular(100),
                                    ),
                                    child: Text(
                                      widget.term.partOfSpeech,
                                      style: TextStyle(
                                          fontFamily: 'Metropolis',
                                          fontSize: 11,
                                          color: c.mutedForeground),
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.term.meaning,
                                  style: TextStyle(
                                    fontFamily: 'Metropolis',
                                    fontSize: 14,
                                    color: c.mutedForeground,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── Neos list ──────────────────────────────────
                          if (_neos.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(40),
                              decoration: BoxDecoration(
                                color: c.card,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: c.border),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.ballot_outlined,
                                      size: 48,
                                      color:
                                          c.primary.withValues(alpha: 0.15)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No Neo suggestions ready for voting yet.',
                                    style: TextStyle(
                                      fontFamily: 'Metropolis',
                                      fontSize: 14,
                                      color: c.mutedForeground,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          else
                            Column(
                              children: _neos
                                  .asMap()
                                  .entries
                                  .map((entry) => Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 10),
                                        child: _NeoCard(
                                          neo: entry.value,
                                          voted:
                                              _votedNeoId == entry.value.id,
                                          onVote: () =>
                                              _castVote(entry.value.id),
                                          isDark: isDark,
                                          c: c,
                                        ),
                                      ))
                                  .toList(),
                            ),

                          const SizedBox(height: 24),

                          // ── Back button ────────────────────────────────
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back, size: 16),
                              label: const Text('Back to Voting Lounge',
                                  style: TextStyle(
                                      fontFamily: 'Metropolis',
                                      fontWeight: FontWeight.w500)),
                              style: OutlinedButton.styleFrom(
                                shape: const StadiumBorder(),
                                foregroundColor: c.foreground,
                                side: BorderSide(color: c.border),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Neo card ─────────────────────────────────────────────────────────────────
class _NeoCard extends StatelessWidget {
  final _NeoOption neo;
  final bool voted;
  final VoidCallback onVote;
  final bool isDark;
  final AppColorScheme c;

  const _NeoCard({
    required this.neo,
    required this.voted,
    required this.onVote,
    required this.isDark,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Type icon
          _NeoTypeIcon(type: neo.type),
          const SizedBox(width: 12),

          // Neo text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  neo.text,
                  style: TextStyle(
                    fontFamily: 'Parkinsans',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                Text(
                  _typeLabel(neo.type),
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 12,
                    color: c.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Vote button
          GestureDetector(
            onTap: onVote,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: voted
                    ? const Color(0xFFcdffce)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: voted
                      ? const Color(0xFF2da529)
                      : const Color(0xFF420FBD),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (voted)
                    const Icon(Icons.check,
                        size: 14, color: Color(0xFF2da529)),
                  if (voted) const SizedBox(width: 4),
                  Text(
                    voted ? 'Voted' : 'Vote',
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: voted
                          ? const Color(0xFF2da529)
                          : const Color(0xFF420FBD),
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

  String _typeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'POPULAR': return 'Popular';
      case 'ADOPTIVE': return 'Adoptive';
      case 'FUNCTIONAL': return 'Functional';
      case 'ROOT': return 'Root';
      case 'CREATIVE': return 'Creative';
      default: return type;
    }
  }
}

// ─── Shared components (used by translate_screen.dart) ────────────────────────

class LoungeHeader extends StatelessWidget {
  final String title;
  final String activeLanguage;
  final VoidCallback onToggleLanguage;

  const LoungeHeader({
    super.key,
    required this.title,
    required this.activeLanguage,
    required this.onToggleLanguage,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: TextStyle(
                  fontFamily: 'Parkinsans',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.foreground,
                )),
          ),
          GestureDetector(
            onTap: onToggleLanguage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: c.secondary,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: c.border)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    activeLanguage == 'english' ? 'Community' : 'EN',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.foreground,
                        fontFamily: 'Metropolis'),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.swap_horiz, size: 14, color: c.mutedForeground),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TermCard extends StatelessWidget {
  final TermWithNeoCount term;
  final VoidCallback onTap;

  const TermCard({super.key, required this.term, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(term.text,
                      style: TextStyle(
                          fontFamily: 'Parkinsans',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.foreground)),
                  const SizedBox(height: 4),
                  Text(term.meaning,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Metropolis',
                          fontSize: 13,
                          color: c.mutedForeground)),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: c.secondary,
                        borderRadius: BorderRadius.circular(100)),
                    child: Text(term.partOfSpeech,
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Metropolis',
                            color: c.mutedForeground)),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF420FBD).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text('${term.neoCount} Neos',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Metropolis',
                          color: Color(0xFF420FBD))),
                ),
                const SizedBox(height: 8),
                Icon(Icons.chevron_right,
                    size: 18,
                    color: AppColorScheme.of(context).mutedForeground),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NeoTypeIcon extends StatelessWidget {
  final String type;
  const _NeoTypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    IconData icon;
    Color color;
    switch (type.toUpperCase()) {
      case 'POPULAR':
        icon = Icons.star_outline;
        color = const Color(0xFFEAAB0B);
        break;
      case 'ADOPTIVE':
        icon = Icons.recycling;
        color = const Color(0xFF10B981);
        break;
      case 'FUNCTIONAL':
        icon = Icons.build_outlined;
        color = const Color(0xFF3B82F6);
        break;
      case 'ROOT':
        icon = Icons.park_outlined;
        color = const Color(0xFF8B5CF6);
        break;
      case 'CREATIVE':
        icon = Icons.psychology_outlined;
        color = const Color(0xFFEC4899);
        break;
      default:
        icon = Icons.circle_outlined;
        color = c.mutedForeground;
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

