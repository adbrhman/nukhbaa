import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fakes.dart';

const _pl = 'a1000000-0000-0000-0000-000000000001';
const _f1 = 'f1000000-0000-0000-0000-000000000001';
const _f2 = 'f1000000-0000-0000-0000-000000000002';

final _kickoff = DateTime.utc(2026, 9, 19, 14);
final _now = DateTime.utc(2026, 9, 19, 17);
final _day = riyadhDayOf(_kickoff);

typedef _Call = ({String fixtureId, int home, int away});

void main() {
  late FakeFootballDataProvider provider;
  late FakeProviderSyncStore store;
  late List<_Call> recorded;
  late SyncProviderResults sync;

  setUp(() {
    provider = FakeFootballDataProvider();
    store = FakeProviderSyncStore()
      ..pending = [
        PendingProviderFixture(
          fixtureId: _f1,
          externalId: 'm1',
          kickoffAt: _kickoff,
          leagueId: _pl,
        ),
        PendingProviderFixture(
          fixtureId: _f2,
          externalId: 'm2',
          kickoffAt: _kickoff,
          leagueId: _pl,
        ),
      ];
    recorded = <_Call>[];
    sync = SyncProviderResults(
      providers: {'highlightly': provider},
      store: store,
      leagueRepository: FakeLeagueRepository(const [
        League(
          id: LeagueRef(_pl),
          name: 'الإنجليزي',
          shortName: null,
          logoUrl: null,
        ),
      ]),
      rules: const [
        ProviderLeagueRule(
          source: 'highlightly',
          externalLeagueId: 'PL',
          leagueName: 'الإنجليزي',
        ),
      ],
      // Confirmation is off here, so these tests are about recording alone;
      // the 'result confirmation' group below turns it on.
      confirmAfter: Duration.zero,
      recorder:
          ({
            required String fixtureId,
            required int homeGoals,
            required int awayGoals,
          }) async {
            recorded.add((
              fixtureId: fixtureId,
              home: homeGoals,
              away: awayGoals,
            ));
            return const Result.ok(null);
          },
    );
  });

  test('records finished matches, one provider call per league-day', () async {
    provider.answer('PL', _day, [
      providerMatch(
        id: 'm1',
        league: 'PL',
        home: 'a',
        away: 'b',
        kickoff: _kickoff,
        status: ProviderMatchStatus.finished,
        homeGoals: 2,
        awayGoals: 1,
      ),
      providerMatch(
        id: 'm2',
        league: 'PL',
        home: 'c',
        away: 'd',
        kickoff: _kickoff,
        status: ProviderMatchStatus.live,
        homeGoals: 0,
        awayGoals: 0,
      ),
    ]);

    final report =
        ((await sync.call(now: _now, apply: true)) as Ok<ProviderSyncReport>)
            .value;

    expect(provider.calls, hasLength(1));
    expect(recorded, [(fixtureId: _f1, home: 2, away: 1)]);
    expect(report.applied, 1);
    expect(report.alreadyKnown, 1);
  });

  test('shadow mode records nothing', () async {
    provider.answer('PL', _day, [
      providerMatch(
        id: 'm1',
        league: 'PL',
        home: 'a',
        away: 'b',
        kickoff: _kickoff,
        status: ProviderMatchStatus.finished,
        homeGoals: 1,
        awayGoals: 1,
      ),
    ]);

    final report =
        ((await sync.call(now: _now, apply: false)) as Ok<ProviderSyncReport>)
            .value;

    expect(recorded, isEmpty);
    expect(report.applied, 1);
  });

  test('a postponed match is left for an admin', () async {
    provider.answer('PL', _day, [
      providerMatch(
        id: 'm1',
        league: 'PL',
        home: 'a',
        away: 'b',
        kickoff: _kickoff,
        status: ProviderMatchStatus.postponed,
      ),
    ]);

    final report =
        ((await sync.call(now: _now, apply: true)) as Ok<ProviderSyncReport>)
            .value;

    expect(recorded, isEmpty);
    expect(report.notes.first, startsWith('needs admin (postponed)'));
    // Not only a log line: the scheduler files it for the admins.
    expect(report.attention.single.code, 'provider_sync.match_postponed');
    expect(report.attention.single.match, 'home-a - away-b');
  });

  test('a cancelled match is left for an admin', () async {
    provider.answer('PL', _day, [
      providerMatch(
        id: 'm1',
        league: 'PL',
        home: 'a',
        away: 'b',
        kickoff: _kickoff,
        status: ProviderMatchStatus.cancelled,
      ),
    ]);

    final report =
        ((await sync.call(now: _now, apply: true)) as Ok<ProviderSyncReport>)
            .value;

    expect(recorded, isEmpty);
    expect(report.attention.single.code, 'provider_sync.match_cancelled');
    expect(report.attention.single.message, contains('أخفِها'));
  });

  test('nothing is fetched before a match can have ended', () async {
    final report =
        ((await sync.call(
                  now: _kickoff.add(const Duration(minutes: 60)),
                  apply: true,
                ))
                as Ok<ProviderSyncReport>)
            .value;

    expect(provider.calls, isEmpty);
    expect(report.requests, 0);
  });

  group('result confirmation', () {
    final base = DateTime.utc(2026, 9, 19, 16);

    // A use-case with the default confirmation time (15 minutes).
    SyncProviderResults confirming() => SyncProviderResults(
      providers: {'highlightly': provider},
      store: store,
      leagueRepository: FakeLeagueRepository(const [
        League(
          id: LeagueRef(_pl),
          name: 'English',
          shortName: null,
          logoUrl: null,
        ),
      ]),
      rules: const [
        ProviderLeagueRule(
          source: 'highlightly',
          externalLeagueId: 'PL',
          leagueName: 'English',
        ),
      ],
      recorder:
          ({
            required String fixtureId,
            required int homeGoals,
            required int awayGoals,
          }) async {
            recorded.add((
              fixtureId: fixtureId,
              home: homeGoals,
              away: awayGoals,
            ));
            return const Result.ok(null);
          },
    );

    void provides(ProviderMatchStatus status, {int? home, int? away}) {
      provider.answer('PL', _day, [
        providerMatch(
          id: 'm1',
          league: 'PL',
          home: 'a',
          away: 'b',
          kickoff: _kickoff,
          status: status,
          homeGoals: home,
          awayGoals: away,
        ),
      ]);
    }

    Future<ProviderSyncReport> runAt(
      SyncProviderResults use,
      Duration afterBase,
    ) async =>
        ((await use.call(now: base.add(afterBase), apply: true))
                as Ok<ProviderSyncReport>)
            .value;

    setUp(() {
      store.pending = [store.pending.first];
    });

    test(
      'a finished score is recorded only after it stands for 15 minutes',
      () async {
        final use = confirming();
        provides(ProviderMatchStatus.finished, home: 2, away: 0);

        final first = await runAt(use, Duration.zero);
        expect(recorded, isEmpty);
        expect(first.applied, 0);
        expect(first.alreadyKnown, 1);
        expect(
          first.notes.single,
          startsWith('finished, confirming for 15 min'),
        );

        await runAt(use, const Duration(minutes: 14));
        expect(recorded, isEmpty);

        final last = await runAt(use, const Duration(minutes: 15));
        expect(recorded, [(fixtureId: _f1, home: 2, away: 0)]);
        expect(last.applied, 1);
      },
    );

    test('a score the provider corrects is recorded as corrected', () async {
      final use = confirming();
      provides(ProviderMatchStatus.finished, home: 2, away: 0);
      await runAt(use, Duration.zero);

      // The provider drops the goal that was ruled out.
      provides(ProviderMatchStatus.finished, home: 1, away: 0);
      final changed = await runAt(use, const Duration(minutes: 10));
      expect(changed.notes.single, startsWith('score changed from 2-0'));

      await runAt(use, const Duration(minutes: 20));
      expect(recorded, isEmpty);

      await runAt(use, const Duration(minutes: 25));
      expect(recorded, [(fixtureId: _f1, home: 1, away: 0)]);
    });

    test('a match that leaves finished has to be confirmed again', () async {
      final use = confirming();
      provides(ProviderMatchStatus.finished, home: 1, away: 0);
      await runAt(use, Duration.zero);

      provides(ProviderMatchStatus.live);
      await runAt(use, const Duration(minutes: 10));

      provides(ProviderMatchStatus.finished, home: 1, away: 0);
      await runAt(use, const Duration(minutes: 20));
      await runAt(use, const Duration(minutes: 30));
      expect(recorded, isEmpty);

      await runAt(use, const Duration(minutes: 35));
      expect(recorded, [(fixtureId: _f1, home: 1, away: 0)]);
    });
  });

  // C-03: a kickoff brought forward and announced too late for the fixtures
  // sync is seen here, the last time before the result is recorded.
  group('a kickoff brought forward is followed before the result', () {
    const arsenal = 'b1000000-0000-0000-0000-000000000001';
    const chelsea = 'b1000000-0000-0000-0000-000000000002';
    const september = 'd1000000-0000-0000-0000-000000000009';
    const competition = 'c1000000-0000-0000-0000-000000000001';
    late FakeFixtureScheduleRepository schedules;
    late List<DateTime> kickoffWhenRecorded;
    late SyncProviderResults following;

    setUp(() {
      store
        ..seed('team', 'a', arsenal)
        ..seed('team', 'b', chelsea);
      schedules = FakeFixtureScheduleRepository()
        ..seed(
          (FixtureSchedule.create(
                    fixture: const FixtureRef(_f1),
                    homeTeam: 'أرسنال',
                    awayTeam: 'تشيلسي',
                    kickoffAt: _kickoff,
                    homeTeamId: const TeamRef(arsenal),
                    awayTeamId: const TeamRef(chelsea),
                    leagueId: const LeagueRef(_pl),
                  )
                  as Ok<FixtureSchedule>)
              .value,
        );
      final competitions = FakeCompetitionRepository()
        ..seedSeason(
          CompetitionSeason.fromStored(
            id: const SeasonId(september),
            competitionId: const CompetitionId(competition),
            label: '09/2026',
            startAt: DateTime.utc(2026, 9),
            endAt: DateTime.utc(2026, 10),
          ),
        );
      kickoffWhenRecorded = <DateTime>[];
      following = SyncProviderResults(
        providers: {'highlightly': provider},
        store: store,
        leagueRepository: FakeLeagueRepository(const [
          League(
            id: LeagueRef(_pl),
            name: 'الإنجليزي',
            shortName: null,
            logoUrl: null,
          ),
        ]),
        rules: const [
          ProviderLeagueRule(
            source: 'highlightly',
            externalLeagueId: 'PL',
            leagueName: 'الإنجليزي',
          ),
        ],
        confirmAfter: Duration.zero,
        kickoffFollower: FollowProviderKickoff(
          fixtureScheduleRepository: schedules,
          competitionRepository: competitions,
        ),
        recorder:
            ({
              required String fixtureId,
              required int homeGoals,
              required int awayGoals,
            }) async {
              final stored = await schedules.findByFixture(
                FixtureRef(fixtureId),
              );
              kickoffWhenRecorded.add(
                (stored as Ok<FixtureSchedule?>).value!.kickoffAt,
              );
              recorded.add((
                fixtureId: fixtureId,
                home: homeGoals,
                away: awayGoals,
              ));
              return const Result.ok(null);
            },
      );
    });

    test('the kickoff moves before the result is recorded', () async {
      final earlier = _kickoff.subtract(const Duration(hours: 3));
      provider.answer('PL', _day, [
        providerMatch(
          id: 'm1',
          league: 'PL',
          home: 'a',
          away: 'b',
          kickoff: earlier,
          status: ProviderMatchStatus.finished,
          homeGoals: 2,
          awayGoals: 0,
        ),
      ]);

      final report =
          ((await following.call(now: _now, apply: true))
                  as Ok<ProviderSyncReport>)
              .value;

      expect(recorded, [(fixtureId: _f1, home: 2, away: 0)]);
      expect(kickoffWhenRecorded, [
        earlier,
      ], reason: 'ScoreFixture grades from the real kickoff');
      expect(report.notes, contains(startsWith('moved kickoff')));
      expect(report.attention, isEmpty);
    });

    test(
      'a kickoff within a minute of the stored one is not looked up',
      () async {
        provider.answer('PL', _day, [
          providerMatch(
            id: 'm1',
            league: 'PL',
            home: 'a',
            away: 'b',
            kickoff: _kickoff.add(const Duration(seconds: 30)),
            status: ProviderMatchStatus.finished,
            homeGoals: 1,
            awayGoals: 1,
          ),
        ]);

        final report =
            ((await following.call(now: _now, apply: true))
                    as Ok<ProviderSyncReport>)
                .value;

        expect(kickoffWhenRecorded, [_kickoff]);
        expect(report.notes.where((n) => n.contains('kickoff')), isEmpty);
      },
    );

    test('a match whose teams are not on file is recorded and left for an '
        'admin', () async {
      final earlier = _kickoff.subtract(const Duration(hours: 3));
      provider.answer('PL', _day, [
        providerMatch(
          id: 'm1',
          league: 'PL',
          home: 'a',
          away: 'zzz',
          kickoff: earlier,
          status: ProviderMatchStatus.finished,
          homeGoals: 1,
          awayGoals: 0,
        ),
      ]);

      final report =
          ((await following.call(now: _now, apply: true))
                  as Ok<ProviderSyncReport>)
              .value;

      expect(kickoffWhenRecorded, [_kickoff]);
      expect(
        report.attention.single.code,
        'provider_sync.kickoff_teams_differ',
      );
    });
  });
}
