import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/streaks/streak_models.dart';
import '../../features/streaks/streak_repository.dart';
import '../../services/auth_provider.dart';
import '../../services/route_observer.dart';
import '../../theme/app_theme.dart';
import '../app_shell.dart';

// Hardcoded Tailwind brand accents this feature uses that have no existing
// AppColors token (fuchsia/orange/amber/cyan/emerald), kept local to this
// screen since nothing else in the app uses them. Values are Tailwind's
// default palette so they match neolingo's daily-streak page exactly.
class _StreakColors {
  static const fuchsia300 = Color(0xFFF0ABFC);
  static const orange500 = Color(0xFFF97316);
  static const amber300 = Color(0xFFFCD34D);
  static const amber400 = Color(0xFFFBBF24);
  static const amber950 = Color(0xFF451A03);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald300 = Color(0xFFA7F3D0);
  static const emerald700 = Color(0xFF047857);
  static const emerald950 = Color(0xFF022C22);
  static const neutral950 = Color(0xFF0A0A0A);
}

class DailyStreakScreen extends StatefulWidget {
  const DailyStreakScreen({super.key});

  @override
  State<DailyStreakScreen> createState() => _DailyStreakScreenState();
}

class _DailyStreakScreenState extends State<DailyStreakScreen> with RouteAware {
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
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  // Mirrors web's refetchOnMount: there's no live subscription on web
  // either (see useStreakDashboardQuery), it just refetches whenever this
  // query re-subscribes. didPopNext fires when a screen pushed from here
  // (e.g. a goal's linked Vote/Translate screen) is popped back to this
  // one, so completing a goal elsewhere and returning shows the updated
  // streak immediately instead of the numbers from before that action.
  @override
  void didPopNext() => _load();

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
        _WeeklyStreakStrip(
          days: dashboard.history,
          availableFreezes: dashboard.availableFreezes,
          currentDays: dashboard.currentDays,
          c: c,
        ),
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

// Mirrors StreakHero.tsx (neolingo: src/components/streaks/StreakHero.tsx)
// after the Figma redesign (commits 7081c7e/eb5e054): gradient ring + the
// literal streak-hero-flame.svg illustration + rotated gradient "day(s)
// streak" badge, replacing the old plain-bordered-circle + Material icon
// version. Pixel offsets below are transcribed from the web component's
// literal CSS (translateX/scale/rotate values); the web team itself needed
// four follow-up commits to tune the flame's exact scale/offset, so treat
// these as a faithful starting point rather than assumed-exact.
const double _kHeroRingSize = 190;
const double _kHeroInnerCircleSize = 166.25;
const double _kHeroFlameWidth = 127.278 * 0.4;
const double _kHeroFlameHeight = 162.28 * 0.4;
const double _kHeroBadgeWidth = 189;
const double _kHeroBadgeHeight = 43;

class _StreakHero extends StatelessWidget {
  final StreakDashboard dashboard;
  final String? displayName;
  const _StreakHero({required this.dashboard, required this.displayName});

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final firstName = _firstName(displayName);
    // CSS `bottom: -8px` on the 43px badge within the 190px ring box: its
    // bottom edge sits 8px past the ring's own bottom edge.
    const badgeTop = _kHeroRingSize + 8 - _kHeroBadgeHeight;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Decorative blurred glow behind the ring (bg-fuchsia-100/70 blur-3xl).
          Positioned(
            top: 76,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF4A044E) : const Color(0xFFFAE8FF))
                        .withValues(alpha: isDark ? 0.3 : 0.7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          Column(
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
              const SizedBox(height: 96),
              SizedBox(
                width: _kHeroRingSize,
                height: badgeTop + _kHeroBadgeHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 0,
                      child: Container(
                        width: _kHeroRingSize,
                        height: _kHeroRingSize,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFB535CA), Color(0xFFF0EDED)],
                          ),
                          boxShadow: [
                            BoxShadow(color: Color(0x1A000000), blurRadius: 30, offset: Offset(0, 24)),
                            BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 10)),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: _kHeroInnerCircleSize,
                          height: _kHeroInnerCircleSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? const Color(0xFF0A0A0A) : Colors.white,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${dashboard.currentDays}',
                            style: const TextStyle(
                              fontFamily: 'Parkinsans',
                              fontSize: 95,
                              fontWeight: FontWeight.w600,
                              height: 1.0,
                              color: Color(0xFFB535CA),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // `top:-136px` + `scale-[.4]` with a bottom transform-origin:
                    // the flame's pre-scale bottom edge (-136 + 162.28 = 26.28px
                    // from the ring's top) stays anchored as the scale shrinks it.
                    Positioned(
                      top: 26.28 - _kHeroFlameHeight,
                      left: (_kHeroRingSize - _kHeroFlameWidth) / 2,
                      width: _kHeroFlameWidth,
                      height: _kHeroFlameHeight,
                      child: SvgPicture.asset('assets/streaks/streak-hero-flame.svg'),
                    ),
                    Positioned(
                      top: badgeTop,
                      left: (_kHeroRingSize - _kHeroBadgeWidth) / 2,
                      child: Transform.rotate(
                        angle: -1 * 3.14159265 / 180,
                        child: Container(
                          width: _kHeroBadgeWidth,
                          height: _kHeroBadgeHeight,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 26),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF6BE39), Color(0xFF795900), Color(0xFFF6BE39)],
                              stops: [0, 0.5, 1],
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
                            boxShadow: const [
                              BoxShadow(color: Color(0x1A000000), blurRadius: 15, offset: Offset(0, 10)),
                              BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4)),
                            ],
                          ),
                          child: Text(
                            dashboard.currentDays == 1 ? 'DAY STREAK' : 'DAYS STREAK',
                            style: const TextStyle(
                              fontFamily: 'Metropolis',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _StreakColors.amber400,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4))],
                ),
                child: Text(
                  '${dashboard.availableFreezes} streak ${dashboard.availableFreezes == 1 ? 'freeze' : 'freezes'} available',
                  style: const TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _StreakColors.amber950,
                  ),
                ),
              ),
            ],
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

bool _isTrackedStreakDay(StreakHistoryDay day) => day.status == 'COMPLETED' || day.status == 'FROZEN';

// Mirrors WeeklyStreakStrip.tsx after the Figma redesign (commit
// 2a7643e): bordered card, a salmon "trail" background connecting
// consecutive tracked (COMPLETED/FROZEN) days with rounded end-caps, the
// new weekly-fire.svg/fire-shield.svg day icons, and a footer row (streak
// length + one freeze icon per available freeze) that didn't exist before.
class _WeeklyStreakStrip extends StatelessWidget {
  final List<StreakHistoryDay> days;
  final int availableFreezes;
  final int currentDays;
  final AppColorScheme c;
  const _WeeklyStreakStrip({
    required this.days,
    required this.availableFreezes,
    required this.currentDays,
    required this.c,
  });

  static const _trailColor = Color(0xFFFFE8E0);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF171717) : Colors.white;
    final displayedDays = days.length > 7 ? days.sublist(days.length - 7) : days;
    final firstTracked = displayedDays.indexWhere(_isTrackedStreakDay);
    final lastTracked = displayedDays.lastIndexWhere(_isTrackedStreakDay);
    // Only flags a trail continuing in from before the visible window —
    // there's no equivalent "continues after" case since the window always
    // ends on today.
    final continuesFromEarlier = firstTracked == 0 && currentDays > 1;
    final streakLabel = '$currentDays day${currentDays == 1 ? '' : 's'}';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF262626) : const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(width: 12, height: 48, color: continuesFromEarlier ? _trailColor : cardColor),
                ...List.generate(displayedDays.length, (i) {
                  final day = displayedDays[i];
                  return Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          day.weekdayLabel.substring(0, day.weekdayLabel.length >= 2 ? 2 : day.weekdayLabel.length),
                          style: TextStyle(
                            fontFamily: 'Metropolis',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark ? const Color(0xFFFAFAFA) : const Color(0xFF030712),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 48,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _isTrackedStreakDay(day) ? _trailColor : null,
                            borderRadius: BorderRadius.horizontal(
                              left: i == firstTracked ? const Radius.circular(999) : Radius.zero,
                              right: i == lastTracked ? const Radius.circular(999) : Radius.zero,
                            ),
                          ),
                          child: Semantics(
                            label: '${day.weekdayLabel}, ${_dayStatusLabel(day.status)}',
                            child: Container(
                              width: 40,
                              height: 40,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: cardColor,
                                border: Border.all(color: _dayBorderColor(day), width: 1.5),
                              ),
                              child: _dayIndicator(day),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                Container(width: 12, height: 48, color: cardColor),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    SvgPicture.asset('assets/streaks/summary-fire.svg', width: 20, height: 20),
                    const SizedBox(width: 8),
                    Text(
                      streakLabel,
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark ? const Color(0xFFFAFAFA) : const Color(0xFF030712),
                      ),
                    ),
                  ],
                ),
                if (availableFreezes > 0)
                  Semantics(
                    label: '$availableFreezes streak ${availableFreezes == 1 ? 'freeze' : 'freezes'} available',
                    child: Row(
                      children: List.generate(
                        availableFreezes,
                        (i) => Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                          child: SvgPicture.asset('assets/streaks/fire-shield.svg', width: 20, height: 20),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _dayBorderColor(StreakHistoryDay day) {
    if (day.status == 'COMPLETED') return const Color(0xFFDE9300);
    if (day.status == 'FROZEN') return const Color(0xFF38BDF8);
    if (day.status == 'MISSED') return const Color(0xFFA30202);
    if (day.isToday) return const Color(0xFFDE9300);
    return const Color(0xFFAAB0BB);
  }

  Widget? _dayIndicator(StreakHistoryDay day) {
    if (day.status == 'COMPLETED') {
      return SvgPicture.asset('assets/streaks/weekly-fire.svg', width: 24, height: 24);
    }
    if (day.status == 'FROZEN') {
      return SvgPicture.asset('assets/streaks/fire-shield.svg', width: 20, height: 20);
    }
    return null;
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
          // AwaQuiz is a tab inside AppShell's own Scaffold, not a
          // standalone route — it has no Scaffold/Material of its own, so
          // pushing it directly here left its Text widgets with no Material
          // ancestor (Flutter's debug fallback renders that as yellow,
          // underlined text). Switch AppShell to the quiz tab and pop back
          // to it instead.
          // TEMP: should eventually return to this Daily Streak screen
          // instead — routed to the Menu tab for now (AppShell's own
          // AwaQuizScreen instance always calls back to Menu).
          AppShell.goToQuiz();
          Navigator.of(context).popUntil(ModalRoute.withName('/home'));
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
