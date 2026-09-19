import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/theme_notifier.dart';

// Mirrors CURATOR_TEST_COOLDOWN_DAYS default (quiz.ts) — used only for the
// result screen's copy, since the eligibility check itself already lives in
// become_curator_screen.dart.
const _kCuratorTestCooldownDays = 7;

// ── Models ────────────────────────────────────────────────────────────────────

// Mirrors quiz.ts's QuizOption: options are stored as JSON
// [{"label": "A", "value": "..."}], and correctAnswer matches a "value".
class _QuizOption {
  final String label;
  final String value;
  const _QuizOption({required this.label, required this.value});
}

class _QuizQuestion {
  final int id;
  final String text;
  final List<_QuizOption> options;
  final String correctAnswer;
  const _QuizQuestion({
    required this.id,
    required this.text,
    required this.options,
    required this.correctAnswer,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class _CuratorTestService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<_QuizQuestion>> loadQuestions(String userId) async {
    final utl = await _db
        .from('user_target_languages')
        .select('languageId')
        .eq('userId', userId)
        .maybeSingle();
    final langId = utl?['languageId'] as int? ?? 1;

    final rows = await _db
        .from('quiz_questions')
        .select('id, text, options, correctAnswer')
        .eq('languageId', langId)
        .eq('isActive', true)
        .limit(30);

    if (rows.isEmpty) return [];

    // Shuffle in memory and take up to 10 — mirrors getCuratorTestQuestions
    // (quiz.ts), which fetches randomized rows and slices to QUIZ_QUESTION_COUNT.
    final list = List.of(rows)..shuffle();
    return list.take(10).map((r) {
      final rawOptions = r['options'];
      List<_QuizOption> options;
      if (rawOptions is List) {
        options = rawOptions
            .whereType<Map>()
            .map(
              (o) => _QuizOption(
                label: o['label']?.toString() ?? '',
                value: o['value']?.toString() ?? '',
              ),
            )
            .where((o) => o.value.isNotEmpty)
            .toList();
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

  // Mirrors submitQuizAttempt's transaction (quiz.ts): record the attempt,
  // then on pass swap EXPLORER→CURATOR, and either way log the cowry change
  // via cowry_ledger (the source of truth everywhere else in the app — see
  // _AwaQuizService.unlockReview) rather than a direct balance write.
  //
  // Each step is independently try/caught: these are separate REST calls
  // with no client-side transaction, so one failing (e.g. a still-missing
  // grant) must not silently block the others — in particular the role
  // promotion, which is the whole point of passing the test.
  Future<bool> submitAttempt(String userId, int score, int total) async {
    final passed = total > 0 && (score / total) >= 0.7;

    try {
      await _db.from('quiz_attempts').insert({
        'userId': userId,
        'score': score,
        'passed': passed,
      });
    } catch (e) {
      debugPrint('CuratorTest submit (quiz_attempts insert): $e');
    }

    if (passed) {
      try {
        // Role escalation can't be a plain client-side table write (any
        // authenticated user could otherwise set their own roleId to
        // anything) — promote_user_to_curator is a SECURITY DEFINER RPC
        // that only ever promotes auth.uid() itself to CURATOR.
        await _db.rpc('promote_user_to_curator');
      } catch (e) {
        debugPrint('CuratorTest submit (role promotion): $e');
      }
    }

    try {
      await _db.from('cowry_ledger').insert({
        'userId': userId,
        'eventType': passed ? 'PASS_CURATOR_TEST' : 'FAIL_CURATOR_TEST',
        'description': passed
            ? 'User passed curator test and was promoted to CURATOR role'
            : 'User failed curator test',
        'cowry_changed': passed ? 10 : -3,
      });
      final ledgerRows = await _db
          .from('cowry_ledger')
          .select('cowry_changed')
          .eq('userId', userId);
      final newBalance = (ledgerRows as List).fold<int>(
        0,
        (sum, r) => sum + (r['cowry_changed'] as int),
      );
      await _db
          .from('user_profile')
          .update({'cowryBalance': newBalance})
          .eq('userId', userId);
    } catch (e) {
      debugPrint('CuratorTest submit (cowry ledger): $e');
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
  bool _timedOut = false;
  String? _fetchError;

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
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final questions = await _service.loadQuestions(userId);
      if (mounted) {
        setState(() {
          _questions = questions;
          _loading = false;
          if (questions.isEmpty) {
            // Mirrors curator-test/page.tsx's empty-questions fetchError copy.
            _fetchError =
                'No questions are currently available for your target language. Please try again later.';
          }
        });
        if (questions.isNotEmpty) _startTimer();
      }
    } catch (e) {
      debugPrint('CuratorTest load: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          // Mirrors curator-test/page.tsx's thrown-error fetchError copy.
          _fetchError =
              'Failed to load questions. Please check your target language settings.';
        });
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        _submit(timedOut: true);
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

  // Mirrors handleBack (curator-test/page.tsx): step to the previous
  // question if there is one, otherwise ask for exit confirmation. Used by
  // both the header back arrow and the hardware/gesture back action, so
  // there's a single back behavior during the test — matching the web,
  // which only has the one header control.
  void _handleBack() {
    if (_current > 0) {
      _prev();
    } else {
      _confirmExit();
    }
  }

  Future<void> _submit({bool timedOut = false}) async {
    _timer?.cancel();
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null || _submitting) return;
    setState(() => _submitting = true);
    final score = _answers.entries
        .where((e) => e.value == _questions[e.key].correctAnswer)
        .length;
    final passed = await _service.submitAttempt(
      userId,
      score,
      _questions.length,
    );
    if (mounted) {
      setState(() {
        _score = score;
        _passed = passed;
        _timedOut = timedOut;
        _done = true;
        _submitting = false;
      });
    }
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
        body: Center(
          child: CircularProgressIndicator(color: c.primary, strokeWidth: 2),
        ),
      );
    }

    // Mirrors curator-test/page.tsx's `fetchError || questions.length === 0`
    // branch: an "Unable to Load Test" card with a "Return to Home" button.
    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Color(0xFFF43F5E)),
                    const SizedBox(height: 16),
                    Text(
                      'Unable to Load Test',
                      style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fetchError ?? 'An unexpected error occurred.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/home'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.primary,
                        foregroundColor: c.primaryForeground,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Return to Home', style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_done) {
      return _ResultView(
        passed: _passed!,
        timedOut: _timedOut,
        score: _score,
        total: _questions.length,
        c: c,
      );
    }

    final q = _questions[_current];
    final answered = _answers[_current];
    final theme = ThemeProvider.of(context);
    final isDark = theme.isDark;
    final isLastQuestion = _current == _questions.length - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => _handleBack(),
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Column(
            children: [
              // Header — mirrors curator-test/page.tsx's <header>: back +
              // theme toggle on the left, a standalone timer badge on the
              // right. No progress bar here — that lives inside the card.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: c.foreground),
                        onPressed: _submitting ? null : _handleBack,
                      ),
                      GestureDetector(
                        onTap: theme.toggle,
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(8)),
                          child: Icon(
                            isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_outlined,
                            size: 18,
                            color: isDark ? const Color(0xFFF59E0B) : c.mutedForeground,
                          ),
                        ),
                      ),
                    ]),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isTimeLow ? const Color(0xFFEF4444).withValues(alpha: 0.1) : c.card,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _isTimeLow ? const Color(0xFFFECACA) : c.border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.schedule, size: 18, color: _isTimeLow ? const Color(0xFFEF4444) : c.mutedForeground),
                        const SizedBox(width: 8),
                        Text(
                          _timerLabel,
                          style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _isTimeLow ? const Color(0xFFEF4444) : c.foreground,
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Card header — logo + title + subtitle, matching
                        // curator-test/page.tsx's "Card Header" block.
                        Container(
                          padding: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
                          child: Column(children: [
                            Image.asset(
                              isDark ? 'assets/branding/logo-wordmark-dark.png' : 'assets/branding/logo-wordmark-light.png',
                              height: 40,
                              errorBuilder: (_, __, ___) => Text('AWALINGO',
                                  style: TextStyle(fontFamily: 'Parkinsans', fontWeight: FontWeight.bold, color: c.foreground)),
                            ),
                            const SizedBox(height: 12),
                            Text('Curator Quiz',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
                            const SizedBox(height: 6),
                            Text('Provide correct answers to become an Awalingo Curator.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
                          ]),
                        ),
                        const SizedBox(height: 20),

                        // Progress — "Question X of Y" + a segmented bar per
                        // question, matching the web exactly (not a single
                        // continuous progress bar).
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Question ${_current + 1} of ${_questions.length}',
                                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, fontWeight: FontWeight.w600, color: c.mutedForeground)),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: Row(
                                  children: [
                                    for (var i = 0; i < _questions.length; i++) ...[
                                      if (i > 0) const SizedBox(width: 4),
                                      Expanded(
                                        child: Container(
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: i <= _current ? c.foreground : c.border,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        Text(
                          q.text,
                          style: TextStyle(fontFamily: 'Parkinsans', fontSize: 19, fontWeight: FontWeight.w600, height: 1.4, color: c.foreground),
                        ),
                        const SizedBox(height: 20),

                        for (final opt in q.options)
                          _OptionTile(
                            badge: opt.label,
                            label: opt.value,
                            selected: answered == opt.value,
                            onTap: () => _answer(opt.value),
                            c: c,
                          ),
                        const SizedBox(height: 8),

                        ElevatedButton(
                          onPressed: answered == null || _submitting ? null : _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.foreground,
                            foregroundColor: c.background,
                            disabledBackgroundColor: c.secondary,
                            disabledForegroundColor: c.mutedForeground,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          // "Sumitting..." mirrors the web's copy verbatim (a typo in the source).
                          child: _submitting
                              ? Text('Sumitting...', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 16, color: c.background))
                              : Text(isLastQuestion ? 'Submit Test' : 'Next Question',
                                  style: const TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600, fontSize: 16)),
                        ),
                      ],
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

  Future<void> _confirmExit() async {
    final c = AppColorScheme.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'End the test?',
          style: TextStyle(
            fontFamily: 'Parkinsans',
            fontSize: 17,
            color: c.foreground,
          ),
        ),
        content: Text(
          'Going back will end your current test session. Your progress will be lost.',
          style: TextStyle(fontFamily: 'Metropolis', color: c.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep going', style: TextStyle(color: c.foreground)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'End test',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
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
  final String badge;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppColorScheme c;
  const _OptionTile({
    required this.badge,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.c,
  });

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
          border: Border.all(
            color: selected ? c.primary : c.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.foreground : c.secondary,
              ),
              child: Center(
                child: Text(
                  badge,
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? c.background : c.mutedForeground,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Metropolis',
                  fontSize: 14,
                  color: c.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Result View ───────────────────────────────────────────────────────────────

// Mirrors curator-test/result/page.tsx exactly: a hero illustration (real
// asset, not an icon-in-circle), copy that differs across passed/timedOut/
// failed, "Score: X/Y" (not a percentage), and a single "Go Home" pill button.
class _ResultView extends StatelessWidget {
  final bool passed;
  final bool timedOut;
  final int score;
  final int total;
  final AppColorScheme c;
  const _ResultView({
    required this.passed,
    required this.timedOut,
    required this.score,
    required this.total,
    required this.c,
  });

  String get _heading {
    if (passed) return 'You passed!!';
    if (timedOut) return 'Time is up!';
    return 'Test failure.';
  }

  String get _body {
    if (passed) {
      return 'You have successfully passed the quiz. Congratulations, you are now an Awalingo Curator!';
    }
    if (timedOut) {
      return 'You ran out of time before completing the quiz. Please try again in $_kCuratorTestCooldownDays days.';
    }
    return "Sorry, you didn't quite make it this time.  Please continue to explore your language community and kindly take the quiz again in $_kCuratorTestCooldownDays days.";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeProvider.of(context).isDark;
    final illustration = passed
        ? (isDark ? 'assets/illustrations/curator-test-passed-white.png' : 'assets/illustrations/curator-test-passed-black.png')
        : (isDark ? 'assets/illustrations/curator-test-failed-white.png' : 'assets/illustrations/curator-test-failed-black.png');

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: c.foreground),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(illustration, height: 220, errorBuilder: (_, __, ___) => Icon(
                          passed ? Icons.emoji_events_outlined : Icons.close,
                          size: 96,
                          color: passed ? const Color(0xFF22C55E) : const Color(0xFFEF4444))),
                      const SizedBox(height: 24),
                      Text(
                        _heading,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Parkinsans', fontSize: 26, fontWeight: FontWeight.w700, color: c.foreground),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _body,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, height: 1.5, color: c.mutedForeground),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Score: $score/ $total',
                        style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == '/home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.foreground,
                  foregroundColor: c.background,
                  minimumSize: const Size(double.infinity, 56),
                  shape: const StadiumBorder(),
                  elevation: 0,
                ),
                child: const Text(
                  'Go Home',
                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
