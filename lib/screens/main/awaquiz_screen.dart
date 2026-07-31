import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';

// ── Models ─────────────────────────────────────────────────────────────────────

enum _Difficulty { beginner, intermediate, advanced }

extension _DifficultyX on _Difficulty {
  String get label => '${name[0].toUpperCase()}${name.substring(1)}';
  String get dbValue => name.toUpperCase();
  String get badgeLabel =>
      const ['Easy', 'Medium', 'Hard'][index];
  int get cowryCost => const [20, 30, 50][index];
  int get secondsPerQuestion => const [30, 25, 20][index];
  int get warningThreshold => this == _Difficulty.advanced ? 5 : 10;
  Color get accent => const [
        Color(0xFF10B981),
        Color(0xFF0EA5E9),
        Color(0xFFF43F5E),
      ][index];
  Color get lightBg => const [
        Color(0xFFD1FAE5),
        Color(0xFFE0F2FE),
        Color(0xFFFFE4E6),
      ][index];
  Color get darkBg => const [
        Color(0xFF064E3B),
        Color(0xFF0C4A6E),
        Color(0xFF4C0519),
      ][index];
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
  const _QuizLevel({
    required this.id,
    required this.difficulty,
    required this.questionCount,
    required this.attemptCount,
  });
}

class _QuizQuestion {
  final int id;
  final String text;
  final List<({String label, String value})> options;
  final String correctAnswer;
  const _QuizQuestion({
    required this.id,
    required this.text,
    required this.options,
    required this.correctAnswer,
  });
}

// ── Service ────────────────────────────────────────────────────────────────────

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
          .not('submittedAt', 'is', null);
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

    final levels = setsRows
        .map((r) {
          final diff = _diffFrom(r['difficulty'] as String? ?? '');
          if (diff == null) return null;
          return _QuizLevel(
            id: r['id'] as int,
            difficulty: diff,
            questionCount: (r['questionCount'] as int?) ?? 10,
            attemptCount: attemptCounts[r['id'] as int] ?? 0,
          );
        })
        .whereType<_QuizLevel>()
        .toList()
      ..sort((a, b) => a.difficulty.index.compareTo(b.difficulty.index));

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
      final norm = (row['text'] as String)
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ');
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
    required String userId,
    required int languageId,
    required int setId,
    required _Difficulty difficulty,
    required int currentBalance,
    required int cowryCost,
  }) async {
    // Deduct cowries
    await _db
        .from('user_profile')
        .update({'cowryBalance': currentBalance - cowryCost}).eq('userId', userId);
    // Create attempt
    final result = await _db.from('community_quiz_attempts').insert({
      'userId': userId,
      'languageId': languageId,
      'setId': setId,
      'difficulty': difficulty.dbValue,
      'score': 0,
      'totalQuestions': 0,
      'entryCostCowries': cowryCost,
    }).select('id').single();
    return result['id'] as int;
  }

  Future<void> submitAttempt(int attemptId, int score, int total) async {
    await _db.from('community_quiz_attempts').update({
      'score': score,
      'totalQuestions': total,
      'submittedAt': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', attemptId);
  }

  Future<void> exitAttempt(int attemptId) async {
    await _db.from('community_quiz_attempts').update({
      'submittedAt': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', attemptId);
  }
}

// ── Level Picker Screen ────────────────────────────────────────────────────────

class AwaQuizScreen extends StatefulWidget {
  final int languageId;
  final String communityName;
  const AwaQuizScreen({
    super.key,
    required this.languageId,
    required this.communityName,
  });

  @override
  State<AwaQuizScreen> createState() => _AwaQuizScreenState();
}

class _AwaQuizScreenState extends State<AwaQuizScreen> {
  final _service = _AwaQuizService();
  bool _loading = true;
  String? _error;
  List<_QuizLevel> _levels = [];
  int _cowryBalance = 0;

  @override
  void initState() {
    super.initState();
    // Defer until after first frame so InheritedWidget lookups are safe
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final userId = AuthProvider.of(context).user?.id;
      if (userId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final data = await _service.loadLevels(userId, widget.languageId);
      if (mounted) setState(() { _levels = data.levels; _cowryBalance = data.cowryBalance; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onLevelTap(_QuizLevel level) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StartModal(
        level: level,
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
      // Load questions first
      final questions = await _service.loadQuestions(level.id, level.questionCount);
      if (questions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No questions available for this level yet.')),
          );
        }
        return;
      }

      // Create the attempt (deducts cowries)
      final attemptId = await _service.startAttempt(
        userId: userId,
        languageId: widget.languageId,
        setId: level.id,
        difficulty: level.difficulty,
        currentBalance: _cowryBalance,
        cowryCost: level.difficulty.cowryCost,
      );

      if (!mounted) return;

      // Navigate to quiz screen
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _QuizScreen(
          questions: questions,
          difficulty: level.difficulty,
          communityName: widget.communityName,
          attemptId: attemptId,
          service: _service,
        ),
      ));

      // Refresh balance after quiz
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start quiz: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: c.background,
      // Minimal back-navigation bar — no title, matches Next.js which has no
      // explicit page-level header (the content card IS the header).
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.foreground),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    children: [
                      // ── Header card — matches Next.js rounded-3xl white card ──
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFF3F4F6),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                              blurRadius: 16,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // "COMMUNITY QUIZ" label — uppercase, tracked, primary
                            Text(
                              'COMMUNITY QUIZ',
                              style: TextStyle(
                                fontFamily: 'Metropolis',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.4,
                                color: c.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // "AwaQuiz Yoruba" title
                            Text(
                              'AwaQuiz ${widget.communityName}',
                              style: TextStyle(
                                fontFamily: 'Parkinsans',
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0A0A0A),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Subtitle
                            Text(
                              'Pick a level, answer a fresh set of questions, and see how far your community language skills can go.',
                              style: TextStyle(
                                fontFamily: 'Metropolis',
                                fontSize: 14,
                                height: 1.5,
                                color: isDark
                                    ? const Color(0xFF9CA3AF)
                                    : const Color(0xFF4B5563),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Level cards ───────────────────────────────────────────
                      if (_levels.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            'No quiz levels available for this community yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.mutedForeground, fontSize: 15),
                          ),
                        )
                      else
                        ..._levels.map((level) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _LevelCard(
                                level: level,
                                cowryBalance: _cowryBalance,
                                isDark: isDark,
                                onTap: () => _onLevelTap(level),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }
}

// ── Level Card ─────────────────────────────────────────────────────────────────

class _LevelCard extends StatelessWidget {
  final _QuizLevel level;
  final int cowryBalance;
  final bool isDark;
  final VoidCallback onTap;

  const _LevelCard({
    required this.level,
    required this.cowryBalance,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final diff = level.difficulty;
    final canAfford = cowryBalance >= diff.cowryCost;
    final bg = isDark ? diff.darkBg : diff.lightBg;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: diff.accent.withValues(alpha: 0.4)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_rounded, color: diff.accent, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    diff.label,
                    style: TextStyle(
                      fontFamily: 'Parkinsans',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: diff.accent,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: diff.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    diff.badgeLabel,
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: diff.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _InfoChip(icon: Icons.quiz_outlined, label: '${level.questionCount} questions'),
                _InfoChip(icon: Icons.timer_outlined, label: '${diff.secondsPerQuestion}s / question'),
                _InfoChip(icon: null, label: '🐚 ${diff.cowryCost} cowries'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: diff.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  canAfford ? 'Start Level' : 'Not enough cowries',
                  style: const TextStyle(
                    fontFamily: 'Metropolis',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            if (level.attemptCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${level.attemptCount} attempt${level.attemptCount == 1 ? '' : 's'} taken',
                style: TextStyle(
                  fontFamily: 'Metropolis',
                  fontSize: 12,
                  color: diff.accent.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  const _InfoChip({this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: const Color(0xFF6B7280)),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Metropolis',
            fontSize: 13,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }
}

// ── Start Modal ────────────────────────────────────────────────────────────────

class _StartModal extends StatefulWidget {
  final _QuizLevel level;
  final int cowryBalance;
  final VoidCallback onStart;
  const _StartModal({required this.level, required this.cowryBalance, required this.onStart});

  @override
  State<_StartModal> createState() => _StartModalState();
}

class _StartModalState extends State<_StartModal> {
  bool _agreed = false;
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final diff = widget.level.difficulty;
    final canAfford = widget.cowryBalance >= diff.cowryCost;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${diff.label} Quiz',
            style: const TextStyle(
              fontFamily: 'Parkinsans',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 16),

          // 2×2 info grid
          Row(children: [
            Expanded(child: _GridTile(label: 'Questions', value: '${widget.level.questionCount}')),
            const SizedBox(width: 10),
            Expanded(child: _GridTile(label: 'Entry fee', value: '🐚 ${diff.cowryCost}')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _GridTile(label: 'Your balance', value: '🐚 ${widget.cowryBalance}')),
            const SizedBox(width: 10),
            Expanded(child: _GridTile(label: 'Time / question', value: '${diff.secondsPerQuestion}s')),
          ]),

          if (!canAfford) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCD34D)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 16),
                const SizedBox(width: 8),
                const Expanded(child: Text(
                  'You don\'t have enough cowries for this level.',
                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFF92400E)),
                )),
              ]),
            ),
          ],

          const SizedBox(height: 16),

          // Rules checkbox
          GestureDetector(
            onTap: () => setState(() => _agreed = !_agreed),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20, height: 20,
                decoration: BoxDecoration(
                  color: _agreed ? diff.accent : Colors.transparent,
                  border: Border.all(color: _agreed ? diff.accent : const Color(0xFFD1D5DB), width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _agreed
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'I have read the rules and understand cowries will be deducted immediately.',
                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFF374151)),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                child: const Text('Cancel', style: TextStyle(fontFamily: 'Metropolis', color: Color(0xFF374151))),
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
                  backgroundColor: diff.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                ),
                child: _starting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Start Quiz', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600)),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontFamily: 'Metropolis', fontSize: 11, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF111827))),
      ]),
    );
  }
}

// ── Active Quiz Screen ─────────────────────────────────────────────────────────

class _QuizScreen extends StatefulWidget {
  final List<_QuizQuestion> questions;
  final _Difficulty difficulty;
  final String communityName;
  final int attemptId;
  final _AwaQuizService service;

  const _QuizScreen({
    required this.questions,
    required this.difficulty,
    required this.communityName,
    required this.attemptId,
    required this.service,
  });

  @override
  State<_QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<_QuizScreen> {
  int _currentIndex = 0;
  final List<String?> _answers = [];
  late int _secondsLeft;
  Timer? _timer;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _answers.addAll(List.filled(widget.questions.length, null));
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _timer?.cancel();
    _secondsLeft = widget.difficulty.secondsPerQuestion;
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
      _resetTimer();
    } else {
      _submit();
    }
  }

  void _selectAnswer(String value) {
    _timer?.cancel();
    setState(() => _answers[_currentIndex] = value);
  }

  void _next() {
    if (_currentIndex < widget.questions.length - 1) {
      setState(() => _currentIndex++);
      _resetTimer();
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    _timer?.cancel();
    if (_submitting) return;
    setState(() => _submitting = true);
    final score = _answers
        .asMap()
        .entries
        .where((e) => e.value == widget.questions[e.key].correctAnswer)
        .length;
    try {
      await widget.service.submitAttempt(widget.attemptId, score, widget.questions.length);
    } catch (_) {}
    if (!mounted) return;

    // Build missed list
    final missed = _answers.asMap().entries
        .where((e) => e.value != widget.questions[e.key].correctAnswer)
        .map((e) => (
              question: widget.questions[e.key],
              selectedAnswer: e.value,
            ))
        .toList();

    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => _ResultScreen(
        score: score,
        total: widget.questions.length,
        difficulty: widget.difficulty,
        communityName: widget.communityName,
        missed: missed,
      ),
    ));
  }

  Future<void> _confirmExit() async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End the quiz?', style: TextStyle(fontFamily: 'Parkinsans', fontWeight: FontWeight.w700)),
        content: const Text(
          'Your cowries won\'t be refunded if you exit now.',
          style: TextStyle(fontFamily: 'Metropolis'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End quiz', style: TextStyle(color: Color(0xFFF43F5E))),
          ),
        ],
      ),
    );
    if (exit == true && mounted) {
      _timer?.cancel();
      try { await widget.service.exitAttempt(widget.attemptId); } catch (_) {}
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.difficulty;
    final question = widget.questions[_currentIndex];
    final isLast = _currentIndex == widget.questions.length - 1;
    final inWarning = _secondsLeft <= diff.warningThreshold;
    final selectedAnswer = _answers[_currentIndex];

    if (_submitting) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Submitting quiz...', style: TextStyle(fontFamily: 'Metropolis', fontSize: 15)),
          ]),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: SafeArea(
          child: Column(children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: _confirmExit,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Icon(Icons.close, size: 18, color: Color(0xFF374151)),
                  ),
                ),
                const Spacer(),
                // Timer badge
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: inWarning ? const Color(0xFFFFF1F2) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: inWarning ? const Color(0xFFFDA4AF) : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timer_outlined,
                        size: 15,
                        color: inWarning ? const Color(0xFFF43F5E) : const Color(0xFF6B7280)),
                    const SizedBox(width: 4),
                    Text(
                      '${_secondsLeft}s',
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: inWarning ? const Color(0xFFF43F5E) : const Color(0xFF374151),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Title + progress
                  Text(
                    'AwaQuiz ${widget.communityName} · ${diff.label}',
                    style: const TextStyle(
                      fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 8),

                  // Progress bar
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (_currentIndex + 1) / widget.questions.length,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: AlwaysStoppedAnimation(diff.accent),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${_currentIndex + 1} / ${widget.questions.length}',
                      style: const TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // Question text
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      question.text,
                      style: const TextStyle(
                        fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF111827)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Answer options
                  ...question.options.map((opt) {
                    final isSelected = selectedAnswer == opt.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => _selectAnswer(opt.value),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? diff.accent.withValues(alpha: 0.08)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? diff.accent : const Color(0xFFE5E7EB),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: isSelected ? diff.accent : const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  opt.label,
                                  style: TextStyle(
                                    fontFamily: 'Metropolis',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: isSelected ? Colors.white : const Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                opt.value,
                                style: TextStyle(
                                  fontFamily: 'Metropolis',
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  color: isSelected ? diff.accent : const Color(0xFF374151),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    );
                  }),
                ]),
              ),
            ),

            // Footer buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                OutlinedButton(
                  onPressed: _confirmExit,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  child: const Text('Exit', style: TextStyle(fontFamily: 'Metropolis', color: Color(0xFF374151))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: selectedAnswer != null ? _next : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: diff.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      disabledBackgroundColor: const Color(0xFFE5E7EB),
                    ),
                    child: Text(
                      isLast ? 'Submit Quiz' : 'Next Question',
                      style: const TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Result Screen ──────────────────────────────────────────────────────────────

class _ResultScreen extends StatefulWidget {
  final int score;
  final int total;
  final _Difficulty difficulty;
  final String communityName;
  final List<({_QuizQuestion question, String? selectedAnswer})> missed;

  const _ResultScreen({
    required this.score,
    required this.total,
    required this.difficulty,
    required this.communityName,
    required this.missed,
  });

  @override
  State<_ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<_ResultScreen> {
  bool _showMissed = false;

  int get _percentage => widget.total > 0
      ? ((widget.score / widget.total) * 100).round()
      : 0;
  bool get _isPerfect => widget.score == widget.total;

  @override
  Widget build(BuildContext context) {
    final diff = widget.difficulty;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          child: Column(children: [
            // Trophy
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: diff.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPerfect ? Icons.emoji_events_rounded : Icons.check_circle_outline_rounded,
                color: diff.accent,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),

            Text(
              '${widget.communityName} · ${diff.label}',
              style: const TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Quiz Complete!',
              style: TextStyle(fontFamily: 'Parkinsans', fontWeight: FontWeight.w700, fontSize: 24, color: Color(0xFF111827)),
            ),
            const SizedBox(height: 8),
            Text(
              'You scored ${widget.score} out of ${widget.total} ($_percentage%)',
              style: const TextStyle(fontFamily: 'Metropolis', fontSize: 15, color: Color(0xFF374151)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Score ring
            SizedBox(
              width: 120, height: 120,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: 120, height: 120,
                  child: CircularProgressIndicator(
                    value: widget.total > 0 ? widget.score / widget.total : 0,
                    strokeWidth: 10,
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor: AlwaysStoppedAnimation(diff.accent),
                  ),
                ),
                Text(
                  '$_percentage%',
                  style: TextStyle(
                    fontFamily: 'Parkinsans',
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                    color: diff.accent,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),

            // Perfect score certificate
            if (_isPerfect) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFCD34D), width: 2),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Digital Certificate',
                    style: TextStyle(fontFamily: 'Parkinsans', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF111827)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Perfect score on ${widget.communityName} ${diff.label} AwaQuiz',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Score: ${widget.score} / ${widget.total}',
                    style: const TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF111827)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // Missed questions toggle
            if (widget.missed.isNotEmpty) ...[
              GestureDetector(
                onTap: () => setState(() => _showMissed = !_showMissed),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(children: [
                    Text(
                      'Review missed questions (${widget.missed.length})',
                      style: const TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF374151)),
                    ),
                    const Spacer(),
                    Icon(_showMissed ? Icons.expand_less : Icons.expand_more, color: const Color(0xFF6B7280)),
                  ]),
                ),
              ),
              if (_showMissed) ...[
                const SizedBox(height: 8),
                ...widget.missed.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            '${e.key + 1}. ${e.value.question.text}',
                            style: const TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF111827)),
                          ),
                          const SizedBox(height: 10),
                          if (e.value.selectedAnswer != null)
                            _ReviewRow(
                              label: 'Your answer',
                              value: e.value.selectedAnswer!,
                              color: const Color(0xFFF43F5E),
                              bg: const Color(0xFFFFF1F2),
                            )
                          else
                            const _ReviewRow(
                              label: 'Your answer',
                              value: 'No answer selected',
                              color: Color(0xFF9CA3AF),
                              bg: Color(0xFFF3F4F6),
                            ),
                          const SizedBox(height: 6),
                          _ReviewRow(
                            label: 'Correct answer',
                            value: e.value.question.correctAnswer,
                            color: const Color(0xFF10B981),
                            bg: const Color(0xFFD1FAE5),
                          ),
                        ]),
                      ),
                    )),
              ],
              const SizedBox(height: 16),
            ],

            // CTAs
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                child: const Text('Try another level', style: TextStyle(fontFamily: 'Metropolis', color: Color(0xFF374151))),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Back to Menu', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600)),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontFamily: 'Metropolis', fontSize: 11, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 13, color: color)),
      ]),
    );
  }
}

// ── Error / helper widgets ─────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFF59E0B), size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: Color(0xFF374151))),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}
