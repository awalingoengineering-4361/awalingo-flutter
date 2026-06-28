import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';

// ── Models ─────────────────────────────────────────────────────────────────────

class _PartOfSpeech {
  final int id;
  final String name;
  const _PartOfSpeech({required this.id, required this.name});
}

class _Bootstrap {
  final int engId;
  final int communityId;
  final String communityName;
  final String communityShort;
  final List<_PartOfSpeech> partsOfSpeech;

  const _Bootstrap({
    required this.engId,
    required this.communityId,
    required this.communityName,
    required this.communityShort,
    required this.partsOfSpeech,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class _RequestService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<_Bootstrap> bootstrap(String userId) async {
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

    final posRows = await _db.from('part_of_speech').select('id, name');

    return _Bootstrap(
      engId: engId,
      communityId: (lang?['id'] as int?) ?? engId,
      communityName: (lang?['name'] as String?) ?? 'Community',
      communityShort: (lang?['short'] as String?) ?? '',
      partsOfSpeech: posRows
          .map((r) => _PartOfSpeech(
              id: r['id'] as int, name: r['name'] as String))
          .toList(),
    );
  }

  Future<void> submit({
    required String userId,
    required String word,
    required String meaning,
    required int sourceLanguageId,
    required int targetLanguageId,
    required int partOfSpeechId,
  }) async {
    await _db.from('translation_requests').insert({
      'word': word.trim(),
      'meaning': meaning.trim(),
      'sourceLanguageId': sourceLanguageId,
      'targetLanguageId': targetLanguageId,
      'partOfSpeechId': partOfSpeechId,
      'userId': userId,
      'status': 'PENDING',
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
          .update({'cowryBalance': current + 3}).eq('userId', userId);
    }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  final _service = _RequestService();
  final _wordCtrl = TextEditingController();
  final _meaningCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _bootstrapping = true;
  bool _submitting = false;
  bool _submitted = false;
  _Bootstrap? _boot;

  // true = English→Community, false = Community→English
  bool _engIsSource = true;
  int? _selectedPosId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapping) _load();
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) {
      setState(() => _bootstrapping = false);
      return;
    }
    try {
      final boot = await _service.bootstrap(userId);
      if (mounted) setState(() { _boot = boot; _bootstrapping = false; });
    } catch (e) {
      debugPrint('Request bootstrap error: $e');
      if (mounted) setState(() => _bootstrapping = false);
    }
  }

  int get _sourceId =>
      _boot == null ? 1 : (_engIsSource ? _boot!.engId : _boot!.communityId);
  int get _targetId =>
      _boot == null ? 1 : (_engIsSource ? _boot!.communityId : _boot!.engId);
  String get _sourceName =>
      _boot == null ? 'English' : (_engIsSource ? 'English' : _boot!.communityName);
  String get _targetName =>
      _boot == null ? 'Community' : (_engIsSource ? _boot!.communityName : 'English');

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedPosId == null) {
      ScaffoldMessenger.of(context).showSnackBar(_snack('Please select a part of speech'));
      return;
    }
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;

    setState(() => _submitting = true);
    try {
      await _service.submit(
        userId: userId,
        word: _wordCtrl.text,
        meaning: _meaningCtrl.text,
        sourceLanguageId: _sourceId,
        targetLanguageId: _targetId,
        partOfSpeechId: _selectedPosId!,
      );
      if (mounted) setState(() { _submitting = false; _submitted = true; });
    } catch (e) {
      debugPrint('Request submit error: $e');
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(_snack('Submission failed. Please try again.'));
      }
    }
  }

  SnackBar _snack(String msg) => SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Metropolis')),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  void _reset() {
    _wordCtrl.clear();
    _meaningCtrl.clear();
    setState(() { _submitted = false; _selectedPosId = null; _engIsSource = true; });
  }

  @override
  void dispose() {
    _wordCtrl.dispose();
    _meaningCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
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
                    'Request a Word',
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

            if (_bootstrapping)
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                      color: c.primary, strokeWidth: 2),
                ),
              )
            else if (_submitted)
              Expanded(
                child: _SuccessView(
                  onRequestAnother: _reset,
                  onBack: () => Navigator.pop(context),
                ),
              )
            else
              Expanded(child: _buildForm(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(AppColorScheme c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        children: [
          // Description
          Text(
            'Submit a word for the community to coin a Neo for.',
            style: TextStyle(
              fontFamily: 'Metropolis',
              fontSize: 14,
              color: c.mutedForeground,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // ── Form card ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: c.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Language direction ──────────────────────────────
                  _FieldLabel('Language', c: c),
                  Text(
                    'Which language is the word in?',
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 12,
                      color: c.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _RadioCard(
                          label: 'English',
                          sublabel: 'Translate from English',
                          selected: _engIsSource,
                          onTap: _boot != null
                              ? () => setState(() => _engIsSource = true)
                              : null,
                          c: c,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _RadioCard(
                          label: _boot?.communityName ?? 'Community',
                          sublabel: 'Translate from ${_boot?.communityName ?? 'Community'}',
                          selected: !_engIsSource,
                          onTap: _boot != null
                              ? () => setState(() => _engIsSource = false)
                              : null,
                          c: c,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Info box: direction indicator
                  if (_boot != null)
                    _DirectionInfoBox(
                      sourceName: _sourceName,
                      targetName: _targetName,
                      isDark: isDark,
                    ),

                  const SizedBox(height: 24),

                  // ── Word ─────────────────────────────────────────────
                  _FieldLabel('Word', c: c),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _wordCtrl,
                    style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 14,
                        color: c.foreground),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Word is required' : null,
                    decoration: _inputDecoration(
                        'Enter the word to translate', c),
                  ),
                  const SizedBox(height: 24),

                  // ── Part of Speech ────────────────────────────────────
                  _FieldLabel('Part of Speech', c: c),
                  const SizedBox(height: 8),
                  if (_boot != null)
                    DropdownButtonFormField<int>(
                      key: ValueKey(_selectedPosId),
                      initialValue: _selectedPosId,
                      hint: Text(
                        'Select part of speech',
                        style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontSize: 13,
                            color: c.mutedForeground),
                      ),
                      dropdownColor: c.card,
                      decoration: _inputDecoration(null, c),
                      items: _boot!.partsOfSpeech
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name,
                                    style: TextStyle(
                                        fontFamily: 'Metropolis',
                                        fontSize: 14,
                                        color: c.foreground)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedPosId = v),
                    ),
                  const SizedBox(height: 24),

                  // ── Meaning ────────────────────────────────────────────
                  _FieldLabel('Meaning', c: c),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _meaningCtrl,
                    maxLines: 4,
                    style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 14,
                        color: c.foreground),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Meaning is required' : null,
                    decoration: _inputDecoration(
                        'Describe what this word means…', c),
                  ),
                  const SizedBox(height: 10),

                  // Meaning helper box
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Provide enough context for translators. The meaning should be written in $_sourceName.',
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 12,
                        color: c.mutedForeground,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Submit ─────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.primary,
                        disabledBackgroundColor:
                            c.primary.withValues(alpha: 0.4),
                        shape: const StadiumBorder(),
                        elevation: 0,
                      ),
                      child: _submitting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.primaryForeground))
                          : Text(
                              'Submit Request',
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
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String? hint, AppColorScheme c) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground),
      filled: true,
      fillColor: c.secondary,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.primary),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error),
      ),
    );
  }
}

// ── Radio card ─────────────────────────────────────────────────────────────────

class _RadioCard extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback? onTap;
  final AppColorScheme c;

  const _RadioCard({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? c.card : c.secondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? c.foreground.withValues(alpha: 0.3) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Radio circle
            Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? c.foreground
                      : c.mutedForeground,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: c.foreground,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 11,
                      color: c.mutedForeground,
                    ),
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

// ── Direction info box ────────────────────────────────────────────────────────

class _DirectionInfoBox extends StatelessWidget {
  final String sourceName;
  final String targetName;
  final bool isDark;

  const _DirectionInfoBox({
    required this.sourceName,
    required this.targetName,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF082F49).withValues(alpha: 0.4)
            : const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? const Color(0xFF0C4A6E).withValues(alpha: 0.5)
              : const Color(0xFFBAE6FD),
        ),
      ),
      child: Row(
        children: [
          _LangPill(name: sourceName, isDark: isDark),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '→',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFF38BDF8).withValues(alpha: 0.6)
                    : const Color(0xFF7DD3FC),
              ),
            ),
          ),
          _LangPill(name: targetName, isDark: isDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Meaning should be in $sourceName',
              style: TextStyle(
                fontFamily: 'Metropolis',
                fontSize: 11,
                color: isDark
                    ? const Color(0xFFBAE6FD)
                    : const Color(0xFF0369A1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LangPill extends StatelessWidget {
  final String name;
  final bool isDark;
  const _LangPill({required this.name, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0C4A6E).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontFamily: 'Metropolis',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFFE0F2FE) : const Color(0xFF0C4A6E),
        ),
      ),
    );
  }
}

// ── Field label ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  final AppColorScheme c;
  const _FieldLabel(this.text, {required this.c});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Parkinsans',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: c.foreground,
      ),
    );
  }
}

// ── Success view ──────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  final VoidCallback onRequestAnother;
  final VoidCallback onBack;

  const _SuccessView({required this.onRequestAnother, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF14532D).withValues(alpha: 0.3)
                : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF166534).withValues(alpha: 0.6)
                  : const Color(0xFFBBF7D0),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF166534).withValues(alpha: 0.5)
                      : const Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  size: 32,
                  color: isDark
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFF16A34A),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Request Submitted!',
                style: TextStyle(
                  fontFamily: 'Parkinsans',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFF14532D),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Your word is under review. You\'ve earned 🐚 3 cowries for contributing to the community!',
                style: TextStyle(
                  fontFamily: 'Metropolis',
                  fontSize: 14,
                  color: isDark
                      ? const Color(0xFF86EFAC)
                      : const Color(0xFF15803D),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onRequestAnother,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF16A34A),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Request Another Word',
                    style: TextStyle(
                      fontFamily: 'Parkinsans',
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFF166534)
                          : const Color(0xFFBBF7D0),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Back to Lounge',
                    style: TextStyle(
                      fontFamily: 'Parkinsans',
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFF15803D),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
