/// The clubs whose matches never appear (migration 0174, script 92) through
/// the real use-cases: the catalog the clients read leaves them out, and the
/// fixtures sync skips their matches before writing anything.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart'
    show FakeIdGenerator, adminPrincipal, userPrincipal;
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fakes.dart';

const _uel = 'a1740000-0000-0000-0000-000000000001';
const _alkmaar = 'b1740000-0000-0000-0000-000000000001';
const _hapoel = 'b1740000-0000-0000-0000-000000000002';
const _celtic = 'b1740000-0000-0000-0000-000000000003';
const _competition = 'c1740000-0000-0000-0000-000000000001';
const _october = 'd1740000-0000-0000-0000-000000000010';
const _newFixture = 'e1740000-0000-0000-0000-000000000001';

final _now = DateTime.utc(2026, 10, 16, 12);
final _kickoff = DateTime.utc(2026, 10, 22, 16, 45);
final _day = riyadhDayOf(_kickoff);

final List<Team> _catalog = <Team>[
  const Team(
    id: TeamRef(_alkmaar),
    name: 'ألكمار',
    shortName: null,
    crestUrl: null,
  ),
  const Team(
    id: TeamRef(_hapoel),
    name: 'هابوعيل بئر السبع',
    shortName: 'HAP',
    crestUrl: null,
    blocked: true,
  ),
  const Team(
    id: TeamRef(_celtic),
    name: 'سلتيك',
    shortName: null,
    crestUrl: null,
  ),
];

void main() {
  test('the catalog the clients read leaves a blocked club out', () async {
    final result = await ListTeams(repository: FakeTeamRepository(_catalog))(
      principal: userPrincipal('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
    );

    final List<Team> teams = (result as Ok<List<Team>>).value;
    expect(
      <String>[for (final t in teams) t.id.value],
      <String>[_alkmaar, _celtic],
    );
  });

  test('an admin reads the same catalog', () async {
    final result = await ListTeams(repository: FakeTeamRepository(_catalog))(
      principal: adminPrincipal('cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
    );

    expect((result as Ok<List<Team>>).value, hasLength(2));
  });

  group('the fixtures sync', () {
    late FakeFootballDataProvider provider;
    late FakeProviderSyncStore store;
    late FakeFixtureScheduleRepository schedules;
    late SyncProviderFixtures sync;

    setUp(() {
      provider = FakeFootballDataProvider();
      store = FakeProviderSyncStore()
        ..seed('team', 'az', _alkmaar)
        ..seed('team', 'hbs', _hapoel)
        ..seed('team', 'cel', _celtic);
      schedules = FakeFixtureScheduleRepository();
      sync = SyncProviderFixtures(
        providers: {'highlightly': provider},
        store: store,
        leagueRepository: FakeLeagueRepository(const [
          League(
            id: LeagueRef(_uel),
            name: 'الدوري الأوروبي',
            shortName: 'UEL',
            logoUrl: null,
            isContinental: true,
          ),
        ]),
        teamRepository: FakeTeamRepository(_catalog),
        competitionRepository: FakeCompetitionRepository()
          ..seedSeason(
            CompetitionSeason.fromStored(
              id: const SeasonId(_october),
              competitionId: const CompetitionId(_competition),
              label: '10/2026',
              startAt: DateTime.utc(2026, 9, 30, 21),
              endAt: DateTime.utc(2026, 10, 31, 21),
            ),
          ),
        fixtureScheduleRepository: schedules,
        fixturePredictionRepository: FakeFixturePredictionRepository(),
        idGenerator: FakeIdGenerator(const [_newFixture]),
        rules: const [
          ProviderLeagueRule(
            source: 'highlightly',
            externalLeagueId: 'UEL',
            leagueName: 'الدوري الأوروبي',
          ),
        ],
      );
    });

    test(
      'a match of a blocked club is skipped and nothing is written',
      () async {
        provider.answer('UEL', _day, [
          providerMatch(
            id: 'm-hbs',
            league: 'UEL',
            home: 'az',
            away: 'hbs',
            kickoff: _kickoff,
          ),
        ]);

        final report =
            ((await sync.call(now: _now, riyadhDays: [_day], apply: true))
                    as Ok<ProviderSyncReport>)
                .value;

        expect(report.applied, 0);
        expect(report.skipped, 1);
        expect(report.notes.single, startsWith('blocked club:'));
        expect(
          ((await schedules.findByFixture(const FixtureRef(_newFixture)))
                  as Ok<FixtureSchedule?>)
              .value,
          isNull,
        );
        expect(store.map.containsKey('highlightly|fixture|m-hbs'), isFalse);
      },
    );

    test('a match of other clubs of the same evening is added', () async {
      provider.answer('UEL', _day, [
        providerMatch(
          id: 'm-cel',
          league: 'UEL',
          home: 'az',
          away: 'cel',
          kickoff: _kickoff,
        ),
      ]);

      final report =
          ((await sync.call(now: _now, riyadhDays: [_day], apply: true))
                  as Ok<ProviderSyncReport>)
              .value;

      expect(report.applied, 1);
      expect(report.skipped, 0);
    });
  });
}
