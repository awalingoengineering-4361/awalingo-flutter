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

  Future<List<_VotingTerm>> loadTerms(int neoLangId) async {
    final neoRows = await _db
        .from('neos')
        .select('termId, ratingCount, rejectCount')
        .eq('languageId', neoLangId)
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

  Future<List<_VotingTerm>> loadTermsForJury({
    required String userId,
    required int neoLangId,
  }) async {
    // Fetch neos not created by user, with rejectCount < 3
    final neoRows = await _db
        .from('neos')
        .select('id, termId')
        .eq('languageId', neoLangId)
        .neq('userId', userId)
        .lt('rejectCount', 3);

    if (neoRows.isEmpty) return [];

    // Exclude neos already rated by this user
    final neoIds = neoRows.map((r) => r['id'] as int).toList();
    final ratedRows = await _db
        .from('neo_rating')
        .select('neoId')
        .eq('userId', userId)
        .inFilter('neoId', neoIds);
    final ratedNeoIds = ratedRows.map((r) => r['neoId'] as int).toSet();

    final validTermIds = neoRows
        .where((n) => !ratedNeoIds.contains(n['id'] as int))
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

  Future<List<_NeoOption>> loadNeosForJury(
      int termId, int neoLangId, String userId) async {
    final rows = await _db
        .from('neos')
        .select('id, text, type, rejectCount')
        .eq('termId', termId)
        .eq('languageId', neoLangId)
        .neq('userId', userId)
        .lt('rejectCount', 3)
        .limit(11);

    if (rows.isEmpty) return [];

    final neoIds = rows.map((r) => r['id'] as int).toList();
    final ratedRows = await _db
        .from('neo_rating')
        .select('neoId')
        .eq('userId', userId)
        .inFilter('neoId', neoIds);
    final ratedIds = ratedRows.map((r) => r['neoId'] as int).toSet();

    return rows
        .where((r) => !ratedIds.contains(r['id'] as int))
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

  Future<_VotingTerm?> fetchTerm(int termId) async {
    final row = await _db
        .from('terms')
        .select('id, text, meaning, partOfSpeech:part_of_speech!partOfSpeechId(name)')
        .eq('id', termId)
        .maybeSingle();
    if (row == null) return null;
    final pos = row['partOfSpeech'] as Map<String, dynamic>?;
    return _VotingTerm(
      id: row['id'] as int,
      text: row['text'] as String,
      meaning: row['meaning'] as String? ?? '',
      partOfSpeech: pos?['name'] as String? ?? '',
    );
  }

  Future<void> deferVote(String userId, int termId) async {
    try {
      await _db.from('defered_terms').upsert({
        'userId': userId,
        'termId': termId,
        'deferType': 'vote',
      }, onConflict: 'userId,termId,deferType');
    } catch (e) {
      debugPrint('deferVote: $e');
    }
  }

  Future<Map<int, int>> getExistingRatings(String userId, List<int> neoIds) async {
    if (neoIds.isEmpty) return {};
    try {
      final rows = await _db
          .from('neo_rating')
          .select('neoId, value')
          .eq('userId', userId)
          .inFilter('neoId', neoIds);
      return {for (final r in rows) r['neoId'] as int: r['value'] as int};
    } catch (e) {
      debugPrint('getExistingRatings: $e');
      return {};
    }
  }

  Future<void> rateNeo(String userId, int neoId, int value,
      {String? rejectionReason}) async {
    await _db.rpc('rate_neo', params: {
      'p_neo_id': neoId,
      'p_user_id': userId,
      'p_value': value,
      'p_rejection_reason':
          (rejectionReason != null && rejectionReason.isNotEmpty)
              ? rejectionReason
              : null,
    });
  }
}

// ─── Voting Lounge Screen ─────────────────────────────────────────────────────
class VoteScreen extends StatefulWidget {
  final bool isJuror;
  const VoteScreen({super.key, this.isJuror = false});

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
  String? _userId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadDone) {
      _loadDone = true;
      _load();
    }
  }

  Future<List<_VotingTerm>> _fetchTerms(bool showEnglish) {
    final neoLangId = showEnglish ? _engId : _communityId;
    if (widget.isJuror && _userId != null) {
      return _service.loadTermsForJury(userId: _userId!, neoLangId: neoLangId);
    }
    return _service.loadTerms(neoLangId);
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    _userId = userId;
    setState(() => _loading = true);
    try {
      final boot = await _service.bootstrap(userId);
      _communityId = boot.communityId;
      _engId = boot.engId;
      _communityShort = boot.communityShort;

      final terms = await _fetchTerms(_showEnglish);
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
      final terms = await _fetchTerms(showEnglish);
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
                      widget.isJuror ? 'Jury Lounge' : 'Voting Lounge',
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
                                                isJuror: widget.isJuror,
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
  final bool isJuror;

  const _TermPill({
    required this.term,
    required this.communityLangId,
    this.isJuror = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => isJuror
            ? JuryDetailScreen(
                termId: term.id,
                communityLangId: communityLangId,
              )
            : VoteDetailScreen(
                termId: term.id,
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
class VoteDetailScreen extends StatefulWidget {
  final int termId;
  final int communityLangId;

  const VoteDetailScreen({
    super.key,
    required this.termId,
    required this.communityLangId,
  });

  @override
  State<VoteDetailScreen> createState() => _VoteDetailScreenState();
}

class _VoteDetailScreenState extends State<VoteDetailScreen> {
  final _service = _VoteDetailService();

  bool _loading = true;
  bool _submitting = false;
  bool _deferring = false;
  _VotingTerm? _term;
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
        _service.fetchTerm(widget.termId),
        _service.loadNeos(widget.termId, widget.communityLangId),
        if (userId != null)
          _service.getExistingVote(userId, widget.termId)
        else
          Future.value(null),
      ]);
      if (mounted) {
        setState(() {
          _term = results[0] as _VotingTerm?;
          _neos = results[1] as List<_NeoOption>;
          _votedNeoId = results[2] as int?;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('VoteDetail load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canDefer {
    if (_votedNeoId == null) return true;
    return !_neos.any((n) => n.id == _votedNeoId);
  }

  Future<void> _defer() async {
    if (_deferring || !_canDefer) return;
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;

    setState(() => _deferring = true);
    try {
      await _service.deferVote(userId, widget.termId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Vote deferred.',
              style: TextStyle(fontFamily: 'Metropolis')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('defer error: $e');
      if (mounted) {
        setState(() => _deferring = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Could not defer. Please try again.',
              style: TextStyle(fontFamily: 'Metropolis')),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _castVote(int neoId) async {
    if (_submitting || _votedNeoId == neoId) return;
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;

    final prev = _votedNeoId;
    setState(() { _votedNeoId = neoId; _submitting = true; });

    try {
      await _service.castVote(userId, widget.termId, neoId);
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
                    _term?.text ?? '',
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
                          if (_term != null) ...[
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
                                    _term!.text,
                                    style: TextStyle(
                                      fontFamily: 'Parkinsans',
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: c.foreground,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (_term!.partOfSpeech.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: c.secondary,
                                        borderRadius:
                                            BorderRadius.circular(100),
                                      ),
                                      child: Text(
                                        _term!.partOfSpeech,
                                        style: TextStyle(
                                            fontFamily: 'Metropolis',
                                            fontSize: 11,
                                            color: c.mutedForeground),
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _term!.meaning,
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
                          ],

                          // ── Neos list (single card with rows) ──────────
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
                            Container(
                              width: double.infinity,
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
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Column(
                                  children: _neos
                                      .asMap()
                                      .entries
                                      .map((entry) => _NeoRow(
                                            neo: entry.value,
                                            voted: _votedNeoId ==
                                                entry.value.id,
                                            isLast: entry.key ==
                                                _neos.length - 1,
                                            onVote: () =>
                                                _castVote(entry.value.id),
                                            c: c,
                                          ))
                                      .toList(),
                                ),
                              ),
                            ),

                          const SizedBox(height: 20),

                          // ── Defer Vote + Vote Lounge ────────────────────
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: (_canDefer && !_deferring)
                                      ? _defer
                                      : null,
                                  icon: _deferring
                                      ? SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: c.foreground))
                                      : const Icon(Icons.refresh, size: 16),
                                  label: const Text('Defer Vote',
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
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  icon: const Icon(Icons.arrow_forward,
                                      size: 16),
                                  label: const Text('Vote Lounge',
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

// ─── Neo row ──────────────────────────────────────────────────────────────────
class _NeoRow extends StatelessWidget {
  final _NeoOption neo;
  final bool voted;
  final bool isLast;
  final VoidCallback onVote;
  final AppColorScheme c;

  const _NeoRow({
    required this.neo,
    required this.voted,
    required this.isLast,
    required this.onVote,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          _NeoTypeIcon(type: neo.type),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              neo.text,
              style: TextStyle(
                fontFamily: 'Metropolis',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.foreground,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onVote,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: voted
                    ? const Color(0xFFCDFFCE)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: voted
                      ? const Color(0xFF2DA529)
                      : const Color(0xFF420FBD),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (voted) ...[
                    const Icon(Icons.check,
                        size: 12, color: Color(0xFF2DA529)),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    voted ? 'Voted' : 'Vote',
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: voted
                          ? const Color(0xFF2DA529)
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

// ─── Jury Detail Screen ───────────────────────────────────────────────────────
class JuryDetailScreen extends StatefulWidget {
  final int termId;
  final int communityLangId;

  const JuryDetailScreen({
    super.key,
    required this.termId,
    required this.communityLangId,
  });

  @override
  State<JuryDetailScreen> createState() => _JuryDetailScreenState();
}

class _JuryDetailScreenState extends State<JuryDetailScreen> {
  final _service = _VoteDetailService();

  bool _loading = true;
  _VotingTerm? _term;
  List<_NeoOption> _neos = [];
  Map<int, int> _myRatings = {};

  static const _rejectionReasons = [
    'Bad Text',
    'Bad Audio',
    'Spam',
    'Out of context',
    'Duplicate',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    try {
      final term = await _service.fetchTerm(widget.termId);
      final neos = userId != null
          ? await _service.loadNeosForJury(
              widget.termId, widget.communityLangId, userId)
          : <_NeoOption>[];
      if (mounted) {
        setState(() {
          _term = term;
          _neos = neos;
          _myRatings = {};
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('JuryDetail load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _rate(int neoId, int value, {String? rejectionReason}) async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;

    setState(() => _myRatings = {..._myRatings, neoId: value});
    try {
      await _service.rateNeo(userId, neoId, value,
          rejectionReason: rejectionReason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            value == 0
                ? 'Neo rejected. You earned 🐚 3 cowries.'
                : 'Rated! You earned 🐚 3 cowries.',
            style: const TextStyle(fontFamily: 'Metropolis'),
          ),
          backgroundColor:
              value == 0 ? const Color(0xFFA30202) : const Color(0xFF2da529),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      debugPrint('rateNeo error: $e');
      if (mounted) setState(() => _myRatings = {..._myRatings}..remove(neoId));
    }
  }

  Future<void> _showRejectModal(int neoId) async {
    final selected = <String>{};
    final c = AppColorScheme.of(context);

    await showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Reject this Neo?',
                style: TextStyle(
                  fontFamily: 'Parkinsans',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.foreground,
                ),
              ),
              const SizedBox(height: 12),
              ..._rejectionReasons.map((reason) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(reason,
                        style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontSize: 14,
                            color: c.foreground)),
                    value: selected.contains(reason),
                    activeColor: c.primary,
                    onChanged: (v) => setModal(() {
                      if (v == true) {
                        selected.add(reason);
                      } else {
                        selected.remove(reason);
                      }
                    }),
                  )),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        foregroundColor: c.foreground,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontFamily: 'Metropolis',
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _rate(neoId, 0,
                            rejectionReason: selected.join(', '));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA30202),
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: const Text('Reject',
                          style: TextStyle(
                              fontFamily: 'Metropolis',
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                    _term?.text ?? '',
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
                          // ── Word card ───────────────────────────────────
                          if (_term != null) ...[
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
                                        'Word to Rate',
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
                                    _term!.text,
                                    style: TextStyle(
                                      fontFamily: 'Parkinsans',
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: c.foreground,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (_term!.partOfSpeech.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: c.secondary,
                                        borderRadius:
                                            BorderRadius.circular(100),
                                      ),
                                      child: Text(
                                        _term!.partOfSpeech,
                                        style: TextStyle(
                                            fontFamily: 'Metropolis',
                                            fontSize: 11,
                                            color: c.mutedForeground),
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _term!.meaning,
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
                          ],

                          // ── Neos to rate (single card) ──────────────────
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
                                    'No Neo suggestions ready for rating yet.',
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
                            Container(
                              width: double.infinity,
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
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Column(
                                  children: _neos
                                      .asMap()
                                      .entries
                                      .map((entry) => _JuryNeoRow(
                                            neo: entry.value,
                                            myRating: _myRatings[entry.value.id],
                                            isLast: entry.key ==
                                                _neos.length - 1,
                                            onRate: (v) =>
                                                _rate(entry.value.id, v),
                                            onReject: () =>
                                                _showRejectModal(entry.value.id),
                                            c: c,
                                          ))
                                      .toList(),
                                ),
                              ),
                            ),

                          const SizedBox(height: 20),

                          // ── Refresh Neos + Jury Lounge ──────────────────
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() => _loading = true);
                                    _load();
                                  },
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Refresh Neos',
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
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  icon: const Icon(Icons.arrow_forward,
                                      size: 16),
                                  label: const Text('Jury Lounge',
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

// ─── Jury neo row ─────────────────────────────────────────────────────────────
class _JuryNeoRow extends StatelessWidget {
  final _NeoOption neo;
  final int? myRating;
  final bool isLast;
  final void Function(int value) onRate;
  final VoidCallback onReject;
  final AppColorScheme c;

  const _JuryNeoRow({
    required this.neo,
    required this.myRating,
    required this.isLast,
    required this.onRate,
    required this.onReject,
    required this.c,
  });

  static const _emojis = ['😓', '😕', '😐', '😁', '😍'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeoTypeIcon(type: neo.type),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  neo.text,
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.foreground,
                  ),
                ),
              ),
              if (myRating != null)
                Text(
                  myRating! == 0
                      ? '❌'
                      : _emojis[(myRating! - 1).clamp(0, 4)],
                  style: const TextStyle(fontSize: 20),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              GestureDetector(
                onTap: onReject,
                child: const Text('❌', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              ..._emojis.asMap().entries.map(
                    (e) => GestureDetector(
                      onTap: () => onRate(e.key + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: AnimatedScale(
                          scale: myRating == e.key + 1 ? 1.35 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: Text(
                            e.value,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

