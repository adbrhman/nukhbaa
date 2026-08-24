import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('Scoring.scoreFixture', () {
    final ruleset =
        (ScoringRuleset.fromSnapshot(
                  (RulesetSnapshot.create(
                            payload: const {
                              'format': 'football_scoreline',
                              'points': {
                                'exact_scoreline': 3,
                                'correct_outcome': 1,
                                'incorrect': 0,
                              },
                            },
                            rulesetVersion: 1,
                          )
                          as Ok<RulesetSnapshot>)
                      .value,
                )
                as Ok<ScoringRuleset>)
            .value;

    FixturePrediction prediction({
      required int home,
      required int away,
      bool isDouble = false,
    }) =>
        (FixturePrediction.submit(
                  id: const PredictionId('prediction-1'),
                  fixture: const FixtureRef(
                    '11111111-1111-1111-1111-111111111111',
                  ),
                  participantId: const ParticipantId('participant-1'),
                  lock: (FixtureLock.at(
                            kickoffAt: DateTime.utc(2026, 8, 2),
                            nowUtc: DateTime.utc(2026, 8, 1),
                          )
                          as Ok<FixtureLock>)
                      .value,
                  homeGoals: home,
                  awayGoals: away,
                  isDouble: isDouble,
                )
                as Ok<FixturePrediction>)
            .value;

    test('grades pending with zero points when no result yet', () {
      final scored = Scoring.scoreFixture(
        prediction: prediction(home: 2, away: 1),
        result: null,
        ruleset: ruleset,
        rulesetVersion: 1,
      );

      expect(scored, isA<Ok<ParticipantFixtureScore>>());
      final score = (scored as Ok<ParticipantFixtureScore>).value;
      expect(score.result.grade, FixtureScoreGrade.pending);
      expect(score.points, 0);
    });

    test('grades exact scoreline, doubled', () {
      final result = FixtureResult.fromStored(
        fixture: const FixtureRef('11111111-1111-1111-1111-111111111111'),
        homeGoals: 2,
        awayGoals: 1,
      );

      final scored = Scoring.scoreFixture(
        prediction: prediction(home: 2, away: 1, isDouble: true),
        result: result,
        ruleset: ruleset,
        rulesetVersion: 1,
      );

      expect(scored, isA<Ok<ParticipantFixtureScore>>());
      final score = (scored as Ok<ParticipantFixtureScore>).value;
      expect(score.result.grade, FixtureScoreGrade.exactScoreline);
      expect(score.points, 6); // 3 * doubleMultiplier(2)
    });

    test('grades correct outcome without exact scoreline', () {
      final result = FixtureResult.fromStored(
        fixture: const FixtureRef('11111111-1111-1111-1111-111111111111'),
        homeGoals: 3,
        awayGoals: 1,
      );

      final scored = Scoring.scoreFixture(
        prediction: prediction(home: 2, away: 0),
        result: result,
        ruleset: ruleset,
        rulesetVersion: 1,
      );

      expect(scored, isA<Ok<ParticipantFixtureScore>>());
      final score = (scored as Ok<ParticipantFixtureScore>).value;
      expect(score.result.grade, FixtureScoreGrade.correctOutcome);
      expect(score.points, 1);
    });

    test('rejects a result for a different fixture', () {
      final result = FixtureResult.fromStored(
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        homeGoals: 1,
        awayGoals: 0,
      );

      final scored = Scoring.scoreFixture(
        prediction: prediction(home: 1, away: 0),
        result: result,
        ruleset: ruleset,
        rulesetVersion: 1,
      );

      expect(scored, isA<Err<ParticipantFixtureScore>>());
      expect(
        (scored as Err<ParticipantFixtureScore>).error.code,
        'scoring.fixture_mismatch',
      );
    });
  });
}
