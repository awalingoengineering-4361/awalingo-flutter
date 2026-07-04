import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import 'vote_screen.dart' show TermWithNeoCount;

// ─── Neo type metadata ────────────────────────────────────────────────────────
const _neoTypes = ['Popular', 'Adoptive', 'Functional', 'Root', 'Creative'];

const _neoDescriptions = {
  'Popular':
      'Suggest an existing Neo. What does your community currently call the root word?',
  'Adoptive':
      'Flow with the sound. Suggest a Neo that adapts to the sound or rhythm of the root word.',
  'Functional':
      'Suggest a Neo based on the function and usage of the root word.',
  'Root':
      'Digging deep. Suggest a Neo that traces the root word back to its ancient origins.',
  'Creative':
      'Put on your genius hat, curate your own Neo suitable as an equivalent for the root word.',
};

const _neoTypeIcons = <String, IconData>{
  'Popular':    Icons.star_outline,
  'Adoptive':   Icons.recycling,
  'Functional': Icons.build_outlined,
  'Root':       Icons.park_outlined,
  'Creative':   Icons.psychology_outlined,
};

// ─── Service ──────────────────────────────────────────────────────────────────
class _TranslateService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<({int engId, int communityId, String communityShort})>
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
      communityShort: (lang?['short'] as String?) ?? 'COM',
    );
  }

  Future<List<TermWithNeoCount>> loadTerms(int langId) async {
    final termRows = await _db
        .from('terms')
        .select('id, text, meaning, partOfSpeech:part_of_speech!partOfSpeechId(name)')
        .eq('languageId', langId)
        .limit(20);

    if (termRows.isEmpty) return [];

    final termIds = termRows.map((r) => r['id'] as int).toList();

    final neoRows = await _db
        .from('neos')
        .select('termId')
        .inFilter('termId', termIds);

    final neoCountMap = <int, int>{};
    for (final row in neoRows) {
      final tid = row['termId'] as int;
      neoCountMap[tid] = (neoCountMap[tid] ?? 0) + 1;
    }

    return termRows.map((r) {
      final pos = r['partOfSpeech'] as Map<String, dynamic>?;
      return TermWithNeoCount(
        id: r['id'] as int,
        text: r['text'] as String,
        meaning: r['meaning'] as String? ?? '',
        partOfSpeech: pos?['name'] as String? ?? '',
        neoCount: neoCountMap[r['id'] as int] ?? 0,
        languageId: langId,
      );
    }).toList();
  }

  Future<int> myNeoCountForTerm(String userId, int termId) async {
    final rows = await _db
        .from('neos')
        .select('id')
        .eq('termId', termId)
        .eq('userId', userId);
    return rows.length;
  }

  // neoLangId = opposite of the term's language (translating direction)
  Future<void> submitNeos({
    required String userId,
    required int termId,
    required int neoLangId,
    required List<_SuggestionEntry> suggestions,
  }) async {
    final valid = suggestions
        .where((s) => s.text.trim().isNotEmpty && s.type != null)
        .toList();
    if (valid.isEmpty) return;

    for (final s in valid) {
      await _db.from('neos').insert({
        'userId': userId,
        'termId': termId,
        'languageId': neoLangId,
        'text': s.text.trim(),
        'type': s.type!.toUpperCase(),
      });
    }

    // Award 5 cowries per neo
    final profile = await _db
        .from('user_profile')
        .select('cowryBalance')
        .eq('userId', userId)
        .maybeSingle();
    if (profile != null) {
      await _db.from('user_profile').update({
        'cowryBalance':
            ((profile['cowryBalance'] as int?) ?? 0) + (valid.length * 5),
      }).eq('userId', userId);
    }
  }
}

// ─── Translation Lounge Screen ────────────────────────────────────────────────
class TranslateScreen extends StatefulWidget {
  const TranslateScreen({super.key});

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  final _service = _TranslateService();

  bool _loading = true;
  bool _loadDone = false;
  List<TermWithNeoCount> _terms = [];
  int _communityId = 1;
  int _engId = 1;
  String _communityShort = 'COM';
  // Default to English, matching Next.js CurationLoungeClient
  bool _showEnglish = true;

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

      final terms =
          await _service.loadTerms(_showEnglish ? _engId : _communityId);
      if (mounted) setState(() { _terms = terms; _loading = false; });
    } catch (e) {
      debugPrint('TranslateScreen load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchLanguage(bool showEnglish) async {
    if (_showEnglish == showEnglish) return;
    setState(() { _showEnglish = showEnglish; _loading = true; });
    try {
      final terms =
          await _service.loadTerms(showEnglish ? _engId : _communityId);
      if (mounted) setState(() { _terms = terms; _loading = false; });
    } catch (e) {
      debugPrint('TranslateScreen switch: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final terms =
          await _service.loadTerms(_showEnglish ? _engId : _communityId);
      if (mounted) setState(() { _terms = terms; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);

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
                      'Translation Lounge',
                      style: TextStyle(
                        fontFamily: 'Parkinsans',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: c.foreground,
                      ),
                    ),
                  ),
                  // Language switcher — matches LanguageSwitchTag (rounded-md)
                  Container(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LangSegment(
                          label: _communityShort.toUpperCase(),
                          active: !_showEnglish,
                          onTap: () => _switchLanguage(false),
                        ),
                        _LangSegment(
                          label: 'EN',
                          active: _showEnglish,
                          onTap: () => _switchLanguage(true),
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
                onRefresh: _refresh,
                color: c.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  child: Column(
                    children: [
                      // Terms list card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: c.border),
                        ),
                        child: _loading
                            ? _LoadingState(c: c)
                            : _terms.isEmpty
                                ? _EmptyState(c: c)
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _terms.map((term) {
                                      return GestureDetector(
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => SuggestScreen(
                                              term: term,
                                              communityLangId: _communityId,
                                              engLangId: _engId,
                                            ),
                                          ),
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF420FBD),
                                            borderRadius:
                                                BorderRadius.circular(100),
                                          ),
                                          child: Text(
                                            term.text,
                                            style: const TextStyle(
                                              fontFamily: 'Metropolis',
                                              fontWeight: FontWeight.w500,
                                              fontSize: 13,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                      ),

                      // Refresh button centered below card
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _refresh,
                        icon: AnimatedRotation(
                          turns: _loading ? 1 : 0,
                          duration: const Duration(milliseconds: 600),
                          child: const Icon(Icons.refresh, size: 18),
                        ),
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

// ─── Language segment (matches Next.js LanguageSwitchTag) ────────────────────
class _LangSegment extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LangSegment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: active ? const Color(0xFF9C62D9) : Colors.transparent,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Metropolis',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : Colors.grey,
          ),
        ),
      ),
    );
  }
}

// ─── Loading state ────────────────────────────────────────────────────────────
class _LoadingState extends StatelessWidget {
  final AppColorScheme c;
  const _LoadingState({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(color: c.mutedForeground, strokeWidth: 2),
        ),
        const SizedBox(height: 16),
        Text(
          'Loading words...',
          style: TextStyle(
            fontFamily: 'Metropolis',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: c.mutedForeground,
          ),
        ),
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final AppColorScheme c;
  const _EmptyState({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'You are the first here!',
          style: TextStyle(
            fontFamily: 'Metropolis',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: c.foreground,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "It looks a bit quiet. Head over to the dictionary to Request or Suggest new words!",
          style: TextStyle(
            fontFamily: 'Metropolis',
            fontSize: 13,
            color: c.mutedForeground,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ─── Suggest (submit Neo) Screen ──────────────────────────────────────────────
class SuggestScreen extends StatefulWidget {
  final TermWithNeoCount term;
  final int communityLangId;
  final int engLangId;

  const SuggestScreen({
    super.key,
    required this.term,
    required this.communityLangId,
    required this.engLangId,
  });

  @override
  State<SuggestScreen> createState() => _SuggestScreenState();
}

class _SuggestScreenState extends State<SuggestScreen> {
  final _service = _TranslateService();
  final List<_SuggestionEntry> _suggestions = [_SuggestionEntry()];
  bool _submitting = false;
  bool _submitted = false;
  int _availableSlots = 5;
  bool _slotsLoaded = false;

  // Neo language is the opposite of the term's language (translation direction)
  int get _neoLangId => widget.term.languageId == widget.engLangId
      ? widget.communityLangId
      : widget.engLangId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_slotsLoaded) {
      _slotsLoaded = true;
      _loadSlots();
    }
  }

  Future<void> _loadSlots() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    try {
      final count =
          await _service.myNeoCountForTerm(userId, widget.term.id);
      if (mounted) {
        setState(() => _availableSlots = (5 - count).clamp(0, 5));
      }
    } catch (e) {
      debugPrint('loadSlots: $e');
    }
  }

  void _addSuggestion() {
    if (_suggestions.length >= _availableSlots) return;
    setState(() => _suggestions.add(_SuggestionEntry()));
  }

  void _removeSuggestion(int index) {
    if (index == 0) return;
    setState(() => _suggestions.removeAt(index));
  }

  bool get _canSubmit =>
      _suggestions.isNotEmpty &&
      _suggestions.every((s) => s.text.trim().isNotEmpty && s.type != null);

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;

    setState(() => _submitting = true);
    try {
      await _service.submitNeos(
        userId: userId,
        termId: widget.term.id,
        neoLangId: _neoLangId,
        suggestions: _suggestions,
      );
      if (mounted) setState(() { _submitting = false; _submitted = true; });
    } catch (e) {
      debugPrint('submitNeos: $e');
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Submission failed. Please try again.',
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
    if (_submitted) {
      return _SuccessScreen(
        onSubmitAnother: () {
          setState(() {
            _submitted = false;
            _suggestions
              ..clear()
              ..add(_SuggestionEntry());
          });
          _loadSlots();
        },
        onBack: () => Navigator.pop(context),
      );
    }

    final c = AppColorScheme.of(context);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header — back arrow only (matches SuggestClient) ─────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.secondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.arrow_back,
                          size: 20, color: c.foreground),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                child: Column(
                  children: [
                    // ── WordOfTheDay card ─────────────────────────────────
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: c.border),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1D4ED8).withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF1D4ED8)
                                  .withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.term.text,
                              style: TextStyle(
                                fontFamily: 'Parkinsans',
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: c.foreground,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.term.partOfSpeech.isNotEmpty
                                  ? widget.term.partOfSpeech
                                  : 'noun',
                              style: TextStyle(
                                fontFamily: 'Metropolis',
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: c.mutedForeground,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.term.meaning,
                              style: TextStyle(
                                fontFamily: 'Metropolis',
                                fontSize: 14,
                                color: c.foreground.withValues(alpha: 0.8),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Slots exhausted ───────────────────────────────────
                    if (_availableSlots == 0)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: c.border),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 48,
                                color: const Color(0xFF2da529)
                                    .withValues(alpha: 0.6)),
                            const SizedBox(height: 12),
                            Text(
                              "You can only suggest 5 neos per word.",
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
                    else ...[
                      // ── Form card ─────────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: c.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Suggestion entries
                            ..._suggestions.asMap().entries.map((entry) {
                              final i = entry.key;
                              final s = entry.value;
                              return Column(
                                children: [
                                  _SuggestionEntryWidget(
                                    key: ValueKey(i),
                                    entry: s,
                                    canDelete: i != 0,
                                    onDelete: () => _removeSuggestion(i),
                                    onChanged: () => setState(() {}),
                                  ),
                                  Divider(color: c.border),
                                  const SizedBox(height: 4),
                                ],
                              );
                            }),

                            // Add more
                            if (_suggestions.length < _availableSlots)
                              GestureDetector(
                                onTap: _addSuggestion,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add,
                                          size: 20,
                                          color: c.mutedForeground),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Add more Suggestion for this word',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontFamily: 'Metropolis',
                                          color: c.mutedForeground,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            const SizedBox(height: 16),

                            // Submit button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: (_canSubmit && !_submitting)
                                    ? _submit
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: c.primary,
                                  disabledBackgroundColor:
                                      c.primary.withValues(alpha: 0.4),
                                  shape: const StadiumBorder(),
                                  elevation: 0,
                                ),
                                child: _submitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : Text(
                                        'Submit',
                                        style: TextStyle(
                                          fontFamily: 'Parkinsans',
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: c.primaryForeground,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── Bottom buttons (Refresh Neos + Curation Lounge) ───
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: null, // disabled, matching Next.js
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh Neos',
                              style: TextStyle(
                                  fontFamily: 'Metropolis',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text('Curation Lounge',
                              style: TextStyle(
                                  fontFamily: 'Metropolis',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
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

// ─── Suggestion entry model ───────────────────────────────────────────────────
class _SuggestionEntry {
  String? type;
  String text = '';
}

// ─── Suggestion entry widget (matches SuggestInput layout) ───────────────────
class _SuggestionEntryWidget extends StatefulWidget {
  final _SuggestionEntry entry;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _SuggestionEntryWidget({
    super.key,
    required this.entry,
    required this.canDelete,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<_SuggestionEntryWidget> createState() =>
      _SuggestionEntryWidgetState();
}

class _SuggestionEntryWidgetState extends State<_SuggestionEntryWidget> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showInfoDialog(BuildContext context) {
    if (widget.entry.type == null) return;
    final c = AppColorScheme.of(context);
    final type = widget.entry.type!;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(_neoTypeIcons[type] ?? Icons.circle_outlined,
                size: 20, color: c.foreground),
            const SizedBox(width: 8),
            Text(type,
                style: TextStyle(
                    fontFamily: 'Parkinsans',
                    fontSize: 16,
                    color: c.foreground)),
          ],
        ),
        content: Text(
          _neoDescriptions[type] ?? '',
          style: TextStyle(
              fontFamily: 'Metropolis',
              fontSize: 14,
              color: c.mutedForeground,
              height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it',
                style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontWeight: FontWeight.w600,
                    color: c.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final selectedType = widget.entry.type;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          // ── Row 1: Type selector + Info + Delete ───────────────────
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: c.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButton<String>(
                    value: selectedType,
                    underline: const SizedBox(),
                    isExpanded: true,
                    dropdownColor: c.card,
                    hint: Row(
                      children: [
                        Icon(Icons.circle_outlined,
                            size: 18,
                            color: c.mutedForeground.withValues(alpha: 0.6)),
                        const SizedBox(width: 8),
                        Text('Choose a type',
                            style: TextStyle(
                                fontSize: 14,
                                fontFamily: 'Metropolis',
                                color: c.mutedForeground)),
                      ],
                    ),
                    selectedItemBuilder: (_) => _neoTypes
                        .map((t) => Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  Icon(_neoTypeIcons[t] ?? Icons.circle_outlined,
                                      size: 18, color: c.foreground),
                                  const SizedBox(width: 8),
                                  Text(t,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontFamily: 'Metropolis',
                                          color: c.foreground)),
                                ],
                              ),
                            ))
                        .toList(),
                    items: _neoTypes
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Row(
                                children: [
                                  Icon(
                                      _neoTypeIcons[t] ??
                                          Icons.circle_outlined,
                                      size: 18,
                                      color: c.foreground),
                                  const SizedBox(width: 8),
                                  Text(t,
                                      style: TextStyle(
                                          fontFamily: 'Metropolis',
                                          fontSize: 14,
                                          color: c.foreground)),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() => widget.entry.type = v);
                      widget.onChanged();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Info button
              InkWell(
                onTap: selectedType != null
                    ? () => _showInfoDialog(context)
                    : null,
                borderRadius: BorderRadius.circular(100),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.info_outline,
                      size: 20,
                      color: selectedType != null
                          ? c.mutedForeground
                          : c.mutedForeground.withValues(alpha: 0.3)),
                ),
              ),
              // Delete button
              if (widget.canDelete)
                InkWell(
                  onTap: widget.onDelete,
                  borderRadius: BorderRadius.circular(100),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.delete_outline,
                        size: 20, color: c.mutedForeground),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Row 2: Text input ──────────────────────────────────────
          TextField(
            controller: _controller,
            maxLength: 50,
            style: TextStyle(
                color: c.foreground,
                fontFamily: 'Metropolis',
                fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Type suggestion here',
              hintStyle: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Metropolis',
                  color: c.mutedForeground),
              counterStyle:
                  TextStyle(fontSize: 11, color: c.mutedForeground),
              filled: true,
              fillColor: c.background,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.primary),
              ),
            ),
            onChanged: (v) {
              widget.entry.text = v;
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}

// ─── Success screen ───────────────────────────────────────────────────────────
class _SuccessScreen extends StatelessWidget {
  final VoidCallback onSubmitAnother;
  final VoidCallback onBack;

  const _SuccessScreen(
      {required this.onSubmitAnother, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2da529).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check,
                        size: 32, color: Color(0xFF2da529)),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Suggestion Submitted!',
                    style: TextStyle(
                      fontFamily: 'Parkinsans',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Thank you for contributing to the Awalingo community. Your suggestion will be reviewed and made available for voting soon.',
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 14,
                      color: c.mutedForeground,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onSubmitAnother,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.primary,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: Text(
                        'Submit Another',
                        style: TextStyle(
                          fontFamily: 'Parkinsans',
                          fontWeight: FontWeight.w600,
                          color: c.primaryForeground,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onBack,
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Back to Home',
                        style: TextStyle(
                          fontFamily: 'Parkinsans',
                          fontWeight: FontWeight.w600,
                          color: c.foreground,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
