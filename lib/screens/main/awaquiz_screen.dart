import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../features/awaquiz/awaquiz_mapper.dart';
import '../../features/awaquiz/awaquiz_progression.dart';
import '../../services/awaquiz_certificate.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/webview_support.dart';
import '../../widgets/cowry_checkout_webview.dart';

// ── Cowry top-up ─────────────────────────────────────────────────────────────

// Mirrors COWRY_TOP_UP_PACKAGES (neolingo/src/lib/cowry-payments.ts) — a
// static, server-defined price list, so it's ported as one here too rather
// than fetched.
class CowryTopUpPackage {
  final String id;
  final String name;
  final int cowries;
  final Map<String, num> amounts; // currency code -> amount
  const CowryTopUpPackage({
    required this.id,
    required this.name,
    required this.cowries,
    required this.amounts,
  });
}

const kCowryTopUpPackages = [
  CowryTopUpPackage(
    id: 'copper-50',
    name: 'Copper',
    cowries: 50,
    amounts: {'NGN': 750, 'USD': 0.5},
  ),
  CowryTopUpPackage(
    id: 'silver-100',
    name: 'Silver',
    cowries: 100,
    amounts: {'NGN': 1500, 'USD': 1},
  ),
  CowryTopUpPackage(
    id: 'gold-500',
    name: 'Gold',
    cowries: 500,
    amounts: {'NGN': 5000, 'USD': 3.5},
  ),
  CowryTopUpPackage(
    id: 'diamond-1000',
    name: 'Diamond',
    cowries: 1000,
    amounts: {'NGN': 7000, 'USD': 5},
  ),
];
const kCowryPaymentCurrencies = ['NGN', 'USD'];

// ── Stage visual constants ──────────────────────────────────────────────────────

const _kStageIcons = [
  Icons.extension_rounded,
  Icons.psychology_rounded,
  Icons.lightbulb_rounded,
  Icons.memory_rounded,
  Icons.auto_awesome_rounded,
  Icons.workspace_premium_rounded,
];

class _StageStyle {
  final Color cardBg; // light-only tinted bg
  final Color topBorder;
  final Color iconBg; // light-only icon bg
  final Color iconBorder;
  final Color accent;
  final Color buttonBg;
  // Only set for stages whose light-mode accent (e.g. Idan's near-black
  // "neutral" look) would have no contrast against a dark card — flips it
  // to something visible instead. Null means the accent is already a
  // saturated hue that reads fine on a dark background as-is.
  final Color? darkAccentOverride;
  const _StageStyle({
    required this.cardBg,
    required this.topBorder,
    required this.iconBg,
    required this.iconBorder,
    required this.accent,
    required this.buttonBg,
    this.darkAccentOverride,
  });

  // Dark mode: tint the card surface with a hint of the accent colour.
  Color darkCardBg() =>
      Color.alphaBlend(accent.withValues(alpha: 0.08), const Color(0xFF171717));
  Color darkIconBg() =>
      Color.alphaBlend(accent.withValues(alpha: 0.15), const Color(0xFF1C1C1E));
  Color darkIconBorder() => accent.withValues(alpha: 0.3);
  Color darkAccent() => darkAccentOverride ?? accent;
}

const _kStageStyles = [
  // 1 JJC – violet
  _StageStyle(
    cardBg: Color(0xFFF5F3FF),
    topBorder: Color(0xFFA78BFA),
    iconBg: Color(0xFFF5F3FF),
    iconBorder: Color(0xFFC4B5FD),
    accent: Color(0xFF7C3AED),
    buttonBg: Color(0xFF8B5CF6),
  ),
  // 2 Sabi Player – green
  _StageStyle(
    cardBg: Color(0xFFF0FDF4),
    topBorder: Color(0xFF22C55E),
    iconBg: Color(0xFFF0FDF4),
    iconBorder: Color(0xFF86EFAC),
    accent: Color(0xFF15803D),
    buttonBg: Color(0xFF16A34A),
  ),
  // 3 Shugaba – amber
  _StageStyle(
    cardBg: Color(0xFFFFFBEB),
    topBorder: Color(0xFFF59E0B),
    iconBg: Color(0xFFFFFBEB),
    iconBorder: Color(0xFFFCD34D),
    accent: Color(0xFFD97706),
    buttonBg: Color(0xFFF59E0B),
  ),
  // 4 Odogwu – cyan
  _StageStyle(
    cardBg: Color(0xFFECFEFF),
    topBorder: Color(0xFF06B6D4),
    iconBg: Color(0xFFECFEFF),
    iconBorder: Color(0xFF67E8F9),
    accent: Color(0xFF0E7490),
    buttonBg: Color(0xFF0891B2),
  ),
  // 5 Idan – neutral/dark. accent is near-black by design in light mode,
  // which is invisible against a dark card, so dark mode flips to near-white.
  _StageStyle(
    cardBg: Color(0xFFFAFAFA),
    topBorder: Color(0xFF111827),
    iconBg: Color(0xFFFFFFFF),
    iconBorder: Color(0xFF9CA3AF),
    accent: Color(0xFF111827),
    buttonBg: Color(0xFF111827),
    darkAccentOverride: Color(0xFFE5E7EB),
  ),
  // 6 Ancestor – red
  _StageStyle(
    cardBg: Color(0xFFFFF5F5),
    topBorder: Color(0xFFEF4444),
    iconBg: Color(0xFFFFF5F5),
    iconBorder: Color(0xFFFCA5A5),
    accent: Color(0xFFB91C1C),
    buttonBg: Color(0xFFB91C1C),
  ),
];

extension _AwaQuizStagePresentation on AwaQuizStage {
  int get _styleIndex => (section - 1).clamp(0, _kStageStyles.length - 1);
  _StageStyle get style => _kStageStyles[_styleIndex];
  String get stageName => name;
  IconData get icon => _kStageIcons[_styleIndex];
  int get stageNumber => section;
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

// ── Service ─────────────────────────────────────────────────────────────────────

class _AwaQuizService {
  final _db = Supabase.instance.client;

  Future<AwaQuizOverview> loadOverview(String userId, int languageId) async {
    final setsRows = await _db
        .from('community_quiz_sets')
        .select('id, difficulty, questionCount')
        .eq('languageId', languageId)
        .eq('isActive', true);

    final setIds = setsRows.map((row) => row['id'] as int).toList();
    final attemptsFuture = _db
        .from('community_quiz_attempts')
        .select('section, score, totalQuestions, submittedAt')
        .eq('userId', userId)
        .eq('languageId', languageId)
        .inFilter('section', const [1, 2, 3, 4, 5, 6]);
    final profileFuture = _db
        .from('user_profile')
        .select('cowryBalance')
        .eq('userId', userId)
        .maybeSingle();
    final questionRowsFuture = setIds.isEmpty
        ? Future.value(const <Map<String, dynamic>>[])
        : _db
              .from('community_quiz_questions')
              .select('setId')
              .inFilter('setId', setIds)
              .eq('isActive', true);
    final (attempts, profile, questionRows) = await (
      attemptsFuture,
      profileFuture,
      questionRowsFuture,
    ).wait;
    final balance = (profile?['cowryBalance'] as int?) ?? 0;

    return mapAwaQuizOverview(
      setRows: setsRows,
      questionSetIds: {
        for (final row in questionRows)
          if (row['setId'] case final int setId) setId,
      },
      attemptRows: attempts,
      cowryBalance: balance,
    );
  }

  // Mirrors community-quiz.ts's `ORDER BY RANDOM() LIMIT limit*3`: PostgREST
  // has no way to request DB-side random ordering through the normal query
  // builder, so this fetches every active question for the set (a curated
  // bank per difficulty, not a large table) and shuffles client-side —
  // without this, PostgREST's unspecified-but-stable row order meant every
  // attempt showed the identical first N questions in the identical order.
  // Mirrors startCommunityQuizAttempt's question selection (community-quiz.ts:863-876):
  // ORDER BY RANDOM() LIMIT n*3, done in Postgres via get_community_quiz_questions
  // rather than fetched-then-shuffled client-side. A plain unordered, unlimited
  // PostgREST select is silently capped at the project's default max rows, so
  // for a set with a pool larger than that cap, client-side shuffling only ever
  // reshuffled the same fixed slice of the table — never reaching the rest of
  // the pool, which read as "not randomized" across attempts.
  Future<List<_QuizQuestion>> loadQuestions(int setId, int limit) async {
    final rows =
        await _db.rpc(
              'get_community_quiz_questions',
              params: {'p_set_id': setId, 'p_limit': limit},
            )
            as List;

    final seen = <String>{};
    final questions = <_QuizQuestion>[];
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final norm = (row['text'] as String).trim().toLowerCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      if (seen.contains(norm)) continue;
      seen.add(norm);
      final opts = (row['options'] as List<dynamic>).map((o) {
        final m = o as Map<String, dynamic>;
        return (label: m['label'] as String, value: m['value'] as String);
      }).toList();
      questions.add(
        _QuizQuestion(
          id: row['id'] as int,
          text: row['text'] as String,
          options: opts,
          correctAnswer: row['correctAnswer'] as String,
        ),
      );
      if (questions.length >= limit) break;
    }
    return questions;
  }

  // Mirrors startCommunityQuizAttempt (community-quiz.ts:653): the entry
  // fee + attempt creation happen server-side in one SECURITY DEFINER RPC,
  // like unlock_awaquiz_review and promote_user_to_curator already do for
  // similarly sensitive cowry/role mutations. A direct client-side insert
  // into cowry_ledger hits Postgres error 42501 ("new row violates
  // row-level security policy") — RLS only allows writes to that table
  // through vetted server-side paths, not arbitrary client eventTypes — and
  // a raw balance write bypasses cowry_ledger entirely, which any later
  // ledger-sum recompute (e.g. unlockReview's charge) would silently erase.
  Future<({int? attemptId, bool insufficientCowries, String? error})>
  startAttempt({
    required String userId,
    required int languageId,
    required AwaQuizStage stage,
  }) async {
    final payload = buildAwaQuizAttemptInsert(
      userId: userId,
      languageId: languageId,
      stage: stage,
    );
    final result =
        await _db.rpc(
              'start_awaquiz_attempt',
              params: {
                'p_set_id': stage.setId,
                'p_language_id': languageId,
                'p_difficulty': payload['difficulty'],
                'p_section': stage.section,
                'p_entry_fee': payload['entryCostCowries'],
              },
            )
            as Map<String, dynamic>;
    return (
      attemptId: result['attemptId'] as int?,
      insufficientCowries: result['insufficientCowries'] as bool? ?? false,
      error: result['error'] as String?,
    );
  }

  Future<void> submitAttempt(int attemptId, int score, int total) async {
    await _db
        .from('community_quiz_attempts')
        .update({
          'score': score,
          'totalQuestions': total,
          'submittedAt': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', attemptId);
  }

  Future<void> exitAttempt(int attemptId) async {
    await _db
        .from('community_quiz_attempts')
        .update({'submittedAt': DateTime.now().toUtc().toIso8601String()})
        .eq('id', attemptId);
  }

  static const reviewCostCowries = 10;

  Future<int> currentCowryBalance(String userId) async {
    final row = await _db
        .from('user_profile')
        .select('cowryBalance')
        .eq('userId', userId)
        .maybeSingle();
    return (row?['cowryBalance'] as int?) ?? 0;
  }

  // Mirrors unlockCommunityQuizReview (community-quiz.ts:993), which wraps
  // the attempt-unlock + cowry charge in one Prisma $transaction so a
  // failure partway through rolls back entirely. The separate REST calls
  // this used to make had no such atomicity: a failure after the
  // reviewUnlockedAt write (but before the cowry charge) left the attempt
  // permanently marked "unlocked" with no charge ever applied, so a retry
  // saw reviewUnlockedAt already set and silently reported success without
  // recharging — "fails once, then works" with nothing actually charged.
  // unlock_awaquiz_review is a single SECURITY DEFINER RPC (auth.uid()-scoped)
  // so the whole thing commits or rolls back as one unit, like the Prisma tx.
  Future<
    ({
      bool success,
      bool alreadyUnlocked,
      bool insufficientCowries,
      String? error,
      int cowryBalance,
    })
  >
  unlockReview(int attemptId, String userId) async {
    final result =
        await _db.rpc(
              'unlock_awaquiz_review',
              params: {'p_attempt_id': attemptId},
            )
            as Map<String, dynamic>;
    return (
      success: result['success'] as bool? ?? false,
      alreadyUnlocked: result['alreadyUnlocked'] as bool? ?? false,
      insufficientCowries: result['insufficientCowries'] as bool? ?? false,
      error: result['error'] as String?,
      cowryBalance: result['cowryBalance'] as int? ?? 0,
    );
  }

  // Mirrors handleTopUp (awaquiz/page.tsx): POSTs to the web app's own
  // /api/payments/flutterwave/initiate route, which talks to Flutterwave
  // server-side and returns a hosted checkout URL. Flutter has no server of
  // its own to hold the Flutterwave secret keys, so this calls the same
  // trusted endpoint the web client calls, authenticated with the user's
  // Supabase access token instead of the browser session cookie the web
  // client relies on.
  Future<String> initiateTopUp({
    required String packageId,
    required String currency,
  }) async {
    final token = _db.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Not authenticated');
    final webBaseUrl = dotenv.env['WEB_BASE_URL'] ?? '';
    final response = await http.post(
      Uri.parse('$webBaseUrl/api/payments/flutterwave/initiate'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'packageId': packageId, 'currency': currency}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final checkoutUrl = data['checkoutUrl'] as String?;
    if (response.statusCode != 200 || checkoutUrl == null) {
      throw Exception(data['error'] as String? ?? 'Unable to start payment.');
    }
    return checkoutUrl;
  }
}

// ── Level Picker Screen ─────────────────────────────────────────────────────────

class AwaQuizScreen extends StatefulWidget {
  final int? languageId;
  final String? communityName;
  final VoidCallback? onBack;
  const AwaQuizScreen({
    super.key,
    this.languageId,
    this.communityName,
    this.onBack,
  });

  // The quiz/result flow (_QuizScreen -> _ResultScreen) uses pushReplacement,
  // so the _startQuiz caller's pending Navigator.push future — and the
  // _load() refresh chained after it — resolves immediately at submission
  // time, not when the user actually leaves _ResultScreen. Any cowry charge
  // that happens later (e.g. paying to unlock missed-question review) never
  // triggers a refresh on its own, leaving this screen's balance stale.
  // Mirrors AppShell.refreshRole()'s same fix for the same class of bug.
  static void refreshBalance() => _AwaQuizScreenState._instance?._load();

  @override
  State<AwaQuizScreen> createState() => _AwaQuizScreenState();
}

class _AwaQuizScreenState extends State<AwaQuizScreen> {
  static _AwaQuizScreenState? _instance;

  final _service = _AwaQuizService();
  bool _loading = true;
  String? _error;
  List<AwaQuizStage> _stages = [];
  int _cowryBalance = 0;
  int _languageId = 1;
  String _communityName = 'Community';

  @override
  void initState() {
    super.initState();
    _instance = this;
    if (widget.languageId != null) {
      _languageId = widget.languageId!;
      _communityName = widget.communityName ?? 'Community';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (identical(_instance, this)) _instance = null;
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = AuthProvider.of(context).user?.id;
      if (userId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

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

      final data = await _service.loadOverview(userId, _languageId);
      if (mounted) {
        setState(() {
          _stages = data.stages;
          _cowryBalance = data.cowryBalance;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _onLevelTap(AwaQuizStage level) {
    if (!level.isUnlocked) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StartModal(
        level: level,
        communityName: _communityName,
        cowryBalance: _cowryBalance,
        onStart: (reportError) => _startQuiz(level, reportError),
        onInsufficientCowries: () => _showNotEnoughCowriesModal(level),
      ),
    );
  }

  // Mirrors handleStartQuiz's insufficient-balance branch (awaquiz/page.tsx):
  // offers "Earn Cowries" (back to Menu) or "Top Up" (real Flutterwave
  // payment) instead of just refusing to start.
  void _showNotEnoughCowriesModal(AwaQuizStage level) {
    final missing = level.difficulty.cowryCost - _cowryBalance;
    showDialog(
      context: context,
      builder: (_) => _NotEnoughCowriesModal(
        missingCowries: missing,
        onEarnCowries: () {
          Navigator.of(context).pop();
          widget.onBack?.call();
        },
        onTopUp: () {
          Navigator.of(context).pop();
          _showTopUpModal();
        },
      ),
    );
  }

  Future<void> _showTopUpModal() async {
    final result = await showDialog<CowryCheckoutResult>(
      context: context,
      builder: (_) => _TopUpCowriesModal(service: _service),
    );
    if (!mounted) return;
    if (result == CowryCheckoutResult.success) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cowries added! Your balance has been updated.'),
          ),
        );
      }
    } else if (result == CowryCheckoutResult.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment failed. Please try again.')),
      );
    }
  }

  // Mirrors handleStartQuiz (awaquiz/page.tsx): on failure the modal stays
  // open and shows the error inline (reportError), instead of closing
  // immediately — so the modal is only popped once we're actually
  // committed to navigating to the quiz screen.
  Future<void> _startQuiz(
    AwaQuizStage level,
    void Function(String) reportError,
  ) async {
    if (_cowryBalance < level.difficulty.cowryCost) return;
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) {
      reportError('Not signed in.');
      return;
    }
    try {
      final questions = await _service.loadQuestions(
        level.setId,
        level.questionCount,
      );
      if (questions.isEmpty) {
        reportError('No questions available for this level yet.');
        return;
      }
      final started = await _service.startAttempt(
        userId: userId,
        languageId: _languageId,
        stage: level,
      );
      if (started.attemptId == null) {
        if (started.insufficientCowries) _load();
        reportError(started.error ?? 'Failed to start quiz. Please try again.');
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => _QuizScreen(
            questions: questions,
            level: level,
            communityName: _communityName,
            attemptId: started.attemptId!,
            service: _service,
          ),
        ),
      );
      _load();
    } catch (e) {
      debugPrint('startQuiz error: $e');
      reportError('Failed to start quiz. Please try again.');
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: c.border),
                ),
                child: Text(
                  'Loading quiz...',
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 14,
                    color: c.mutedForeground,
                  ),
                ),
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        Text(
                          'AwaQuiz $_communityName',
                          style: TextStyle(
                            fontFamily: 'Parkinsans',
                            fontFamilyFallback: kContentFontFallback,
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: c.foreground,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Pick a level, answer a fresh set of questions, and see how far your community language skills can go.',
                          style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontSize: 13,
                            height: 1.5,
                            color: c.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_stages.isEmpty)
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
                        style: TextStyle(
                          fontFamily: 'Metropolis',
                          fontSize: 13,
                          color: c.mutedForeground,
                        ),
                      ),
                    )
                  else
                    ..._stages.map(
                      (level) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _LevelCard(
                          level: level,
                          cowryBalance: _cowryBalance,
                          onTap: () => _onLevelTap(level),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ── Level Card ──────────────────────────────────────────────────────────────────

class _LevelCard extends StatelessWidget {
  final AwaQuizStage level;
  final int cowryBalance;
  final VoidCallback onTap;
  const _LevelCard({
    required this.level,
    required this.cowryBalance,
    required this.onTap,
  });

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
    final accent = isDark ? st.darkAccent() : st.accent;
    final topBorder = isDark ? st.darkAccent() : st.topBorder;
    final buttonBg = isDark ? st.darkAccent() : st.buttonBg;
    // The Play button's white label only works against the vivid stage
    // hues — Idan's dark-mode accent flips to a light neutral, which needs
    // dark text instead.
    final buttonFg = isDark && st.darkAccentOverride != null
        ? Colors.black
        : Colors.white;

    // Mirrors AwaQuizLevelCard (AwaQuizMenuCard.tsx): locked only dims the
    // Play/Locked button — the card, icon and copy stay at full color.
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.07),
              blurRadius: 15,
              spreadRadius: -3,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 20,
              spreadRadius: -2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: DecoratedBox(
            decoration: BoxDecoration(color: cardBg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 2, color: topBorder),
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
                        child: Icon(level.icon, size: 20, color: accent),
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
                                    style: TextStyle(
                                      fontFamily: 'Parkinsans',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: accent,
                                    ),
                                  ),
                                ),
                                if (locked)
                                  Icon(
                                    Icons.lock_rounded,
                                    size: 16,
                                    color: c.mutedForeground,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${level.questionCount} questions · ${level.difficulty.cowryCost} cowries · ${level.difficulty.secondsPerQuestion}s / question',
                              style: TextStyle(
                                fontFamily: 'Metropolis',
                                fontSize: 12,
                                color: c.mutedForeground,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  level.isUnlocked
                                      ? '$attempts ${attempts == 1 ? 'attempt' : 'attempts'}'
                                      : 'Score 100% on ${level.previousStageName ?? 'the previous stage'}',
                                  style: TextStyle(
                                    fontFamily: 'Metropolis',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: accent,
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: locked ? null : onTap,
                                  icon: Icon(
                                    locked
                                        ? Icons.lock_rounded
                                        : Icons.rocket_launch_rounded,
                                    size: 14,
                                  ),
                                  label: Text(locked ? 'Locked' : 'Play'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: buttonBg,
                                    foregroundColor: buttonFg,
                                    disabledBackgroundColor: c.secondary,
                                    disabledForegroundColor: c.mutedForeground,
                                    textStyle: const TextStyle(
                                      fontFamily: 'Metropolis',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 9,
                                    ),
                                    shape: const StadiumBorder(),
                                    elevation: 0,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
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
    );
  }
}

// ── Start Modal ─────────────────────────────────────────────────────────────

// Mirrors formatCommunityQuizDuration (community-quiz.ts:89).
String _formatQuizDuration(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (seconds == 0) return '$minutes min${minutes == 1 ? '' : 's'}';
  if (minutes == 0) return '$seconds sec${seconds == 1 ? '' : 's'}';
  return '$minutes min $seconds sec';
}

// Mirrors AwaQuizStartModal (awaquiz/page.tsx:298-413) exactly: a fully
// rounded card floating above the bottom edge with margin on every side
// (matching the web's mobile `items-end px-4 pb-4` layout), not a
// flush-to-the-edge native bottom sheet.
class _StartModal extends StatefulWidget {
  final AwaQuizStage level;
  final String communityName;
  final int cowryBalance;
  final void Function(void Function(String) reportError) onStart;
  final VoidCallback onInsufficientCowries;
  const _StartModal({
    required this.level,
    required this.communityName,
    required this.cowryBalance,
    required this.onStart,
    required this.onInsufficientCowries,
  });

  @override
  State<_StartModal> createState() => _StartModalState();
}

class _StartModalState extends State<_StartModal> {
  bool _agreed = false;
  bool _starting = false;
  String? _error;

  void _reportError(String message) {
    if (mounted)
      setState(() {
        _starting = false;
        _error = message;
      });
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    final st = level.style;
    final diff = level.difficulty;
    final canAfford = widget.cowryBalance >= diff.cowryCost;
    final c = AppColorScheme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            16,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stage ${level.stageNumber}',
                        style: TextStyle(
                          fontFamily: 'Metropolis',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: st.accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ready for ${level.stageName}?',
                        style: TextStyle(
                          fontFamily: 'Parkinsans',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: c.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? st.darkIconBg()
                        : st.iconBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(level.icon, size: 20, color: st.accent),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _GridTile(
                    label: 'Questions',
                    value: '${level.questionCount}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _GridTile(
                    label: 'Entry fee',
                    value: '${diff.cowryCost} cowries',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _GridTile(
                    label: 'Your balance',
                    value: '${widget.cowryBalance} cowries',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _GridTile(
                    label: 'Duration',
                    value:
                        '${_formatQuizDuration(diff.secondsPerQuestion)} / question',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Cowries are deducted as soon as you start. If you exit after the quiz begins, the session ends and the fee is still used.',
              style: TextStyle(
                fontFamily: 'Metropolis',
                fontSize: 13,
                height: 1.4,
                color: c.mutedForeground,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _starting
                  ? null
                  : () => setState(() => _agreed = !_agreed),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.secondary,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(top: 2),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _agreed ? st.accent : Colors.transparent,
                        border: Border.all(
                          color: _agreed ? st.accent : c.border,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: _agreed
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 14,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'I have read the rules and I am ready to start.',
                        style: TextStyle(
                          fontFamily: 'Metropolis',
                          fontSize: 13,
                          color: c.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 13,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _starting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: c.border),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        color: c.foreground,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    // Mirrors handleStartQuiz (awaquiz/page.tsx): the button
                    // isn't disabled by an insufficient balance — tapping it
                    // routes to the Not Enough Cowries flow instead of just
                    // refusing, and only pops this modal once _startQuiz is
                    // actually committed to navigating to the quiz screen; a
                    // failure keeps the modal open with an inline error.
                    onPressed: (!_agreed || _starting)
                        ? null
                        : () {
                            if (!canAfford) {
                              Navigator.of(context).pop();
                              widget.onInsufficientCowries();
                              return;
                            }
                            setState(() {
                              _starting = true;
                              _error = null;
                            });
                            widget.onStart(_reportError);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: st.buttonBg,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                      disabledBackgroundColor: c.secondary,
                      disabledForegroundColor: c.mutedForeground,
                    ),
                    child: _starting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Start quiz',
                            style: TextStyle(
                              fontFamily: 'Metropolis',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Not Enough Cowries / Top Up ─────────────────────────────────────────────────

// Mirrors NotEnoughCowriesModal (awaquiz/page.tsx).
class _NotEnoughCowriesModal extends StatelessWidget {
  final int missingCowries;
  final VoidCallback onEarnCowries;
  final VoidCallback onTopUp;
  const _NotEnoughCowriesModal({
    required this.missingCowries,
    required this.onEarnCowries,
    required this.onTopUp,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(Icons.close, size: 16, color: c.mutedForeground),
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: c.secondary,
                  minimumSize: const Size(28, 28),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: c.secondary,
                shape: BoxShape.circle,
                border: Border.all(color: c.border),
              ),
              child: const Center(
                child: Text('🐚', style: TextStyle(fontSize: 42)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Not Enough Cowries',
              style: TextStyle(
                fontFamily: 'Parkinsans',
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: c.foreground,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You are $missingCowries cowries short from testing your language skills. '
              'Top up your cowries, or perform activities to earn cowries.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Metropolis',
                fontSize: 13,
                color: c.mutedForeground,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onTopUp,
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                      foregroundColor: c.foreground,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Top Up',
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onEarnCowries,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.foreground,
                      foregroundColor: c.background,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Earn Cowries',
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Mirrors TopUpCowriesModal (awaquiz/page.tsx): currency toggle + the static
// package list, POSTing to the same Flutterwave-initiate endpoint the web
// client calls and opening the returned checkout URL in-app (CowryCheckoutScreen)
// instead of a full page redirect.
class _TopUpCowriesModal extends StatefulWidget {
  final _AwaQuizService service;
  const _TopUpCowriesModal({required this.service});

  @override
  State<_TopUpCowriesModal> createState() => _TopUpCowriesModalState();
}

class _TopUpCowriesModalState extends State<_TopUpCowriesModal> {
  String _currency = 'NGN';
  String? _startingPackageId;
  String? _error;

  Future<void> _pay(CowryTopUpPackage pkg) async {
    setState(() {
      _startingPackageId = pkg.id;
      _error = null;
    });
    try {
      final checkoutUrl = await widget.service.initiateTopUp(
        packageId: pkg.id,
        currency: _currency,
      );
      if (!mounted) return;
      final webBaseUrl = dotenv.env['WEB_BASE_URL'] ?? '';
      CowryCheckoutResult? result;
      if (supportsInAppWebView) {
        result = await Navigator.of(context, rootNavigator: true)
            .push<CowryCheckoutResult>(
              MaterialPageRoute(
                builder: (_) => CowryCheckoutScreen(
                  checkoutUrl: checkoutUrl,
                  webBaseUrl: webBaseUrl,
                ),
              ),
            );
      } else {
        // webview_flutter has no desktop/web implementation — fall back to
        // the external browser there instead of crashing. We can't watch
        // for the callback redirect this way, so the balance only updates
        // on the next natural refresh.
        await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      Navigator.of(context).pop(result ?? CowryCheckoutResult.cancelled);
    } catch (e) {
      if (mounted) {
        setState(() {
          _startingPackageId = null;
          _error = 'Unable to start payment. Please try again.';
        });
      }
    }
  }

  String _formatAmount(num amount, String currency) {
    final symbol = currency == 'USD' ? '\$' : '₦';
    final isWhole = amount == amount.roundToDouble();
    return '$symbol${isWhole ? amount.toInt() : amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Top Up your cowries',
                        style: TextStyle(
                          fontFamily: 'Parkinsans',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: c.foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pay in Naira or Dollars.',
                        style: TextStyle(
                          fontFamily: 'Metropolis',
                          fontSize: 13,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: c.mutedForeground),
                  onPressed: _startingPackageId != null
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: c.secondary,
                    minimumSize: const Size(28, 28),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: c.secondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: kCowryPaymentCurrencies.map((cur) {
                  final selected = cur == _currency;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _currency = cur),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selected ? c.card : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          cur,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: selected ? c.foreground : c.mutedForeground,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(
                  fontFamily: 'Metropolis',
                  fontSize: 12,
                  color: Color(0xFFDC2626),
                ),
              ),
              const SizedBox(height: 8),
            ],
            for (final pkg in kCowryTopUpPackages)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: _startingPackageId != null ? null : () => _pay(pkg),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.secondary,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pkg.name,
                                style: TextStyle(
                                  fontFamily: 'Metropolis',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: c.foreground,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '🐚 ${pkg.cowries} cowries',
                                style: TextStyle(
                                  fontFamily: 'Metropolis',
                                  fontSize: 12,
                                  color: c.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_startingPackageId == pkg.id)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.primary,
                            ),
                          )
                        else
                          Text(
                            _formatAmount(pkg.amounts[_currency]!, _currency),
                            style: TextStyle(
                              fontFamily: 'Metropolis',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: c.foreground,
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

class _GridTile extends StatelessWidget {
  final String label;
  final String value;
  const _GridTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Metropolis',
              fontSize: 12,
              color: c.mutedForeground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Metropolis',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: c.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Active Quiz Screen ──────────────────────────────────────────────────────────

String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

class _QuizScreen extends StatefulWidget {
  final List<_QuizQuestion> questions;
  final AwaQuizStage level;
  final String communityName;
  final int attemptId;
  final _AwaQuizService service;
  const _QuizScreen({
    required this.questions,
    required this.level,
    required this.communityName,
    required this.attemptId,
    required this.service,
  });

  @override
  State<_QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<_QuizScreen> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // Anti-cheat: backgrounding the app (e.g. to look up the answer elsewhere)
  // forfeits the current question exactly as a timeout would, rather than
  // leaving it frozen for the user to return to at their leisure.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        !_submitting &&
        !_showExitDialog &&
        _timer != null) {
      _onTimeout();
    }
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
    final score = _answers
        .asMap()
        .entries
        .where((e) => e.value == widget.questions[e.key].correctAnswer)
        .length;
    try {
      await widget.service.submitAttempt(
        widget.attemptId,
        score,
        widget.questions.length,
      );
    } catch (_) {}
    if (!mounted) return;
    final missed = _answers
        .asMap()
        .entries
        .where((e) => e.value != widget.questions[e.key].correctAnswer)
        .map(
          (e) => (question: widget.questions[e.key], selectedAnswer: e.value),
        )
        .toList();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _ResultScreen(
          score: score,
          total: widget.questions.length,
          level: widget.level,
          communityName: widget.communityName,
          missed: missed,
          attemptId: widget.attemptId,
          service: widget.service,
        ),
      ),
    );
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
    try {
      await widget.service.exitAttempt(widget.attemptId);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: c.border),
            ),
            child: Text(
              'Submitting quiz...',
              style: TextStyle(
                fontFamily: 'Metropolis',
                fontSize: 14,
                color: c.mutedForeground,
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openExitDialog();
      },
      child: Scaffold(
        backgroundColor: c.background,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _openExitDialog,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: c.card,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.close,
                              size: 18,
                              color: c.foreground,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: logo + timer + counter
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Image.asset(
                                        isDark
                                            ? 'assets/branding/logo-wordmark-dark.png'
                                            : 'assets/branding/logo-wordmark-light.png',
                                        height: 28,
                                        errorBuilder: (_, e, st) => Text(
                                          'AwaQuiz',
                                          style: TextStyle(
                                            fontFamily: 'Parkinsans',
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: c.foreground,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${widget.communityName} · ${widget.level.stageName}',
                                        style: TextStyle(
                                          fontFamily: 'Metropolis',
                                          fontFamilyFallback:
                                              kContentFontFallback,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: c.mutedForeground,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: inWarning
                                            ? const Color(0xFFFFF1F2)
                                            : c.secondary,
                                        borderRadius: BorderRadius.circular(
                                          100,
                                        ),
                                        border: Border.all(
                                          color: inWarning
                                              ? const Color(0xFFFDA4AF)
                                              : c.border,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.access_time_rounded,
                                            size: 15,
                                            color: inWarning
                                                ? const Color(0xFFE11D48)
                                                : c.mutedForeground,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            _fmt(_secondsLeft.clamp(0, 9999)),
                                            style: TextStyle(
                                              fontFamily: 'Metropolis',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              color: inWarning
                                                  ? const Color(0xFFE11D48)
                                                  : c.foreground,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: c.secondary,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        '${_currentIndex + 1} / ${widget.questions.length}',
                                        style: TextStyle(
                                          fontFamily: 'Metropolis',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: c.foreground,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),

                            // Question box
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: c.secondary,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Text(
                                question.text,
                                style: TextStyle(
                                  fontFamily: 'Metropolis',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                  height: 1.5,
                                  color: c.foreground,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Answer options
                            ...question.options.map((opt) {
                              final isSelected = selectedAnswer == opt.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _answers[_currentIndex] = opt.value,
                                  ),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? st.accent.withValues(alpha: 0.06)
                                          : c.card,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected
                                            ? st.accent
                                            : c.border,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          '${opt.label}.',
                                          style: TextStyle(
                                            fontFamily: 'Metropolis',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: isSelected
                                                ? st.accent
                                                : c.foreground,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            opt.value,
                                            style: TextStyle(
                                              fontFamily: 'Metropolis',
                                              fontSize: 14,
                                              color: isSelected
                                                  ? st.accent
                                                  : c.foreground,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Footer
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: _openExitDialog,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(color: c.border),
                          ),
                          child: Text(
                            'Exit',
                            style: TextStyle(
                              fontFamily: 'Metropolis',
                              color: c.foreground,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedAnswer != null ? _next : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: st.buttonBg,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                              disabledBackgroundColor: c.secondary,
                              disabledForegroundColor: c.mutedForeground,
                            ),
                            child: Text(
                              isLast ? 'Submit quiz' : 'Next question',
                              style: const TextStyle(
                                fontFamily: 'Metropolis',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End the quiz?',
                              style: TextStyle(
                                fontFamily: 'Parkinsans',
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: c.foreground,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Leaving now will end this quiz session. Your progress will be lost.',
                              style: TextStyle(
                                fontFamily: 'Metropolis',
                                fontSize: 14,
                                height: 1.5,
                                color: c.mutedForeground,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _closeExitDialog,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(color: c.border),
                                    ),
                                    child: Text(
                                      'Keep going',
                                      style: TextStyle(
                                        fontFamily: 'Metropolis',
                                        color: c.foreground,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _doExit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE11D48),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      'End quiz',
                                      style: TextStyle(
                                        fontFamily: 'Metropolis',
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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

// ── Result Screen ───────────────────────────────────────────────────────────────

class _ResultScreen extends StatefulWidget {
  final int score;
  final int total;
  final AwaQuizStage level;
  final String communityName;
  final List<({_QuizQuestion question, String? selectedAnswer})> missed;
  final int attemptId;
  final _AwaQuizService service;
  const _ResultScreen({
    required this.score,
    required this.total,
    required this.level,
    required this.communityName,
    required this.missed,
    required this.attemptId,
    required this.service,
  });

  @override
  State<_ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<_ResultScreen> {
  bool _showMissed = false;
  bool _reviewUnlocked = false;

  bool _downloadingCertificate = false;

  int get _pct =>
      widget.total > 0 ? ((widget.score / widget.total) * 100).round() : 0;
  bool get _isPerfect => widget.score == widget.total && widget.total > 0;

  String get _certificateName {
    final meta = AuthProvider.of(context).user;
    return (meta?.userMetadata?['name'] as String?)?.trim() ??
        (meta?.userMetadata?['full_name'] as String?)?.trim() ??
        meta?.email?.split('@').first ??
        'Awalingo Learner';
  }

  // Mirrors handleDownloadCertificate (result/page.tsx:142-157).
  Future<void> _downloadCertificate() async {
    if (_downloadingCertificate) return;
    setState(() => _downloadingCertificate = true);
    try {
      Uint8List? logoBytes;
      try {
        final data = await rootBundle.load(
          'assets/branding/logo-wordmark-dark.png',
        );
        logoBytes = data.buffer.asUint8List();
      } catch (_) {}

      final recipientName = _certificateName;
      final pdfBytes = await buildAwaQuizCertificatePdf(
        language: widget.communityName,
        levelLabel: widget.level.stageName,
        recipientName: recipientName,
        logoBytes: logoBytes,
      );

      final fileSafeName = recipientName
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      if (mounted) {
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename:
              '${fileSafeName.isEmpty ? 'awalingo' : fileSafeName}-awaquiz-certificate.pdf',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to generate certificate. Please try again.',
              style: TextStyle(fontFamily: 'Metropolis'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingCertificate = false);
    }
  }

  // Mirrors getReviewButtonLabel (result/page.tsx:29-39).
  String get _reviewButtonLabel {
    if (_showMissed) return 'Hide My Mistake';
    if (_reviewUnlocked) return 'Show My Mistake';
    return 'Show My Mistake · ${_AwaQuizService.reviewCostCowries} Cowries';
  }

  // Mirrors handleReviewToggle (result/page.tsx:103-116).
  void _handleReviewToggle() {
    if (_showMissed) {
      setState(() => _showMissed = false);
      return;
    }
    if (_reviewUnlocked) {
      setState(() => _showMissed = true);
      return;
    }
    _openPurchaseModal();
  }

  Future<void> _openPurchaseModal() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    int balance = 0;
    try {
      balance = await widget.service.currentCowryBalance(userId);
    } catch (_) {}
    if (!mounted) return;
    final c = AppColorScheme.of(context);
    bool isUnlocking = false;
    String? error;
    final missedCount = widget.missed.length;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) => Dialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: c.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('🐚', style: TextStyle(fontSize: 32)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Reveal your mistakes?',
                  style: TextStyle(
                    fontFamily: 'Parkinsans',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'See your $missedCount ${missedCount == 1 ? 'mistake' : 'mistakes'} for ${_AwaQuizService.reviewCostCowries} Cowries. '
                  'This charge only applies once to this result.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 13,
                    color: c.mutedForeground,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Balance: $balance Cowries',
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isUnlocking
                            ? null
                            : () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder(),
                          foregroundColor: c.foreground,
                          side: BorderSide(color: c.border),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isUnlocking
                            ? null
                            : () async {
                                setModalState(() {
                                  isUnlocking = true;
                                  error = null;
                                });
                                try {
                                  final result = await widget.service
                                      .unlockReview(widget.attemptId, userId);
                                  if (!result.success &&
                                      !result.alreadyUnlocked) {
                                    setModalState(() {
                                      isUnlocking = false;
                                      error = result.error;
                                      if (result.insufficientCowries)
                                        balance = result.cowryBalance;
                                    });
                                    return;
                                  }
                                  if (dialogContext.mounted)
                                    Navigator.pop(dialogContext);
                                  if (mounted)
                                    setState(() {
                                      _reviewUnlocked = true;
                                      _showMissed = true;
                                    });
                                  // Mirrors result/page.tsx's void checkAuth()
                                  // after a successful unlock: the AwaQuiz
                                  // overview's cached balance otherwise never
                                  // learns about this charge (see
                                  // AwaQuizScreen.refreshBalance's doc comment).
                                  AwaQuizScreen.refreshBalance();
                                } catch (e) {
                                  debugPrint('unlockReview failed: $e');
                                  setModalState(() {
                                    isUnlocking = false;
                                    error =
                                        'Failed to reveal your mistakes. Please try again.';
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.foreground,
                          foregroundColor: c.background,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: Text(
                          isUnlocking
                              ? 'Revealing...'
                              : 'Pay ${_AwaQuizService.reviewCostCowries} Cowries',
                          style: const TextStyle(
                            fontFamily: 'Metropolis',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final st = widget.level.style;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
          child: Column(
            children: [
              // Score card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: c.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: st.accent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.emoji_events_rounded,
                        color: st.accent,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${widget.communityName} · ${widget.level.stageName}',
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontFamilyFallback: kContentFontFallback,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: st.accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Quiz complete',
                      style: TextStyle(
                        fontFamily: 'Parkinsans',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: c.foreground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You scored ${widget.score} out of ${widget.total} ($_pct%).',
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 15,
                        color: c.mutedForeground,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: CircularProgressIndicator(
                              value: widget.total > 0
                                  ? widget.score / widget.total
                                  : 0,
                              strokeWidth: 10,
                              backgroundColor: c.border,
                              valueColor: AlwaysStoppedAnimation(st.accent),
                            ),
                          ),
                          Text(
                            '$_pct%',
                            style: TextStyle(
                              fontFamily: 'Parkinsans',
                              fontWeight: FontWeight.w800,
                              fontSize: 26,
                              color: st.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              // Certificate (perfect score only) — mirrors result/page.tsx's
              // earnedCertificate card exactly; intentionally stays
              // light-themed regardless of app theme, matching the web.
              if (_isPerfect) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: const Color(0xFFE5E5E5)),
                  ),
                  child: Column(
                    children: [
                      _CertificateCard(
                        recipientName: _certificateName,
                        language: widget.communityName,
                        levelLabel: widget.level.stageName,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _downloadingCertificate
                            ? null
                            : _downloadCertificate,
                        icon: _downloadingCertificate
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 16),
                        label: Text(
                          _downloadingCertificate
                              ? 'Preparing...'
                              : 'Download Certificate',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.primary,
                          foregroundColor: c.primaryForeground,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: const StadiumBorder(),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontFamily: 'Metropolis',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Missed questions
              if (widget.missed.isNotEmpty) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _handleReviewToggle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _reviewButtonLabel,
                            style: TextStyle(
                              fontFamily: 'Metropolis',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: c.foreground,
                            ),
                          ),
                        ),
                        Icon(
                          _showMissed
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: c.mutedForeground,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showMissed) ...[
                  const SizedBox(height: 8),
                  ...widget.missed.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: c.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.question.text,
                              style: TextStyle(
                                fontFamily: 'Metropolis',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: c.foreground,
                              ),
                            ),
                            const SizedBox(height: 10),
                            e.selectedAnswer != null
                                ? _ReviewRow(
                                    label: 'Your answer:',
                                    value: e.selectedAnswer!,
                                    color: const Color(0xFFB91C1C),
                                    bg: const Color(0xFFFFF5F5),
                                  )
                                : const _ReviewRow(
                                    label: 'Your answer:',
                                    value: 'No answer selected',
                                    color: Color(0xFF6B7280),
                                    bg: Color(0xFFF3F4F6),
                                  ),
                            const SizedBox(height: 6),
                            _ReviewRow(
                              label: 'Correct answer:',
                              value: e.question.correctAnswer,
                              color: const Color(0xFF059669),
                              bg: const Color(0xFFF0FDF4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: st.buttonBg,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Try another level',
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).popUntil((r) => r.isFirst || r.settings.name == '/home'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: c.border),
                  ),
                  child: Text(
                    'Back to menu',
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: c.foreground,
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

// Mirrors the earnedCertificate preview card (result/page.tsx:214-284) —
// an A4-ratio (1.414) card with layered navy/gold corner ribbons, dotted
// corner accents, a black logo panel, and a gold trophy seal. Always
// light-themed regardless of app theme, matching the web exactly.
class _CertificateCard extends StatelessWidget {
  final String recipientName;
  final String language;
  final String levelLabel;
  const _CertificateCard({
    required this.recipientName,
    required this.language,
    required this.levelLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1.414,
        child: ColoredBox(
          color: Colors.white,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              double clampFont(double minPx, double pctOfWidth, double maxPx) =>
                  (w * pctOfWidth / 100).clamp(minPx, maxPx);

              return Stack(
                children: [
                  Positioned(
                    left: w * 0.13,
                    top: 0,
                    width: w * 0.18,
                    height: h * 0.25,
                    child: CustomPaint(painter: _DotGridPainter()),
                  ),
                  Positioned(
                    right: w * 0.13,
                    bottom: 0,
                    width: w * 0.18,
                    height: h * 0.25,
                    child: CustomPaint(painter: _DotGridPainter()),
                  ),
                  Positioned.fill(
                    child: CustomPaint(painter: _CornerRibbonPainter()),
                  ),

                  Positioned(
                    left: w * 0.5 - w * 0.14,
                    top: 0,
                    width: w * 0.28,
                    height: h * 0.15,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: w * 0.02),
                      decoration: const BoxDecoration(
                        color: Color(0xFF08080A),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(24),
                        ),
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/branding/logo-wordmark-dark.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Text(
                            'AWALINGO',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: w * 0.10,
                    right: w * 0.10,
                    top: h * 0.22,
                    child: Text(
                      'CERTIFICATE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: clampFont(16.8, 7.5, 48),
                        color: const Color(0xFF272320),
                      ),
                    ),
                  ),
                  Positioned(
                    left: w * 0.10,
                    right: w * 0.10,
                    top: h * 0.33,
                    child: Text(
                      'OF ACHIEVEMENT',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: clampFont(8, 3, 20.8),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: const Color(0xFFAE7014),
                      ),
                    ),
                  ),
                  Positioned(
                    left: w * 0.10,
                    right: w * 0.10,
                    top: h * 0.41,
                    child: Text(
                      'This is to certify that',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: clampFont(8, 2.4, 16.8),
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Positioned(
                    left: w * 0.14,
                    right: w * 0.14,
                    top: h * 0.50,
                    child: Text(
                      recipientName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: clampFont(12, 5.5, 40),
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Positioned(
                    left: w * 0.16,
                    right: w * 0.16,
                    top: h * 0.59,
                    child: Container(height: 1, color: const Color(0xFFAE7014)),
                  ),
                  Positioned(
                    left: w * 0.13,
                    right: w * 0.13,
                    top: h * 0.63,
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: clampFont(6.4, 2.3, 16),
                          color: Colors.black,
                          fontFamily: 'Metropolis',
                        ),
                        children: [
                          const TextSpan(
                            text: 'Has aced the Awalingo Language Quiz for ',
                          ),
                          TextSpan(
                            text: '$language, ',
                            style: const TextStyle(color: Color(0xFFC4007E)),
                          ),
                          TextSpan(
                            text: levelLabel,
                            style: const TextStyle(color: Color(0xFFD69718)),
                          ),
                          const TextSpan(text: ' Level.'),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: w * 0.13,
                    right: w * 0.13,
                    top: h * 0.71,
                    child: Text(
                      'Please put some respect on their name!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: clampFont(6.4, 2.3, 16),
                        color: Colors.black,
                      ),
                    ),
                  ),

                  Positioned(
                    left: w * 0.05,
                    bottom: h * 0.04,
                    width: w * 0.12,
                    height: w * 0.12,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFD69718),
                        border: Border.all(
                          color: const Color(0xFFF7C74C),
                          width: (w * 0.012).clamp(4, 8),
                        ),
                      ),
                      child: Icon(
                        Icons.emoji_events,
                        color: const Color(0xFFF7C74C),
                        size: w * 0.06,
                      ),
                    ),
                  ),

                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: h * 0.05,
                    child: Column(
                      children: [
                        Text(
                          'Signed:',
                          style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontSize: clampFont(6.4, 2.3, 16),
                            fontStyle: FontStyle.italic,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'The Ancestors',
                          style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontSize: clampFont(7.2, 2.8, 19.2),
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// Matches the dotted-accent corners (radial-gradient dot pattern, 12px grid).
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFD7D1C7);
    for (double y = 6; y < size.height; y += 12) {
      for (double x = 6; x < size.width; x += 12) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Matches the nested navy/gold corner-ribbon triangles (top-left and
// bottom-right), each a percentage of the card's own size, painted
// largest-to-smallest to match the web's DOM stacking order.
class _CornerRibbonPainter extends CustomPainter {
  static const _layers = [
    (0.38, Color(0xFF0C142F)),
    (0.34, Color(0xFF23305E)),
    (0.29, Color(0xFFD69718)),
    (0.27, Color(0xFF141F46)),
    (0.19, Color(0xFF0C142F)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (fraction, color) in _layers) {
      final paint = Paint()..color = color;
      final w = size.width * fraction;
      final h = size.height * fraction;

      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(w, 0)
          ..lineTo(0, h)
          ..close(),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(size.width, size.height)
          ..lineTo(size.width - w, size.height)
          ..lineTo(size.width, size.height - h)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color bg;
  const _ReviewRow({
    required this.label,
    required this.value,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Metropolis',
              fontSize: 11,
              color: color.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Metropolis',
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
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
            color: c.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFCD34D)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFF59E0B),
                size: 32,
              ),
              const SizedBox(height: 12),
              const Text(
                'AwaQuiz unavailable',
                style: TextStyle(
                  fontFamily: 'Parkinsans',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFF92400E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Metropolis',
                  fontSize: 13,
                  color: Color(0xFF92400E),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
