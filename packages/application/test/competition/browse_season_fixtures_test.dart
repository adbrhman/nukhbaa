import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _season = '55555555-5555-5555-5555-555555555555';
const _otherSeason = '66666666-6666-6666-6666-666666666666';

const _fa = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _fb = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _fc = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

SeasonFixture _link({
  required String seasonId,
  required String fixtureId,
  required int order,
}) =>
    (SeasonFixture.create(
              seasonId: SeasonId(seasonId),
              fixture: FixtureRef(fixtureId),
              displayOrder: order,
            )
            as Ok<SeasonFixture>)
        .value;

void main() {
  late FakeFixturePredictionRepository fixturePredictions;
  late FakeFixtureScheduleRepository scheduleRepo;
  late BrowseSeasonFixtures useCase;

  setUp(() {
    fixturePredictions = FakeFixturePredictionRepository();
    scheduleRepo = FakeFixtureScheduleRepository();
    useCase = BrowseSeasonFixtures(
      fixturePredictionRepository: fixturePredictions,
      fixtureScheduleRepository: scheduleRepo,
    );
  });

  test(
    'an authenticated user browses a season\'s fixtures in display order',
    () async {
      // Seeded out of order to prove the read imposes display_order ordering.
      fixturePredictions.seedSeasonFixture(
        _link(seasonId: _season, fixtureId: _fb, order: 1),
      );
      fixturePredictions.seedSeasonFixture(
        _link(seasonId: _season, fixtureId: _fa, order: 0),
      );
      fixturePredictions.seedSeasonFixture(
        _link(seasonId: _season, fixtureId: _fc, order: 2),
      );

      final r = await useCase.call(
        principal: userPrincipal(_user),
        seasonId: _season,
      );

      final list = (r as Ok<List<SeasonFixtureCard>>).value;
      expect(list.map((x) => x.fixtureId.value).toList(), [_fa, _fb, _fc]);
    },
  );

  test('a linked fixture with a registered schedule carries its team names '
      'and kickoff', () async {
    fixturePredictions.seedSeasonFixture(
      _link(seasonId: _season, fixtureId: _fa, order: 0),
    );
    final schedule =
        (FixtureSchedule.create(
                  fixture: const FixtureRef(_fa),
                  homeTeam: 'Al Hilal',
                  awayTeam: 'Al Nassr',
                  kickoffAt: DateTime.utc(2026, 8, 20, 18),
                )
                as Ok<FixtureSchedule>)
            .value;
    scheduleRepo.seed(schedule);

    final r = await useCase.call(
      principal: userPrincipal(_user),
      seasonId: _season,
    );

    final card = (r as Ok<List<SeasonFixtureCard>>).value.single;
    expect(card.homeTeam, 'Al Hilal');
    expect(card.awayTeam, 'Al Nassr');
    expect(card.kickoffAt, DateTime.utc(2026, 8, 20, 18));
  });

  test('a linked fixture with no registered schedule yet carries null fields '
      '(Axiom 3 — the link never verifies a schedule exists)', () async {
    fixturePredictions.seedSeasonFixture(
      _link(seasonId: _season, fixtureId: _fa, order: 0),
    );

    final r = await useCase.call(
      principal: userPrincipal(_user),
      seasonId: _season,
    );

    final card = (r as Ok<List<SeasonFixtureCard>>).value.single;
    expect(card.homeTeam, isNull);
    expect(card.awayTeam, isNull);
    expect(card.kickoffAt, isNull);
  });

  test('only the requested season\'s fixtures are returned', () async {
    fixturePredictions.seedSeasonFixture(
      _link(seasonId: _season, fixtureId: _fa, order: 0),
    );
    fixturePredictions.seedSeasonFixture(
      _link(seasonId: _otherSeason, fixtureId: _fb, order: 0),
    );

    final r = await useCase.call(
      principal: userPrincipal(_user),
      seasonId: _season,
    );

    final list = (r as Ok<List<SeasonFixtureCard>>).value;
    expect(list.map((x) => x.fixtureId.value).toList(), [_fa]);
  });

  test(
    'an absent/empty season is a legitimate empty list, never not-found',
    () async {
      final r = await useCase.call(
        principal: userPrincipal(_user),
        seasonId: _season,
      );

      expect(r, isA<Ok<List<SeasonFixtureCard>>>());
      expect((r as Ok<List<SeasonFixtureCard>>).value, isEmpty);
    },
  );

  test('a malformed id is a validation error before any lookup', () async {
    final r = await useCase.call(
      principal: userPrincipal(_user),
      seasonId: 'not-a-uuid',
    );

    expect(
      (r as Err<List<SeasonFixtureCard>>).error.kind,
      ErrorKind.validation,
    );
  });

  test('a transient fixture-prediction-repository failure is propagated '
      'unchanged', () async {
    fixturePredictions.failNextWith(
      const AppError.transient('db.unavailable', 'connection reset'),
    );

    final r = await useCase.call(
      principal: userPrincipal(_user),
      seasonId: _season,
    );

    final err = (r as Err<List<SeasonFixtureCard>>).error;
    expect(err.kind, ErrorKind.transient);
    expect(err.code, 'db.unavailable');
  });
}
