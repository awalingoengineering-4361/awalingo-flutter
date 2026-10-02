import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/streaks/streak_models.dart';
import '../../features/streaks/streak_repository.dart';
import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../app_shell.dart';
import 'awaquiz_screen.dart';

// Hardcoded Tailwind brand accents this feature uses that have no existing
// AppColors token (fuchsia/orange/amber/cyan/emerald), kept local to this
// screen since nothing else in the app uses them. Values are Tailwind's
// default palette so they match neolingo's daily-streak page exactly.
class _StreakColors {
  static const fuchsia300 = Color(0xFFF0ABFC);
  static const fuchsia500 = Color(0xFFD946EF);
  static const fuchsia600 = Color(0xFFC026D3);
  static const orange400 = Color(0xFFFB923C);
  static const orange50 = Color(0xFFFFF7ED);
  static const orange500 = Color(0xFFF97316);
  static const orange950 = Color(0xFF431407);
  static const amber300 = Color(0xFFFCD34D);
  static const amber400 = Color(0xFFFBBF24);
  static const amber700 = Color(0xFFB45309);
  static const amber950 = Color(0xFF451A03);
  static const cyan400 = Color(0xFF22D3EE);
  static const cyan50 = Color(0xFFECFEFF);
  static const cyan600 = Color(0xFF0891B2);
  static const cyan950 = Color(0xFF083344);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald300 = Color(0xFFA7F3D0);
  static const emerald700 = Color(0xFF047857);
  static const emerald950 = Color(0xFF022C22);
  static const neutral300 = Color(0xFFD4D4D4);
  static const neutral700 = Color(0xFF404040);
  static const neutral950 = Color(0xFF0A0A0A);
}

class DailyStreakScreen extends StatefulWidget {
  const DailyStreakScreen({super.key});

  @override
  State<DailyStreakScreen> createState() => _DailyStreakScreenState();
}

class _DailyStreakScreenState extends State<DailyStreakScreen> {
  late final StreakRepository _repo = StreakRepository(Supabase.instance.client);

  bool _loading = true;
  bool _loadDone = false;
  StreakDashboard? _dashboard;
  String? _displayName;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadDone) {
      _loadDone = true;
      _load();
    }
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to view your streak.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final timeZone = await currentStreakTimeZone();
      final results = await Future.wait<Object?>([
        _repo.fetchDashboard(userId, timeZone),
        Supabase.instance.client
            .from('user_profile')
            .select('name')
            .eq('userId', userId)
            .maybeSingle(),
      ]);
      if (!mounted) return;
      final dashboard = results[0] as StreakDashboard;
      final profile = results[1] as Map<String, dynamic>?;
      setState(() {
        _dashboard = dashboard;
        _displayName = profile?['name'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load your streak.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _BackButton(c: c),
                  const SizedBox(width: 12),
                  Text(
                    'Daily Streak',
                    style: TextStyle(
                      fontFamily: 'Parkinsans',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _buildBody(c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppColorScheme c) {
    final dashboard = _dashboard;
    if (_loading && dashboard == null) {
      return _LoadingState(c: c);
    }
    if (_error != null && dashboard == null) {
      return _DashboardError(c: c, message: _error!, onRetry: _load);
    }
    if (dashboard == null) return const SizedBox.shrink();

    return Column(
      children: [
        _StreakHero(dashboard: dashboard, displayName: _displayName),
        const SizedBox(height: 16),
        _WeeklyStreakStrip(days: dashboard.history, c: c),
        const SizedBox(height: 16),
        _DailyGoalList(goals: dashboard.goals, c: c),
        const SizedBox(height: 16),
        _NextMilestoneCard(
          currentDays: dashboard.currentDays,
          milestone: dashboard.nextMilestone,
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
        const SizedBox(height: 16),
        _StreakAction(todayComplete: dashboard.todayComplete),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  final AppColorScheme c;
  const _BackButton({required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.secondary,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.arrow_back, size: 20, color: c.foreground),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  final AppColorScheme c;
  const _LoadingState({required this.c});

  Widget _block(double height, double radius) => Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: c.secondary,
          borderRadius: BorderRadius.circular(radius),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _block(320, 32),
        _block(96, 24),
        _block(256, 24),
      ],
    );
  }
}

class _DashboardError extends StatelessWidget {
  final AppColorScheme c;
  final String message;
  final VoidCallback onRetry;
  const _DashboardError({required this.c, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Icon(Icons.local_fire_department, size: 32, color: _StreakColors.orange500),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: c.primaryForeground,
            ),
          ),
        ],
      ),
    );
  }
}

String _firstName(String? displayName) {
  final trimmed = displayName?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'there';
  return trimmed.split(RegExp(r'\s+')).first;
}

String _heroPrompt(StreakDashboard dashboard, String firstName) {
  if (dashboard.currentDays == 0 && !dashboard.todayComplete) {
    return 'Start your first streak today';
  }
  if (dashboard.todayComplete) {
    return 'You kept the flame alive, $firstName!';
  }
  return 'Keep your streak alive today, $firstName.';
}

class _StreakHero extends StatelessWidget {
  final StreakDashboard dashboard;
  final String? displayName;
  const _StreakHero({required this.dashboard, required this.displayName});

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final firstName = _firstName(displayName);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        children: [
          Text(
            _heroPrompt(dashboard, firstName),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Metropolis',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: c.foreground80,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 176,
            height: 176,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 176,
                  height: 176,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF0A0A0A) : Colors.white,
                    border: Border.all(color: _StreakColors.fuchsia500, width: 10),
                    boxShadow: [
                      BoxShadow(
                        color: _StreakColors.fuchsia500.withValues(alpha: 0.10),
                        blurRadius: 0,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    '${dashboard.currentDays}',
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      color: isDark ? _StreakColors.fuchsia300 : _StreakColors.fuchsia600,
                    ),
                  ),
                ),
                Positioned(
                  top: -48,
                  child: Icon(
                    Icons.local_fire_department,
                    size: 96,
                    color: _StreakColors.orange500,
                    shadows: const [
                      Shadow(
                        color: Color(0x4DF97316),
                        blurRadius: 8,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            dashboard.currentDays == 1 ? 'DAY STREAK' : 'DAYS STREAK',
            style: TextStyle(
              fontFamily: 'Metropolis',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
              color: isDark ? const Color(0xFFFCD34D) : _StreakColors.amber700,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _StreakColors.amber400,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user, size: 16, color: _StreakColors.amber950),
                const SizedBox(width: 8),
                Text(
                  '${dashboard.availableFreezes} streak ${dashboard.availableFreezes == 1 ? 'freeze' : 'freezes'} available',
                  style: const TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _StreakColors.amber950,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.ac_unit, size: 16, color: _StreakColors.amber950),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _dayStatusLabel(String status) {
  switch (status) {
    case 'COMPLETED':
      return 'streak completed';
    case 'FROZEN':
      return 'streak protected by a freeze';
    case 'IN_PROGRESS':
      return 'streak in progress';
    case 'MISSED':
      return 'streak missed';
    default:
      return 'streak pending';
  }
}

class _WeeklyStreakStrip extends StatelessWidget {
  final List<StreakHistoryDay> days;
  final AppColorScheme c;
  const _WeeklyStreakStrip({required this.days, required this.c});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final last7 = days.length > 7 ? days.sublist(days.length - 7) : days;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: last7.map((day) => _dayCell(day, isDark)).toList(),
      ),
    );
  }

  Widget _dayCell(StreakHistoryDay day, bool isDark) {
    final done = day.status == 'COMPLETED';
    final frozen = day.status == 'FROZEN';

    Color borderColor;
    Color? bgColor;
    Color fgColor;
    if (done) {
      borderColor = _StreakColors.orange400;
      bgColor = isDark ? _StreakColors.orange950.withValues(alpha: 0.3) : _StreakColors.orange50;
      fgColor = _StreakColors.orange500;
    } else if (frozen) {
      borderColor = _StreakColors.cyan400;
      bgColor = isDark ? _StreakColors.cyan950.withValues(alpha: 0.3) : _StreakColors.cyan50;
      fgColor = _StreakColors.cyan600;
    } else if (day.isToday) {
      borderColor = _StreakColors.fuchsia500;
      bgColor = null;
      fgColor = isDark ? _StreakColors.fuchsia300 : _StreakColors.fuchsia600;
    } else {
      borderColor = isDark ? _StreakColors.neutral700 : _StreakColors.neutral300;
      bgColor = null;
      fgColor = borderColor;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          day.weekdayLabel.substring(0, day.weekdayLabel.length >= 2 ? 2 : day.weekdayLabel.length),
          style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, fontWeight: FontWeight.w500, color: c.mutedForeground),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: '${day.weekdayLabel}, ${_dayStatusLabel(day.status)}',
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              border: Border.all(color: borderColor),
            ),
            alignment: Alignment.center,
            child: done
                ? Icon(Icons.local_fire_department, size: 16, color: fgColor)
                : frozen
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user, size: 16, color: fgColor),
                          Icon(Icons.ac_unit, size: 12, color: fgColor),
                        ],
                      )
                    : null,
          ),
        ),
      ],
    );
  }
}

class _DailyGoalList extends StatelessWidget {
  final List<StreakGoalProgress> goals;
  final AppColorScheme c;
  const _DailyGoalList({required this.goals, required this.c});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Today's goals",
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, fontWeight: FontWeight.w700, color: c.foreground),
              ),
              Text(
                'Complete one to keep going',
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...goals.map((goal) => _goalRow(context, goal, isDark)),
        ],
      ),
    );
  }

  Widget _goalRow(BuildContext context, StreakGoalProgress goal, bool isDark) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        // Web navigates via goal.href; the matching in-app destinations
        // aren't all wired to deep-link from here yet, so this is a no-op
        // until each goal's screen supports being opened this way.
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: goal.complete
                    ? (isDark ? _StreakColors.emerald950.withValues(alpha: 0.4) : _StreakColors.emerald100)
                    : c.secondary,
              ),
              alignment: Alignment.center,
              child: Icon(
                goal.complete ? Icons.check : Icons.circle_outlined,
                size: 16,
                color: goal.complete
                    ? (isDark ? _StreakColors.emerald300 : _StreakColors.emerald700)
                    : c.mutedForeground,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                goal.label,
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, fontWeight: FontWeight.w500, color: c.foreground),
              ),
            ),
            Text(
              '${goal.label} ${goal.current}/${goal.target}',
              style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, fontWeight: FontWeight.w600, color: c.mutedForeground),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: c.mutedForeground),
          ],
        ),
      ),
    );
  }
}

class _NextMilestoneCard extends StatelessWidget {
  final int currentDays;
  final StreakMilestone? milestone;
  final bool isDark;
  const _NextMilestoneCard({required this.currentDays, required this.milestone, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF262626) : _StreakColors.neutral950;
    final milestone = this.milestone;

    if (milestone == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All streak milestones complete',
              style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            SizedBox(height: 4),
            Text(
              'Keep showing up and growing your personal best.',
              style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: Color(0xFFD4D4D4)),
            ),
          ],
        ),
      );
    }

    final progress = (currentDays / milestone.days).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
      child: Column(
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
                      'NEXT REWARD: ${milestone.days} DAYS',
                      style: const TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        color: _StreakColors.fuchsia300,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '${milestone.cowries} Cowries',
                          style: const TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFFE5E5E5)),
                        ),
                        const Text(
                          '  ·  ',
                          style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFF737373)),
                        ),
                        Text(
                          '${milestone.freezes} ',
                          style: const TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFFE5E5E5)),
                        ),
                        const Icon(Icons.ac_unit, size: 12, color: Color(0xFFE5E5E5)),
                        const Text(
                          ' streak freezes',
                          style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFFE5E5E5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.card_giftcard, size: 24, color: _StreakColors.amber300),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: Colors.white.withValues(alpha: 0.15)),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_StreakColors.fuchsia300, _StreakColors.amber300],
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
}

class _StreakAction extends StatelessWidget {
  final bool todayComplete;
  const _StreakAction({required this.todayComplete});

  @override
  Widget build(BuildContext context) {
    if (todayComplete) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFD1FAE5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          "Today's streak is complete",
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF065F46)),
        ),
      );
    }

    final c = AppColorScheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AwaQuizScreen(
                // TEMP: should eventually return to this Daily Streak
                // screen instead — routed to the Menu tab for now.
                onBack: () {
                  AppShell.goToMenu();
                  Navigator.of(context).popUntil(ModalRoute.withName('/home'));
                },
              ),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.primaryForeground,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: const Text(
          'Take AwaQuiz',
          style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
