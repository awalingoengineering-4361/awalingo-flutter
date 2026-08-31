import 'package:awalingo/features/awaquiz/awaquiz_mapper.dart';
import 'package:awalingo/features/awaquiz/awaquiz_progression.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps Supabase rows into six section-scoped stages', () {
    final overview = mapAwaQuizOverview(
      setRows: const [
        {'id': 11, 'difficulty': 'BEGINNER', 'questionCount': 10},
        {'id': 22, 'difficulty': 'INTERMEDIATE', 'questionCount': 12},
        {'id': 33, 'difficulty': 'ADVANCED', 'questionCount': 8},
      ],
      questionSetIds: const {11, 22, 33},
      attemptRows: const [
        {
          'section': 1,
          'score': 10,
          'totalQuestions': 10,
          'submittedAt': '2026-08-30T12:00:00.000Z',
        },
        {'section': 2, 'score': 0, 'totalQuestions': 0, 'submittedAt': null},
      ],
      cowryBalance: 90,
    );

    expect(overview.cowryBalance, 90);
    expect(overview.stages.map((stage) => stage.section).toList(), [
      1,
      2,
      3,
      4,
      5,
      6,
    ]);
    expect(overview.stages.map((stage) => stage.attemptCount).toList(), [
      1,
      1,
      0,
      0,
      0,
      0,
    ]);
    expect(overview.stages.map((stage) => stage.isUnlocked).toList(), [
      true,
      true,
      false,
      false,
      false,
      false,
    ]);
  });

  test('filters empty and malformed question banks at the data boundary', () {
    final overview = mapAwaQuizOverview(
      setRows: const [
        {'id': 11, 'difficulty': 'BEGINNER', 'questionCount': null},
        {'id': 22, 'difficulty': 'INTERMEDIATE', 'questionCount': 12},
        {'id': 33, 'difficulty': 'UNKNOWN', 'questionCount': 8},
      ],
      questionSetIds: const {11, 33},
      attemptRows: const [],
      cowryBalance: 0,
    );

    expect(overview.stages.map((stage) => stage.section).toList(), [1, 2]);
    expect(overview.stages.map((stage) => stage.questionCount).toList(), [
      10,
      10,
    ]);
  });

  test('new attempt payload includes the selected stage section', () {
    final payload = buildAwaQuizAttemptInsert(
      userId: 'user-1',
      languageId: 7,
      stage: const AwaQuizStage(
        section: 4,
        name: 'Odogwu',
        difficulty: AwaQuizDifficulty.intermediate,
        setId: 22,
        questionCount: 12,
        attemptCount: 0,
        isUnlocked: true,
      ),
    );

    expect(payload, {
      'userId': 'user-1',
      'languageId': 7,
      'setId': 22,
      'difficulty': 'INTERMEDIATE',
      'section': 4,
      'score': 0,
      'totalQuestions': 0,
      'entryCostCowries': 30,
    });
  });
}
