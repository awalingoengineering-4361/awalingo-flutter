import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';

// ── Stage visual constants ──────────────────────────────────────────────────────

const _kStageNames = ['JJC', 'Sabi Player', 'Shugaba', 'Odogwu', 'Idan', 'Ancestor'];

const _kStageIcons = [
  Icons.extension_rounded,
  Icons.psychology_rounded,
  Icons.lightbulb_rounded,
  Icons.memory_rounded,
  Icons.auto_awesome_rounded,
  Icons.workspace_premium_rounded,
];

class _StageStyle {
  final Color cardBg;      // light-only tinted bg
  final Color topBorder;
  final Color iconBg;      // light-only icon bg
  final Color iconBorder;
  final Color accent;
  final Color buttonBg;
  const _StageStyle({
    required this.cardBg, required this.topBorder,
    required this.iconBg, required this.iconBorder,
    required this.accent, required this.buttonBg,
  });

  // Dark mode: tint the card surface with a hint of the accent colour.
  Color darkCardBg() => Color.alphaBlend(accent.withValues(alpha: 0.08), const Color(0xFF171717));
  Color darkIconBg() => Color.alphaBlend(accent.withValues(alpha: 0.15), const Color(0xFF1C1C1E));
  Color darkIconBorder() => accent.withValues(alpha: 0.3);
}

const _kStageStyles = [
  // 1 JJC – violet
  _StageStyle(cardBg: Color(0xFFF5F3FF), topBorder: Color(0xFFA78BFA),
      iconBg: Color(0xFFF5F3FF), iconBorder: Color(0xFFC4B5FD),
      accent: Color(0xFF7C3AED), buttonBg: Color(0xFF8B5CF6)),
  // 2 Sabi Player – green
  _StageStyle(cardBg: Color(0xFFF0FDF4), topBorder: Color(0xFF22C55E),
      iconBg: Color(0xFFF0FDF4), iconBorder: Color(0xFF86EFAC),
      accent: Color(0xFF15803D), buttonBg: Color(0xFF16A34A)),
  // 3 Shugaba – amber
  _StageStyle(cardBg: Color(0xFFFFFBEB), topBorder: Color(0xFFF59E0B),
      iconBg: Color(0xFFFFFBEB), iconBorder: Color(0xFFFCD34D),
      accent: Color(0xFFD97706), buttonBg: Color(0xFFF59E0B)),
  // 4 Odogwu – cyan
  _StageStyle(cardBg: Color(0xFFECFEFF), topBorder: Color(0xFF06B6D4),
      iconBg: Color(0xFFECFEFF), iconBorder: Color(0xFF67E8F9),
      accent: Color(0xFF0E7490), buttonBg: Color(0xFF0891B2)),
  // 5 Idan – neutral/dark
  _StageStyle(cardBg: Color(0xFFFAFAFA), topBorder: Color(0xFF111827),
      iconBg: Color(0xFFFFFFFF), iconBorder: Color(0xFF9CA3AF),
      accent: Color(0xFF111827), buttonBg: Color(0xFF111827)),
  // 6 Ancestor – red
  _StageStyle(cardBg: Color(0xFFFFF5F5), topBorder: Color(0xFFEF4444),
      iconBg: Color(0xFFFFF5F5), iconBorder: Color(0xFFFCA5A5),
      accent: Color(0xFFB91C1C), buttonBg: Color(0xFFB91C1C)),
];

// ── Domain models ───────────────────────────────────────────────────────────────

enum _Difficulty { beginner, intermediate, advanced }

extension _DifficultyX on _Difficulty {
  String get dbValue => name.toUpperCase();
  int get cowryCost => const [20, 30, 50][index];
  int get secondsPerQuestion => const [30, 25, 20][index];
  int get warningThreshold => this == _Difficulty.advanced ? 5 : 10;
}

_Difficulty? _diffFrom(String s) => switch (s.toUpperCase()) {
      'BEGINNER' => _Difficulty.beginner,
      'INTERMEDIATE' => _Difficulty.intermediate,
      'ADVANCED' => _Difficulty.advanced,
      _ => null,
    };

class _QuizLevel {
  final int id;
  final _Difficulty difficulty;
  final int questionCount;
  final int attemptCount;
  final int stageIndex; // 0-based → maps to name/icon/style
  final bool isUnlocked;

  const _QuizLevel({
    required this.id,
    required this.difficulty,
    required this.questionCount,
    required this.attemptCount,
    required this.stageIndex,
    required this.isUnlocked,
  });

  int get _si => stageIndex.clamp(0, 5);
  _StageStyle get style => _kStageStyles[_si];
  String get stageName => _kStageNames[_si];
  IconData get icon => _kStageIcons[_si];
  int get stageNumber => stageIndex + 1;
}

class _QuizQuestion {
  final int id;
  final String text;
  final List<({String label, String value})> options;
  final String correctAnswer;
  const _QuizQuestion({
    required this.id, required this.text,
    required this.options, required this.correctAnswer,
  });
}

// ── Service ─────────────────────────────────────────────────────────────────────

class _AwaQuizService {
  final _db = Supabase.instance.client;

  Future<({List<_QuizLevel> levels, int cowryBalance})> loadLevels(
      String userId, int languageId) async {
    final setsRows = await _db
        .from('community_quiz_sets')
        .select('id, difficulty, questionCount')
        .eq('languageId', languageId)
        .eq('isActive', true);

    final setIds = setsRows.map((r) => r['id'] as int).toList();
    final attemptCounts = <int, int>{};
    if (setIds.isNotEmpty) {
      final rows = await _db
          .from('community_quiz_attempts')
          .select('setId')
          .eq('userId', userId)
          .inFilter('setId', setIds)
          .not('submittedAt', 'is', null)
          .gt('totalQuestions', 0); // early exits don't set totalQuestions
      for (final r in rows) {
        final sid = r['setId'] as int;
        attemptCounts[sid] = (attemptCounts[sid] ?? 0) + 1;
      }
    }

    final profile = await _db
        .from('user_profile')
        .select('cowryBalance')
        .eq('userId', userId)
        .maybeSingle();
    final balance = (profile?['cowryBalance'] as int?) ?? 0;

    final raw = setsRows
        .map((r) {
          final diff = _diffFrom(r['difficulty'] as String? ?? '');
          if (diff == null) return null;
          return (id: r['id'] as int, difficulty: diff, questionCount: (r['questionCount'] as int?) ?? 10);
        })
        .whereType<({int id, _Difficulty difficulty, int questionCount})>()
        .toList()
      ..sort((a, b) {
        final dc = a.difficulty.index.compareTo(b.difficulty.index);
        return dc != 0 ? dc : a.id.compareTo(b.id);
      });

    final levels = raw.asMap().entries.map((e) {
      final idx = e.key;
      final r = e.value;
      return _QuizLevel(
        id: r.id,
        difficulty: r.difficulty,
        questionCount: r.questionCount,
        attemptCount: attemptCounts[r.id] ?? 0,
        stageIndex: idx,
        isUnlocked: idx == 0 || (attemptCounts[raw[idx - 1].id] ?? 0) > 0,
      );
    }).toList();

    return (levels: levels, cowryBalance: balance);
  }

  Future<List<_QuizQuestion>> loadQuestions(int setId, int limit) async {
    final rows = await _db
        .from('community_quiz_questions')
        .select('id, text, options, correctAnswer')
        .eq('setId', setId)
        .eq('isActive', true)
        .limit(limit * 3);

    final seen = <String>{};
    final questions = <_QuizQuestion>[];
    for (final row in rows) {
      final norm = (row['text'] as String).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (seen.contains(norm)) continue;
      seen.add(norm);
      final opts = (row['options'] as List<dynamic>).map((o) {
        final m = o as Map<String, dynamic>;
        return (label: m['label'] as String, value: m['value'] as String);
      }).toList();
      questions.add(_QuizQuestion(
        id: row['id'] as int,
        text: row['text'] as String,
        options: opts,
        correctAnswer: row['correctAnswer'] as String,
      ));
      if (questions.length >= limit) break;
    }
    return questions;
  }

  Future<int> startAttempt({
    required String userId, required int languageId, required int setId,
    required _Difficulty difficulty, required int currentBalance, required int cowryCost,
  }) async {
    await _db.from('user_profile')
        .update({'cowryBalance': currentBalance - cowryCost}).eq('userId', userId);
    final result = await _db.from('community_quiz_attempts').insert({
      'userId': userId, 'languageId': languageId, 'setId': setId,
      'difficulty': difficulty.dbValue, 'score': 0, 'totalQuestions': 0,
      'entryCostCowries': cowryCost,
    }).select('id').single();
    return result['id'] as int;
  }

  Future<void> submitAttempt(int attemptId, int score, int total) async {
    await _db.from('community_quiz_attempts').update({
      'score': score, 'totalQuestions': total,
      'submittedAt': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', attemptId);
  }

  Future<void> exitAttempt(int attemptId) async {
    await _db.from('community_quiz_attempts').update({
      'submittedAt': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', attemptId);
  }
}

// ── Level Picker Screen ─────────────────────────────────────────────────────────

class AwaQuizScreen extends StatefulWidget {
  final int? languageId;
  final String? communityName;
  const AwaQuizScreen({super.key, this.languageId, this.communityName});

  @override
  State<AwaQuizScreen> createState() => _AwaQuizScreenState();
}

class _AwaQuizScreenState extends State<AwaQuizScreen> {
  final _service = _AwaQuizService();
  bool _loading = true;
  String? _error;
  List<_QuizLevel> _levels = [];
  int _cowryBalance = 0;
  int _languageId = 1;
  String _communityName = 'Community';

  @override
  void initState() {
    super.initState();
    if (widget.languageId != null) {
      _languageId = widget.languageId!;
      _communityName = widget.communityName ?? 'Community';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final userId = AuthProvider.of(context).user?.id;
      if (userId == null) { if (mounted) setState(() => _loading = false); return; }

      if (widget.languageId == null) {
        final row = await Supabase.instance.client
            .from('user_target_languages')
            .select('language:languages!languageId(id, name)')
            .eq('userId', userId)
            .maybeSingle();
        final lang = row?['language'] as Map<String, dynamic>?;
        _languageId = (lang?['id'] as int?) ?? 1;
        _communityName = (lang?['name'] as String?) ?? 'Community';
      }

      final data = await _service.loadLevels(userId, _languageId);
      if (mounted) setState(() { _levels = data.levels; _cowryBalance = data.cowryBalance; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onLevelTap(_QuizLevel level) {
    if (!level.isUnlocked) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StartModal(
        level: level,
        communityName: _communityName,
        cowryBalance: _cowryBalance,
        onStart: () => _startQuiz(level),
      ),
    );
  }

  Future<void> _startQuiz(_QuizLevel level) async {
    if (_cowryBalance < level.difficulty.cowryCost) return;
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    try {
      final questions = await _service.loadQuestions(level.id, level.questionCount);
      if (questions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No questions available for this level yet.')));
        }
        return;
      }
      final attemptId = await _service.startAttempt(
        userId: userId, languageId: _languageId, setId: level.id,
        difficulty: level.difficulty, currentBalance: _cowryBalance,
        cowryCost: level.difficulty.cowryCost,
      );
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => _QuizScreen(
          questions: questions, level: level,
          communityName: _communityName,
          attemptId: attemptId, service: _service,
        ),
      ));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start quiz: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    // No Scaffold — rendered inside AppShell so top/bottom nav stay visible.
    return ColoredBox(
      color: c.background,
      child: _loading
          ? Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: c.border),
                ),
                child: Text('Loading quiz...', style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground)),
              ),
            )
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    children: [
                      // Header card
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: c.border),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 2))],
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'COMMUNITY QUIZ',
                              style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: c.primary),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'AwaQuiz $_communityName',
                              style: TextStyle(fontFamily: 'Parkinsans', fontSize: 28, fontWeight: FontWeight.w600, color: c.foreground),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Pick a level, answer a fresh set of questions, and see how far your community language skills can go.',
                              style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, height: 1.5, color: c.mutedForeground),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_levels.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: c.secondary,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: c.border),
                          ),
                          child: Text(
                            'No quiz levels available for this community yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground),
                          ),
                        )
                      else
                        ..._levels.map((level) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _LevelCard(level: level, cowryBalance: _cowryBalance, onTap: () => _onLevelTap(level)),
                            )),
                    ],
                  ),
                ),
    );
  }
}

// ── Level Card ──────────────────────────────────────────────────────────────────

class _LevelCard extends StatelessWidget {
  final _QuizLevel level;
  final int cowryBalance;
  final VoidCallback onTap;
  const _LevelCard({required this.level, required this.cowryBalance, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final st = level.style;
    final locked = !level.isUnlocked;
    final attempts = level.attemptCount;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColorScheme.of(context);

    final cardBg = isDark ? st.darkCardBg() : st.cardBg;
    final iconBg = isDark ? st.darkIconBg() : st.iconBg;
    final iconBorder = isDark ? st.darkIconBorder() : st.iconBorder;

    return Opacity(
      opacity: locked ? 0.7 : 1.0,
      child: GestureDetector(
        onTap: locked ? null : onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.07), blurRadius: 15, spreadRadius: -3, offset: const Offset(0, 2)),
              BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 20, spreadRadius: -2, offset: const Offset(0, 10)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: DecoratedBox(
              decoration: BoxDecoration(color: cardBg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 2, color: st.topBorder),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: iconBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: iconBorder),
                          ),
                          child: Icon(level.icon, size: 20, color: st.accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      level.stageName,
                                      style: TextStyle(fontFamily: 'Parkinsans', fontSize: 16, fontWeight: FontWeight.w600, color: st.accent),
                                    ),
                                  ),
                                  if (locked)
                                    Icon(Icons.lock_rounded, size: 16, color: c.mutedForeground),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${level.questionCount} questions · ${level.difficulty.cowryCost} cowries · ${level.difficulty.secondsPerQuestion}s / question',
                                style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '$attempts ${attempts == 1 ? 'attempt' : 'attempts'}',
                                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, fontWeight: FontWeight.w500, color: st.accent),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: locked ? null : onTap,
                                    icon: const Icon(Icons.rocket_launch_rounded, size: 14),
                                    label: const Text('Play'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: st.buttonBg,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: c.secondary,
                                      disabledForegroundColor: c.mutedForeground,
                                      textStyle: const TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 13),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                      shape: const StadiumBorder(),
                                      elevation: 0,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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

// ── Start Modal ─────────────────────────────────────────────────────────────────

class _StartModal extends StatefulWidget {
  final _QuizLevel level;
  final String communityName;
  final int cowryBalance;
  final VoidCallback onStart;
  const _StartModal({required this.level, required this.communityName, required this.cowryBalance, required this.onStart});

  @override
  State<_StartModal> createState() => _StartModalState();
}

class _StartModalState extends State<_StartModal> {
  bool _agreed = false;
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    final st = level.style;
    final diff = level.difficulty;
    final canAfford = widget.cowryBalance >= diff.cowryCost;
    final c = AppColorScheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stage ${level.stageNumber}',
                        style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, fontWeight: FontWeight.w500, color: st.accent)),
                    const SizedBox(height: 4),
                    Text('Ready for ${level.stageName}?',
                        style: TextStyle(fontFamily: 'Parkinsans', fontSize: 22, fontWeight: FontWeight.w700, color: c.foreground)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? st.darkIconBg() : st.iconBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark ? st.darkIconBorder() : st.iconBorder,
                  ),
                ),
                child: Icon(level.icon, size: 24, color: st.accent),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _GridTile(label: 'Questions', value: '${level.questionCount}')),
            const SizedBox(width: 10),
            Expanded(child: _GridTile(label: 'Entry fee', value: '🐚 ${diff.cowryCost}')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _GridTile(label: 'Your balance', value: '🐚 ${widget.cowryBalance}')),
            const SizedBox(width: 10),
            Expanded(child: _GridTile(label: 'Duration', value: '${diff.secondsPerQuestion}s / question')),
          ]),
          const SizedBox(height: 16),
          if (!canAfford) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFCD34D)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 16),
                SizedBox(width: 8),
                Expanded(child: Text('You don\'t have enough cowries for this level.',
                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFF92400E)))),
              ]),
            ),
          ],
          Text(
            'Cowries are deducted as soon as you start. If you exit after the quiz begins, the session ends and the fee is still used.',
            style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, height: 1.5, color: c.mutedForeground),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _agreed = !_agreed),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.secondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: _agreed ? st.accent : Colors.transparent,
                    border: Border.all(color: _agreed ? st.accent : c.border, width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: _agreed ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('I have read the rules and I am ready to start.',
                      style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.foreground)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: c.border),
                ),
                child: Text('Cancel', style: TextStyle(fontFamily: 'Metropolis', color: c.foreground)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: (!_agreed || !canAfford || _starting) ? null : () async {
                  setState(() => _starting = true);
                  Navigator.of(context).pop();
                  widget.onStart();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: st.buttonBg,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  disabledBackgroundColor: c.secondary,
                  disabledForegroundColor: c.mutedForeground,
                ),
                child: _starting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Start quiz', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  final String label;
  final String value;
  const _GridTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, color: c.mutedForeground)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w700, fontSize: 15, color: c.foreground)),
      ]),
    );
  }
}

// ── Active Quiz Screen ──────────────────────────────────────────────────────────

String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

class _QuizScreen extends StatefulWidget {
  final List<_QuizQuestion> questions;
  final _QuizLevel level;
  final String communityName;
  final int attemptId;
  final _AwaQuizService service;
  const _QuizScreen({required this.questions, required this.level, required this.communityName, required this.attemptId, required this.service});

  @override
  State<_QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<_QuizScreen> {
  int _currentIndex = 0;
  late final List<String?> _answers;
  late int _secondsLeft;
  Timer? _timer;
  bool _submitting = false;
  bool _showExitDialog = false;

  @override
  void initState() {
    super.initState();
    _answers = List.filled(widget.questions.length, null);
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = widget.level.difficulty.secondsPerQuestion;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) _onTimeout();
    });
  }

  void _onTimeout() {
    _timer?.cancel();
    if (_currentIndex < widget.questions.length - 1) {
      setState(() => _currentIndex++);
      _startTimer();
    } else {
      _submit();
    }
  }

  void _next() {
    if (_currentIndex < widget.questions.length - 1) {
      setState(() => _currentIndex++);
      _startTimer();
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    _timer?.cancel();
    if (_submitting) return;
    setState(() => _submitting = true);
    final score = _answers.asMap().entries
        .where((e) => e.value == widget.questions[e.key].correctAnswer).length;
    try { await widget.service.submitAttempt(widget.attemptId, score, widget.questions.length); } catch (_) {}
    if (!mounted) return;
    final missed = _answers.asMap().entries
        .where((e) => e.value != widget.questions[e.key].correctAnswer)
        .map((e) => (question: widget.questions[e.key], selectedAnswer: e.value))
        .toList();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => _ResultScreen(
        score: score, total: widget.questions.length,
        level: widget.level, communityName: widget.communityName, missed: missed,
      ),
    ));
  }

  void _openExitDialog() {
    _timer?.cancel();
    setState(() => _showExitDialog = true);
  }

  void _closeExitDialog() {
    setState(() => _showExitDialog = false);
    _startTimer();
  }

  Future<void> _doExit() async {
    try { await widget.service.exitAttempt(widget.attemptId); } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final diff = widget.level.difficulty;
    final st = widget.level.style;
    final question = widget.questions[_currentIndex];
    final isLast = _currentIndex == widget.questions.length - 1;
    final inWarning = _secondsLeft <= diff.warningThreshold;
    final selectedAnswer = _answers[_currentIndex];

    if (_submitting) {
      return Scaffold(
        backgroundColor: c.background,
        body: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: c.border)),
            child: Text('Submitting quiz...', style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground)),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _openExitDialog(); },
      child: Scaffold(
        backgroundColor: c.background,
        body: Stack(children: [
          SafeArea(
            child: Column(children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(children: [
                  GestureDetector(
                    onTap: _openExitDialog,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: c.card, shape: BoxShape.circle,
                        border: Border.all(color: c.border),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
                      ),
                      child: Icon(Icons.close, size: 18, color: c.foreground),
                    ),
                  ),
                ]),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: c.border),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Header: logo + timer + counter
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Image.asset('assets/branding/logo-wordmark-light.png', height: 28,
                                errorBuilder: (_, e, st) => Text('AwaQuiz',
                                    style: TextStyle(fontFamily: 'Parkinsans', fontSize: 20, fontWeight: FontWeight.w700, color: c.foreground))),
                            const SizedBox(height: 4),
                            Text('${widget.communityName} · ${widget.level.stageName}',
                                style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w500, color: c.mutedForeground)),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: inWarning ? const Color(0xFFFFF1F2) : c.secondary,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(color: inWarning ? const Color(0xFFFDA4AF) : c.border),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.access_time_rounded, size: 15,
                                  color: inWarning ? const Color(0xFFE11D48) : c.mutedForeground),
                              const SizedBox(width: 5),
                              Text(_fmt(_secondsLeft.clamp(0, 9999)),
                                  style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w700, fontSize: 16,
                                      color: inWarning ? const Color(0xFFE11D48) : c.foreground)),
                            ]),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(16)),
                            child: Text('${_currentIndex + 1} / ${widget.questions.length}',
                                style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground)),
                          ),
                        ]),
                      ]),
                      const SizedBox(height: 28),

                      // Question box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(24)),
                        child: Text(question.text,
                            style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w500, fontSize: 16, height: 1.5, color: c.foreground)),
                      ),
                      const SizedBox(height: 16),

                      // Answer options
                      ...question.options.map((opt) {
                        final isSelected = selectedAnswer == opt.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GestureDetector(
                            onTap: () => setState(() => _answers[_currentIndex] = opt.value),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(
                                color: isSelected ? st.accent.withValues(alpha: 0.06) : c.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isSelected ? st.accent : c.border, width: isSelected ? 2 : 1),
                              ),
                              child: Row(children: [
                                Text('${opt.label}.',
                                    style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w700, fontSize: 14,
                                        color: isSelected ? st.accent : c.foreground)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(opt.value,
                                      style: TextStyle(fontFamily: 'Metropolis', fontSize: 14,
                                          color: isSelected ? st.accent : c.foreground)),
                                ),
                              ]),
                            ),
                          ),
                        );
                      }),
                    ]),
                  ),
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Row(children: [
                  OutlinedButton(
                    onPressed: _openExitDialog,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: c.border),
                    ),
                    child: Text('Exit', style: TextStyle(fontFamily: 'Metropolis', color: c.foreground)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: selectedAnswer != null ? _next : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: st.buttonBg,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                        disabledBackgroundColor: c.secondary,
                        disabledForegroundColor: c.mutedForeground,
                      ),
                      child: Text(isLast ? 'Submit quiz' : 'Next question',
                          style: const TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),

          // Exit confirmation overlay
          if (_showExitDialog)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 380),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('End the quiz?',
                            style: TextStyle(fontFamily: 'Parkinsans', fontSize: 20, fontWeight: FontWeight.w700, color: c.foreground)),
                        const SizedBox(height: 8),
                        Text('Leaving now will end this quiz session. Your progress will be lost.',
                            style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, height: 1.5, color: c.mutedForeground)),
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _closeExitDialog,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: c.border),
                              ),
                              child: Text('Keep going', style: TextStyle(fontFamily: 'Metropolis', color: c.foreground)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _doExit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE11D48),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Text('End quiz', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ── Result Screen ───────────────────────────────────────────────────────────────

class _ResultScreen extends StatefulWidget {
  final int score;
  final int total;
  final _QuizLevel level;
  final String communityName;
  final List<({_QuizQuestion question, String? selectedAnswer})> missed;
  const _ResultScreen({required this.score, required this.total, required this.level, required this.communityName, required this.missed});

  @override
  State<_ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<_ResultScreen> {
  bool _showMissed = false;

  int get _pct => widget.total > 0 ? ((widget.score / widget.total) * 100).round() : 0;
  bool get _isPerfect => widget.score == widget.total && widget.total > 0;

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final st = widget.level.style;
    final meta = AuthProvider.of(context).user;
    final userName = (meta?.userMetadata?['name'] as String?)?.trim()
        ?? (meta?.userMetadata?['full_name'] as String?)?.trim()
        ?? meta?.email?.split('@').first
        ?? 'You';

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
          child: Column(children: [
            // Score card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: c.border),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(color: st.accent.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(Icons.emoji_events_rounded, color: st.accent, size: 32),
                ),
                const SizedBox(height: 16),
                Text('${widget.communityName} · ${widget.level.stageName}',
                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w500, color: st.accent)),
                const SizedBox(height: 6),
                Text('Quiz complete', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 26, fontWeight: FontWeight.w700, color: c.foreground)),
                const SizedBox(height: 8),
                Text('You scored ${widget.score} out of ${widget.total} ($_pct%).',
                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, color: c.mutedForeground), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                SizedBox(
                  width: 120, height: 120,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 120, height: 120,
                      child: CircularProgressIndicator(
                        value: widget.total > 0 ? widget.score / widget.total : 0,
                        strokeWidth: 10,
                        backgroundColor: c.border,
                        valueColor: AlwaysStoppedAnimation(st.accent),
                      ),
                    ),
                    Text('$_pct%',
                        style: TextStyle(fontFamily: 'Parkinsans', fontWeight: FontWeight.w800, fontSize: 26, color: st.accent)),
                  ]),
                ),
                const SizedBox(height: 8),
              ]),
            ),

            // Certificate (perfect score only) — intentionally stays light/parchment-themed
            if (_isPerfect) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFFFFF9E6), Colors.white, Color(0xFFF4FBF7)]),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFFCD34D), width: 1.5),
                ),
                padding: const EdgeInsets.all(4),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(25), border: Border.all(color: const Color(0xFFFBBF24), width: 2)),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    child: Column(children: [
                      Image.asset('assets/branding/logo-wordmark-light.png', height: 24,
                          errorBuilder: (_, e, s) => const Text('Awalingo', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w700))),
                      const SizedBox(height: 16),
                      const Text('Digital Certificate',
                          style: TextStyle(fontFamily: 'Parkinsans', fontSize: 28, fontWeight: FontWeight.w600, color: Color(0xFF111827)), textAlign: TextAlign.center),
                      const SizedBox(height: 6),
                      const Text('Presented in recognition of a perfect AwaQuiz score',
                          style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFF6B7280)), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      const Text('THIS CERTIFIES THAT',
                          style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, letterSpacing: 2, color: Color(0xFF9CA3AF))),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.only(bottom: 8),
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFFCD34D), width: 2))),
                        child: Text(userName,
                            style: const TextStyle(fontFamily: 'Parkinsans', fontSize: 26, fontWeight: FontWeight.w600, color: Color(0xFF111827)), textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: 12),
                      const Text('achieved a perfect score of', style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFF6B7280))),
                      const SizedBox(height: 4),
                      Text('${widget.score} / ${widget.total}',
                          style: const TextStyle(fontFamily: 'Parkinsans', fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
                      const SizedBox(height: 4),
                      Text('${widget.communityName} · ${widget.level.stageName}',
                          style: const TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                      const SizedBox(height: 16),
                      Container(height: 1, color: const Color(0xFFFCD34D)),
                      const SizedBox(height: 12),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                            style: const TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: Color(0xFF9CA3AF))),
                        const Text('Awalingo Certification',
                            style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: Color(0xFF9CA3AF))),
                      ]),
                    ]),
                  ),
                ),
              ),
            ],

            // Missed questions
            if (widget.missed.isNotEmpty) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => setState(() => _showMissed = !_showMissed),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
                  child: Row(children: [
                    Expanded(
                      child: Text(_showMissed ? 'Hide My Mistakes' : 'Show My Mistakes',
                          style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 14, color: c.foreground)),
                    ),
                    Icon(_showMissed ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: c.mutedForeground),
                  ]),
                ),
              ),
              if (_showMissed) ...[
                const SizedBox(height: 8),
                ...widget.missed.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.question.text, style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 14, color: c.foreground)),
                          const SizedBox(height: 10),
                          e.selectedAnswer != null
                              ? _ReviewRow(label: 'Your answer:', value: e.selectedAnswer!, color: const Color(0xFFB91C1C), bg: const Color(0xFFFFF5F5))
                              : const _ReviewRow(label: 'Your answer:', value: 'No answer selected', color: Color(0xFF6B7280), bg: Color(0xFFF3F4F6)),
                          const SizedBox(height: 6),
                          _ReviewRow(label: 'Correct answer:', value: e.question.correctAnswer, color: const Color(0xFF059669), bg: const Color(0xFFF0FDF4)),
                        ]),
                      ),
                    )),
              ],
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: st.buttonBg, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Try another level', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/home'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: c.border),
                ),
                child: Text('Back to menu', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 15, color: c.foreground)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color bg;
  const _ReviewRow({required this.label, required this.value, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, color: color.withValues(alpha: 0.7))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 13, color: color)),
      ]),
    );
  }
}

// ── Error widget ─────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.card, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFCD34D)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 32),
            const SizedBox(height: 12),
            const Text('AwaQuiz unavailable',
                style: TextStyle(fontFamily: 'Parkinsans', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF92400E))),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFF92400E))),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      ),
    );
  }
}
