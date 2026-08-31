import 'package:awalingo/features/awaquiz/awaquiz_progression.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const banks = [
    AwaQuizQuestionBank(
      id: 33,
      difficulty: AwaQuizDifficulty.advanced,
      questionCount: 8,
    ),
    AwaQuizQuestionBank(
      id: 11,
      difficulty: AwaQuizDifficulty.beginner,
      questionCount: 10,
    ),
    AwaQuizQuestionBank(
      id: 22,
      difficulty: AwaQuizDifficulty.intermediate,
      questionCount: 12,
    ),
  ];

  group('buildAwaQuizStages', () {
    test('expands three difficulty banks into the six product stages', () {
      final stages = buildAwaQuizStages(banks: banks, attempts: const []);

      expect(
        stages
            .map(
              (stage) => (
                stage.section,
                stage.name,
                stage.difficulty,
                stage.setId,
                stage.questionCount,
              ),
            )
            .toList(),
        [
          (1, 'JJC', AwaQuizDifficulty.beginner, 11, 10),
          (2, 'Sabi Player', AwaQuizDifficulty.beginner, 11, 10),
          (3, 'Shugaba', AwaQuizDifficulty.intermediate, 22, 12),
          (4, 'Odogwu', AwaQuizDifficulty.intermediate, 22, 12),
          (5, 'Idan', AwaQuizDifficulty.advanced, 33, 8),
          (6, 'Ancestor', AwaQuizDifficulty.advanced, 33, 8),
        ],
      );
      expect(stages.map((stage) => stage.isUnlocked).toList(), [
        true,
        false,
        false,
        false,
        false,
        false,
      ]);
    });

    test('only exposes stages backed by an available question bank', () {
      final stages = buildAwaQuizStages(
        banks: const [
          AwaQuizQuestionBank(
            id: 11,
            difficulty: AwaQuizDifficulty.beginner,
            questionCount: 10,
          ),
          AwaQuizQuestionBank(
            id: 33,
            difficulty: AwaQuizDifficulty.advanced,
            questionCount: 8,
          ),
        ],
        attempts: const [],
      );

      expect(stages.map((stage) => stage.section).toList(), [1, 2, 5, 6]);
      expect(stages.map((stage) => stage.isUnlocked).toList(), [
        true,
        false,
        false,
        false,
      ]);
    });

    test(
      'requires a submitted perfect score on the immediately previous stage',
      () {
        final stages = buildAwaQuizStages(
          banks: banks,
          attempts: [
            AwaQuizAttemptSnapshot(
              section: 1,
              score: 9,
              totalQuestions: 10,
              submittedAt: DateTime.utc(2026, 8, 30),
            ),
            AwaQuizAttemptSnapshot(
              section: 1,
              score: 0,
              totalQuestions: 0,
              submittedAt: DateTime.utc(2026, 8, 31),
            ),
            const AwaQuizAttemptSnapshot(
              section: 2,
              score: 10,
              totalQuestions: 10,
            ),
          ],
        );

        expect(stages[0].isUnlocked, isTrue);
        expect(stages[1].isUnlocked, isFalse);
        expect(stages[2].isUnlocked, isFalse);
      },
    );

    test('preserves completed history when the same user starts again', () {
      final stages = buildAwaQuizStages(
        banks: banks,
        attempts: [
          AwaQuizAttemptSnapshot(
            section: 1,
            score: 10,
            totalQuestions: 10,
            submittedAt: DateTime.utc(2026, 8, 29),
          ),
          AwaQuizAttemptSnapshot(
            section: 1,
            score: 7,
            totalQuestions: 10,
            submittedAt: DateTime.utc(2026, 8, 30),
          ),
          const AwaQuizAttemptSnapshot(section: 1, score: 0, totalQuestions: 0),
        ],
      );

      expect(stages[0].attemptCount, 3);
      expect(stages[1].isUnlocked, isTrue);
      expect(stages[1].attemptCount, 0);
    });
  });
}
