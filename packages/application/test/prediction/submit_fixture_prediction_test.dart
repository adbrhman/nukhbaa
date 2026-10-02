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

    const seasonId = '33333333-3333-3333-3333-333333333333';
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
        idGenerator: FakeIdGenerator(['66666666-6666-6666-6666-666666666666']),
        clock: FixedClock(DateTime.utc(2026, 8, 1, 10)),
      );

      fixturePredictions.seedSeasonFixture(
        (SeasonFixture.create(
                  seasonId: const SeasonId(seasonId),
                  fixture: const FixtureRef(fixtureId),
                  displayOrder: 0,
                )
                as Ok<SeasonFixture>)
            .value,
      );
      competition.seedParticipant(
        Participant.fromStored(
          id: const ParticipantId(participantId),
          seasonId: const SeasonId(seasonId),
          userId: const UserId(userId),
          status: ParticipantStatus.active,
          joinedAt: DateTime.utc(2026),
        ),
      );
      // A registered kickoff, later than the fixed clock. Before the
      // unscheduled-fixture rule this seed was unnecessary -- an absent
      // schedule read as "open" -- so every test here implicitly relied on
      // the hole this suite now closes.
      schedules.seed(
        FixtureSchedule.fromStored(
          fixture: const FixtureRef(fixtureId),
          homeTeam: 'Home FC',
          awayTeam: 'Away FC',
          kickoffAt: DateTime.utc(2026, 8, 1, 20),
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

    test('rejects a fixture with no registered kickoff', () async {
      const unscheduledId = '44444444-4444-4444-4444-444444444444';
      fixturePredictions.seedSeasonFixture(
        (SeasonFixture.create(
                  seasonId: const SeasonId(seasonId),
                  fixture: const FixtureRef(unscheduledId),
                  displayOrder: 2,
                )
                as Ok<SeasonFixture>)
            .value,
      );

      final result = await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: unscheduledId,
        homeGoals: 1,
        awayGoals: 0,
      );

      expect(result, isA<Err<FixturePredictionView>>());
      expect(
        (result as Err<FixturePredictionView>).error.code,
        'prediction.fixture_not_scheduled',
      );
    });

    test('rejects a fixture that has already kicked off', () async {
      schedules.seed(
        FixtureSchedule.fromStored(
          fixture: const FixtureRef(fixtureId),
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
                  seasonId: const SeasonId(seasonId),
                  fixture: const FixtureRef(otherFixtureId),
                  displayOrder: 1,
                )
                as Ok<SeasonFixture>)
            .value,
      );
      schedules.seed(
        FixtureSchedule.fromStored(
          fixture: const FixtureRef(otherFixtureId),
          homeTeam: 'Other Home FC',
          awayTeam: 'Other Away FC',
          kickoffAt: DateTime.utc(2026, 8, 1, 12),
        ),
      );
      fixturePredictions.seedKickoff(
        const FixtureRef(otherFixtureId),
        DateTime.utc(2026, 8, 1, 12),
      );
      fixturePredictions.seedKickoff(
        const FixtureRef(fixtureId),
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

    test('a double after midnight Riyadh counts on the next day', () async {
      // 23:00 Riyadh on 1 August (20:00Z), 00:30 Riyadh on 2 August
      // (21:30Z on 1 August) and 22:00 Riyadh on 2 August (19:00Z): the
      // first two share a UTC day, the last two the day the player sees.
      const lateFixtureId = '44444444-4444-4444-4444-444444444444';
      const nextFixtureId = '55555555-5555-5555-5555-555555555555';
      for (final (id, order, kickoff) in <(String, int, DateTime)>[
        (lateFixtureId, 1, DateTime.utc(2026, 8, 1, 21, 30)),
        (nextFixtureId, 2, DateTime.utc(2026, 8, 2, 19)),
      ]) {
        fixturePredictions.seedSeasonFixture(
          (SeasonFixture.create(
                    seasonId: const SeasonId(seasonId),
                    fixture: FixtureRef(id),
                    displayOrder: order,
                  )
                  as Ok<SeasonFixture>)
              .value,
        );
        schedules.seed(
          FixtureSchedule.fromStored(
            fixture: FixtureRef(id),
            homeTeam: 'Home $order',
            awayTeam: 'Away $order',
            kickoffAt: kickoff,
          ),
        );
        fixturePredictions.seedKickoff(FixtureRef(id), kickoff);
      }
      fixturePredictions.seedKickoff(
        const FixtureRef(fixtureId),
        DateTime.utc(2026, 8, 1, 20),
      );

      Future<Result<FixturePredictionView>> placeDouble(String id) => useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: id,
        homeGoals: 1,
        awayGoals: 0,
        isDouble: true,
      );

      expect(await placeDouble(fixtureId), isA<Ok<FixturePredictionView>>());
      expect(
        await placeDouble(lateFixtureId),
        isA<Ok<FixturePredictionView>>(),
      );
      final third = await placeDouble(nextFixtureId);
      expect(
        (third as Err<FixturePredictionView>).error.code,
        'prediction.daily_double_exceeded',
      );
    });

    test('records one prediction_placed event, and none on an amend', () async {
      final events = _RecordingGamificationEventSink();
      final withSink = SubmitFixturePrediction(
        fixturePredictionRepository: fixturePredictions,
        competitionRepository: competition,
        fixtureScheduleRepository: schedules,
        idGenerator: FakeIdGenerator(const <String>[
          '66666666-6666-6666-6666-666666666666',
          '77777777-7777-7777-7777-777777777777',
        ]),
        clock: FixedClock(DateTime.utc(2026, 8, 1, 10)),
        gamificationEventSink: events,
      );

      await withSink(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 1,
        awayGoals: 0,
      );

      expect(events.recorded, hasLength(1));
      final event = events.recorded.single;
      expect(event.type, GamificationEventType.predictionPlaced);
      expect(event.userId.value, userId);
      expect(event.refType, 'fixture');
      expect(event.refId, fixtureId);
      expect(event.ruleVersion, 1);
      // Keyed on the prediction, so a replay can never place it twice.
      expect(
        event.dedupeKey,
        'prediction_placed:66666666-6666-6666-6666-666666666666',
      );

      // An amendment is not a new placement.
      await withSink(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 2,
        awayGoals: 1,
      );

      expect(events.recorded, hasLength(1));
    });
  });
}

/// Captures what the use-case appends to the gamification stream.
final class _RecordingGamificationEventSink implements GamificationEventSink {
  final List<GamificationEvent> recorded = <GamificationEvent>[];

  @override
  Future<Result<void>> record(GamificationEvent event) async {
    recorded.add(event);
    return const Result.ok(null);
  }
}
