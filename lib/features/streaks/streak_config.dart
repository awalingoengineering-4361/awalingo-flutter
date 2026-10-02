// Mirrors neolingo/src/lib/streaks/config.ts exactly — this is the single
// source of truth for daily-streak goal thresholds and milestone rewards on
// web, and the RPC functions on Postgres (get_streak_dashboard /
// record_streak_activity) are hand-written to match these same values, so
// any change here must be mirrored there too.

class StreakGoalConfig {
  final String activityType;
  final String label;
  final String href;
  final int threshold;

  const StreakGoalConfig({
    required this.activityType,
    required this.label,
    required this.href,
    required this.threshold,
  });
}

const List<StreakGoalConfig> kStreakGoals = [
  StreakGoalConfig(
    activityType: 'AWAQUIZ_SUBMIT',
    label: 'AwaQuiz',
    href: '/awaquiz',
    threshold: 1,
  ),
  StreakGoalConfig(
    activityType: 'CURATE_NEO',
    label: 'Curate',
    href: '/curation-lounge',
    threshold: 1,
  ),
  StreakGoalConfig(
    activityType: 'VOTE_NEO',
    label: 'Votes',
    href: '/vote',
    threshold: 3,
  ),
  StreakGoalConfig(
    activityType: 'JURY_RATE_NEO',
    label: 'Jury ratings',
    href: '/jury',
    threshold: 3,
  ),
  StreakGoalConfig(
    activityType: 'REQUEST_NEO',
    label: 'Requests',
    href: '/dictionary/request',
    threshold: 2,
  ),
];

class StreakMilestoneConfig {
  final int days;
  final int cowries;
  final int freezes;

  const StreakMilestoneConfig({
    required this.days,
    required this.cowries,
    required this.freezes,
  });
}

const List<StreakMilestoneConfig> kStreakMilestones = [
  StreakMilestoneConfig(days: 10, cowries: 10, freezes: 0),
  StreakMilestoneConfig(days: 25, cowries: 25, freezes: 1),
  StreakMilestoneConfig(days: 50, cowries: 50, freezes: 1),
  StreakMilestoneConfig(days: 75, cowries: 75, freezes: 2),
  StreakMilestoneConfig(days: 100, cowries: 100, freezes: 2),
  StreakMilestoneConfig(days: 200, cowries: 200, freezes: 3),
  StreakMilestoneConfig(days: 300, cowries: 300, freezes: 3),
  StreakMilestoneConfig(days: 365, cowries: 365, freezes: 3),
  StreakMilestoneConfig(days: 500, cowries: 500, freezes: 3),
  StreakMilestoneConfig(days: 750, cowries: 750, freezes: 3),
  StreakMilestoneConfig(days: 1000, cowries: 1000, freezes: 3),
];
