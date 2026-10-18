import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

// Paris FC - Rennes, 2026-10-18: Rennes' second goal was ruled out by VAR in
// the 51st minute, and the feed still reported 2-2 eleven minutes later.
const _fl1 = 'a1000000-0000-0000-0000-0000000000f1';
const _fixture = 'f1000000-0000-0000-0000-000000000018';
const _other = 'f1000000-0000-0000-0000-000000000019';

const _admin = AuthenticatedUser(
  userId: UserId('5e5e5e5e-0000-4000-8000-0000000001c1'),
  role: PlatformRole.admin,
);
const _player = AuthenticatedUser(
  userId: UserId('5e5e5e5e-0000-4000-8000-0000000001c2'),
  role: PlatformRole.user,
);

final _kickoff = DateTime.utc(2026, 10, 18, 15);
final _day = riyadhDayOf(_kickoff);

/// The provider's figures, as the poll writes them.
final class _RawBoard implements LiveScoreBoard {
  final Map<String, LiveScore> scores = {};

  @override
  void put(Map<String, LiveScore> s) => scores.addAll(s);

  @override
  void remove(Iterable<String> ids) => ids.forEach(scores.remove);

  @override
  Map<String, LiveScore> read(Iterable<String> ids) => {
    for (final id in ids)
      if (scores[id] != null) id: scores[id]!,
  };
}

final class _Corrections implements LiveScoreCorrections {
  final Map<String, LiveScoreCorrection> map = {};

  @override
  void set(String fixtureId, LiveScoreCorrection correction) =>
      map[fixtureId] = correction;

  @override
  void clear(String fixtureId) => map.remove(fixtureId);

  @override
  LiveScoreCorrection? of(String fixtureId) => map[fixtureId];
}

final class _Clock implements Clock {
  final DateTime now = DateTime.utc(2026, 10, 18, 16, 2);

  @override
  DateTime nowUtc() => now;
}

typedef _Recorded = ({String fixtureId, int home, int away});

void main() {
  late FakeFootballDataProvider provider;
  late FakeProviderSyncStore store;
  late _RawBoard raw;
  late _Corrections corrections;
  late CorrectedLiveScoreBoard board;
  late _Clock clock;
  late AdminCorrectLiveScore correct;
  late List<_Recorded> recorded;

  final league = FakeLeagueRepository(const [
    League(
      id: LeagueRef(_fl1),
      name: 'الدوري الفرنسي',
      shortName: null,
      logoUrl: null,
    ),
  ]);
  const rules = [
    ProviderLeagueRule(
      source: 'football-data',
      externalLeagueId: 'FL1',
      leagueName: 'الدوري الفرنسي',
    ),
  ];

  // The real poll, writing through the corrected board as the server wires
  // it.
  RefreshLiveScores poll() => RefreshLiveScores(
    providers: {'football-data': provider},
    store: store,
    leagueRepository: league,
    rules: rules,
    board: board,
    liveSources: const {'football-data'},
  );

  SyncProviderResults results() => SyncProviderResults(
    providers: {'football-data': provider},
    store: store,
    leagueRepository: league,
    rules: rules,
    corrections: corrections,
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

  void provides(ProviderMatchStatus status, int home, int away) {
    final live = status == ProviderMatchStatus.live;
    provider.answer('FL1', _day, [
      providerMatch(
        id: 'm1',
        league: 'FL1',
        home: 'paris',
        away: 'rennes',
        kickoff: _kickoff,
        status: status,
        currentHomeGoals: live ? home : null,
        currentAwayGoals: live ? away : null,
        homeGoals: live ? null : home,
        awayGoals: live ? null : away,
        minute: live ? 62 : null,
      ),
    ]);
  }

  Future<void> pollAt(Duration afterKickoff) async {
    final run = await poll().call(now: _kickoff.add(afterKickoff));
    expect(run.isOk, isTrue);
  }

  Future<ProviderSyncReport> resultsAt(
    SyncProviderResults use,
    Duration afterKickoff,
  ) async =>
      ((await use.call(now: _kickoff.add(afterKickoff), apply: true))
              as Ok<ProviderSyncReport>)
          .value;

  LiveScore shown() => board.read([_fixture])[_fixture]!;

  setUp(() {
    provider = FakeFootballDataProvider();
    store = FakeProviderSyncStore()
      ..pending = [
        PendingProviderFixture(
          fixtureId: _fixture,
          externalId: 'm1',
          kickoffAt: _kickoff,
          leagueId: _fl1,
          game: 'باريس إف سي - رين',
        ),
      ];
    raw = _RawBoard();
    corrections = _Corrections();
    board = CorrectedLiveScoreBoard(raw: raw, corrections: corrections);
    clock = _Clock();
    correct = AdminCorrectLiveScore(
      providerScores: raw,
      corrections: corrections,
      clock: clock,
    );
    recorded = <_Recorded>[];
  });

  test(
    'a goal ruled out that the feed still counts is corrected for '
    'everyone at once, and the corrected score is the one recorded',
    () async {
      provides(ProviderMatchStatus.live, 2, 2);
      await pollAt(const Duration(minutes: 62));
      expect((shown().homeGoals, shown().awayGoals), (2, 2));

      final made = correct(
        principal: _admin,
        fixtureId: _fixture,
        homeGoals: 2,
        awayGoals: 1,
      );
      expect(made.isOk, isTrue);
      expect(
        (shown().homeGoals, shown().awayGoals, shown().minute),
        (2, 1, 62),
      );

      // The next poll still reads 2-2 from the feed; players still see 2-1.
      await pollAt(const Duration(minutes: 64));
      expect((shown().homeGoals, shown().awayGoals), (2, 1));

      // Full time: the feed ends at 2-2, the recorded result is 2-1.
      provides(ProviderMatchStatus.finished, 2, 2);
      final use = results();
      await resultsAt(use, const Duration(minutes: 110));
      expect(recorded, isEmpty);
      final last = await resultsAt(use, const Duration(minutes: 125));
      expect(recorded, [(fixtureId: _fixture, home: 2, away: 1)]);
      expect(last.applied, 1);
      expect(last.notes.last, contains('admin correction of the provider 2-2'));
    },
  );

  test(
    'without a correction the provider figure is recorded as before',
    () async {
      provides(ProviderMatchStatus.finished, 2, 2);
      final use = results();
      await resultsAt(use, const Duration(minutes: 110));
      await resultsAt(use, const Duration(minutes: 125));

      expect(recorded, [(fixtureId: _fixture, home: 2, away: 2)]);
    },
  );

  test(
    'the provider fixing the same goal itself agrees with the correction',
    () async {
      provides(ProviderMatchStatus.live, 2, 2);
      await pollAt(const Duration(minutes: 62));
      correct(
        principal: _admin,
        fixtureId: _fixture,
        homeGoals: 2,
        awayGoals: 1,
      );

      provides(ProviderMatchStatus.live, 2, 1);
      await pollAt(const Duration(minutes: 70));
      expect((shown().homeGoals, shown().awayGoals), (2, 1));

      provides(ProviderMatchStatus.finished, 2, 1);
      final use = results();
      await resultsAt(use, const Duration(minutes: 110));
      await resultsAt(use, const Duration(minutes: 125));
      expect(recorded, [(fixtureId: _fixture, home: 2, away: 1)]);
    },
  );

  test('a goal after the correction shows on top of it, and the result waits '
      'for an admin until the correction is made again', () async {
    provides(ProviderMatchStatus.live, 2, 2);
    await pollAt(const Duration(minutes: 62));
    correct(principal: _admin, fixtureId: _fixture, homeGoals: 2, awayGoals: 1);

    // Paris scores again; the feed still counts the ruled-out goal.
    provides(ProviderMatchStatus.live, 3, 2);
    await pollAt(const Duration(minutes: 80));
    expect((shown().homeGoals, shown().awayGoals), (3, 1));

    provides(ProviderMatchStatus.finished, 3, 2);
    final use = results();
    await resultsAt(use, const Duration(minutes: 110));
    final held = await resultsAt(use, const Duration(minutes: 125));
    expect(recorded, isEmpty);
    expect(held.attention.single.code, 'provider_sync.correction_unsettled');
    expect(held.attention.single.match, 'باريس إف سي - رين');
    // Told once, not on every run.
    final again = await resultsAt(use, const Duration(minutes: 135));
    expect(again.attention, isEmpty);
    expect(recorded, isEmpty);

    // The admin confirms 3-1 against the feed's 3-2: settled at once.
    provides(ProviderMatchStatus.live, 3, 2);
    await pollAt(const Duration(minutes: 136));
    correct(principal: _admin, fixtureId: _fixture, homeGoals: 3, awayGoals: 1);
    provides(ProviderMatchStatus.finished, 3, 2);
    await resultsAt(use, const Duration(minutes: 140));
    expect(recorded, [(fixtureId: _fixture, home: 3, away: 1)]);
  });

  test(
    'a correction taken back lets the provider figure count again',
    () async {
      provides(ProviderMatchStatus.live, 2, 2);
      await pollAt(const Duration(minutes: 62));
      correct(
        principal: _admin,
        fixtureId: _fixture,
        homeGoals: 2,
        awayGoals: 1,
      );

      expect(
        correct.clear(principal: _admin, fixtureId: _fixture).isOk,
        isTrue,
      );
      expect((shown().homeGoals, shown().awayGoals), (2, 2));
    },
  );

  test(
    'only an admin corrects, only a match in play, only a valid score',
    () async {
      provides(ProviderMatchStatus.live, 2, 2);
      await pollAt(const Duration(minutes: 62));

      final byPlayer = correct(
        principal: _player,
        fixtureId: _fixture,
        homeGoals: 2,
        awayGoals: 1,
      );
      expect(
        (byPlayer as Err<LiveScoreCorrection>).error.kind,
        ErrorKind.authorization,
      );
      expect(
        correct.clear(principal: _player, fixtureId: _fixture).isOk,
        isFalse,
      );

      final notLive = correct(
        principal: _admin,
        fixtureId: _other,
        homeGoals: 1,
        awayGoals: 0,
      );
      expect(
        (notLive as Err<LiveScoreCorrection>).error.code,
        'football_data.not_live',
      );

      final negative = correct(
        principal: _admin,
        fixtureId: _fixture,
        homeGoals: -1,
        awayGoals: 0,
      );
      expect(
        (negative as Err<LiveScoreCorrection>).error.kind,
        ErrorKind.validation,
      );

      expect((shown().homeGoals, shown().awayGoals), (2, 2));
      expect(corrections.map, isEmpty);
    },
  );
}
