import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import '../prediction/fake_fixture_prediction_repository.dart';
import 'duel_application_fakes.dart';

const _user = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _season = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _fixture = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const _participant = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
final _now = DateTime.utc(2026, 10, 5, 12);

void main() {
  test('creates a challenge after the caller has a prediction', () async {
    final competition = FakeCompetitionRepository();
    final predictions = FakeFixturePredictionRepository();
    final duels = FakeDuelChallengeRepository();
    final schedules = FakeFixtureScheduleRepository();
    final participant = Participant.fromStored(
      id: const ParticipantId(_participant),
      seasonId: const SeasonId(_season),
      userId: const UserId(_user),
      status: ParticipantStatus.active,
      joinedAt: _now.subtract(const Duration(days: 1)),
    );
    competition.seedParticipant(participant);
    predictions.seedSeasonFixture(
      SeasonFixture.fromStored(
        seasonId: const SeasonId(_season),
        fixture: const FixtureRef(_fixture),
        displayOrder: 1,
      ),
    );
    predictions.seedPrediction(
      FixturePrediction.fromStored(
        id: const PredictionId('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
        fixture: const FixtureRef(_fixture),
        participantId: const ParticipantId(_participant),
        homeGoals: 1,
        awayGoals: 0,
        isDouble: false,
      ),
      _now,
    );
    schedules.seed(
      FixtureSchedule.fromStored(
        fixture: const FixtureRef(_fixture),
        homeTeam: 'Home',
        awayTeam: 'Away',
        kickoffAt: _now.add(const Duration(hours: 2)),
      ),
    );

    final result =
        await CreateDuelChallenge(
          duels: duels,
          competition: competition,
          predictions: predictions,
          schedules: schedules,
          clock: FixedClock(_now),
        ).call(
          principal: userPrincipal(_user),
          seasonId: _season,
          fixtureId: _fixture,
        );

    expect(result, isA<Ok<DuelChallenge>>());
    expect(duels.createCalls, 1);
  });

  test('refuses creation without a prediction', () async {
    final competition = FakeCompetitionRepository();
    final predictions = FakeFixturePredictionRepository();
    final schedules = FakeFixtureScheduleRepository();
    competition.seedParticipant(
      Participant.fromStored(
        id: const ParticipantId(_participant),
        seasonId: const SeasonId(_season),
        userId: const UserId(_user),
        status: ParticipantStatus.active,
        joinedAt: _now,
      ),
    );
    predictions.seedSeasonFixture(
      SeasonFixture.fromStored(
        seasonId: const SeasonId(_season),
        fixture: const FixtureRef(_fixture),
        displayOrder: 1,
      ),
    );
    schedules.seed(
      FixtureSchedule.fromStored(
        fixture: const FixtureRef(_fixture),
        homeTeam: 'Home',
        awayTeam: 'Away',
        kickoffAt: _now.add(const Duration(hours: 2)),
      ),
    );

    final result =
        await CreateDuelChallenge(
          duels: FakeDuelChallengeRepository(),
          competition: competition,
          predictions: predictions,
          schedules: schedules,
          clock: FixedClock(_now),
        ).call(
          principal: userPrincipal(_user),
          seasonId: _season,
          fixtureId: _fixture,
        );

    expect(
      (result as Err<DuelChallenge>).error.code,
      'social.duel_prediction_required',
    );
  });

  test('private challenge rejects capacity other than one', () async {
    final result = DuelPolicy.validateCapacity(
      capacity: 5,
      targetUserId: const UserId('ffffffff-ffff-ffff-ffff-ffffffffffff'),
    );
    expect(
      (result as Err<void>).error.code,
      'social.duel_private_capacity_invalid',
    );
  });
}
