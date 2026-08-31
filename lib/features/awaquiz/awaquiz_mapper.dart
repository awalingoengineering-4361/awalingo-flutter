import 'awaquiz_progression.dart';

class AwaQuizOverview {
  final List<AwaQuizStage> stages;
  final int cowryBalance;

  const AwaQuizOverview({required this.stages, required this.cowryBalance});
}

AwaQuizOverview mapAwaQuizOverview({
  required List<Map<String, dynamic>> setRows,
  required Set<int> questionSetIds,
  required List<Map<String, dynamic>> attemptRows,
  required int cowryBalance,
}) {
  final banks = setRows
      .expand((row) {
        final id = row['id'];
        final difficultyValue = row['difficulty'];
        if (id is! int ||
            difficultyValue is! String ||
            !questionSetIds.contains(id)) {
          return const <AwaQuizQuestionBank>[];
        }

        final difficulty = _parseDifficulty(difficultyValue);
        if (difficulty == null) {
          return const <AwaQuizQuestionBank>[];
        }

        final configuredQuestionCount = row['questionCount'];
        final questionCount =
            configuredQuestionCount is int && configuredQuestionCount > 0
            ? configuredQuestionCount
            : 10;

        return [
          AwaQuizQuestionBank(
            id: id,
            difficulty: difficulty,
            questionCount: questionCount,
          ),
        ];
      })
      .toList(growable: false);

  final attempts = attemptRows
      .expand((row) {
        final section = row['section'];
        final score = row['score'];
        final totalQuestions = row['totalQuestions'];
        if (section is! int || score is! int || totalQuestions is! int) {
          return const <AwaQuizAttemptSnapshot>[];
        }

        return [
          AwaQuizAttemptSnapshot(
            section: section,
            score: score,
            totalQuestions: totalQuestions,
            submittedAt: _parseDateTime(row['submittedAt']),
          ),
        ];
      })
      .toList(growable: false);

  return AwaQuizOverview(
    stages: buildAwaQuizStages(banks: banks, attempts: attempts),
    cowryBalance: cowryBalance,
  );
}

DateTime? _parseDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

AwaQuizDifficulty? _parseDifficulty(String value) =>
    switch (value.trim().toUpperCase()) {
      'BEGINNER' => AwaQuizDifficulty.beginner,
      'INTERMEDIATE' => AwaQuizDifficulty.intermediate,
      'ADVANCED' => AwaQuizDifficulty.advanced,
      _ => null,
    };

String _serializeDifficulty(AwaQuizDifficulty difficulty) =>
    switch (difficulty) {
      AwaQuizDifficulty.beginner => 'BEGINNER',
      AwaQuizDifficulty.intermediate => 'INTERMEDIATE',
      AwaQuizDifficulty.advanced => 'ADVANCED',
    };

Map<String, Object> buildAwaQuizAttemptInsert({
  required String userId,
  required int languageId,
  required AwaQuizStage stage,
}) => {
  'userId': userId,
  'languageId': languageId,
  'setId': stage.setId,
  'difficulty': _serializeDifficulty(stage.difficulty),
  'section': stage.section,
  'score': 0,
  'totalQuestions': 0,
  'entryCostCowries': stage.difficulty.cowryCost,
};
