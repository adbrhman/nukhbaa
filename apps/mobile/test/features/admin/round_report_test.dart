import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/round_report.dart';

RoundScoreDto _score(
  String participantId,
  int total,
  List<FixtureScoreResultDto> results,
) => RoundScoreDto(
  roundId: 'round-1',
  participantId: participantId,
  rulesetVersion: 1,
  totalPoints: total,
  fixtureResults: results,
);

PredictionDto _prediction(
  String participantId,
  List<FixtureScoreDto> scores,
) => PredictionDto(
  id: 'pred-$participantId',
  participantId: participantId,
  roundId: 'round-1',
  submittedAt: '2026-08-01T12:00:00Z',
  fixtureScores: scores,
);

void main() {
  test('ranks participants by total points descending', () {
    final scores = RoundScoresDto(
      roundId: 'round-1',
      scores: [
        _score('p-low', 3, const [
          FixtureScoreResultDto(
            fixtureId: 'f1',
            grade: 'correct_outcome',
            points: 3,
          ),
        ]),
        _score('p-high', 10, const [
          FixtureScoreResultDto(
            fixtureId: 'f1',
            grade: 'exact_scoreline',
            points: 10,
          ),
        ]),
      ],
    );
    final raw = [
      _prediction('p-low', const [
        FixtureScoreDto(fixtureId: 'f1', homeGoals: 1, awayGoals: 1),
      ]),
      _prediction('p-high', const [
        FixtureScoreDto(
          fixtureId: 'f1',
          homeGoals: 2,
          awayGoals: 0,
          isDouble: true,
        ),
      ]),
    ];

    final rows = buildRoundReport(scores: scores, rawPredictions: raw);

    expect(rows, hasLength(2));
    expect(rows[0].participantId, 'p-high');
    expect(rows[0].rank, 1);
    expect(rows[0].cells.single.homeGoals, 2);
    expect(rows[0].cells.single.awayGoals, 0);
    expect(rows[0].cells.single.isDouble, isTrue);
    expect(rows[1].participantId, 'p-low');
    expect(rows[1].rank, 2);
  });

  test(
    'a cell with no matching raw prediction has null scores (missed fixture)',
    () {
      final scores = RoundScoresDto(
        roundId: 'round-1',
        scores: [
          _score('p1', 0, const [
            FixtureScoreResultDto(
              fixtureId: 'f1',
              grade: 'missed',
              points: 0,
            ),
          ]),
        ],
      );

      final rows = buildRoundReport(scores: scores, rawPredictions: const []);

      expect(rows.single.cells.single.hasRawScore, isFalse);
      expect(rows.single.cells.single.grade, 'missed');
    },
  );

  test('an empty scored round produces an empty report', () {
    const scores = RoundScoresDto(roundId: 'round-1', scores: []);
    final rows = buildRoundReport(scores: scores, rawPredictions: const []);
    expect(rows, isEmpty);
  });
}
