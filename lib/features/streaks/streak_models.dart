// Mirrors neolingo/src/lib/streaks/types.ts.

class StreakGoalProgress {
  final String activityType;
  final String label;
  final String href;
  final int current;
  final int target;
  final bool complete;

  const StreakGoalProgress({
    required this.activityType,
    required this.label,
    required this.href,
    required this.current,
    required this.target,
    required this.complete,
  });

  factory StreakGoalProgress.fromJson(Map<String, dynamic> json) =>
      StreakGoalProgress(
        activityType: json['activityType'] as String,
        label: json['label'] as String,
        href: json['href'] as String,
        current: json['current'] as int,
        target: json['target'] as int,
        complete: json['complete'] as bool,
      );
}

// 'IN_PROGRESS' | 'COMPLETED' | 'FROZEN' | 'MISSED' | 'PENDING'
class StreakHistoryDay {
  final String dateKey;
  final String weekdayLabel;
  final String status;
  final bool isToday;

  const StreakHistoryDay({
    required this.dateKey,
    required this.weekdayLabel,
    required this.status,
    required this.isToday,
  });

  factory StreakHistoryDay.fromJson(Map<String, dynamic> json) =>
      StreakHistoryDay(
        dateKey: json['dateKey'] as String,
        weekdayLabel: json['weekdayLabel'] as String,
        status: json['status'] as String,
        isToday: json['isToday'] as bool,
      );
}

class StreakMilestone {
  final int days;
  final int cowries;
  final int freezes;

  const StreakMilestone({
    required this.days,
    required this.cowries,
    required this.freezes,
  });

  factory StreakMilestone.fromJson(Map<String, dynamic> json) =>
      StreakMilestone(
        days: json['days'] as int,
        cowries: json['cowries'] as int,
        freezes: json['freezes'] as int,
      );
}

class StreakDashboard {
  final int currentDays;
  final int longestDays;
  final int availableFreezes;
  final String timeZone;
  final bool todayComplete;
  final List<StreakGoalProgress> goals;
  final List<StreakHistoryDay> history;
  final StreakMilestone? nextMilestone;
  final String? level;
  final String? levelName;

  const StreakDashboard({
    required this.currentDays,
    required this.longestDays,
    required this.availableFreezes,
    required this.timeZone,
    required this.todayComplete,
    required this.goals,
    required this.history,
    required this.nextMilestone,
    this.level,
    this.levelName,
  });

  factory StreakDashboard.fromJson(
    Map<String, dynamic> json, {
    String? level,
    String? levelName,
  }) {
    return StreakDashboard(
      currentDays: json['currentDays'] as int,
      longestDays: json['longestDays'] as int,
      availableFreezes: json['availableFreezes'] as int,
      timeZone: json['timeZone'] as String,
      todayComplete: json['todayComplete'] as bool,
      goals: (json['goals'] as List<dynamic>? ?? [])
          .map((g) => StreakGoalProgress.fromJson(g as Map<String, dynamic>))
          .toList(),
      history: (json['history'] as List<dynamic>? ?? [])
          .map((d) => StreakHistoryDay.fromJson(d as Map<String, dynamic>))
          .toList(),
      nextMilestone: json['nextMilestone'] == null
          ? null
          : StreakMilestone.fromJson(
              json['nextMilestone'] as Map<String, dynamic>,
            ),
      level: level,
      levelName: levelName,
    );
  }
}
