import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart';
import '../prediction/fake_fixture_prediction_repository.dart';
import 'fake_fixture_score_repository.dart';
import 'fakes.dart';

void main() {
  group('ScoreFixture', () {
    late FakeFixturePredictionRepository fixturePredictions;
    late FakeFixtureResultRepository results;
    late FakeFixtureScoreRepository scores;
    late ScoreFixture useCase;

    const fixtureId = '11111111-1111-1111-1111-111111111111';
    const participantId = 'participant-1';

    setUp(() {
      fixturePredictions = FakeFixturePredictionRepository();
      results = FakeFixtureResultRepository();
      scores = FakeFixtureScoreRepository();
      useCase = ScoreFixture(
        fixturePredictionRepository: fixturePredictions,
        resultRepository: results,
        scoreRepository: scores,
        rulesetProvider: FakeRulesetProvider(Result.ok(scoringSnapshot())),
      );
    });

    FixturePrediction seedPrediction({
      required int home,
      required int away,
      bool isDouble = false,
    }) {
      final prediction =
          (FixturePrediction.submit(
                    id: const PredictionId('prediction-1'),
                    fixture: const FixtureRef(fixtureId),
                    participantId: const ParticipantId(participantId),
                    lock:
                        (FixtureLock.at(
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
      fixturePredictions.seedPrediction(prediction, DateTime.utc(2026, 8, 1));
      return prediction;
    }

    test(
      'grades an exact-scoreline prediction once the result lands',
      () async {
        seedPrediction(home: 2, away: 1);
        results.seed(
          const FixtureResult.fromStored(
            fixture: FixtureRef(fixtureId),
            homeGoals: 2,
            awayGoals: 1,
          ),
        );

        final result = await useCase(
          principal: adminPrincipal('admin-1'),
          fixtureId: fixtureId,
        );

        expect(result, isA<Ok<List<ParticipantFixtureScore>>>());
        final list = (result as Ok<List<ParticipantFixtureScore>>).value;
        expect(list, hasLength(1));
        expect(list.single.result.grade, FixtureScoreGrade.exactScoreline);
        expect(scores.count, 1);
      },
    );

    test('grades pending when no result has been recorded yet', () async {
      seedPrediction(home: 2, away: 1);

      final result = await useCase(
        principal: adminPrincipal('admin-1'),
        fixtureId: fixtureId,
      );

      expect(result, isA<Ok<List<ParticipantFixtureScore>>>());
      final list = (result as Ok<List<ParticipantFixtureScore>>).value;
      expect(list.single.result.grade, FixtureScoreGrade.pending);
      expect(list.single.points, 0);
    });

    test('a fixture with no predictions scores an empty list, not an error',
        () async {
      final result = await useCase(
        principal: adminPrincipal('admin-1'),
        fixtureId: fixtureId,
      );

      expect(result, isA<Ok<List<ParticipantFixtureScore>>>());
      expect((result as Ok<List<ParticipantFixtureScore>>).value, isEmpty);
    });

    test('rejects a non-admin caller', () async {
      seedPrediction(home: 1, away: 0);

      final result = await useCase(
        principal: userPrincipal('user-1'),
        fixtureId: fixtureId,
      );

      expect(result, isA<Err<List<ParticipantFixtureScore>>>());
    });
  });
}
