import 'package:supabase_flutter/supabase_flutter.dart';

// Based on getDailyWord/getWordOfTheDayForLanguage (neolingo/src/actions/wotd.ts),
// still a deterministic, date-rotating pick — but deliberately personalized
// for this app (not a web behavior): the voting word additionally excludes
// any term the current user has already voted on (same `votes` table check
// the Voting Lounge itself uses), so the card shown here never points at a
// term that's already unavailable to vote on. suggestWord is unchanged from
// web's algorithm.
// `type` is 'suggestion' or 'voting'.

class DailyWord {
  final int id;
  final String text;
  const DailyWord(this.id, this.text);
}

const DailyWord _kFallbackWord = DailyWord(0, 'Awalingo');

Future<int?> _englishLanguageId(SupabaseClient db) async {
  final row = await db
      .from('languages')
      .select('id')
      .eq('code', 'eng')
      .maybeSingle();
  return row?['id'] as int?;
}

Future<Set<int>> _votedTermIds(SupabaseClient db, String userId) async {
  final rows = await db.from('votes').select('termId').eq('userId', userId);
  return rows.map((r) => r['termId'] as int).toSet();
}

Future<Set<int>> _termIdsWithNeos(
  SupabaseClient db,
  int neoLanguageId, {
  bool ratedOnly = false,
}) async {
  var query = db.from('neos').select('termId').eq('languageId', neoLanguageId);
  final rows = ratedOnly ? await query.gt('ratingCount', 0) : await query;
  return rows.map((r) => r['termId'] as int).toSet();
}

Future<List<Map<String, dynamic>>> _termsInLanguage(
  SupabaseClient db,
  int languageId,
) =>
    db
        .from('terms')
        .select('id, text')
        .eq('languageId', languageId)
        .isFilter('withdrawnAt', null)
        .order('id');

DailyWord? _pick(List<Map<String, dynamic>> terms, int dayIndex, int offsetMultiplier) {
  if (terms.isEmpty) return null;
  final skip = (dayIndex * offsetMultiplier) % terms.length;
  final row = terms[skip];
  return DailyWord(row['id'] as int, row['text'] as String);
}

Future<DailyWord?> _wordOfTheDayForLanguage(
  SupabaseClient db, {
  required int languageId,
  required int offsetMultiplier,
  required String type, // 'suggestion' | 'voting'
  required int neoLanguageId,
  required int dayIndex,
  Set<int> excludeTermIds = const {},
}) async {
  var allInLanguage = await _termsInLanguage(db, languageId);
  if (type == 'voting' && excludeTermIds.isNotEmpty) {
    allInLanguage =
        allInLanguage.where((t) => !excludeTermIds.contains(t['id'] as int)).toList();
  }

  List<Map<String, dynamic>> strict;
  if (type == 'voting') {
    final ratedIds = await _termIdsWithNeos(db, neoLanguageId, ratedOnly: true);
    strict = allInLanguage.where((t) => ratedIds.contains(t['id'] as int)).toList();
  } else {
    final anyIds = await _termIdsWithNeos(db, neoLanguageId);
    strict = allInLanguage.where((t) => !anyIds.contains(t['id'] as int)).toList();
  }

  if (strict.isNotEmpty) return _pick(strict, dayIndex, offsetMultiplier);

  // Strict filter matched nothing.
  if (type == 'voting') {
    // For voting, try terms with any neo (regardless of rating) before
    // widening further, so the vote card always has something to vote on.
    final anyNeoIds = await _termIdsWithNeos(db, neoLanguageId);
    final withAnyNeo =
        allInLanguage.where((t) => anyNeoIds.contains(t['id'] as int)).toList();
    final picked = _pick(withAnyNeo, dayIndex, offsetMultiplier);
    if (picked != null) return picked;
  }

  // Final widening: any term in this language.
  return _pick(allInLanguage, dayIndex, offsetMultiplier);
}

Future<({DailyWord suggestWord, DailyWord voteWord})> getDailyWord(
  SupabaseClient db, {
  required String userId,
  int? communityLanguageId,
}) async {
  try {
    final englishLanguageId = await _englishLanguageId(db);
    final votedTermIds = await _votedTermIds(db, userId);
    final dayIndex = DateTime.now().millisecondsSinceEpoch ~/ 86400000;

    int? activeLanguageId = englishLanguageId;
    int? neoLanguageId = communityLanguageId ?? englishLanguageId;
    if (communityLanguageId != null && communityLanguageId != englishLanguageId) {
      if (dayIndex % 2 != 0) {
        activeLanguageId = communityLanguageId;
        neoLanguageId = englishLanguageId;
      }
    }

    DailyWord? suggestWord;
    DailyWord? voteWord;

    if (activeLanguageId != null && neoLanguageId != null) {
      suggestWord = await _wordOfTheDayForLanguage(
        db,
        languageId: activeLanguageId,
        offsetMultiplier: 1,
        type: 'suggestion',
        neoLanguageId: neoLanguageId,
        dayIndex: dayIndex,
      );
      voteWord = await _wordOfTheDayForLanguage(
        db,
        languageId: activeLanguageId,
        offsetMultiplier: 3,
        type: 'voting',
        neoLanguageId: neoLanguageId,
        dayIndex: dayIndex,
        excludeTermIds: votedTermIds,
      );
    }

    if (activeLanguageId != englishLanguageId && englishLanguageId != null) {
      final fallbackNeoLanguageId = communityLanguageId ?? englishLanguageId;
      voteWord ??= await _wordOfTheDayForLanguage(
        db,
        languageId: englishLanguageId,
        offsetMultiplier: 3,
        type: 'voting',
        neoLanguageId: fallbackNeoLanguageId,
        dayIndex: dayIndex,
        excludeTermIds: votedTermIds,
      );
      suggestWord ??= await _wordOfTheDayForLanguage(
        db,
        languageId: englishLanguageId,
        offsetMultiplier: 1,
        type: 'suggestion',
        neoLanguageId: fallbackNeoLanguageId,
        dayIndex: dayIndex,
      );
    }

    return (
      suggestWord: suggestWord ?? _kFallbackWord,
      voteWord: voteWord ?? _kFallbackWord,
    );
  } catch (_) {
    return (suggestWord: _kFallbackWord, voteWord: _kFallbackWord);
  }
}
