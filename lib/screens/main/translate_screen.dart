import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'vote_screen.dart';

// ─── Neo Types ────────────────────────────────────────────────────────────────
const _neoTypes = ['Popular', 'Adoptive', 'Functional', 'Root', 'Creative'];

const _neoDescriptions = {
  'Popular': 'Suggest an existing Neo. What does your community currently call the root word?',
  'Adoptive': 'Flow with the sound. Suggest a Neo that adapts to the sound or rhythm of the root word.',
  'Functional': 'Suggest a Neo based on the function and usage of the root word.',
  'Root': 'Digging deep. Suggest a Neo that traces the root word back to its ancient origins.',
  'Creative': 'Put on your genius hat, curate your own Neo suitable as an equivalent for the root word.',
};

// ─── Translation (Curation) Lounge Screen ─────────────────────────────────────
class TranslateScreen extends StatefulWidget {
  const TranslateScreen({super.key});

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  String _activeLanguage = 'english';
  bool _loading = false;

  final List<TermWithNeoCount> _terms = const [
    TermWithNeoCount(id: 1, text: 'Internet', meaning: 'A global network connecting computers worldwide', partOfSpeech: 'Noun', neoCount: 3, languageId: 1),
    TermWithNeoCount(id: 2, text: 'Algorithm', meaning: 'A step-by-step procedure for solving a problem', partOfSpeech: 'Noun', neoCount: 2, languageId: 1),
    TermWithNeoCount(id: 3, text: 'Democracy', meaning: 'A system of government by the people', partOfSpeech: 'Noun', neoCount: 0, languageId: 1),
    TermWithNeoCount(id: 4, text: 'Climate', meaning: 'The weather conditions in an area over a long period', partOfSpeech: 'Noun', neoCount: 1, languageId: 1),
  ];

  void _toggleLanguage() => setState(() {
    _activeLanguage = _activeLanguage == 'english' ? 'community' : 'english';
  });

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.of(context).background,
      body: SafeArea(
        child: Column(
          children: [
            LoungeHeader(
              title: 'Translation Lounge',
              activeLanguage: _activeLanguage,
              onToggleLanguage: _toggleLanguage,
            ),
            Divider(height: 1, color: AppColorScheme.of(context).border),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      color: AppColorScheme.of(context).primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 100),
                        itemCount: _terms.length + 1,
                        itemBuilder: (_, i) {
                          if (i == 0) return _RequestBanner();
                          final term = _terms[i - 1];
                          return TermCard(
                            term: term,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => SuggestScreen(term: term)),
                            ),
                          );
                        },
                      ),
                    ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  foregroundColor: AppColorScheme.of(context).foreground,
                  side: BorderSide(color: AppColorScheme.of(context).border),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Suggest (submit Neo) Screen ──────────────────────────────────────────────
class SuggestScreen extends StatefulWidget {
  final TermWithNeoCount term;
  const SuggestScreen({super.key, required this.term});

  @override
  State<SuggestScreen> createState() => _SuggestScreenState();
}

class _SuggestScreenState extends State<SuggestScreen> {
  final List<_SuggestionEntry> _suggestions = [_SuggestionEntry()];
  bool _submitting = false;
  bool _submitted = false;

  void _addSuggestion() {
    if (_suggestions.length >= 5) return;
    setState(() => _suggestions.add(_SuggestionEntry()));
  }

  void _removeSuggestion(int index) {
    if (index == 0) return;
    setState(() => _suggestions.removeAt(index));
  }

  bool get _canSubmit => _suggestions.every((s) => s.text.isNotEmpty && s.type != null);

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() { _submitting = false; _submitted = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _SuccessScreen(onSubmitAnother: () => setState(() => _submitted = false), onBack: () => Navigator.pop(context));

    final c = AppColorScheme.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.arrow_back, size: 20, color: c.foreground),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Suggest a Neo', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Word of the day card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome, size: 16, color: AppColors.gold),
                              const SizedBox(width: 6),
                              Text('Word to Translate', style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(widget.term.text, style: TextStyle(fontFamily: 'Parkinsans', fontSize: 24, fontWeight: FontWeight.w600, color: c.foreground)),
                          const SizedBox(height: 4),
                          Text(widget.term.meaning, style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(100)),
                            child: Text(widget.term.partOfSpeech, style: TextStyle(fontSize: 11, fontFamily: 'Metropolis', color: c.mutedForeground)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Suggestion form card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ..._suggestions.asMap().entries.map((entry) {
                            final i = entry.key;
                            final s = entry.value;
                            return _SuggestionEntryWidget(
                              entry: s,
                              index: i,
                              canDelete: i != 0,
                              onDelete: () => _removeSuggestion(i),
                              onChanged: () => setState(() {}),
                            );
                          }),

                          // Add more
                          if (_suggestions.length < 5)
                            GestureDetector(
                              onTap: _addSuggestion,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add, size: 18, color: c.mutedForeground),
                                    const SizedBox(width: 6),
                                    Text('Add another suggestion', style: TextStyle(fontSize: 13, fontFamily: 'Metropolis', color: c.mutedForeground)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _canSubmit ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
                          shape: const StadiumBorder(),
                        ),
                        child: _submitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Submit', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
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

// ─── Suggestion entry widget ──────────────────────────────────────────────────
class _SuggestionEntry {
  String? type;
  String text = '';
}

class _SuggestionEntryWidget extends StatefulWidget {
  final _SuggestionEntry entry;
  final int index;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _SuggestionEntryWidget({
    required this.entry,
    required this.index,
    required this.canDelete,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<_SuggestionEntryWidget> createState() => _SuggestionEntryWidgetState();
}

class _SuggestionEntryWidgetState extends State<_SuggestionEntryWidget> {
  final _controller = TextEditingController();

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Suggestion ${widget.index + 1}', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 14, fontWeight: FontWeight.w600, color: c.foreground)),
              const Spacer(),
              if (widget.canDelete)
                GestureDetector(onTap: widget.onDelete, child: Icon(Icons.close, size: 18, color: c.mutedForeground)),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: widget.entry.type,
            hint: Text('Choose a type', style: TextStyle(fontSize: 13, fontFamily: 'Metropolis', color: c.mutedForeground)),
            dropdownColor: c.card,
            decoration: InputDecoration(
              filled: true,
              fillColor: c.secondary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
            ),
            items: _neoTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.foreground)))).toList(),
            onChanged: (v) { setState(() => widget.entry.type = v); widget.onChanged(); },
          ),
          if (widget.entry.type != null) ...[
            const SizedBox(height: 6),
            Text(_neoDescriptions[widget.entry.type!] ?? '', style: TextStyle(fontSize: 12, fontFamily: 'Metropolis', color: c.mutedForeground, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            style: TextStyle(color: c.foreground),
            decoration: InputDecoration(
              hintText: 'Enter your Neo word',
              hintStyle: TextStyle(fontSize: 13, fontFamily: 'Metropolis', color: c.mutedForeground),
              filled: true,
              fillColor: c.secondary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.primary)),
            ),
            onChanged: (v) { widget.entry.text = v; widget.onChanged(); },
          ),
          const SizedBox(height: 12),
          Divider(color: c.border),
        ],
      ),
    );
  }
}

// ─── Success screen after submission ─────────────────────────────────────────
class _SuccessScreen extends StatelessWidget {
  final VoidCallback onSubmitAnother;
  final VoidCallback onBack;

  const _SuccessScreen({required this.onSubmitAnother, required this.onBack});

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
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: c.border)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.check, size: 36, color: AppColors.success),
                  ),
                  const SizedBox(height: 20),
                  Text('Suggestion Submitted!', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 22, fontWeight: FontWeight.w600, color: c.foreground), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text('Thank you for contributing to the Awalingo community. Your suggestion will be reviewed and made available for voting soon.',
                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground), textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onSubmitAnother,
                      style: ElevatedButton.styleFrom(backgroundColor: c.primary, shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Submit Another', style: TextStyle(fontFamily: 'Parkinsans', fontWeight: FontWeight.w600, color: c.primaryForeground)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onBack,
                      style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide(color: c.border), padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Back to Lounge', style: TextStyle(fontFamily: 'Parkinsans', fontWeight: FontWeight.w600, color: c.foreground)),
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

// ─── Request a Word Banner ────────────────────────────────────────────────────
class _RequestBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pushNamed('/request'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColorScheme.of(context).secondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                    child: Text('📖', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Don\'t see a word?',
                      style: TextStyle(
                        fontFamily: 'Parkinsans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.foreground,
                      ),
                    ),
                    Text(
                      'Request it for the community to translate',
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 12,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.foreground,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'Request',
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: c.primaryForeground,
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
