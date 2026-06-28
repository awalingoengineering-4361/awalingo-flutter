import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class DictionaryTerm {
  final int id;
  final String text;
  final String meaning;
  final String? phonics;
  final String partOfSpeech;
  final String? translation;
  final int? translationWordId;
  final List<NeoSuggestion> neos;
  final bool isDirectMatch;

  const DictionaryTerm({
    required this.id,
    required this.text,
    required this.meaning,
    this.phonics,
    required this.partOfSpeech,
    this.translation,
    this.translationWordId,
    required this.neos,
    this.isDirectMatch = true,
  });
}

class NeoSuggestion {
  final int id;
  final String text;
  final String type;
  final int ratingScore;

  const NeoSuggestion({
    required this.id,
    required this.text,
    required this.type,
    this.ratingScore = 0,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

typedef _UserContext = ({int engId, int communityId, String name, String short});

class _DictionaryService {
  final SupabaseClient _db = Supabase.instance.client;

  /// Single parallel query: English language ID + user's community language info.
  Future<_UserContext?> bootstrapUserContext(String userId) async {
    final engRow = await _db
        .from('languages')
        .select('id')
        .eq('code', 'eng')
        .maybeSingle();

    final utl = await _db
        .from('user_target_languages')
        .select('language:languages!languageId(id, name, short)')
        .eq('userId', userId)
        .maybeSingle();

    final lang = utl?['language'] as Map<String, dynamic>?;
    if (lang == null) return null;

    final communityId = lang['id'] as int;
    final name = (lang['name'] as String?) ?? '';
    final rawShort = (lang['short'] as String?) ?? '';
    final short = rawShort.isNotEmpty ? rawShort : _shortOf(name);

    return (
      engId: (engRow?['id'] as int?) ?? 0,
      communityId: communityId,
      name: name,
      short: short,
    );
  }

  /// Distinct first-letters for the alphabet sidebar.
  Future<List<String>> getAlphabets(int languageId) async {
    try {
      final rows = await _db
          .from('terms')
          .select('text')
          .eq('languageId', languageId);
      final letters = <String>{};
      for (final row in rows) {
        final text = (row['text'] as String?) ?? '';
        if (text.isNotEmpty) letters.add(text[0].toUpperCase());
      }
      return letters.toList()..sort();
    } catch (_) {
      return [];
    }
  }

  /// Paginated terms with translations and (community-language) neo suggestions.
  Future<({List<DictionaryTerm> terms, bool hasMore})> getTerms(
    int primaryId,
    int secondaryId,
    int communityLanguageId, {
    int skip = 0,
    int take = 20,
    String searchQuery = '',
    String alphabet = '',
  }) async {
    var query = _db
        .from('terms')
        .select(
          'id, text, meaning, phonics, conceptId, '
          'part_of_speech!partOfSpeechId(name), '
          'neos!termId(id, text, type, ratingScore, languageId)',
        )
        .eq('languageId', primaryId);

    if (searchQuery.isNotEmpty) {
      query = query.or('text.ilike.%$searchQuery%,meaning.ilike.%$searchQuery%');
    } else if (alphabet.isNotEmpty) {
      query = query.ilike('text', '$alphabet%');
    }

    final res = await query.order('text').range(skip, skip + take);
    final hasMore = res.length > take;
    final page = hasMore ? res.sublist(0, take) : res;

    // Batch-fetch sibling terms in the other language via shared conceptId
    final conceptIds =
        page.map((t) => t['conceptId'] as int?).whereType<int>().toSet().toList();
    final Map<int, ({int id, String text})> siblingByConceptId = {};
    if (conceptIds.isNotEmpty) {
      final sibs = await _db
          .from('terms')
          .select('id, text, conceptId')
          .eq('languageId', secondaryId)
          .inFilter('conceptId', conceptIds);
      for (final s in sibs) {
        final cId = s['conceptId'] as int?;
        if (cId != null) {
          siblingByConceptId[cId] = (id: s['id'] as int, text: s['text'] as String);
        }
      }
    }

    final qLower = searchQuery.toLowerCase();
    final terms = page.map((t) {
      final conceptId = t['conceptId'] as int?;
      final sibling = conceptId != null ? siblingByConceptId[conceptId] : null;
      final neosRaw = (t['neos'] as List<dynamic>?) ?? [];
      final textLower = ((t['text'] as String?) ?? '').toLowerCase();

      // Mirror Next.js: only community-language neos, top 3 by ratingScore
      final neos = neosRaw
          .where((n) => (n['languageId'] as int?) == communityLanguageId)
          .map((n) => NeoSuggestion(
                id: n['id'] as int,
                text: (n['text'] as String?) ?? '',
                type: _neoTypeLabel((n['type'] as String?) ?? 'POPULAR'),
                ratingScore: (n['ratingScore'] as int?) ?? 0,
              ))
          .toList()
        ..sort((a, b) => b.ratingScore.compareTo(a.ratingScore));

      return DictionaryTerm(
        id: t['id'] as int,
        text: (t['text'] as String?) ?? '',
        meaning: (t['meaning'] as String?) ?? '',
        phonics: t['phonics'] as String?,
        partOfSpeech:
            ((t['part_of_speech'] as Map<String, dynamic>?)?['name'] as String?) ?? 'Unknown',
        translation: sibling?.text,
        translationWordId: sibling?.id,
        neos: neos.take(3).toList(),
        isDirectMatch:
            searchQuery.isEmpty || textLower.startsWith(qLower) || textLower.contains(qLower),
      );
    }).toList();

    return (terms: terms, hasMore: hasMore);
  }

  static String _shortOf(String name) {
    if (name.isEmpty) return 'NEO';
    return name.length >= 3 ? name.substring(0, 3).toUpperCase() : name.toUpperCase();
  }

  static String _neoTypeLabel(String type) {
    switch (type) {
      case 'POPULAR':
        return 'Popular';
      case 'ADOPTIVE':
        return 'Adoptive';
      case 'FUNCTIONAL':
        return 'Functional';
      case 'ROOT':
        return 'Root';
      case 'CREATIVE':
        return 'Creative';
      default:
        return type;
    }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final _service = _DictionaryService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  bool _bootstrapDone = false;

  bool _bootstrapLoading = true;
  bool _resultsLoading = false;
  bool _loadingMore = false;
  bool _hasMore = false;

  int? _englishLanguageId;
  int? _communityLanguageId;
  int? _activeLanguageId;
  String _activeLanguage = 'community';
  String _communityName = '';
  String _communityShort = 'NEO';

  List<DictionaryTerm> _words = [];
  List<String> _alphabets = [];
  String _currentAlphabet = '';
  String _debouncedQuery = '';
  int _skip = 0;
  int? _openWordId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bootstrapDone) {
      _bootstrapDone = true;
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        _hasMore &&
        !_resultsLoading &&
        !_loadingMore) {
      _loadMore();
    }
  }

  Future<void> _bootstrap() async {
    final auth = AuthProvider.of(context);
    final userId = auth.user?.id;
    if (userId == null) {
      setState(() => _bootstrapLoading = false);
      return;
    }

    try {
      // Single parallel call: English language ID + user's community info
      final ctx = await _service.bootstrapUserContext(userId);
      if (ctx == null || !mounted) {
        setState(() => _bootstrapLoading = false);
        return;
      }

      final primaryId =
          _activeLanguage == 'english' && ctx.engId != 0 ? ctx.engId : ctx.communityId;
      final secondaryId =
          primaryId == ctx.engId ? ctx.communityId : (ctx.engId != 0 ? ctx.engId : ctx.communityId);

      // Alphabets and first page of terms run in parallel
      final results = await Future.wait([
        _service.getAlphabets(primaryId),
        _service.getTerms(primaryId, secondaryId, ctx.communityId, skip: 0, take: 20),
      ]);

      if (!mounted) return;
      final alphabets = results[0] as List<String>;
      final termsResult = results[1] as ({List<DictionaryTerm> terms, bool hasMore});

      setState(() {
        _englishLanguageId = ctx.engId != 0 ? ctx.engId : null;
        _communityLanguageId = ctx.communityId;
        _activeLanguageId = primaryId;
        _communityName = ctx.name;
        _communityShort = ctx.short;
        _alphabets = alphabets;
        _words = termsResult.terms;
        _hasMore = termsResult.hasMore;
        _skip = termsResult.terms.length;
        _bootstrapLoading = false;
      });
    } catch (e, stack) {
      debugPrint('Dictionary bootstrap error: $e');
      debugPrint(stack.toString());
      if (mounted) setState(() => _bootstrapLoading = false);
    }
  }

  Future<void> _fetchTerms({bool reset = true}) async {
    if (_bootstrapLoading || _communityLanguageId == null) return;
    if (reset) {
      setState(() {
        _resultsLoading = true;
        _openWordId = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    final primaryId = _activeLanguageId ?? _communityLanguageId!;
    final secondaryId = primaryId == _englishLanguageId
        ? _communityLanguageId!
        : (_englishLanguageId ?? _communityLanguageId!);
    final skip = reset ? 0 : _skip;

    try {
      final result = await _service.getTerms(
        primaryId,
        secondaryId,
        _communityLanguageId!,
        skip: skip,
        take: 20,
        searchQuery: _debouncedQuery,
        alphabet: _currentAlphabet,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _words = result.terms;
        } else {
          final ids = _words.map((w) => w.id).toSet();
          _words = [..._words, ...result.terms.where((t) => !ids.contains(t.id))];
        }
        _hasMore = result.hasMore;
        _skip = skip + result.terms.length;
        _resultsLoading = false;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('Dictionary fetch error: $e');
      if (mounted) {
        setState(() {
          _resultsLoading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _loadMore() => _fetchTerms(reset: false);

  void _onSearchChanged(String value) {
    setState(() => _currentAlphabet = '');
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      setState(() {
        _debouncedQuery = value;
        _skip = 0;
      });
      _fetchTerms();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _debouncedQuery = '';
      _currentAlphabet = '';
      _skip = 0;
    });
    _fetchTerms();
  }

  void _onAlphabetTap(String letter) {
    final next = _currentAlphabet == letter ? '' : letter;
    setState(() {
      _currentAlphabet = next;
      _skip = 0;
    });
    _fetchTerms();
  }

  void _toggleLanguage() {
    if (_communityLanguageId == null || _englishLanguageId == null) return;
    final next = _activeLanguage == 'community' ? 'english' : 'community';
    final nextId = next == 'community' ? _communityLanguageId! : _englishLanguageId!;
    _searchController.clear();
    setState(() {
      _activeLanguage = next;
      _activeLanguageId = nextId;
      _debouncedQuery = '';
      _currentAlphabet = '';
      _skip = 0;
    });
    _fetchTerms();
    _service.getAlphabets(nextId).then((letters) {
      if (mounted) setState(() => _alphabets = letters);
    });
  }

  void _switchToTranslation(DictionaryTerm term) {
    final otherLang = _activeLanguage == 'english' ? 'community' : 'english';
    final otherLangId = otherLang == 'english' ? _englishLanguageId : _communityLanguageId;
    if (otherLangId == null || term.translation == null) return;
    _searchController.text = term.translation!;
    setState(() {
      _activeLanguage = otherLang;
      _activeLanguageId = otherLangId;
      _debouncedQuery = term.translation!;
      _currentAlphabet = '';
      _skip = 0;
      _openWordId = null;
    });
    _fetchTerms();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    if (_bootstrapLoading) {
      return Center(child: CircularProgressIndicator(color: c.primary, strokeWidth: 2));
    }
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                Divider(height: 1, color: c.border),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildWordList()),
                      _buildAlphabetSidebar(),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 90,
              right: 56,
              child: _buildFloatingButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final c = AppColorScheme.of(context);
    final title = _communityName.isNotEmpty ? 'AwaDiko $_communityName' : 'AwaDiko';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Parkinsans',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.foreground,
              ),
            ),
          ),
          _LanguageSwitchTag(
            communityShort: _communityShort,
            activeLanguage: _activeLanguage,
            onToggle: _toggleLanguage,
          ),
        ],
      ),
    );
  }

  Widget _buildWordList() {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(child: _buildSearchBar()),
        if (_resultsLoading && _words.isEmpty)
          SliverToBoxAdapter(child: _buildSkeleton())
        else if (_words.isEmpty)
          SliverToBoxAdapter(child: _buildEmptyState())
        else ...[
          if (_debouncedQuery.isNotEmpty && _words.any((w) => w.isDirectMatch))
            _buildSectionHeader('Direct Matches'),
          _buildTermsList(_debouncedQuery.isEmpty ? _words : _words.where((w) => w.isDirectMatch).toList()),
          if (_debouncedQuery.isNotEmpty && _words.any((w) => !w.isDirectMatch)) ...[
            _buildSectionHeader('Related Results'),
            _buildTermsList(_words.where((w) => !w.isDirectMatch).toList()),
          ],
        ],
        if (_loadingMore) SliverToBoxAdapter(child: _buildLoadingMore()),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildSearchBar() {
    final c = AppColorScheme.of(context);
    final placeholder = _activeLanguage == 'english'
        ? 'Search English words'
        : 'Search ${_communityName.isNotEmpty ? _communityName : 'community'} words';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.foreground),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground),
          filled: true,
          fillColor: c.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(100), borderSide: BorderSide(color: c.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(100), borderSide: BorderSide(color: c.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(100), borderSide: BorderSide(color: c.primary, width: 1.5)),
          prefixIcon: Icon(Icons.search, size: 18, color: c.mutedForeground),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, size: 18, color: c.mutedForeground),
                  onPressed: _clearSearch,
                )
              : null,
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildSectionHeader(String title) {
    final c = AppColorScheme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          title,
          style: TextStyle(
            fontFamily: 'Parkinsans',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: c.foreground,
          ),
        ),
      ),
    );
  }

  SliverList _buildTermsList(List<DictionaryTerm> terms) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          if (i >= terms.length) return null;
          final term = terms[i];
          return _WordCard(
            term: term,
            index: i,
            languageName: _activeLanguage == 'english' ? _communityName : 'English',
            isOpen: _openWordId == term.id,
            onToggle: () => setState(() => _openWordId = _openWordId == term.id ? null : term.id),
            onTranslationTap: term.translation != null ? () => _switchToTranslation(term) : null,
            onVote: () => _showSnack('Vote feature coming soon'),
            onTranslate: () => _showSnack('Suggest translation coming soon'),
          );
        },
        childCount: terms.length,
      ),
    );
  }

  Widget _buildAlphabetSidebar() {
    final c = AppColorScheme.of(context);
    return Container(
      width: 36,
      margin: const EdgeInsets.fromLTRB(0, 14, 4, 4),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: c.border),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // "All" button
            _AlphabetButton(
              label: '≡',
              isActive: _currentAlphabet.isEmpty,
              isFirst: true,
              onTap: () {
                setState(() { _currentAlphabet = ''; _skip = 0; });
                _fetchTerms();
              },
            ),
            ..._alphabets.map((letter) => _AlphabetButton(
                  label: letter,
                  isActive: _currentAlphabet == letter,
                  onTap: () => _onAlphabetTap(letter),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final c = AppColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
      child: Column(
        children: [
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
                const Icon(Icons.search_off_rounded, size: 64, color: Color(0x22111111)),
                const SizedBox(height: 16),
                Text(
                  'Word Not Found',
                  style: TextStyle(
                    fontFamily: 'Parkinsans',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Kindly nominate a word for your community to suggest Neos for it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground),
                ),
                const SizedBox(height: 20),
                if (_debouncedQuery.isNotEmpty)
                  GestureDetector(
                    onTap: _clearSearch,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Text('Clear Search',
                          style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    final c = AppColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          4,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 120,
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingMore() {
    final c = AppColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.mutedForeground)),
          const SizedBox(width: 8),
          Text('Loading more words...', style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
        ],
      ),
    );
  }

  Widget _buildFloatingButton() {
    final c = AppColorScheme.of(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed('/request'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: BorderRadius.circular(100),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: c.primaryForeground),
            const SizedBox(width: 6),
            Text('Request Word', style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w600, color: c.primaryForeground)),
          ],
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontFamily: 'Metropolis')),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

// ── Word Card ─────────────────────────────────────────────────────────────────

class _WordCard extends StatelessWidget {
  final DictionaryTerm term;
  final int index;
  final String languageName;
  final bool isOpen;
  final VoidCallback onToggle;
  final VoidCallback? onTranslationTap;
  final VoidCallback onVote;
  final VoidCallback onTranslate;

  const _WordCard({
    required this.term,
    required this.index,
    required this.languageName,
    required this.isOpen,
    required this.onToggle,
    this.onTranslationTap,
    required this.onVote,
    required this.onTranslate,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Word + share button row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        term.text,
                        style: TextStyle(
                          fontFamily: 'Metropolis',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.foreground,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _shareWord(context),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.share_outlined, size: 18, color: c.mutedForeground.withValues(alpha: 0.7)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Translation
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'AwaDiko $languageName: ',
                        style: const TextStyle(
                          fontFamily: 'Metropolis',
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFFA30202),
                        ),
                      ),
                      if (onTranslationTap != null && term.translation != null)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: GestureDetector(
                            onTap: onTranslationTap,
                            child: Text(
                              term.translation!,
                              style: const TextStyle(
                                fontFamily: 'Metropolis',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF6B3FA0),
                                decoration: TextDecoration.underline,
                                decorationStyle: TextDecorationStyle.dashed,
                              ),
                            ),
                          ),
                        )
                      else
                        TextSpan(
                          text: term.translation ?? '—',
                          style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: c.foreground80,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Part of speech
                Text(
                  term.partOfSpeech,
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: c.mutedForeground,
                  ),
                ),
                const SizedBox(height: 4),
                // Definition
                Text(
                  term.meaning,
                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.foreground80, height: 1.5),
                ),
              ],
            ),
          ),
          // Footer: Ranks toggle + Vote + Translate
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    // Ranks toggle
                    GestureDetector(
                      onTap: onToggle,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: c.secondary,
                          border: Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bar_chart_rounded, size: 14, color: c.mutedForeground),
                            const SizedBox(width: 4),
                            Text('Ranks', style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, fontWeight: FontWeight.w500, color: c.foreground)),
                            const SizedBox(width: 4),
                            AnimatedRotation(
                              turns: isOpen ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(Icons.keyboard_arrow_down, size: 16, color: c.mutedForeground),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Vote
                    GestureDetector(
                      onTap: onVote,
                      child: const Row(
                        children: [
                          Icon(Icons.how_to_vote_outlined, size: 16, color: Color(0xFFA30202)),
                          SizedBox(width: 4),
                          Text('Vote', style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFA30202))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Translate
                    GestureDetector(
                      onTap: onTranslate,
                      child: const Row(
                        children: [
                          Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFFA30202)),
                          SizedBox(width: 4),
                          Text('Translate', style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFA30202))),
                        ],
                      ),
                    ),
                  ],
                ),
                // Expandable Neos
                AnimatedCrossFade(
                  crossFadeState: isOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 220),
                  firstChild: const SizedBox.shrink(),
                  secondChild: _buildNeosList(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeosList(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: term.neos.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('You are the first here!',
                      style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground)),
                  const SizedBox(height: 4),
                  Text('Use Vote or Translate to add the first suggestion.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
                ],
              ),
            )
          : Column(
              children: term.neos.asMap().entries.map((entry) {
                final i = entry.key;
                final neo = entry.value;
                final isLast = i == term.neos.length - 1;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: isLast ? null : Border(bottom: BorderSide(color: c.border)),
                  ),
                  child: Row(
                    children: [
                      _NeoTypeIcon(type: neo.type),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(neo.text,
                            style: TextStyle(fontFamily: 'Parkinsans', fontSize: 14, fontWeight: FontWeight.w500, color: c.foreground)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.secondary,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(neo.type,
                            style: TextStyle(fontFamily: 'Metropolis', fontSize: 10, color: c.mutedForeground)),
                      ),
                      if (neo.ratingScore > 0) ...[
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 12, color: Color(0xFFEAAB0B)),
                            const SizedBox(width: 2),
                            Text('${neo.ratingScore}',
                                style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, color: c.mutedForeground)),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  void _shareWord(BuildContext context) {
    Clipboard.setData(ClipboardData(text: '${term.text}: ${term.meaning}'));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Copied to clipboard', style: TextStyle(fontFamily: 'Metropolis')),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

// ── Language Switch Tag ───────────────────────────────────────────────────────

class _LanguageSwitchTag extends StatelessWidget {
  final String communityShort;
  final String activeLanguage;
  final VoidCallback onToggle;

  const _LanguageSwitchTag({
    required this.communityShort,
    required this.activeLanguage,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Tab(label: communityShort, isActive: activeLanguage == 'community'),
            _Tab(label: 'EN', isActive: activeLanguage == 'english'),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool isActive;

  const _Tab({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF9C62D9) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Metropolis',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isActive ? Colors.white : c.mutedForeground,
        ),
      ),
    );
  }
}

// ── Alphabet Button ───────────────────────────────────────────────────────────

class _AlphabetButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isFirst;
  final VoidCallback onTap;

  const _AlphabetButton({
    required this.label,
    required this.isActive,
    this.isFirst = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: isFirst ? 8 : 5),
        decoration: BoxDecoration(
          color: isActive ? c.secondary : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Metropolis',
              fontSize: isFirst ? 14 : 11,
              fontWeight: FontWeight.w600,
              color: isActive ? c.primary : c.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Neo Type Icon ─────────────────────────────────────────────────────────────

class _NeoTypeIcon extends StatelessWidget {
  final String type;
  const _NeoTypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    IconData icon;
    switch (type.toLowerCase()) {
      case 'popular':
        icon = Icons.star_outline;
        break;
      case 'adoptive':
        icon = Icons.recycling;
        break;
      case 'functional':
        icon = Icons.build_outlined;
        break;
      case 'root':
        icon = Icons.park_outlined;
        break;
      case 'creative':
        icon = Icons.psychology_outlined;
        break;
      default:
        icon = Icons.circle_outlined;
    }
    return Icon(icon, size: 16, color: c.foreground80);
  }
}
