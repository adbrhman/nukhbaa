import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/fixture_report.dart';

ParticipantFixtureScoreDto _score(
  String participantId,
  int points, {
  String grade = 'correct_outcome',
}) => ParticipantFixtureScoreDto(
  fixtureId: 'fx-1',
  participantId: participantId,
  rulesetVersion: 1,
  grade: grade,
  points: points,
);

FixturePredictionDto _prediction(
  String participantId, {
  int homeGoals = 1,
  int awayGoals = 1,
  bool isDouble = false,
}) => FixturePredictionDto(
  id: 'pred-$participantId',
  participantId: participantId,
  fixtureId: 'fx-1',
  submittedAt: '2026-08-01T12:00:00Z',
  homeGoals: homeGoals,
  awayGoals: awayGoals,
  isDouble: isDouble,
);

void main() {
  test('ranks participants by points descending', () {
    final scores = FixtureScoresDto(
      fixtureId: 'fx-1',
      scores: [
        _score('p-low', 3),
        _score('p-high', 10, grade: 'exact_scoreline'),
      ],
    );
    final raw = [
      _prediction('p-low'),
      _prediction('p-high', homeGoals: 2, awayGoals: 0, isDouble: true),
    ];

    final rows = buildFixtureReport(scores: scores, rawPredictions: raw);

    expect(rows, hasLength(2));
    expect(rows[0].participantId, 'p-high');
    expect(rows[0].rank, 1);
    expect(rows[0].homeGoals, 2);
    expect(rows[0].awayGoals, 0);
    expect(rows[0].isDouble, isTrue);
    expect(rows[1].participantId, 'p-low');
    expect(rows[1].rank, 2);
  });

  test(
    'a row with no matching raw prediction has null scores (missed fixture)',
    () {
      const scores = FixtureScoresDto(
        fixtureId: 'fx-1',
        scores: [
          ParticipantFixtureScoreDto(
            fixtureId: 'fx-1',
            participantId: 'p1',
            rulesetVersion: 1,
            grade: 'missed',
            points: 0,
          ),
        ],
      );

      final rows = buildFixtureReport(scores: scores, rawPredictions: const []);

      expect(rows.single.hasRawScore, isFalse);
      expect(rows.single.grade, 'missed');
    },
  );

  test('an empty scored fixture produces an empty report', () {
    const scores = FixtureScoresDto(fixtureId: 'fx-1', scores: []);
    final rows = buildFixtureReport(scores: scores, rawPredictions: const []);
    expect(rows, isEmpty);
  });
}
