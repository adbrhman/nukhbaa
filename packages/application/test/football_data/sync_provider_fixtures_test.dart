import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart' show FakeIdGenerator;
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fakes.dart';

const _pl = 'a1000000-0000-0000-0000-000000000001';
const _laLiga = 'a1000000-0000-0000-0000-000000000002';
const _cup = 'a1000000-0000-0000-0000-000000000003';
const _arsenal = 'b1000000-0000-0000-0000-000000000001';
const _chelsea = 'b1000000-0000-0000-0000-000000000002';
const _madrid = 'b1000000-0000-0000-0000-000000000003';
const _getafe = 'b1000000-0000-0000-0000-000000000004';
const _competition = 'c1000000-0000-0000-0000-000000000001';
const _september = 'd1000000-0000-0000-0000-000000000009';
const _newFixture = 'e1000000-0000-0000-0000-000000000001';

final _now = DateTime.utc(2026, 9, 16, 12);
final _kickoff = DateTime.utc(2026, 9, 19, 14);
final _day = riyadhDayOf(_kickoff);

const _rules = [
  ProviderLeagueRule(
    source: 'highlightly',
    externalLeagueId: 'PL',
    leagueName: 'الإنجليزي',
  ),
  ProviderLeagueRule(
    source: 'highlightly',
    externalLeagueId: 'LL',
    leagueName: 'الإسباني',
    clubs: {'rm'},
  ),
  ProviderLeagueRule(
    source: 'highlightly',
    externalLeagueId: 'LC',
    leagueName: 'كأس الرابطة',
    bothFromLeagueName: 'الإنجليزي',
  ),
];

Team _team(String id, String name, String league) => Team(
  id: TeamRef(id),
  name: name,
  shortName: null,
  crestUrl: null,
  leagueId: LeagueRef(league),
);

void main() {
  late FakeFootballDataProvider provider;
  late FakeProviderSyncStore store;
  late FakeFixtureScheduleRepository schedules;
  late FakeFixturePredictionRepository links;
  late SyncProviderFixtures sync;

  setUp(() {
    provider = FakeFootballDataProvider();
    store = FakeProviderSyncStore()
      ..seed('team', 'ars', _arsenal)
      ..seed('team', 'che', _chelsea)
      ..seed('team', 'rm', _madrid)
      ..seed('team', 'get', _getafe);
    schedules = FakeFixtureScheduleRepository();
    links = FakeFixturePredictionRepository();
    final competitions = FakeCompetitionRepository()
      ..seedSeason(
        CompetitionSeason.fromStored(
          id: const SeasonId(_september),
          competitionId: const CompetitionId(_competition),
          label: '09/2026',
          startAt: DateTime.utc(2026, 9),
          endAt: DateTime.utc(2026, 10),
        ),
      );
    sync = SyncProviderFixtures(
      providers: {'highlightly': provider},
      store: store,
      leagueRepository: FakeLeagueRepository(const [
        League(
          id: LeagueRef(_pl),
          name: 'الإنجليزي',
          shortName: null,
          logoUrl: null,
        ),
        League(
          id: LeagueRef(_laLiga),
          name: 'الإسباني',
          shortName: null,
          logoUrl: null,
        ),
        League(
          id: LeagueRef(_cup),
          name: 'كأس الرابطة',
          shortName: null,
          logoUrl: null,
          isContinental: true,
        ),
      ]),
      teamRepository: FakeTeamRepository([
        _team(_arsenal, 'أرسنال', _pl),
        _team(_chelsea, 'تشيلسي', _pl),
        _team(_madrid, 'ريال مدريد', _laLiga),
        _team(_getafe, 'خيتافي', _laLiga),
      ]),
      competitionRepository: competitions,
      fixtureScheduleRepository: schedules,
      fixturePredictionRepository: links,
      idGenerator: FakeIdGenerator(const [_newFixture]),
      rules: _rules,
    );
  });

  test('adds a selected match like an admin would', () async {
    provider.answer('PL', _day, [
      providerMatch(
        id: 'm1',
        league: 'PL',
        home: 'ars',
        away: 'che',
        kickoff: _kickoff,
      ),
    ]);

    final result = await sync.call(now: _now, riyadhDays: [_day], apply: true);

    expect((result as Ok<ProviderSyncReport>).value.applied, 1);
    final saved =
        ((await schedules.findByFixture(const FixtureRef(_newFixture)))
                as Ok<FixtureSchedule?>)
            .value!;
    expect(saved.homeTeam, 'أرسنال');
    expect(saved.awayTeam, 'تشيلسي');
    expect(saved.homeTeamId, const TeamRef(_arsenal));
    expect(saved.leagueId, const LeagueRef(_pl));
    expect(saved.kickoffAt, _kickoff);
    final linked =
        ((await links.listSeasonFixtures(const SeasonId(_september)))
                as Ok<List<FixtureRef>>)
            .value;
    expect(linked, [const FixtureRef(_newFixture)]);
    expect(store.map['highlightly|fixture|m1'], _newFixture);
  });

  test('shadow mode writes nothing', () async {
    provider.answer('PL', _day, [
      providerMatch(
        id: 'm1',
        league: 'PL',
        home: 'ars',
        away: 'che',
        kickoff: _kickoff,
      ),
    ]);

    final result = await sync.call(now: _now, riyadhDays: [_day], apply: false);

    final report = (result as Ok<ProviderSyncReport>).value;
    expect(report.applied, 1);
    expect(report.notes.single, startsWith('would add'));
    expect(
      ((await schedules.findByFixture(const FixtureRef(_newFixture)))
              as Ok<FixtureSchedule?>)
          .value,
      isNull,
    );
    expect(store.map.containsKey('highlightly|fixture|m1'), isFalse);
  });

  test('a match added on an earlier run is not added again', () async {
    store.seed('fixture', 'm1', 'e1000000-0000-0000-0000-00000000000f');
    provider.answer('PL', _day, [
      providerMatch(
        id: 'm1',
        league: 'PL',
        home: 'ars',
        away: 'che',
        kickoff: _kickoff,
      ),
    ]);

    final report =
        ((await sync.call(now: _now, riyadhDays: [_day], apply: true))
                as Ok<ProviderSyncReport>)
            .value;

    expect(report.applied, 0);
    expect(report.alreadyKnown, 1);
  });

  test('a club rule admits only matches of a listed club', () async {
    provider.answer('LL', _day, [
      providerMatch(
        id: 'x',
        league: 'LL',
        home: 'get',
        away: 'zzz',
        kickoff: _kickoff,
      ),
      providerMatch(
        id: 'y',
        league: 'LL',
        home: 'get',
        away: 'rm',
        kickoff: _kickoff,
      ),
    ]);

    final report =
        ((await sync.call(now: _now, riyadhDays: [_day], apply: false))
                as Ok<ProviderSyncReport>)
            .value;

    expect(report.applied, 1);
    expect(report.notes.single, contains('خيتافي - ريال مدريد'));
  });

  test('an unmapped team is skipped, never guessed', () async {
    provider.answer('PL', _day, [
      providerMatch(
        id: 'm2',
        league: 'PL',
        home: 'ars',
        away: 'new',
        kickoff: _kickoff,
      ),
    ]);

    final report =
        ((await sync.call(now: _now, riyadhDays: [_day], apply: true))
                as Ok<ProviderSyncReport>)
            .value;

    expect(report.applied, 0);
    expect(report.skipped, 1);
    expect(report.notes.single, startsWith('unmapped team'));
  });

  test('League Cup ties are added only between Premier League clubs', () async {
    provider.answer('LC', _day, [
      providerMatch(
        id: 'c1',
        league: 'LC',
        home: 'ars',
        away: 'che',
        kickoff: _kickoff,
      ),
      providerMatch(
        id: 'c2',
        league: 'LC',
        home: 'ars',
        away: 'rm',
        kickoff: _kickoff,
      ),
    ]);

    final report =
        ((await sync.call(now: _now, riyadhDays: [_day], apply: false))
                as Ok<ProviderSyncReport>)
            .value;

    expect(report.applied, 1);
    expect(report.skipped, 1);
  });

  test('too-soon, started and out-of-contest matches are left alone', () async {
    provider.answer('PL', _day, [
      providerMatch(
        id: 'soon',
        league: 'PL',
        home: 'ars',
        away: 'che',
        kickoff: _now.add(const Duration(minutes: 10)),
      ),
      providerMatch(
        id: 'live',
        league: 'PL',
        home: 'ars',
        away: 'che',
        kickoff: _kickoff,
        status: ProviderMatchStatus.live,
      ),
      providerMatch(
        id: 'october',
        league: 'PL',
        home: 'ars',
        away: 'che',
        kickoff: DateTime.utc(2026, 10, 3, 14),
      ),
    ]);

    final report =
        ((await sync.call(now: _now, riyadhDays: [_day], apply: true))
                as Ok<ProviderSyncReport>)
            .value;

    expect(report.applied, 0);
    expect(report.skipped, 1);
    expect(report.notes.single, startsWith('no monthly contest'));
  });

  test(
    'a hand-added fixture is adopted even after the provider reports it finished',
    () async {
      const handAdded = 'e1000000-0000-0000-0000-0000000000ab';

      final finishedKickoff = _now.subtract(const Duration(hours: 3));

      store.existing['$_arsenal|$_chelsea'] = (finishedKickoff, handAdded);

      provider.answer('PL', riyadhDayOf(finishedKickoff), [
        providerMatch(
          id: 'finished-1',
          league: 'PL',
          home: 'ars',
          away: 'che',
          kickoff: finishedKickoff,
          status: ProviderMatchStatus.finished,
          homeGoals: 2,
          awayGoals: 1,
        ),
      ]);

      final report =
          ((await sync.call(
                    now: _now,
                    riyadhDays: [riyadhDayOf(finishedKickoff)],
                    apply: true,
                  ))
                  as Ok<ProviderSyncReport>)
              .value;

      expect(report.applied, 0);
      expect(report.alreadyKnown, 1);
      expect(store.map['highlightly|fixture|finished-1'], handAdded);
    },
  );

  test('a fixture already added by hand is adopted, not duplicated', () async {
    const handAdded = 'e1000000-0000-0000-0000-0000000000aa';
    store.existing['$_arsenal|$_chelsea'] = (
      _kickoff.add(const Duration(hours: 1)),
      handAdded,
    );
    provider.answer('PL', _day, [
      providerMatch(
        id: 'm1',
        league: 'PL',
        home: 'ars',
        away: 'che',
        kickoff: _kickoff,
      ),
    ]);

    final report =
        ((await sync.call(now: _now, riyadhDays: [_day], apply: true))
                as Ok<ProviderSyncReport>)
            .value;

    expect(report.applied, 0);
    expect(report.alreadyKnown, 1);
    expect(store.map['highlightly|fixture|m1'], handAdded);
    expect(
      ((await schedules.findByFixture(const FixtureRef(_newFixture)))
              as Ok<FixtureSchedule?>)
          .value,
      isNull,
    );
  });

  test(
    'League Cup ties with an unmapped side are passed over quietly',
    () async {
      provider.answer('LC', _day, [
        providerMatch(
          id: 'c3',
          league: 'LC',
          home: 'ars',
          away: 'nobody',
          kickoff: _kickoff,
        ),
      ]);

      final report =
          ((await sync.call(now: _now, riyadhDays: [_day], apply: false))
                  as Ok<ProviderSyncReport>)
              .value;

      expect(report.skipped, 1);
      expect(report.notes, isEmpty);
    },
  );

  test('a quota stop ends the run', () async {
    provider.answers['PL|${isoDay(_day)}'] = const Result.err(
      AppError.transient(providerQuotaErrorCode, 'reserve'),
    );

    final report =
        ((await sync.call(now: _now, riyadhDays: [_day], apply: true))
                as Ok<ProviderSyncReport>)
            .value;

    expect(provider.calls, ['PL|${isoDay(_day)}']);
    expect(report.requests, 1);
  });
}
