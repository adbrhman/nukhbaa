import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import 'fake_competition_repository.dart';
import 'fakes.dart';

const _adminId = '11111111-1111-1111-1111-111111111111';
const _competitionId = '22222222-2222-2222-2222-222222222222';
const _seasonId = '33333333-3333-3333-3333-333333333333';
const _fixtureId = '44444444-4444-4444-4444-444444444444';

CompetitionSeason _season() =>
    (CompetitionSeason.create(
              id: const SeasonId(_seasonId),
              competitionId: const CompetitionId(_competitionId),
              label: 'August',
              startAt: DateTime.utc(2026, 8, 1),
              endAt: DateTime.utc(2026, 9, 1),
            )
            as Ok<CompetitionSeason>)
        .value;

void main() {
  late FakeCompetitionRepository competitionRepo;
  late FakeFixturePredictionRepository fixturePredictionRepo;
  late LinkFixtureToSeason useCase;

  setUp(() {
    competitionRepo = FakeCompetitionRepository();
    fixturePredictionRepo = FakeFixturePredictionRepository();
    useCase = LinkFixtureToSeason(
      competitionRepository: competitionRepo,
      fixturePredictionRepository: fixturePredictionRepo,
    );
  });

  test('admin links a fixture to a season', () async {
    competitionRepo.seedSeason(_season());

    final result = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: 0,
    );

    final link = (result as Ok<SeasonFixture>).value;
    expect(link.seasonId, const SeasonId(_seasonId));
    expect(link.fixture, const FixtureRef(_fixtureId));
    expect(link.displayOrder, 0);
    expect(fixturePredictionRepo.count, 0);
  });

  test('non-admin is rejected', () async {
    competitionRepo.seedSeason(_season());
    final result = await useCase(
      principal: userPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: 0,
    );
    expect((result as Err<SeasonFixture>).error.kind, ErrorKind.authorization);
  });

  test('a missing season is an invariant precondition failure', () async {
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: 0,
    );
    expect(
      (result as Err<SeasonFixture>).error.code,
      'competition.season_not_found',
    );
  });

  test('a malformed fixture id is a validation error', () async {
    competitionRepo.seedSeason(_season());
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: 'x',
      displayOrder: 0,
    );
    expect(
      (result as Err<SeasonFixture>).error.code,
      'competition.fixture_ref_malformed',
    );
  });

  test('a negative display order is rejected by the domain', () async {
    competitionRepo.seedSeason(_season());
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: -1,
    );
    expect(
      (result as Err<SeasonFixture>).error.code,
      'competition.season_fixture_order_invalid',
    );
  });

  test('a duplicate link surfaces as an invariant conflict', () async {
    competitionRepo.seedSeason(_season());
    await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: 0,
    );

    final again = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
      displayOrder: 1,
    );
    expect(
      (again as Err<SeasonFixture>).error.code,
      'competition.season_fixture_already_linked',
    );
  });
}
