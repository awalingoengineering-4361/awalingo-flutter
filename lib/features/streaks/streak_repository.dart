import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../awaquiz/awaquiz_progression.dart';
import 'streak_models.dart';

const Map<String, int> _kAwaquizDifficultyRank = {
  'BEGINNER': 1,
  'INTERMEDIATE': 2,
  'ADVANCED': 3,
};

/// IANA time zone name for this device (e.g. "Africa/Lagos"), mirroring
/// getBrowserTimeZone() (streaks/calendar.ts) which reads
/// Intl.DateTimeFormat().resolvedOptions().timeZone on web. The Postgres
/// side (get_streak_dashboard / record_streak_activity) falls back to UTC
/// if this string isn't a recognized zone, same as normalizeTimeZone().
Future<String> currentStreakTimeZone() async {
  try {
    return await FlutterTimezone.getLocalTimezone();
  } catch (_) {
    return 'UTC';
  }
}

class StreakRepository {
  final SupabaseClient _db;

  StreakRepository(this._db);

  Future<StreakDashboard> fetchDashboard(String userId, String timeZone) async {
    final dashboardJson = await _db.rpc(
      'get_streak_dashboard',
      params: {'p_time_zone': timeZone},
    ) as Map<String, dynamic>;
    final progress = await _highestQuizProgress(userId);
    return StreakDashboard.fromJson(
      dashboardJson,
      level: progress.level,
      levelName: progress.levelName,
    );
  }

  // Mirrors getHighestQuizProgress (streaks/service.ts) — same query/logic
  // already used by ProfileScreen's _highestQuizProgress.
  Future<({String? level, String? levelName})> _highestQuizProgress(
    String userId,
  ) async {
    final rows = await _db
        .from('community_quiz_attempts')
        .select('difficulty, section, submittedAt')
        .eq('userId', userId);
    final submitted = rows.where((r) => r['submittedAt'] != null).toList();
    if (submitted.isEmpty) return (level: null, levelName: null);

    int rank(String d) => _kAwaquizDifficultyRank[d] ?? 0;
    submitted.sort((a, b) {
      final byRank = rank(
        b['difficulty'] as String,
      ).compareTo(rank(a['difficulty'] as String));
      if (byRank != 0) return byRank;
      return (b['section'] as int).compareTo(a['section'] as int);
    });
    final top = submitted.first;
    final level = top['difficulty'] as String;
    return (
      level: level,
      levelName: stageNameForQuizProgress(level, top['section'] as int),
    );
  }

  /// Fire-and-forget: records one unit of progress toward today's streak
  /// goals. Mirrors recordStreakActivity (streaks/service.ts), called after
  /// AwaQuiz submission, curating a Neo, voting, jury rating, or requesting
  /// a word. Deliberately swallows errors — a streak-recording failure
  /// should never surface as a failure of the action the user just took,
  /// same spirit as the existing rpc()/debugPrint error handling elsewhere
  /// in this app (e.g. VoteScreen.deferVote).
  Future<void> recordActivity({
    required String activityType,
    required String sourceId,
    required String timeZone,
  }) async {
    try {
      await _db.rpc('record_streak_activity', params: {
        'p_activity_type': activityType,
        'p_source_id': sourceId,
        'p_time_zone': timeZone,
      });
    } catch (e) {
      debugPrint('recordStreakActivity($activityType, $sourceId): $e');
    }
  }
}
