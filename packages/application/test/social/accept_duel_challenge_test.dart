import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'duel_application_fakes.dart';

const _opponent = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _season = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const _fixture = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const _opponentParticipant = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _challenge = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
final _now = DateTime.utc(2026, 10, 5, 12);

DuelChallenge _challengeRow() =>
    (DuelChallenge.create(
              id: const DuelChallengeId(_challenge),
              code: (DuelCode.tryParse('ABCDEFGHJKMN') as Ok<DuelCode>).value,
              seasonId: const SeasonId(_season),
              fixture: const FixtureRef(_fixture),
              challengerParticipantId: const ParticipantId(
                '11111111-1111-1111-1111-111111111111',
              ),
              targetUserId: null,
              createdAt: _now,
            )
            as Ok<DuelChallenge>)
        .value;

SubmitFixturePrediction _submit({
  required FakeCompetitionRepository competition,
  required FakeFixturePredictionRepository predictions,
  required FakeFixtureScheduleRepository schedules,
}) => SubmitFixturePrediction(
  fixturePredictionRepository: predictions,
  competitionRepository: competition,
  fixtureScheduleRepository: schedules,
  idGenerator: FakeIdGenerator(['22222222-2222-2222-2222-222222222222']),
  clock: FixedClock(_now),
);

void main() {
  test(
    'submits the prediction before calling atomic duel acceptance',
    () async {
      final competition = FakeCompetitionRepository();
      final predictions = FakeFixturePredictionRepository();
      final schedules = FakeFixtureScheduleRepository();
      final duels = FakeDuelChallengeRepository()
        ..seedChallenge(_challengeRow());

      competition.seedParticipant(
        Participant.fromStored(
          id: const ParticipantId(_opponentParticipant),
          seasonId: const SeasonId(_season),
          userId: const UserId(_opponent),
          status: ParticipantStatus.active,
          joinedAt: _now.subtract(const Duration(days: 1)),
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
          homeTeam: 'A',
          awayTeam: 'B',
          kickoffAt: _now.add(const Duration(hours: 2)),
        ),
      );

      final result =
          await AcceptDuelChallenge(
            duels: duels,
            submitPrediction: _submit(
              competition: competition,
              predictions: predictions,
              schedules: schedules,
            ),
            clock: FixedClock(_now),
          ).call(
            principal: userPrincipal(_opponent),
            challengeId: _challenge,
            homeGoals: 2,
            awayGoals: 1,
          );

      expect(result, isA<Ok<Duel>>());
      expect(predictions.count, 1);
      expect(duels.acceptCalls, 1);
    },
  );

  test('does not call duel acceptance when prediction is locked', () async {
    final competition = FakeCompetitionRepository();
    final predictions = FakeFixturePredictionRepository();
    final schedules = FakeFixtureScheduleRepository();
    final duels = FakeDuelChallengeRepository()..seedChallenge(_challengeRow());

    competition.seedParticipant(
      Participant.fromStored(
        id: const ParticipantId(_opponentParticipant),
        seasonId: const SeasonId(_season),
        userId: const UserId(_opponent),
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
        homeTeam: 'A',
        awayTeam: 'B',
        kickoffAt: _now.subtract(const Duration(minutes: 1)),
      ),
    );

    final result =
        await AcceptDuelChallenge(
          duels: duels,
          submitPrediction: _submit(
            competition: competition,
            predictions: predictions,
            schedules: schedules,
          ),
          clock: FixedClock(_now),
        ).call(
          principal: userPrincipal(_opponent),
          challengeId: _challenge,
          homeGoals: 2,
          awayGoals: 1,
        );

    expect((result as Err<Duel>).error.code, 'prediction.fixture_locked');
    expect(duels.acceptCalls, 0);
    expect(predictions.count, 0);
  });
}
