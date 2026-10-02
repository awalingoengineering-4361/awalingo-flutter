enum AwaQuizDifficulty { beginner, intermediate, advanced }

extension AwaQuizDifficultyDetails on AwaQuizDifficulty {
  int get cowryCost => switch (this) {
    AwaQuizDifficulty.beginner => 20,
    AwaQuizDifficulty.intermediate => 30,
    AwaQuizDifficulty.advanced => 50,
  };

  int get secondsPerQuestion => switch (this) {
    AwaQuizDifficulty.beginner => 30,
    AwaQuizDifficulty.intermediate => 25,
    AwaQuizDifficulty.advanced => 20,
  };

  int get warningThreshold => this == AwaQuizDifficulty.advanced ? 5 : 10;
}

class AwaQuizQuestionBank {
  final int id;
  final AwaQuizDifficulty difficulty;
  final int questionCount;

  const AwaQuizQuestionBank({
    required this.id,
    required this.difficulty,
    required this.questionCount,
  });
}

class AwaQuizAttemptSnapshot {
  final int section;
  final int score;
  final int totalQuestions;
  final DateTime? submittedAt;

  const AwaQuizAttemptSnapshot({
    required this.section,
    required this.score,
    required this.totalQuestions,
    this.submittedAt,
  });

  bool get isPerfect =>
      submittedAt != null && totalQuestions > 0 && score == totalQuestions;
}

class AwaQuizStage {
  final int section;
  final String name;
  final AwaQuizDifficulty difficulty;
  final int setId;
  final int questionCount;
  final int attemptCount;
  final bool isUnlocked;

  const AwaQuizStage({
    required this.section,
    required this.name,
    required this.difficulty,
    required this.setId,
    required this.questionCount,
    required this.attemptCount,
    required this.isUnlocked,
  });

  String? get previousStageName =>
      section <= 1 ? null : _stageDefinitions[section - 2].name;
}

class _AwaQuizStageDefinition {
  final int section;
  final String name;
  final AwaQuizDifficulty difficulty;

  const _AwaQuizStageDefinition({
    required this.section,
    required this.name,
    required this.difficulty,
  });
}

const _stageDefinitions = [
  _AwaQuizStageDefinition(
    section: 1,
    name: 'JJC',
    difficulty: AwaQuizDifficulty.beginner,
  ),
  _AwaQuizStageDefinition(
    section: 2,
    name: 'Sabi Player',
    difficulty: AwaQuizDifficulty.beginner,
  ),
  _AwaQuizStageDefinition(
    section: 3,
    name: 'Shugaba',
    difficulty: AwaQuizDifficulty.intermediate,
  ),
  _AwaQuizStageDefinition(
    section: 4,
    name: 'Odogwu',
    difficulty: AwaQuizDifficulty.intermediate,
  ),
  _AwaQuizStageDefinition(
    section: 5,
    name: 'Idan',
    difficulty: AwaQuizDifficulty.advanced,
  ),
  _AwaQuizStageDefinition(
    section: 6,
    name: 'Ancestor',
    difficulty: AwaQuizDifficulty.advanced,
  ),
];

// Mirrors getStageName (lib/streaks/service.ts): resolves the human stage
// label for a raw (difficulty, section) pair read straight from
// community_quiz_attempts — used by the Profile "Level" stat, which reads
// the user's single highest-ranked attempt directly rather than going
// through the unlocked-stage list buildAwaQuizStages produces. Falls back to
// DEFAULT_STAGE_BY_DIFFICULTY when section isn't one of the canonical 1-6
// stages (e.g. legacy/ad-hoc quiz data).
String stageNameForQuizProgress(String difficulty, int section) {
  for (final def in _stageDefinitions) {
    if (def.section == section) return def.name;
  }
  return switch (difficulty.toUpperCase()) {
    'INTERMEDIATE' => 'Shugaba',
    'ADVANCED' => 'Idan',
    _ => 'Sabi Player',
  };
}

List<AwaQuizStage> buildAwaQuizStages({
  required List<AwaQuizQuestionBank> banks,
  required List<AwaQuizAttemptSnapshot> attempts,
}) {
  final banksByDifficulty = {for (final bank in banks) bank.difficulty: bank};
  final attemptsBySection = <int, int>{};
  final perfectSections = <int>{};

  for (final attempt in attempts) {
    attemptsBySection.update(
      attempt.section,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    if (attempt.isPerfect) {
      perfectSections.add(attempt.section);
    }
  }

  return _stageDefinitions
      .expand((definition) {
        final bank = banksByDifficulty[definition.difficulty];
        if (bank == null) {
          return const <AwaQuizStage>[];
        }

        return [
          AwaQuizStage(
            section: definition.section,
            name: definition.name,
            difficulty: definition.difficulty,
            setId: bank.id,
            questionCount: bank.questionCount,
            attemptCount: attemptsBySection[definition.section] ?? 0,
            isUnlocked:
                definition.section == 1 ||
                perfectSections.contains(definition.section - 1),
          ),
        ];
      })
      .toList(growable: false);
}
