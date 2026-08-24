import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';
import 'fake_fixture_prediction_repository.dart';
import 'fake_fixture_schedule_repository.dart';

void main() {
  group('SubmitFixturePrediction', () {
    late FakeFixturePredictionRepository fixturePredictions;
    late FakeCompetitionRepository competition;
    late FakeFixtureScheduleRepository schedules;
    late SubmitFixturePrediction useCase;

    const seasonId = 'season-1';
    const fixtureId = '11111111-1111-1111-1111-111111111111';
    const userId = 'user-1';
    const participantId = 'participant-1';

    setUp(() {
      fixturePredictions = FakeFixturePredictionRepository();
      competition = FakeCompetitionRepository();
      schedules = FakeFixtureScheduleRepository();
      useCase = SubmitFixturePrediction(
        fixturePredictionRepository: fixturePredictions,
        competitionRepository: competition,
        fixtureScheduleRepository: schedules,
        idGenerator: FakeIdGenerator(['prediction-1']),
        clock: FixedClock(DateTime.utc(2026, 8, 1, 10)),
      );

      fixturePredictions.seedSeasonFixture(
        (SeasonFixture.create(
                  seasonId: SeasonId(seasonId),
                  fixture: FixtureRef(fixtureId),
                  displayOrder: 0,
                )
                as Ok<SeasonFixture>)
            .value,
      );
      competition.seedParticipant(
        Participant.fromStored(
          id: ParticipantId(participantId),
          seasonId: SeasonId(seasonId),
          userId: UserId(userId),
          status: ParticipantStatus.active,
          joinedAt: DateTime.utc(2026),
        ),
      );
    });

    test('inserts a new prediction on first submission', () async {
      final result = await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 2,
        awayGoals: 1,
        isDouble: true,
      );

      expect(result, isA<Ok<FixturePredictionView>>());
      final view = (result as Ok<FixturePredictionView>).value;
      expect(view.prediction.homeGoals, 2);
      expect(view.prediction.awayGoals, 1);
      expect(view.prediction.isDouble, isTrue);
      expect(fixturePredictions.count, 1);
    });

    test('amends the same row on a repeat submission', () async {
      await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 2,
        awayGoals: 1,
      );
      final result = await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 0,
        awayGoals: 0,
      );

      expect(result, isA<Ok<FixturePredictionView>>());
      final view = (result as Ok<FixturePredictionView>).value;
      expect(view.prediction.homeGoals, 0);
      expect(view.prediction.awayGoals, 0);
      expect(fixturePredictions.count, 1);
    });

    test('rejects a fixture not linked to the season', () async {
      final result = await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: '22222222-2222-2222-2222-222222222222',
        homeGoals: 1,
        awayGoals: 0,
      );

      expect(result, isA<Err<FixturePredictionView>>());
      expect(
        (result as Err<FixturePredictionView>).error.code,
        'prediction.fixture_not_in_season',
      );
    });

    test('rejects a caller who has not joined the season', () async {
      final result = await useCase(
        principal: userPrincipal('someone-else'),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 1,
        awayGoals: 0,
      );

      expect(result, isA<Err<FixturePredictionView>>());
      expect(
        (result as Err<FixturePredictionView>).error.code,
        'prediction.not_a_participant',
      );
    });

    test('rejects a fixture that has already kicked off', () async {
      schedules.seed(
        FixtureSchedule.fromStored(
          fixture: FixtureRef(fixtureId),
          homeTeam: 'Home FC',
          awayTeam: 'Away FC',
          kickoffAt: DateTime.utc(2026, 8, 1, 9), // before the fixed clock
        ),
      );

      final result = await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 1,
        awayGoals: 0,
      );

      expect(result, isA<Err<FixturePredictionView>>());
      expect(
        (result as Err<FixturePredictionView>).error.code,
        'prediction.fixture_locked',
      );
    });

    test('rejects a second double on the same UTC day', () async {
      const otherFixtureId = '33333333-3333-3333-3333-333333333333';
      fixturePredictions.seedSeasonFixture(
        (SeasonFixture.create(
                  seasonId: SeasonId(seasonId),
                  fixture: FixtureRef(otherFixtureId),
                  displayOrder: 1,
                )
                as Ok<SeasonFixture>)
            .value,
      );
      fixturePredictions.seedKickoff(
        FixtureRef(otherFixtureId),
        DateTime.utc(2026, 8, 1, 12),
      );
      fixturePredictions.seedKickoff(
        FixtureRef(fixtureId),
        DateTime.utc(2026, 8, 1, 20),
      );
      await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: otherFixtureId,
        homeGoals: 1,
        awayGoals: 1,
        isDouble: true,
      );

      final result = await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 2,
        awayGoals: 0,
        isDouble: true,
      );

      expect(result, isA<Err<FixturePredictionView>>());
      expect(
        (result as Err<FixturePredictionView>).error.code,
        'prediction.daily_double_exceeded',
      );
    });
  });
}
