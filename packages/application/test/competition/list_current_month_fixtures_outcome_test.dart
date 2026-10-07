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
      homeWins: 60,
      awayWins: 18,
      draws: 22,
    ),
  ]);
}

/// The live card's three-way split -- home win, draw, away win -- over every
/// prediction, draws included, adding up to 100.
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

  test('each entry carries the three-way split of all its calls', () async {
    final r = await useCase(tallies: _Tallies())(
      principal: userPrincipal(_user),
    );

    final entries = (r as Ok<List<CurrentMonthFixtureEntry>>).value;
    final busy = entries.firstWhere(
      (e) => e.fixture.fixtureId.value == _fixture,
    );
    expect(
      (busy.homeOutcomeShare, busy.drawOutcomeShare, busy.awayOutcomeShare),
      (60, 22, 18),
    );
    expect(busy.totalPredictions, 100);
    // The decisive shares keep their own meaning: 60 of 78.
    expect(busy.homeWinPercentage, 77);

    final quiet = entries.firstWhere(
      (e) => e.fixture.fixtureId.value == _quiet,
    );
    expect(
      (quiet.homeOutcomeShare, quiet.drawOutcomeShare, quiet.awayOutcomeShare),
      (0, 0, 0),
    );
    expect(quiet.totalPredictions, 0);
  });

  test('without a tally reader there is no split', () async {
    final r = await useCase()(principal: userPrincipal(_user));

    final entries = (r as Ok<List<CurrentMonthFixtureEntry>>).value;
    expect(entries.every((e) => e.totalPredictions == null), isTrue);
    expect(entries.every((e) => e.drawOutcomeShare == null), isTrue);
  });

  test('a split always adds up to 100', () {
    const tally = FixtureOutcomeTally(
      fixture: FixtureRef(_fixture),
      homeWins: 1,
      awayWins: 1,
      draws: 1,
    );
    final shares = tally.outcomeShares;
    expect(shares.home + shares.draw + shares.away, 100);
    expect((shares.home, shares.draw, shares.away), (34, 33, 33));
  });
}
