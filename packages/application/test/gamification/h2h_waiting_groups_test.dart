/// New players and the waiting group through the real use-cases (NK277,
/// decided by the owner on 2026-11-14, December 2026 on): a new player is
/// seated at his first prediction, never twice; the twentieth starts the
/// group from the next round not started; a waiting group plays nothing and
/// is never a substitute; a late group takes no part in the month's moves
/// and keeps its results; the groups already playing are not touched; and
/// November keeps every rule it had.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _december = DateTime.utc(2026, 12);
final _november = DateTime.utc(2026, 11);

H2hLeagueId _group(int n) =>
    H2hLeagueId('11111111-1111-4111-8111-${n.toString().padLeft(12, '0')}');

H2hRoundId _rid(DateTime month, int n) => H2hRoundId(
  '22222222-2222-4222-8222-${month.month.toString().padLeft(4, '0')}'
  '${n.toString().padLeft(8, '0')}',
);

/// The database as the newcomer job sees it, with its refusals: one seat a
/// month a player, one open waiting group, a start only with twenty and
/// never from a round that has started.
final class _Newcomers implements H2hNewcomerStore {
  _Newcomers(this.rounds);

  final FakeH2hRoundStore rounds;
  final List<UserId> candidates = <UserId>[];
  final Map<H2hLeagueId, List<UserId>> seats = <H2hLeagueId, List<UserId>>{};
  final Map<H2hLeagueId, int> indexOf = <H2hLeagueId, int>{};
  final Map<H2hLeagueId, int> starts = <H2hLeagueId, int>{};
  final List<UserId> newcomerRecords = <UserId>[];
  int nextIndex = 1;
  bool frozen = false;

  bool _seated(UserId u) => seats.values.any((s) => s.contains(u));

  @override
  Future<Result<List<UserId>>> newcomersOf(DateTime monthStart) async =>
      Result.ok([
        for (final u in candidates)
          if (!_seated(u)) u,
      ]);

  @override
  Future<Result<H2hWaitingGroup?>> waitingGroupOf(DateTime monthStart) async {
    for (final e in seats.entries) {
      if (!starts.containsKey(e.key)) {
        return Result.ok(
          H2hWaitingGroup(
            leagueId: e.key,
            groupIndex: indexOf[e.key]!,
            seated: e.value.length,
          ),
        );
      }
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<int>> nextExtraIndexOf(DateTime monthStart) async =>
      Result.ok(nextIndex);

  @override
  Future<Result<void>> openWaitingGroup({
    required DateTime monthStart,
    required H2hLeagueId leagueId,
    required int groupIndex,
  }) async {
    if (seats.keys.any((k) => !starts.containsKey(k))) {
      return const Result.err(
        AppError.invariant('h2h.newcomer_refused', 'one open'),
      );
    }
    seats[leagueId] = <UserId>[];
    indexOf[leagueId] = groupIndex;
    nextIndex = groupIndex + 1;
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> seat({
    required DateTime monthStart,
    required H2hLeagueId leagueId,
    required UserId userId,
    required int slot,
    int? startFrom,
  }) async {
    if (frozen) {
      return const Result.err(
        AppError.invariant('h2h.newcomers_frozen', 'frozen'),
      );
    }
    final group = seats[leagueId]!;
    if (_seated(userId) || slot != group.length || starts[leagueId] != null) {
      return const Result.err(
        AppError.invariant('h2h.newcomer_refused', 'refused'),
      );
    }
    if (startFrom != null) {
      final rs =
          (await rounds.roundsOf(monthStart) as Ok<List<H2hRound>>).value;
      final played = rs.where((r) => r.locked).length;
      if (group.length + 1 < 20 || startFrom <= played) {
        return const Result.err(
          AppError.invariant('h2h.newcomer_refused', 'start refused'),
        );
      }
      starts[leagueId] = startFrom;
    }
    group.add(userId);
    newcomerRecords.add(userId);
    return const Result.ok(null);
  }
}

/// A month drawn with [locked] rounds started.
({FakeH2hLeagueStore leagues, FakeH2hRoundStore rounds, _Newcomers store})
_world(DateTime month, {int locked = 7, bool pilot = false}) {
  final leagues = FakeH2hLeagueStore()
    ..months[month] = H2hMonthInfo(
      monthStart: month,
      isPilot: pilot,
      seatedCount: 100,
    );
  final rounds = FakeH2hRoundStore();
  for (var n = 1; n <= locked + 1; n++) {
    rounds.addRound(
      H2hRound(
        id: _rid(month, n),
        monthStart: month,
        number: n,
        day: DateTime.utc(month.year, month.month, n),
        fixtureCount: 8,
        approvedBy: null,
        lockedAt: n <= locked ? DateTime.utc(month.year, month.month, n) : null,
      ),
    );
  }
  return (leagues: leagues, rounds: rounds, store: _Newcomers(rounds));
}

SeatH2hNewcomers _job(
  ({FakeH2hLeagueStore leagues, FakeH2hRoundStore rounds, _Newcomers store})
  w, {
  bool enabled = true,
}) => SeatH2hNewcomers(
  newcomers: w.store,
  leagues: w.leagues,
  rounds: w.rounds,
  idGenerator: SequenceIds(),
  enabled: enabled,
);

final class _Unwired implements H2hGroupExtension, H2hControlStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not reached: ${invocation.memberName}');
}

final class _Moves implements H2hSeatMoveStore {
  @override
  Future<Result<List<H2hSeatMove>>> movesOf(DateTime monthStart) async =>
      const Result.ok(<H2hSeatMove>[]);

  @override
  Future<Result<List<H2hRoundAttendance>>> attendance(
    List<H2hRound> rounds,
  ) async => const Result.ok(<H2hRoundAttendance>[]);

  @override
  Future<Result<Map<H2hRoundId, H2hRoundExcusal>>> excusals(
    List<H2hRound> rounds,
  ) async => const Result.ok(<H2hRoundId, H2hRoundExcusal>{});

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not reached: ${invocation.memberName}');
}

H2hMember _member(int user, int slot, {int fromRound = 1}) => H2hMember(
  userId: userNo(user),
  slot: slot,
  joinedAt: DateTime.utc(2026, 12),
  fromRound: fromRound,
);

void main() {
  group('SeatH2hNewcomers', () {
    final now = DateTime.utc(2026, 12, 8, 12);

    test('the twentieth new player starts the group from the next round '
        'not started; the next one opens a new waiting group', () async {
      final w = _world(_december);
      // The draw's waiting group holds seventeen.
      w.store.seats[_group(6)] = [for (var i = 0; i < 17; i++) userNo(i)];
      w.store.indexOf[_group(6)] = 1;
      w.store.nextIndex = 2;
      w.store.candidates.addAll([for (var i = 100; i < 104; i++) userNo(i)]);

      final result = await _job(w)(now: now);

      final run = (result as Ok<H2hNewcomersRun>).value;
      expect(run.seated, 4);
      expect(run.started, 1);
      expect(run.opened, 1);
      expect(w.store.seats[_group(6)], hasLength(20));
      expect(w.store.starts[_group(6)], 8);
      final next = w.store.seats.keys.singleWhere((k) => k != _group(6));
      expect(w.store.seats[next], [userNo(103)]);
      expect(w.store.indexOf[next], 2);
      expect(w.store.starts.containsKey(next), isFalse);
    });

    test('a player is seated once: a second run seats nobody', () async {
      final w = _world(_december);
      w.store.candidates.addAll([userNo(1), userNo(2)]);
      await _job(w)(now: now);
      final again = await _job(w)(now: now);

      expect((again as Ok<H2hNewcomersRun>).value.seated, 0);
      expect(w.store.newcomerRecords, [userNo(1), userNo(2)]);
      expect(w.store.seats.values.expand((s) => s).toList(), [
        userNo(1),
        userNo(2),
      ]);
    });

    test('a refused seat is skipped, the others are seated', () async {
      final w = _world(_december);
      w.store.seats[_group(6)] = [userNo(1)];
      w.store.indexOf[_group(6)] = 1;
      // userNo(1) is offered again (seated meanwhile by another run).
      w.store.candidates.addAll([userNo(1), userNo(2)]);
      final store = w.store;
      final job = SeatH2hNewcomers(
        newcomers: _Offering(store),
        leagues: w.leagues,
        rounds: w.rounds,
        idGenerator: SequenceIds(),
      );

      final run = (await job(now: now) as Ok<H2hNewcomersRun>).value;

      expect(run.seated, 1);
      expect(store.seats[_group(6)], [userNo(1), userNo(2)]);
    });

    test('a freeze by the owner stops the run with its own code', () async {
      final w = _world(_december);
      w.store.candidates.add(userNo(1));
      w.store.frozen = true;

      final result = await _job(w)(now: now);

      expect(
        (result as Err<H2hNewcomersRun>).error.code,
        'h2h.newcomers_frozen',
      );
    });

    test('nobody joins once the last round has started', () async {
      final w = _world(_december, locked: 19);
      w.store.candidates.add(userNo(1));

      final run = (await _job(w)(now: now) as Ok<H2hNewcomersRun>).value;

      expect(run.seated, 0);
      expect(w.store.seats, isEmpty);
    });

    test('November, a pilot, a month not drawn, a judged month and the '
        'switch off: nothing at all', () async {
      final nov = _world(_november);
      nov.store.candidates.add(userNo(1));
      expect(
        (await _job(nov)(now: DateTime.utc(2026, 11, 20))
                as Ok<H2hNewcomersRun>)
            .value
            .seated,
        0,
      );
      expect(nov.store.seats, isEmpty);

      final pilot = _world(_december, pilot: true)
        ..store.candidates.add(userNo(1));
      await _job(pilot)(now: now);
      expect(pilot.store.seats, isEmpty);

      final undrawn = _world(_december)..store.candidates.add(userNo(1));
      undrawn.leagues.months.clear();
      await _job(undrawn)(now: now);
      expect(undrawn.store.seats, isEmpty);

      final judged = _world(_december)..store.candidates.add(userNo(1));
      judged.leagues.closed[_december] = 100;
      await _job(judged)(now: now);
      expect(judged.store.seats, isEmpty);

      final off = _world(_december)..store.candidates.add(userNo(1));
      await _job(off, enabled: false)(now: now);
      expect(off.store.seats, isEmpty);
    });
  });

  group('the draw', () {
    test('December: the last extra group under twenty is drawn waiting; '
        'off, or November, it is not', () async {
      Future<List<H2hDrawnGroup>> drawn(
        DateTime month, {
        bool on = true,
      }) async {
        final leagues = FakeH2hLeagueStore();
        final source = FakeH2hDrawSource()
          ..active[H2hLeaguePolicy.previousMonthOf(month)] = [
            for (var i = 0; i < 113; i++) userNo(i),
          ];
        await DrawH2hMonth(
          leagues: leagues,
          source: source,
          idGenerator: SequenceIds(),
          waitingGroups: on,
        )(now: month.add(const Duration(hours: 1)));
        return leagues.drawn[month]!;
      }

      final december = await drawn(_december);
      expect(
        [for (final d in december) d.group.waiting],
        [false, false, false, false, false, true],
      );
      expect(december.last.group.seats, hasLength(13));
      expect(
        (await drawn(_december, on: false)).any((d) => d.group.waiting),
        isFalse,
      );
      expect((await drawn(_november)).any((d) => d.group.waiting), isFalse);
    });
  });

  group('reading a waiting group and a late group', () {
    // Group 5 plays from round 1 (users 0..19); group 6 started at round 8
    // (users 20..39); group 7 waits with five (users 40..44).
    final sheets = FakeH2hSheetReader()
      ..sheets[_group(5)] = H2hGroupSheet(
        members: [for (var s = 0; s < 20; s++) _member(s, s)],
        scores: [
          for (var n = 1; n <= 9; n++)
            for (var s = 0; s < 45; s++)
              H2hRoundScore(
                userId: userNo(s),
                round: n,
                points: s % 7,
                exactCount: 0,
                predictedCount: 6,
              ),
        ],
        settledRounds: {for (var n = 1; n <= 9; n++) n},
        voidRounds: const <int>{},
      )
      ..sheets[_group(6)] = H2hGroupSheet(
        members: [
          for (var s = 0; s < 20; s++) _member(20 + s, s, fromRound: 8),
        ],
        scores: [
          for (var n = 1; n <= 9; n++)
            for (var s = 20; s < 40; s++)
              H2hRoundScore(
                userId: userNo(s),
                round: n,
                points: s % 5,
                exactCount: 0,
                predictedCount: 6,
              ),
        ],
        settledRounds: {for (var n = 1; n <= 9; n++) n},
        voidRounds: const <int>{},
      )
      ..sheets[_group(7)] = H2hGroupSheet(
        members: [
          for (var s = 0; s < 5; s++)
            _member(40 + s, s, fromRound: H2hLeaguePolicy.waitingFromRound),
        ],
        scores: const <H2hRoundScore>[],
        settledRounds: {for (var n = 1; n <= 9; n++) n},
        voidRounds: const <int>{},
      );

    ({FakeH2hLeagueStore leagues, FakeH2hRoundStore rounds}) world() {
      final leagues = FakeH2hLeagueStore()
        ..months[_december] = H2hMonthInfo(
          monthStart: _december,
          isPilot: false,
          seatedCount: 45,
        )
        ..drawn[_december] = [
          for (var g = 5; g <= 7; g++)
            H2hDrawnGroup(
              leagueId: _group(g),
              group: H2hDrawGroup(
                division: H2hLeaguePolicy.extraDivision,
                groupIndex: g - 5,
                seats: const <H2hDrawSeat>[],
              ),
            ),
        ];
      for (var g = 5; g <= 7; g++) {
        for (final m in sheets.sheets[_group(g)]!.members) {
          leagues.seat(
            m.userId,
            H2hSeat(
              leagueId: _group(g),
              monthStart: _december,
              division: H2hLeaguePolicy.extraDivision,
              groupIndex: g - 5,
              slot: m.slot,
              capacity: 20,
              divisionGroups: 3,
              isPilot: false,
              joinedAt: _december,
            ),
          );
        }
      }
      final rounds = FakeH2hRoundStore();
      for (var n = 1; n <= 9; n++) {
        rounds.addRound(
          H2hRound(
            id: _rid(_december, n),
            monthStart: _december,
            number: n,
            day: DateTime.utc(2026, 12, n),
            fixtureCount: 8,
            approvedBy: null,
            lockedAt: DateTime.utc(2026, 12, n),
          ),
        );
      }
      return (leagues: leagues, rounds: rounds);
    }

    Future<MyH2hLeague> mine(int user) async {
      final w = world();
      final result =
          await GetMyH2hLeague(
            leagues: w.leagues,
            rounds: w.rounds,
            sheets: sheets,
            profiles: NamingProfiles(),
            clock: AtClock(DateTime.utc(2026, 12, 10, 12)),
          )(
            principal: AuthenticatedUser(
              userId: userNo(user),
              role: PlatformRole.user,
            ),
          );
      return (result as Ok<MyH2hLeague>).value;
    }

    test('a waiting player: no round, nothing played, and how many it waits '
        'for', () async {
      final league = await mine(42);
      expect(league.rounds, isEmpty);
      expect(league.waitingFor, 15);
      expect(league.groupStart, H2hLeaguePolicy.waitingFromRound);
      expect(league.placings.every((p) => p.standing.played == 0), isTrue);
    });

    test('a late player: rounds 8 and 9 only, and no waiting', () async {
      final league = await mine(25);
      expect([for (final r in league.rounds) r.round.number], [8, 9]);
      expect(league.groupStart, 8);
      expect(league.waitingFor, isNull);
      expect(league.placings.every((p) => p.standing.played == 2), isTrue);
    });

    test(
      'a player of a group drawn at the start: every round, as before',
      () async {
        final league = await mine(3);
        expect(league.rounds, hasLength(9));
        expect(league.groupStart, 1);
        expect(league.waitingFor, isNull);
      },
    );

    test('the playing group reads the same whether the waiting group has '
        'started or not', () async {
      final before = await mine(3);
      final members = sheets.sheets[_group(7)]!;
      sheets.sheets[_group(7)] = H2hGroupSheet(
        members: [
          for (final m in members.members)
            H2hMember(
              userId: m.userId,
              slot: m.slot,
              joinedAt: m.joinedAt,
              fromRound: 9,
            ),
        ],
        scores: members.scores,
        settledRounds: members.settledRounds,
        voidRounds: members.voidRounds,
      );
      final after = await mine(3);
      sheets.sheets[_group(7)] = members;
      expect(
        [
          for (final p in after.placings)
            (p.rank, p.standing.userId, p.standing.leaguePoints),
        ],
        [
          for (final p in before.placings)
            (p.rank, p.standing.userId, p.standing.leaguePoints),
        ],
      );
    });

    test('a waiting player is never a substitute for absence', () async {
      final w = world();
      final state =
          (await loadH2hAbsenceState(
                    leagues: w.leagues,
                    rounds: w.rounds,
                    sheets: sheets,
                    moves: _Moves(),
                    now: DateTime.utc(2026, 12, 10, 12),
                  )
                  as Ok<H2hAbsenceState?>)
              .value!;
      final extra = {for (final s in state.extra) s.userId};
      expect(extra.contains(userNo(3)), isTrue);
      expect(extra.contains(userNo(25)), isTrue);
      for (var u = 40; u < 45; u++) {
        expect(extra.contains(userNo(u)), isFalse, reason: '$u');
      }
    });
  });

  group('the month\'s close', () {
    // December 2026 judged: one elite group (0..3), group 5 (10..13) and
    // group 6 started at round 15 (20..23). November the same, every group
    // from round 1.
    Future<List<GamificationEvent>> close(DateTime month) async {
      final december = month == _december;
      final leagues = FakeH2hLeagueStore()
        ..months[month] = H2hMonthInfo(
          monthStart: month,
          isPilot: false,
          seatedCount: 12,
        )
        ..drawn[month] = [
          H2hDrawnGroup(
            leagueId: _group(1),
            group: const H2hDrawGroup(
              division: H2hDivision.first,
              groupIndex: 0,
              seats: <H2hDrawSeat>[],
            ),
          ),
          H2hDrawnGroup(
            leagueId: _group(5),
            group: const H2hDrawGroup(
              division: H2hDivision.second,
              groupIndex: 0,
              seats: <H2hDrawSeat>[],
            ),
          ),
          H2hDrawnGroup(
            leagueId: _group(6),
            group: const H2hDrawGroup(
              division: H2hDivision.second,
              groupIndex: 1,
              seats: <H2hDrawSeat>[],
            ),
          ),
        ];
      final rounds = FakeH2hRoundStore();
      for (var n = 1; n <= 19; n++) {
        rounds.addRound(
          H2hRound(
            id: _rid(month, n),
            monthStart: month,
            number: n,
            day: DateTime.utc(month.year, month.month, n),
            fixtureCount: 8,
            approvedBy: null,
            lockedAt: DateTime.utc(month.year, month.month, n),
          ),
        );
      }
      final reader = FakeH2hSheetReader();
      for (final (g, first, from) in [
        (1, 0, 1),
        (5, 10, 1),
        (6, 20, december ? 15 : 1),
      ]) {
        reader.sheets[_group(g)] = H2hGroupSheet(
          members: [
            for (var s = 0; s < 4; s++) _member(first + s, s, fromRound: from),
          ],
          scores: [
            for (var n = 1; n <= 19; n++)
              for (var s = 0; s < 4; s++)
                H2hRoundScore(
                  userId: userNo(first + s),
                  round: n,
                  points: 10 - s,
                  exactCount: 0,
                  predictedCount: 6,
                ),
          ],
          settledRounds: {for (var n = 1; n <= 19; n++) n},
          voidRounds: const <int>{},
        );
        for (var s = 0; s < 4; s++) {
          reader.activeDays[userNo(first + s)] = 20;
        }
      }
      final events = RecordingEvents();
      final closed = await CloseH2hMonth(
        leagues: leagues,
        rounds: rounds,
        sheets: reader,
        events: events,
        idGenerator: SequenceIds(),
      )(now: DateTime.utc(month.year, month.month + 1, 1, 12));
      expect((closed as Ok<int>).value, 1);
      return events.recorded;
    }

    test('December: the late group is held, not counted, with its results '
        'kept; a move carries its reason', () async {
      final events = await close(_december);
      final byUser = {for (final e in events) e.userId: e.payload};
      for (var u = 20; u < 24; u++) {
        expect(byUser[userNo(u)]!['reason'], 'not_counted', reason: '$u');
        expect(byUser[userNo(u)]!['outcome'], 'held');
      }
      // Its results are kept: rounds 15..19 played, the table ranked.
      expect(byUser[userNo(20)]!['league_points'], greaterThan(0));
      expect(byUser[userNo(20)]!['rank'], 1);
      // Group 5 takes part: up to the elite, by commitment.
      expect(byUser[userNo(10)]!['outcome'], 'promoted');
      expect(byUser[userNo(10)]!['reason'], 'commitment');
      // The elite's leader stays: no reason recorded.
      expect(byUser[userNo(0)]!['outcome'], 'held');
      expect(byUser[userNo(0)]!.containsKey('reason'), isFalse);
    });

    test('November: no reason in any event, as before script 277', () async {
      final events = await close(_november);
      expect(events, hasLength(12));
      expect(events.every((e) => !e.payload.containsKey('reason')), isTrue);
      final byUser = {for (final e in events) e.userId: e.payload};
      expect(byUser[userNo(20)]!['outcome'], isNot('held'));
    });
  });

  test(
    'AddH2hGroups is refused from December, before anything is read',
    () async {
      final result = await AddH2hGroups(
        leagues: FakeH2hLeagueStore(),
        extension: _Unwired(),
        controls: _Unwired(),
        idGenerator: SequenceIds(),
        clock: AtClock(DateTime.utc(2026, 12, 5)),
      )(principal: admin, groups: 1);

      expect(
        (result as Err<H2hGroupsAdded>).error.code,
        'h2h.groups_by_newcomers',
      );
    },
  );
}

/// Offers its store's candidates without filtering the seated ones, as a
/// read taken before another run seated one of them.
final class _Offering implements H2hNewcomerStore {
  _Offering(this._store);

  final _Newcomers _store;

  @override
  Future<Result<List<UserId>>> newcomersOf(DateTime monthStart) async =>
      Result.ok(List<UserId>.of(_store.candidates));

  @override
  Future<Result<H2hWaitingGroup?>> waitingGroupOf(DateTime monthStart) =>
      _store.waitingGroupOf(monthStart);

  @override
  Future<Result<int>> nextExtraIndexOf(DateTime monthStart) =>
      _store.nextExtraIndexOf(monthStart);

  @override
  Future<Result<void>> openWaitingGroup({
    required DateTime monthStart,
    required H2hLeagueId leagueId,
    required int groupIndex,
  }) => _store.openWaitingGroup(
    monthStart: monthStart,
    leagueId: leagueId,
    groupIndex: groupIndex,
  );

  @override
  Future<Result<void>> seat({
    required DateTime monthStart,
    required H2hLeagueId leagueId,
    required UserId userId,
    required int slot,
    int? startFrom,
  }) => _store.seat(
    monthStart: monthStart,
    leagueId: leagueId,
    userId: userId,
    slot: slot,
    startFrom: startFrom,
  );
}
