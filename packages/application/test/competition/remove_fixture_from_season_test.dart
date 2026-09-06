import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import '../scoring/fakes.dart';
import 'fake_competition_repository.dart';
import 'fakes.dart';

const _adminId = '11111111-1111-1111-1111-111111111111';
const _competitionId = '22222222-2222-2222-2222-222222222222';
const _seasonId = '33333333-3333-3333-3333-333333333333';
const _fixtureId = '44444444-4444-4444-4444-444444444444';
const _predictionId = '55555555-5555-5555-5555-555555555555';
const _participantId = '66666666-6666-6666-6666-666666666666';

CompetitionSeason _season() =>
    (CompetitionSeason.create(
              id: const SeasonId(_seasonId),
              competitionId: const CompetitionId(_competitionId),
              label: '09/2026',
              startAt: DateTime.utc(2026, 9),
              endAt: DateTime.utc(2026, 10),
            )
            as Ok<CompetitionSeason>)
        .value;

SeasonFixture _link() =>
    (SeasonFixture.create(
              seasonId: const SeasonId(_seasonId),
              fixture: const FixtureRef(_fixtureId),
              displayOrder: 0,
            )
            as Ok<SeasonFixture>)
        .value;

void main() {
  late FakeCompetitionRepository competitionRepo;
  late FakeFixturePredictionRepository predictions;
  late FakeFixtureResultRepository results;
  late RemoveFixtureFromSeason useCase;

  setUp(() {
    competitionRepo = FakeCompetitionRepository();
    predictions = FakeFixturePredictionRepository();
    results = FakeFixtureResultRepository();
    useCase = RemoveFixtureFromSeason(
      competitionRepository: competitionRepo,
      fixturePredictionRepository: predictions,
      fixtureResultRepository: results,
    );
    competitionRepo.seedSeason(_season());
  });

  Future<Result<bool>> remove({String? principalId}) => useCase(
    principal: adminPrincipal(principalId ?? _adminId),
    seasonId: _seasonId,
    fixtureId: _fixtureId,
  );

  test('admin removes an untouched fixture from the season', () async {
    predictions.seedSeasonFixture(_link());

    expect((await remove() as Ok<bool>).value, isTrue);

    final gone = await predictions.findSeasonFixture(
      const SeasonId(_seasonId),
      const FixtureRef(_fixtureId),
    );
    expect((gone as Ok<SeasonFixture?>).value, isNull);
  });

  test('removing an already-removed link converges on false', () async {
    predictions.seedSeasonFixture(_link());
    await remove();

    // Idempotent, not an error: a retried removal must not fail.
    expect((await remove() as Ok<bool>).value, isFalse);
  });

  test('refuses once anyone has predicted the fixture', () async {
    predictions
      ..seedSeasonFixture(_link())
      ..seedPrediction(
        const FixturePrediction.fromStored(
          id: PredictionId(_predictionId),
          fixture: FixtureRef(_fixtureId),
          participantId: ParticipantId(_participantId),
          homeGoals: 2,
          awayGoals: 1,
        ),
        DateTime.utc(2026, 9, 5),
      );

    final error = (await remove() as Err<bool>).error;
    expect(error.kind, ErrorKind.invariant);
    expect(error.code, 'competition.fixture_has_predictions');

    // The guard must REFUSE, never cascade: the link is still there, so the
    // ledger can never end up holding points for a fixture no screen shows.
    final still = await predictions.findSeasonFixture(
      const SeasonId(_seasonId),
      const FixtureRef(_fixtureId),
    );
    expect((still as Ok<SeasonFixture?>).value, isNotNull);
  });

  test('refuses once a result is recorded, even with no predictions', () async {
    predictions.seedSeasonFixture(_link());
    results.seed(
      (FixtureResult.create(
                fixture: const FixtureRef(_fixtureId),
                homeGoals: 1,
                awayGoals: 0,
              )
              as Ok<FixtureResult>)
          .value,
    );

    final error = (await remove() as Err<bool>).error;
    expect(error.kind, ErrorKind.invariant);
    expect(error.code, 'competition.fixture_result_already_recorded');
  });

  test('non-admin is rejected before any read', () async {
    predictions.seedSeasonFixture(_link());

    final result = await useCase(
      principal: userPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
    );

    expect((result as Err<bool>).error.kind, ErrorKind.authorization);
    final still = await predictions.findSeasonFixture(
      const SeasonId(_seasonId),
      const FixtureRef(_fixtureId),
    );
    expect((still as Ok<SeasonFixture?>).value, isNotNull);
  });

  test('rejects a malformed fixture id', () async {
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: 'not-a-uuid',
    );
    expect((result as Err<bool>).error.kind, ErrorKind.validation);
  });
}
