import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';
import 'fake_fixture_prediction_repository.dart';
import 'fake_fixture_schedule_repository.dart';

/// The claims table of migration 0197, in memory: the first account that
/// predicts a match from an install holds it there.
final class _Claims implements InstallFixtureClaims {
  final Map<String, UserId> holders = <String, UserId>{};
  int calls = 0;

  @override
  Future<Result<UserId>> claim({
    required String installId,
    required FixtureRef fixture,
    required UserId userId,
  }) async {
    calls++;
    return Result.ok(
      holders.putIfAbsent('$installId|${fixture.value}', () => userId),
    );
  }
}

/// Script 200 (decided by the owner on 2026-11-02): one phone may hold
/// several accounts, but never two accounts predicting the same match.
void main() {
  const seasonId = '33333333-3333-3333-3333-333333333333';
  const fixtureId = '11111111-1111-1111-1111-111111111111';
  const phone = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const otherPhone = 'ffffffff-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

  late FakeFixturePredictionRepository predictions;
  late FakeCompetitionRepository competition;
  late FakeFixtureScheduleRepository schedules;
  late _Claims claims;
  late SubmitFixturePrediction submit;

  void seedParticipant(String user, String participant) {
    competition.seedParticipant(
      Participant.fromStored(
        id: ParticipantId(participant),
        seasonId: const SeasonId(seasonId),
        userId: UserId(user),
        status: ParticipantStatus.active,
        joinedAt: DateTime.utc(2026),
      ),
    );
  }

  setUp(() {
    predictions = FakeFixturePredictionRepository();
    competition = FakeCompetitionRepository();
    schedules = FakeFixtureScheduleRepository();
    claims = _Claims();
    submit = SubmitFixturePrediction(
      fixturePredictionRepository: predictions,
      competitionRepository: competition,
      fixtureScheduleRepository: schedules,
      idGenerator: FakeIdGenerator([
        '66666666-6666-6666-6666-666666666661',
        '66666666-6666-6666-6666-666666666662',
        '66666666-6666-6666-6666-666666666663',
      ]),
      clock: FixedClock(DateTime.utc(2026, 11, 2, 10)),
      installFixtureClaims: claims,
    );
    predictions.seedSeasonFixture(
      (SeasonFixture.create(
                seasonId: const SeasonId(seasonId),
                fixture: const FixtureRef(fixtureId),
                displayOrder: 0,
              )
              as Ok<SeasonFixture>)
          .value,
    );
    seedParticipant('user-a', 'participant-a');
    seedParticipant('user-b', 'participant-b');
    schedules.seed(
      FixtureSchedule.fromStored(
        fixture: const FixtureRef(fixtureId),
        homeTeam: 'Home FC',
        awayTeam: 'Away FC',
        kickoffAt: DateTime.utc(2026, 11, 2, 20),
      ),
    );
  });

  Future<Result<FixturePredictionView>> predict(
    AuthenticatedUser who, {
    String? installId,
    int home = 1,
  }) => submit(
    principal: who,
    seasonId: seasonId,
    fixtureId: fixtureId,
    homeGoals: home,
    awayGoals: 0,
    installId: installId,
  );

  test('a second account on the same phone is refused the match', () async {
    final first = await predict(userPrincipal('user-a'), installId: phone);
    final second = await predict(userPrincipal('user-b'), installId: phone);

    expect(first, isA<Ok<FixturePredictionView>>());
    expect(
      (second as Err<FixturePredictionView>).error.code,
      'prediction.shared_device',
    );
    expect(second.error.kind, ErrorKind.invariant);
    expect(predictions.count, 1);
  });

  test('the account that holds the match amends it freely', () async {
    await predict(userPrincipal('user-a'), installId: phone);
    final again = await predict(
      userPrincipal('user-a'),
      installId: phone,
      home: 3,
    );

    expect((again as Ok<FixturePredictionView>).value.prediction.homeGoals, 3);
    expect(predictions.count, 1);
  });

  test('another phone is another phone', () async {
    await predict(userPrincipal('user-a'), installId: phone);
    final other = await predict(userPrincipal('user-b'), installId: otherPhone);

    expect(other, isA<Ok<FixturePredictionView>>());
    expect(predictions.count, 2);
  });

  test('the id is read in any case and with spaces', () async {
    await predict(userPrincipal('user-a'), installId: phone);
    final shouted = await predict(
      userPrincipal('user-b'),
      installId: ' ${phone.toUpperCase()} ',
    );

    expect(
      (shouted as Err<FixturePredictionView>).error.code,
      'prediction.shared_device',
    );
  });

  test('no install id (the web, an older build) is not checked', () async {
    await predict(userPrincipal('user-a'), installId: phone);
    final web = await predict(userPrincipal('user-b'));
    final junk = await predict(userPrincipal('user-b'), installId: 'abc');

    expect(web, isA<Ok<FixturePredictionView>>());
    expect(junk, isA<Ok<FixturePredictionView>>());
    expect(claims.calls, 1);
  });

  test('a test fixture counts for nothing and is not claimed', () async {
    schedules.seed(
      FixtureSchedule.fromStored(
        fixture: const FixtureRef(fixtureId),
        homeTeam: 'Home FC',
        awayTeam: 'Away FC',
        kickoffAt: DateTime.utc(2026, 11, 2, 20),
        isTest: true,
      ),
    );
    seedParticipant('admin-a', 'participant-c');

    final result = await predict(adminPrincipal('admin-a'), installId: phone);

    expect(result, isA<Ok<FixturePredictionView>>());
    expect(claims.calls, 0);
  });

  test('a failed claim stores nothing', () async {
    final failing = SubmitFixturePrediction(
      fixturePredictionRepository: predictions,
      competitionRepository: competition,
      fixtureScheduleRepository: schedules,
      idGenerator: FakeIdGenerator(['66666666-6666-6666-6666-666666666669']),
      clock: FixedClock(DateTime.utc(2026, 11, 2, 10)),
      installFixtureClaims: _FailingClaims(),
    );

    final result = await failing(
      principal: userPrincipal('user-a'),
      seasonId: seasonId,
      fixtureId: fixtureId,
      homeGoals: 1,
      awayGoals: 0,
      installId: phone,
    );

    expect(
      (result as Err<FixturePredictionView>).error.kind,
      ErrorKind.transient,
    );
    expect(predictions.count, 0);
  });
}

final class _FailingClaims implements InstallFixtureClaims {
  @override
  Future<Result<UserId>> claim({
    required String installId,
    required FixtureRef fixture,
    required UserId userId,
  }) async => const Result.err(AppError.transient('db.unavailable', 'down'));
}
