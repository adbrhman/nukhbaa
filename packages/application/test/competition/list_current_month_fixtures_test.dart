import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fake_competition_repository.dart';
import 'fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

const _competitionA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _competitionB = 'bbbbbbbb-0000-0000-0000-000000000002';
const _competitionPrivate = 'cccccccc-0000-0000-0000-000000000003';
const _seasonA = 'aaaaaaaa-0000-0000-0000-000000000011';
const _seasonBExpired = 'bbbbbbbb-0000-0000-0000-000000000012';
const _seasonBCurrent = 'bbbbbbbb-0000-0000-0000-000000000013';
const _seasonPrivate = 'cccccccc-0000-0000-0000-000000000014';

const _fixtureX = 'ffffffff-0000-0000-0000-0000000000f1';
const _fixtureY = 'ffffffff-0000-0000-0000-0000000000f2';

final _now = DateTime.utc(2026, 8, 15);

Competition _competition(String id, String name, {bool public = true}) =>
    (Competition.create(
              id: CompetitionId(id),
              name: name,
              format: FormatType.footballScoreline,
              visibility: public
                  ? CompetitionVisibility.public
                  : CompetitionVisibility.private,
            )
            as Ok<Competition>)
        .value;

CompetitionSeason _season(
  String id,
  String competitionId, {
  required DateTime startAt,
  required DateTime endAt,
  String label = '08/2026',
}) =>
    (CompetitionSeason.create(
              id: SeasonId(id),
              competitionId: CompetitionId(competitionId),
              label: label,
              startAt: startAt,
              endAt: endAt,
            )
            as Ok<CompetitionSeason>)
        .value;

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
  late FakeCompetitionRepository competitionRepo;
  late FakeFixturePredictionRepository fixturePredictions;
  late FakeFixtureScheduleRepository scheduleRepo;
  late ListCurrentMonthFixtures useCase;

  setUp(() {
    competitionRepo = FakeCompetitionRepository();
    fixturePredictions = FakeFixturePredictionRepository();
    scheduleRepo = FakeFixtureScheduleRepository();
    useCase = ListCurrentMonthFixtures(
      competitionRepository: competitionRepo,
      fixturePredictionRepository: fixturePredictions,
      fixtureScheduleRepository: scheduleRepo,
      clock: FixedClock(_now),
    );
  });

  test('flattens the current season\'s fixtures of every public competition, '
      'in competition-name then display order', () async {
    competitionRepo
      ..seedCompetition(_competition(_competitionB, 'Beta League'))
      ..seedCompetition(_competition(_competitionA, 'Alpha League'))
      ..seedSeason(
        _season(
          _seasonA,
          _competitionA,
          startAt: DateTime.utc(2026, 8, 1),
          endAt: DateTime.utc(2026, 9, 1),
        ),
      )
      ..seedSeason(
        _season(
          _seasonBCurrent,
          _competitionB,
          startAt: DateTime.utc(2026, 8, 1),
          endAt: DateTime.utc(2026, 9, 1),
        ),
      );
    fixturePredictions
      ..seedSeasonFixture(
        _link(seasonId: _seasonA, fixtureId: _fixtureY, order: 1),
      )
      ..seedSeasonFixture(
        _link(seasonId: _seasonA, fixtureId: _fixtureX, order: 0),
      )
      ..seedSeasonFixture(
        _link(seasonId: _seasonBCurrent, fixtureId: _fixtureX, order: 0),
      );

    final r = await useCase.call(principal: userPrincipal(_user));

    final list = (r as Ok<List<CurrentMonthFixtureEntry>>).value;
    expect(list.map((e) => (e.competitionName, e.fixture.fixtureId.value)), [
      ('Alpha League', _fixtureX),
      ('Alpha League', _fixtureY),
      ('Beta League', _fixtureX),
    ]);
  });

  test('a competition whose season window does not cover now contributes '
      'nothing', () async {
    competitionRepo
      ..seedCompetition(_competition(_competitionB, 'Beta League'))
      ..seedSeason(
        _season(
          _seasonBExpired,
          _competitionB,
          startAt: DateTime.utc(2026, 7, 1),
          endAt: DateTime.utc(2026, 8, 1),
        ),
      );
    fixturePredictions.seedSeasonFixture(
      _link(seasonId: _seasonBExpired, fixtureId: _fixtureX, order: 0),
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    expect((r as Ok<List<CurrentMonthFixtureEntry>>).value, isEmpty);
  });

  test('excludes seasons of private competitions', () async {
    competitionRepo
      ..seedCompetition(
        _competition(_competitionPrivate, 'Private League', public: false),
      )
      ..seedSeason(
        _season(
          _seasonPrivate,
          _competitionPrivate,
          startAt: DateTime.utc(2026, 8, 1),
          endAt: DateTime.utc(2026, 9, 1),
        ),
      );
    fixturePredictions.seedSeasonFixture(
      _link(seasonId: _seasonPrivate, fixtureId: _fixtureX, order: 0),
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    expect((r as Ok<List<CurrentMonthFixtureEntry>>).value, isEmpty);
  });

  test('a current season with no linked fixtures contributes nothing (never '
      'an empty placeholder row)', () async {
    competitionRepo
      ..seedCompetition(_competition(_competitionA, 'Alpha League'))
      ..seedSeason(
        _season(
          _seasonA,
          _competitionA,
          startAt: DateTime.utc(2026, 8, 1),
          endAt: DateTime.utc(2026, 9, 1),
        ),
      );

    final r = await useCase.call(principal: userPrincipal(_user));

    expect((r as Ok<List<CurrentMonthFixtureEntry>>).value, isEmpty);
  });

  test('no public competitions anywhere is a legitimate empty list', () async {
    final r = await useCase.call(principal: userPrincipal(_user));

    expect(r, isA<Ok<List<CurrentMonthFixtureEntry>>>());
    expect((r as Ok<List<CurrentMonthFixtureEntry>>).value, isEmpty);
  });

  test('a linked fixture with a registered schedule carries its team names '
      'and kickoff', () async {
    competitionRepo
      ..seedCompetition(_competition(_competitionA, 'Alpha League'))
      ..seedSeason(
        _season(
          _seasonA,
          _competitionA,
          startAt: DateTime.utc(2026, 8, 1),
          endAt: DateTime.utc(2026, 9, 1),
        ),
      );
    fixturePredictions.seedSeasonFixture(
      _link(seasonId: _seasonA, fixtureId: _fixtureX, order: 0),
    );
    scheduleRepo.seed(
      (FixtureSchedule.create(
                fixture: const FixtureRef(_fixtureX),
                homeTeam: 'Al Hilal',
                awayTeam: 'Al Nassr',
                kickoffAt: DateTime.utc(2026, 8, 20, 18),
              )
              as Ok<FixtureSchedule>)
          .value,
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    final entry = (r as Ok<List<CurrentMonthFixtureEntry>>).value.single;
    expect(entry.fixture.homeTeam, 'Al Hilal');
    expect(entry.fixture.awayTeam, 'Al Nassr');
    expect(entry.fixture.kickoffAt, DateTime.utc(2026, 8, 20, 18));
  });

  test('a linked fixture with no registered schedule carries null fields '
      '(Axiom 3)', () async {
    competitionRepo
      ..seedCompetition(_competition(_competitionA, 'Alpha League'))
      ..seedSeason(
        _season(
          _seasonA,
          _competitionA,
          startAt: DateTime.utc(2026, 8, 1),
          endAt: DateTime.utc(2026, 9, 1),
        ),
      );
    fixturePredictions.seedSeasonFixture(
      _link(seasonId: _seasonA, fixtureId: _fixtureX, order: 0),
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    final entry = (r as Ok<List<CurrentMonthFixtureEntry>>).value.single;
    expect(entry.fixture.homeTeam, isNull);
    expect(entry.fixture.awayTeam, isNull);
    expect(entry.fixture.kickoffAt, isNull);
  });

  test('a transient competition-repository failure on the competitions query '
      'is propagated unchanged', () async {
    competitionRepo.failNextWith(
      const AppError.transient('db.unavailable', 'connection reset'),
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    final err = (r as Err<List<CurrentMonthFixtureEntry>>).error;
    expect(err.kind, ErrorKind.transient);
    expect(err.code, 'db.unavailable');
  });

  test('a transient fixture-prediction-repository failure on the '
      'season-fixtures query is propagated unchanged', () async {
    competitionRepo
      ..seedCompetition(_competition(_competitionA, 'Alpha League'))
      ..seedSeason(
        _season(
          _seasonA,
          _competitionA,
          startAt: DateTime.utc(2026, 8, 1),
          endAt: DateTime.utc(2026, 9, 1),
        ),
      );
    fixturePredictions.failNextWith(
      const AppError.transient('db.unavailable', 'connection reset'),
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    final err = (r as Err<List<CurrentMonthFixtureEntry>>).error;
    expect(err.kind, ErrorKind.transient);
    expect(err.code, 'db.unavailable');
  });
}
