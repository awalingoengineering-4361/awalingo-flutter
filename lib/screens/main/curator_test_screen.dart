import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class _QuizQuestion {
  final int id;
  final String text;
  final List<String> options;
  final String correctAnswer;
  const _QuizQuestion({required this.id, required this.text, required this.options, required this.correctAnswer});
}

// ── Service ───────────────────────────────────────────────────────────────────

class _CuratorTestService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<_QuizQuestion>> loadQuestions(String userId) async {
    final utl = await _db.from('user_target_languages').select('languageId').eq('userId', userId).maybeSingle();
    final langId = utl?['languageId'] as int? ?? 1;

    final rows = await _db
        .from('quiz_questions')
        .select('id, text, options, correctAnswer')
        .eq('languageId', langId)
        .eq('isActive', true)
        .limit(30);

    if (rows.isEmpty) return [];

    // Shuffle in memory and take up to 10
    final list = List.of(rows)..shuffle();
    return list.take(10).map((r) {
      final rawOptions = r['options'];
      List<String> options;
      if (rawOptions is List) {
        options = rawOptions.map((o) => o.toString()).toList();
      } else {
        options = [];
      }
      return _QuizQuestion(
        id: r['id'] as int,
        text: r['text'] as String,
        options: options,
        correctAnswer: r['correctAnswer'] as String,
      );
    }).toList();
  }

  Future<bool> submitAttempt(String userId, int score, int total) async {
    final passed = total > 0 && (score / total) >= 0.7;
    try {
      await _db.from('quiz_attempts').insert({
        'userId': userId,
        'score': score,
        'totalQuestions': total,
        'passed': passed,
      });
      if (passed) {
        // Attempt to upgrade role via RPC — the backend handles the transaction
        await _db.rpc('upgrade_user_to_curator', params: {'p_user_id': userId});
      }
    } catch (e) {
      debugPrint('CuratorTest submit: $e');
    }
    return passed;
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CuratorTestScreen extends StatefulWidget {
  const CuratorTestScreen({super.key});

  @override
  State<CuratorTestScreen> createState() => _CuratorTestScreenState();
}

class _CuratorTestScreenState extends State<CuratorTestScreen> {
  final _service = _CuratorTestService();
  bool _loading = true;
  bool _submitting = false;
  bool _done = false;
  List<_QuizQuestion> _questions = [];
  int _current = 0;
  final Map<int, String> _answers = {};
  bool? _passed;
  int _score = 0;

  // Timer
  static const _totalSeconds = 600; // 10 minutes
  int _secondsLeft = _totalSeconds;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) { setState(() => _loading = false); return; }
    try {
      final questions = await _service.loadQuestions(userId);
      if (mounted) {
        setState(() { _questions = questions; _loading = false; });
        if (questions.isNotEmpty) _startTimer();
      }
    } catch (e) {
      debugPrint('CuratorTest load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        _submit();
      }
    });
  }

  void _answer(String choice) {
    setState(() => _answers[_current] = choice);
  }

  void _next() {
    if (_current < _questions.length - 1) {
      setState(() => _current++);
    } else {
      _submit();
    }
  }

  void _prev() {
    if (_current > 0) setState(() => _current--);
  }

  Future<void> _submit() async {
    _timer?.cancel();
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null || _submitting) return;
    setState(() => _submitting = true);
    final score = _answers.entries
        .where((e) => e.value == _questions[e.key].correctAnswer)
        .length;
    final passed = await _service.submitAttempt(userId, score, _questions.length);
    if (mounted) setState(() { _score = score; _passed = passed; _done = true; _submitting = false; });
  }

  String get _timerLabel {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get _isTimeLow => _secondsLeft <= 120;

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: c.background,
        body: Center(child: CircularProgressIndicator(color: c.primary, strokeWidth: 2)),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(backgroundColor: c.card, elevation: 0, leading: BackButton(color: c.foreground)),
        body: Center(child: Text('No questions available for your language yet.',
            style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground))),
      );
    }

    if (_done) return _ResultView(passed: _passed!, score: _score, total: _questions.length, c: c);

    final q = _questions[_current];
    final answered = _answers[_current];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => _confirmExit(),
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.card,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Row(children: [
            Expanded(
              child: LinearProgressIndicator(
                value: (_current + 1) / _questions.length,
                color: c.primary,
                backgroundColor: c.border,
                minHeight: 4,
              ),
            ),
            const SizedBox(width: 12),
            Text('${_current + 1}/${_questions.length}',
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
          ]),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isTimeLow ? const Color(0xFFEF4444).withValues(alpha: 0.1) : c.secondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_timerLabel,
                  style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _isTimeLow ? const Color(0xFFEF4444) : c.foreground)),
            ),
          ],
          bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.border)),
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Question ${_current + 1}',
                        style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, fontWeight: FontWeight.w600,
                            color: c.mutedForeground, letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    Text(q.text,
                        style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
                    const SizedBox(height: 24),
                    for (final opt in q.options)
                      _OptionTile(
                        label: opt,
                        selected: answered == opt,
                        onTap: () => _answer(opt),
                        c: c,
                      ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: BoxDecoration(color: c.card, border: Border(top: BorderSide(color: c.border))),
              child: Row(children: [
                if (_current > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _prev,
                      style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          foregroundColor: c.foreground,
                          side: BorderSide(color: c.border),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('Back', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w500)),
                    ),
                  ),
                if (_current > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: answered == null ? null : _next,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: c.primary,
                        foregroundColor: c.primaryForeground,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: _submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_current == _questions.length - 1 ? 'Submit' : 'Next',
                            style: const TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    final c = AppColorScheme.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Exit test?', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, color: c.foreground)),
        content: Text('Your progress will be lost and you will not receive a score.',
            style: TextStyle(fontFamily: 'Metropolis', color: c.mutedForeground)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Stay', style: TextStyle(color: c.foreground))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Exit', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      _timer?.cancel();
      Navigator.of(context).pop();
    }
  }
}

// ── Option Tile ───────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppColorScheme c;
  const _OptionTile({required this.label, required this.selected, required this.onTap, required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? c.primary.withValues(alpha: 0.08) : c.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? c.primary : c.border, width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? c.primary : c.border, width: 2),
              color: selected ? c.primary : Colors.transparent,
            ),
            child: selected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.foreground))),
        ]),
      ),
    );
  }
}

// ── Result View ───────────────────────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  final bool passed;
  final int score;
  final int total;
  final AppColorScheme c;
  const _ResultView({required this.passed, required this.score, required this.total, required this.c});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (score / total * 100).round() : 0;
    final color = passed ? const Color(0xFF22C55E) : const Color(0xFFEF4444);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(passed ? Icons.emoji_events_outlined : Icons.close, size: 40, color: color),
                ),
                const SizedBox(height: 24),
                Text(passed ? '🎉 You passed!' : 'Not quite this time',
                    style: TextStyle(fontFamily: 'Parkinsans', fontSize: 22, fontWeight: FontWeight.w700, color: c.foreground)),
                const SizedBox(height: 8),
                Text('$score / $total correct ($pct%)',
                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, color: c.mutedForeground)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
                  child: Text(
                    passed
                        ? 'Congratulations! You\'ve earned the Curator role. Restart the app to see your new badge and start translating words.'
                        : 'You need 70% to pass. Review the community language and try again in 7 days.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/home'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: c.primary,
                      foregroundColor: c.primaryForeground,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Back to Home', style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
