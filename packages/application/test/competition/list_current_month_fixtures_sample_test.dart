import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fake_competition_repository.dart';
import 'fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _competition = 'aaaaaaaa-0000-0000-0000-000000000001';
const _season = 'aaaaaaaa-0000-0000-0000-000000000011';
const _fixture = 'ffffffff-0000-0000-0000-0000000000f1';
const _quiet = 'ffffffff-0000-0000-0000-0000000000f2';

final class _Tallies implements FixturePredictionTallyReader {
  @override
  Future<Result<List<FixtureOutcomeTally>>> tallyByFixtures(
    List<FixtureRef> fixtures,
  ) async => const Result.ok(<FixtureOutcomeTally>[
    FixtureOutcomeTally(
      fixture: FixtureRef(_fixture),
      homeWins: 3,
      awayWins: 1,
    ),
  ]);
}

/// The feed says how many decisive calls a share stands on, so the card can
/// keep a share over a handful of calls off the screen.
void main() {
  ListCurrentMonthFixtures useCase({FixturePredictionTallyReader? tallies}) {
    final competitions = FakeCompetitionRepository()
      ..seedCompetition(
        (Competition.create(
                  id: const CompetitionId(_competition),
                  name: 'League',
                  format: FormatType.footballScoreline,
                  visibility: CompetitionVisibility.public,
                )
                as Ok<Competition>)
            .value,
      )
      ..seedSeason(
        (CompetitionSeason.create(
                  id: const SeasonId(_season),
                  competitionId: const CompetitionId(_competition),
                  label: '10/2026',
                  startAt: DateTime.utc(2026, 10),
                  endAt: DateTime.utc(2026, 11),
                )
                as Ok<CompetitionSeason>)
            .value,
      );
    final fixtures = FakeFixturePredictionRepository();
    for (final (String id, int order) in [(_fixture, 0), (_quiet, 1)]) {
      fixtures.seedSeasonFixture(
        (SeasonFixture.create(
                  seasonId: const SeasonId(_season),
                  fixture: FixtureRef(id),
                  displayOrder: order,
                )
                as Ok<SeasonFixture>)
            .value,
      );
    }
    return ListCurrentMonthFixtures(
      competitionRepository: competitions,
      fixturePredictionRepository: fixtures,
      fixtureScheduleRepository: FakeFixtureScheduleRepository(),
      clock: FixedClock(DateTime.utc(2026, 10, 7)),
      predictionTallyReader: tallies,
    );
  }

  test('each entry carries its decisive calls; none predicted is 0', () async {
    final r = await useCase(tallies: _Tallies())(
      principal: userPrincipal(_user),
    );

    final entries = (r as Ok<List<CurrentMonthFixtureEntry>>).value;
    final Map<String, int?> byFixture = {
      for (final e in entries) e.fixture.fixtureId.value: e.decisivePredictions,
    };
    expect(byFixture, {_fixture: 4, _quiet: 0});
  });

  test('without a tally reader there is no count', () async {
    final r = await useCase()(principal: userPrincipal(_user));

    final entries = (r as Ok<List<CurrentMonthFixtureEntry>>).value;
    expect(entries.every((e) => e.decisivePredictions == null), isTrue);
  });
}
