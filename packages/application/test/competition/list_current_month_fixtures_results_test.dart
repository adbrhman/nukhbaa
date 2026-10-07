import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import '../scoring/fakes.dart' show FakeFixtureResultRepository;
import 'fake_competition_repository.dart';
import 'fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _competition = 'aaaaaaaa-0000-0000-0000-000000000001';
const _season = 'aaaaaaaa-0000-0000-0000-000000000011';
const _played = 'ffffffff-0000-0000-0000-0000000000f1';
const _coming = 'ffffffff-0000-0000-0000-0000000000f2';

/// The feed carries each fixture's recorded result, read in one batch, so
/// a finished card shows the final score without asking per card; a
/// failed read leaves the results out rather than failing the feed.
void main() {
  late FakeFixtureResultRepository results;
  late ListCurrentMonthFixtures useCase;

  setUp(() {
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
    for (final (String id, int order) in [(_played, 0), (_coming, 1)]) {
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
    results = FakeFixtureResultRepository()
      ..seed(
        const FixtureResult.fromStored(
          fixture: FixtureRef(_played),
          homeGoals: 2,
          awayGoals: 1,
        ),
      );
    useCase = ListCurrentMonthFixtures(
      competitionRepository: competitions,
      fixturePredictionRepository: fixtures,
      fixtureScheduleRepository: FakeFixtureScheduleRepository(),
      clock: FixedClock(DateTime.utc(2026, 10, 7)),
      resultRepository: results,
    );
  });

  test('a played fixture carries its recorded result, the rest none', () async {
    final r = await useCase.call(principal: userPrincipal(_user));

    final entries = (r as Ok<List<CurrentMonthFixtureEntry>>).value;
    final played = entries.firstWhere(
      (e) => e.fixture.fixtureId.value == _played,
    );
    final coming = entries.firstWhere(
      (e) => e.fixture.fixtureId.value == _coming,
    );
    expect((played.resultHomeGoals, played.resultAwayGoals), (2, 1));
    expect((coming.resultHomeGoals, coming.resultAwayGoals), (null, null));
  });

  test('a failed result read leaves the results out, not the feed', () async {
    results.failNextWith(const AppError.transient('db.down', 'down'));

    final r = await useCase.call(principal: userPrincipal(_user));

    final entries = (r as Ok<List<CurrentMonthFixtureEntry>>).value;
    expect(entries, hasLength(2));
    expect(entries.every((e) => e.resultHomeGoals == null), isTrue);
  });
}
