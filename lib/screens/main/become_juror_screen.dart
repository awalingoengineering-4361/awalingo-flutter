import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/permissions.dart';
import '../../widgets/neo_audio_play_button.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class _PracticeSuggestion {
  final int id;
  final String text;
  final String type;
  final String? audioUrl;
  const _PracticeSuggestion({required this.id, required this.text, required this.type, this.audioUrl});
}

class _PracticeTerm {
  final int id;
  final String text;
  final String? phonics;
  final String partOfSpeech;
  final String meaning;
  final bool isFallback;
  final List<_PracticeSuggestion> suggestions;
  const _PracticeTerm({
    required this.id, required this.text, this.phonics, required this.partOfSpeech,
    required this.meaning, required this.isFallback, required this.suggestions,
  });
}

// Mirrors juror-applications.ts's FALLBACK_PRACTICE_TERM exactly — shown
// when the user's community has no jury-eligible candidates at all.
const _fallbackPracticeTerm = _PracticeTerm(
  id: 0,
  text: 'Bookmark',
  phonics: '/ˈbʊkmɑːk/',
  partOfSpeech: 'noun',
  meaning: 'a piece of thick paper, leather, or plastic that you put between '
      'the pages of a book so that you can find a page again quickly.',
  isFallback: true,
  suggestions: [
    _PracticeSuggestion(id: -1, text: 'Bookuumarrkiiiii', type: 'POPULAR'),
    _PracticeSuggestion(id: -2, text: 'Bookuumarrkiiiii', type: 'ADOPTIVE'),
    _PracticeSuggestion(id: -3, text: 'Bookuumarrkiiiii', type: 'FUNCTIONAL'),
    _PracticeSuggestion(id: -4, text: 'Bookuumarrkiiiii', type: 'CREATIVE'),
  ],
);

const _practiceTypeIcons = <String, IconData>{
  'POPULAR': Icons.star_outline,
  'ADOPTIVE': Icons.recycling,
  'FUNCTIONAL': Icons.build_outlined,
  'ROOT': Icons.park_outlined,
  'CREATIVE': Icons.psychology_outlined,
};

// Mirrors getStableUserIndex (juror-applications.ts:94-105) exactly: a
// deterministic per-user hash so the same curator always lands on the same
// practice term across reloads, instead of a fresh random one each time.
int _stableUserIndex(String userId, int size) {
  if (size <= 0) return 0;
  var hash = 0;
  for (final codeUnit in userId.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0xFFFFFFFF;
  }
  return hash % size;
}

// ── Service ───────────────────────────────────────────────────────────────────

class _BecomeJurorService {
  final SupabaseClient _db = Supabase.instance.client;

  // Mirrors getPracticeTermForUser (juror-applications.ts:107-159): builds
  // jury-eligible candidates in both directions (English terms needing
  // community-language neos, and vice versa), rotates them starting from a
  // stable per-user index, and returns the first candidate that actually
  // has neo suggestions — falling back to the canned joke term otherwise.
  Future<_PracticeTerm> loadPracticeTerm(String userId) async {
    final utl = await _db.from('user_target_languages').select('languageId').eq('userId', userId).maybeSingle();
    final communityId = utl?['languageId'] as int?;
    if (communityId == null) return _fallbackPracticeTerm;

    final results = await Future.wait([
      _loadJuryTerms(languageId: 1, targetLanguageId: communityId, userId: userId),
      _loadJuryTerms(languageId: communityId, targetLanguageId: 1, userId: userId),
    ]);
    final candidates = [
      for (final t in results[0]) (term: t, suggestionLanguageId: communityId),
      for (final t in results[1]) (term: t, suggestionLanguageId: 1),
    ];
    if (candidates.isEmpty) return _fallbackPracticeTerm;

    final start = _stableUserIndex(userId, candidates.length);
    final ordered = [...candidates.sublist(start), ...candidates.sublist(0, start)];

    for (final candidate in ordered) {
      final suggestions = await _loadJuryNeosForTerm(
        termId: candidate.term.id,
        neoLangId: candidate.suggestionLanguageId,
        userId: userId,
      );
      if (suggestions.isEmpty) continue;
      return _PracticeTerm(
        id: candidate.term.id,
        text: candidate.term.text,
        phonics: candidate.term.phonics,
        partOfSpeech: candidate.term.partOfSpeech,
        meaning: candidate.term.meaning.isNotEmpty ? candidate.term.meaning : 'No definition available.',
        isFallback: false,
        suggestions: suggestions.take(4).toList(),
      );
    }
    return _fallbackPracticeTerm;
  }

  // Mirrors getTerms(languageId, userId, 'jury', targetLanguageId): terms
  // whose language is `languageId` that have at least one qualifying neo
  // (rejectCount<3, not this user's own, not already rated by this user)
  // in `targetLanguageId`.
  Future<List<({int id, String text, String? phonics, String partOfSpeech, String meaning})>> _loadJuryTerms({
    required int languageId,
    required int targetLanguageId,
    required String userId,
  }) async {
    final neoRows = await _db
        .from('neos')
        .select('id, termId')
        .eq('languageId', targetLanguageId)
        .neq('userId', userId)
        .lt('rejectCount', 3);
    if (neoRows.isEmpty) return [];

    final neoIds = neoRows.map((r) => r['id'] as int).toList();
    final ratedRows = await _db.from('neo_rating').select('neoId').eq('userId', userId).inFilter('neoId', neoIds);
    final ratedNeoIds = ratedRows.map((r) => r['neoId'] as int).toSet();

    final validTermIds = neoRows
        .where((n) => !ratedNeoIds.contains(n['id'] as int))
        .map((n) => n['termId'] as int)
        .toSet()
        .toList();
    if (validTermIds.isEmpty) return [];

    final termRows = await _db
        .from('terms')
        .select('id, text, phonics, meaning, partOfSpeech:part_of_speech!partOfSpeechId(name)')
        .eq('languageId', languageId)
        .inFilter('id', validTermIds);

    return termRows.map((r) {
      final pos = r['partOfSpeech'] as Map<String, dynamic>?;
      return (
        id: r['id'] as int,
        text: r['text'] as String,
        phonics: r['phonics'] as String?,
        partOfSpeech: pos?['name'] as String? ?? 'noun',
        meaning: r['meaning'] as String? ?? '',
      );
    }).toList();
  }

  // Mirrors getTermNeos(termId, false, userId, neoLangId, 'jury'): neos for
  // this term/language not created by this user, rejectCount<3, and not
  // already rated by this user.
  Future<List<_PracticeSuggestion>> _loadJuryNeosForTerm({
    required int termId,
    required int neoLangId,
    required String userId,
  }) async {
    final rows = await _db
        .from('neos')
        .select('id, text, type, audioUrl')
        .eq('termId', termId)
        .eq('languageId', neoLangId)
        .neq('userId', userId)
        .lt('rejectCount', 3);
    if (rows.isEmpty) return [];

    final neoIds = rows.map((r) => r['id'] as int).toList();
    final ratedRows = await _db.from('neo_rating').select('neoId').eq('userId', userId).inFilter('neoId', neoIds);
    final ratedNeoIds = ratedRows.map((r) => r['neoId'] as int).toSet();

    return rows
        .where((r) => !ratedNeoIds.contains(r['id'] as int))
        .map((r) => _PracticeSuggestion(
              id: r['id'] as int,
              text: r['text'] as String,
              type: r['type'] as String? ?? 'POPULAR',
              audioUrl: r['audioUrl'] as String?,
            ))
        .toList();
  }

  Future<bool> hasExistingApplication(String userId) async {
    final row = await _db
        .from('juror_applications')
        .select('id')
        .eq('userId', userId)
        .maybeSingle();
    return row != null;
  }

  Future<({String? name, String? email})> prefillFromProfile(String userId) async {
    final row = await _db.from('user_profile').select('name').eq('userId', userId).maybeSingle();
    final name = row?['name'] as String?;
    final authUser = _db.auth.currentUser;
    return (name: name, email: authUser?.email);
  }

  // Mirrors submitJurorApplication's actual persisted fields exactly
  // (juror-applications.ts:249-257) — practice ratings are a client-side
  // gate only and are never written to juror_applications; those columns
  // don't exist on the table.
  Future<void> submitApplication({
    required String userId,
    required String name,
    required String email,
    required String phone,
  }) async {
    await _db.from('juror_applications').upsert({
      'userId': userId,
      'name': name,
      'email': email,
      'phone': phone,
      'agreementAccepted': true,
      'status': 'PENDING',
    }, onConflict: 'userId');
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class BecomeJurorScreen extends StatefulWidget {
  const BecomeJurorScreen({super.key});

  @override
  State<BecomeJurorScreen> createState() => _BecomeJurorScreenState();
}

class _BecomeJurorScreenState extends State<BecomeJurorScreen> {
  final _service = _BecomeJurorService();
  bool _loading = true;
  bool _submitting = false;
  int _step = 0; // 0 = practice, 1 = form, 2 = done

  _PracticeTerm? _practiceTerm;
  final Map<int, int> _ratings = {};
  bool _alreadyApplied = false;

  // Mirrors neolingo's requireCuratorApplicant(): only CURATORs may view or
  // submit a juror application — enforced there before even loading the
  // page's data, not just on submit.
  bool _isCurator = false;

  // Form
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl = TextEditingController();
  late final TextEditingController _emailCtrl = TextEditingController();
  late final TextEditingController _phoneCtrl = TextEditingController();
  bool _agreementAccepted = false;

  static const _emojis = [
    (char: '❌', label: 'Reject', value: 0),
    (char: '😓', label: 'Weak', value: 1),
    (char: '😕', label: 'Unclear', value: 2),
    (char: '😐', label: 'Okay', value: 3),
    (char: '😁', label: 'Good', value: 4),
    (char: '😍', label: 'Excellent', value: 5),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) { setState(() => _loading = false); return; }
    try {
      final role = await fetchUserRole(Supabase.instance.client, userId);
      final isCurator = role == 'CURATOR';
      if (!isCurator) {
        if (mounted) setState(() { _isCurator = false; _loading = false; });
        return;
      }

      final results = await Future.wait([
        _service.loadPracticeTerm(userId),
        _service.hasExistingApplication(userId),
        _service.prefillFromProfile(userId),
      ]);
      final term = results[0] as _PracticeTerm;
      final hasApp = results[1] as bool;
      final prefill = results[2] as ({String? name, String? email});

      if (mounted) {
        _nameCtrl.text = prefill.name ?? '';
        _emailCtrl.text = prefill.email ?? '';
        setState(() {
          _isCurator = true;
          _practiceTerm = term;
          _alreadyApplied = hasApp;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('BecomeJuror load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_isCurator) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_agreementAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please accept the agreement to continue.', style: TextStyle(fontFamily: 'Metropolis')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    setState(() => _submitting = true);
    try {
      await _service.submitApplication(
        userId: userId,
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      if (mounted) setState(() { _step = 2; _submitting = false; });
    } catch (e) {
      debugPrint('BecomeJuror submit: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Submission failed. Please try again.', style: TextStyle(fontFamily: 'Metropolis')),
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _submitting = false);
      }
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
        title: Text('Become a Juror', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.border)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary, strokeWidth: 2))
          : !_isCurator
              ? _NotCuratorView(c: c)
              : _alreadyApplied && _step != 2
              ? _AlreadyAppliedView(c: c)
              : _step == 0
                  ? _PracticeStep(
                      term: _practiceTerm,
                      ratings: _ratings,
                      emojis: _emojis,
                      c: c,
                      onRate: (suggestionId, v) => setState(() => _ratings[suggestionId] = v),
                      onContinue: () => setState(() => _step = 1),
                    )
                  : _step == 1
                      ? _FormStep(
                          formKey: _formKey,
                          nameCtrl: _nameCtrl,
                          emailCtrl: _emailCtrl,
                          phoneCtrl: _phoneCtrl,
                          agreementAccepted: _agreementAccepted,
                          submitting: _submitting,
                          c: c,
                          onAgreementChanged: (v) => setState(() => _agreementAccepted = v ?? false),
                          onSubmit: _submit,
                        )
                      : _DoneView(c: c),
    );
  }
}

// ── Practice Step ─────────────────────────────────────────────────────────────

class _PracticeStep extends StatelessWidget {
  final _PracticeTerm? term;
  final Map<int, int> ratings;
  final List<({String char, String label, int value})> emojis;
  final AppColorScheme c;
  final void Function(int suggestionId, int value) onRate;
  final VoidCallback onContinue;

  const _PracticeStep({
    required this.term, required this.ratings, required this.emojis,
    required this.c, required this.onRate, required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    // Mirrors PracticeStep in become-juror/page.tsx: enabled once the user
    // has rated at least one suggestion, not all of them.
    final hasInteracted = ratings.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How would you rate these translations below?',
              style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, fontWeight: FontWeight.w500, color: c.foreground)),
          const SizedBox(height: 12),

          if (term != null) ...[
            // Term card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFECFEFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFA5F3FC)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(term!.text, style: TextStyle(fontFamily: 'Parkinsans', fontFamilyFallback: kContentFontFallback, fontSize: 20, fontWeight: FontWeight.w600, color: c.foreground)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: [
                  if ((term!.phonics ?? '').isNotEmpty)
                    Text(term!.phonics!, style: TextStyle(fontFamily: 'Metropolis', fontFamilyFallback: kContentFontFallback, fontSize: 12, color: c.mutedForeground)),
                  Text('• ${term!.partOfSpeech}', style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
                ]),
                const SizedBox(height: 10),
                Text(term!.meaning, style: TextStyle(fontFamily: 'Metropolis', fontFamilyFallback: kContentFontFallback, fontSize: 13, color: c.foreground.withValues(alpha: 0.85))),
              ]),
            ),
            const SizedBox(height: 16),

            // Up to 4 practice suggestions, each independently rated.
            Container(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: term!.suggestions.asMap().entries.map((entry) {
                  final isLast = entry.key == term!.suggestions.length - 1;
                  final s = entry.value;
                  final myRating = ratings[s.id];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: isLast ? null : Border(bottom: BorderSide(color: c.border)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(_practiceTypeIcons[s.type] ?? Icons.circle_outlined, size: 18, color: c.foreground),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(s.text,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'Metropolis', fontFamilyFallback: kContentFontFallback, fontSize: 15, color: c.foreground)),
                        ),
                        NeoAudioPlayButton(audioUrl: s.audioUrl),
                      ]),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: emojis.map((e) => GestureDetector(
                          onTap: () => onRate(s.id, e.value),
                          child: AnimatedScale(
                            scale: myRating == e.value ? 1.25 : 1.0,
                            duration: const Duration(milliseconds: 150),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: myRating == e.value ? c.secondary : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(e.char, style: const TextStyle(fontSize: 24)),
                            ),
                          ),
                        )).toList(),
                      ),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
              child: Text('No practice suggestions available for your language yet. You can still apply.',
                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
            ),

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: hasInteracted ? onContinue : null,
            style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: c.primaryForeground,
                disabledBackgroundColor: c.primary.withValues(alpha: 0.4),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Next', style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Form Step ─────────────────────────────────────────────────────────────────

class _FormStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl, emailCtrl, phoneCtrl;
  final bool agreementAccepted;
  final bool submitting;
  final AppColorScheme c;
  final ValueChanged<bool?> onAgreementChanged;
  final VoidCallback onSubmit;

  const _FormStep({
    required this.formKey, required this.nameCtrl, required this.emailCtrl,
    required this.phoneCtrl, required this.agreementAccepted, required this.submitting,
    required this.c, required this.onAgreementChanged, required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
            child: Text('Step 2 of 2 — Application Form\nA member of our team will review your application.',
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
          ),
          _FormField(label: 'Full Name', controller: nameCtrl, c: c, validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Name is required' : null),
          const SizedBox(height: 12),
          _FormField(label: 'Email Address', controller: emailCtrl, c: c, keyboardType: TextInputType.emailAddress,
              validator: (v) => (v?.contains('@') ?? false) ? null : 'Enter a valid email'),
          const SizedBox(height: 12),
          _FormField(label: 'Phone Number', controller: phoneCtrl, c: c, keyboardType: TextInputType.phone,
              validator: (v) => (v?.trim().length ?? 0) < 5 ? 'Phone number is required' : null),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => onAgreementChanged(!agreementAccepted),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(value: agreementAccepted, onChanged: onAgreementChanged, activeColor: c.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('I agree to uphold community standards, rate fairly, and commit to regular participation as a Juror.',
                      style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.foreground)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: submitting ? null : onSubmit,
            style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: c.primaryForeground,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Submit Application', style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final AppColorScheme c;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  const _FormField({required this.label, required this.controller, required this.c, this.keyboardType, this.validator});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground)),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(fontFamily: 'Metropolis', color: c.foreground),
        decoration: InputDecoration(
          filled: true,
          fillColor: c.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.primary)),
        ),
      ),
    ]);
  }
}

class _DoneView extends StatelessWidget {
  final AppColorScheme c;
  const _DoneView({required this.c});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: const Color(0xFF22C55E).withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline, size: 36, color: Color(0xFF22C55E)),
            ),
            const SizedBox(height: 20),
            Text('Application submitted!', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 20, fontWeight: FontWeight.w700, color: c.foreground)),
            const SizedBox(height: 8),
            Text('Our team will review your application. You\'ll receive a notification when a decision is made.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: c.primaryForeground,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Done', style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotCuratorView extends StatelessWidget {
  final AppColorScheme c;
  const _NotCuratorView({required this.c});

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
              decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
              child: Icon(Icons.lock_outline, size: 30, color: c.mutedForeground),
            ),
            const SizedBox(height: 20),
            Text('Not Available', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
            const SizedBox(height: 8),
            Text('Only curators can apply to become a Juror. Become a curator first to unlock this.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}

class _AlreadyAppliedView extends StatelessWidget {
  final AppColorScheme c;
  const _AlreadyAppliedView({required this.c});

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
              decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
              child: Icon(Icons.schedule, size: 30, color: c.mutedForeground),
            ),
            const SizedBox(height: 20),
            Text('Application Pending', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
            const SizedBox(height: 8),
            Text('You have already submitted a Juror application. Our team will review it and notify you of the decision.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}
