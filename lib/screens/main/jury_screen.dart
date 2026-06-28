import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'vote_screen.dart';

// ─── Jury Lounge Screen ───────────────────────────────────────────────────────
class JuryScreen extends StatefulWidget {
  const JuryScreen({super.key});

  @override
  State<JuryScreen> createState() => _JuryScreenState();
}

class _JuryScreenState extends State<JuryScreen> {
  String _activeLanguage = 'english';
  bool _loading = false;

  final List<TermWithNeoCount> _terms = const [
    TermWithNeoCount(id: 1, text: 'Internet', meaning: 'A global network connecting computers worldwide', partOfSpeech: 'Noun', neoCount: 8, languageId: 1),
    TermWithNeoCount(id: 2, text: 'Algorithm', meaning: 'A step-by-step procedure for solving a problem', partOfSpeech: 'Noun', neoCount: 12, languageId: 1),
    TermWithNeoCount(id: 3, text: 'Democracy', meaning: 'A system of government by the people', partOfSpeech: 'Noun', neoCount: 6, languageId: 1),
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
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            LoungeHeader(
              title: 'Jury Lounge',
              activeLanguage: _activeLanguage,
              onToggleLanguage: _toggleLanguage,
            ),
            const Divider(height: 1, color: AppColors.border),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 100),
                        itemCount: _terms.length,
                        itemBuilder: (_, i) => TermCard(
                          term: _terms[i],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => JuryDetailScreen(term: _terms[i])),
                          ),
                        ),
                      ),
                    ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh Neos'),
                style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  foregroundColor: AppColors.foreground,
                  side: const BorderSide(color: AppColors.border),
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

// ─── Jury Detail Screen ───────────────────────────────────────────────────────
class JuryDetailScreen extends StatefulWidget {
  final TermWithNeoCount term;
  const JuryDetailScreen({super.key, required this.term});

  @override
  State<JuryDetailScreen> createState() => _JuryDetailScreenState();
}

class _JuryDetailScreenState extends State<JuryDetailScreen> {
  final List<_JuryNeo> _neos = const [
    _JuryNeo(id: 1, text: 'Àárọ̀', type: 'Popular', ratingCount: 24, ratingScore: 96),
    _JuryNeo(id: 2, text: 'Ẹ̀rọ̀-ìmọ̀', type: 'Root', ratingCount: 18, ratingScore: 72),
    _JuryNeo(id: 3, text: 'Onírọ̀', type: 'Creative', ratingCount: 31, ratingScore: 124),
    _JuryNeo(id: 4, text: 'Àyíkà', type: 'Adoptive', ratingCount: 10, ratingScore: 40),
  ];

  final Map<int, int> _ratings = {};
  final List<String> _rejectionReasons = ['Bad Text', 'Bad Audio', 'Spam', 'Out of context', 'Duplicate'];

  final List<_EmojiRating> _emojis = const [
    _EmojiRating(char: '😓', label: 'Poor', value: 1),
    _EmojiRating(char: '😕', label: 'Meh', value: 2),
    _EmojiRating(char: '😐', label: 'Okay', value: 3),
    _EmojiRating(char: '😁', label: 'Good', value: 4),
    _EmojiRating(char: '😍', label: 'Love it', value: 5),
  ];

  void _rate(int neoId, int value) {
    setState(() => _ratings[neoId] = value);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Rated: ${_emojis.firstWhere((e) => e.value == value).label}'),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showRejectModal(int neoId) {
    final Set<String> selected = {};
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reject this Neo?', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              ..._rejectionReasons.map((r) => CheckboxListTile(
                title: Text(r, style: const TextStyle(fontFamily: 'Metropolis', fontSize: 14)),
                value: selected.contains(r),
                activeColor: AppColors.primary,
                onChanged: (v) => setModal(() => v! ? selected.add(r) : selected.remove(r)),
                contentPadding: EdgeInsets.zero,
              )),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                    child: const Text('Cancel'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(
                    onPressed: () { Navigator.pop(ctx); setState(() => _ratings[neoId] = 0); },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, shape: const StadiumBorder()),
                    child: const Text('Reject', style: TextStyle(color: Colors.white)),
                  )),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
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
                    child: const Icon(Icons.arrow_back, color: AppColors.foreground),
                  ),
                  const SizedBox(width: 12),
                  const Text('Jury Review', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600)),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Word card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.gavel, size: 16, color: AppColors.gold),
                              const SizedBox(width: 6),
                              const Text('Under Review', style: TextStyle(fontSize: 12, fontFamily: 'Metropolis', color: AppColors.mutedForeground)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(widget.term.text, style: const TextStyle(fontFamily: 'Parkinsans', fontSize: 22, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(widget.term.meaning, style: const TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: AppColors.mutedForeground)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(100)),
                            child: Text(widget.term.partOfSpeech, style: const TextStyle(fontSize: 11, fontFamily: 'Metropolis', color: AppColors.mutedForeground)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Neo cards for jury rating
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: _neos.map((neo) {
                          final rated = _ratings[neo.id];
                          final isLast = neo.id == _neos.last.id;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              border: Border(bottom: !isLast ? const BorderSide(color: AppColors.border) : BorderSide.none),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Neo header row
                                Row(
                                  children: [
                                    _NeoTypeIcon(type: neo.type),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(neo.text, style: const TextStyle(fontFamily: 'Parkinsans', fontSize: 16, fontWeight: FontWeight.w500)),
                                    ),
                                    // Rating score badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(100),
                                      ),
                                      child: Text('${neo.ratingCount} ratings',
                                        style: const TextStyle(fontSize: 11, fontFamily: 'Metropolis', color: AppColors.primary)),
                                    ),
                                    if (rated != null) ...[
                                      const SizedBox(width: 8),
                                      Text(rated == 0 ? '❌' : _emojis.firstWhere((e) => e.value == rated).char,
                                        style: const TextStyle(fontSize: 18)),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(neo.type, style: const TextStyle(fontSize: 12, fontFamily: 'Metropolis', color: AppColors.mutedForeground)),
                                const SizedBox(height: 12),

                                // Rating row
                                Row(
                                  children: [
                                    // Reject
                                    GestureDetector(
                                      onTap: () => _showRejectModal(neo.id),
                                      child: const Icon(Icons.cancel_outlined, color: Color(0xFFA30202), size: 28),
                                    ),
                                    const SizedBox(width: 12),
                                    // Emoji ratings
                                    ..._emojis.map((e) => GestureDetector(
                                      onTap: () => _rate(neo.id, e.value),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 5),
                                        child: Text(e.char, style: const TextStyle(fontSize: 26)),
                                      ),
                                    )),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Bottom actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Refresh Neos'),
                            style: OutlinedButton.styleFrom(
                              shape: const StadiumBorder(),
                              foregroundColor: AppColors.foreground,
                              side: const BorderSide(color: AppColors.border),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_forward, size: 16),
                            label: const Text('Jury Lounge'),
                            style: OutlinedButton.styleFrom(
                              shape: const StadiumBorder(),
                              foregroundColor: AppColors.foreground,
                              side: const BorderSide(color: AppColors.border),
                            ),
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

class _JuryNeo {
  final int id;
  final String text;
  final String type;
  final int ratingCount;
  final int ratingScore;
  const _JuryNeo({required this.id, required this.text, required this.type, required this.ratingCount, required this.ratingScore});
}

class _EmojiRating {
  final String char;
  final String label;
  final int value;
  const _EmojiRating({required this.char, required this.label, required this.value});
}

class _NeoTypeIcon extends StatelessWidget {
  final String type;
  const _NeoTypeIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (type.toLowerCase()) {
      case 'popular': icon = Icons.star_outline; break;
      case 'adoptive': icon = Icons.recycling; break;
      case 'functional': icon = Icons.build_outlined; break;
      case 'root': icon = Icons.park_outlined; break;
      case 'creative': icon = Icons.psychology_outlined; break;
      default: icon = Icons.circle_outlined;
    }
    return Icon(icon, size: 18, color: AppColors.foreground.withOpacity(0.8));
  }
}
