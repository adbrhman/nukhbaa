/// Relegation for absence through the real use-cases (NK183, migration
/// 0189): the warning after a second consecutive absence, the swap an hour
/// before the next round, the substitute's conditions, the admin's hand
/// relegation and excusal, and the tables after a swap (each player keeps
/// his own month).
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);
const _elite = H2hLeagueId('11111111-1111-4111-8111-000000000001');
const _extra = H2hLeagueId('11111111-1111-4111-8111-000000000005');

// Elite group 1: e1..e4 in slots 0..3. Extra group 5: x1..x3 in slots 0..2.
final _e = [for (var i = 1; i <= 4; i++) userNo(100 + i)];
final _x = [for (var i = 1; i <= 3; i++) userNo(200 + i)];

H2hRoundId _rid(int n) =>
    H2hRoundId('22222222-2222-4222-8222-${n.toString().padLeft(12, '0')}');

/// Round 4's first kickoff: 2026-11-04 15:00 UTC.
final _round4Kickoff = DateTime.utc(2026, 11, 4, 15);

H2hRound _round(int n, {required bool locked}) => H2hRound(
  id: _rid(n),
  monthStart: _november,
  number: n,
  day: DateTime.utc(2026, 11, n),
  fixtureCount: 8,
  approvedBy: null,
  lockedAt: locked ? DateTime.utc(2026, 11, n, 12) : null,
);

/// The database as the use-cases see it, with the swap applied to the
/// sheets and seats the way the SQL of 0189 reads it.
final class _World {
  _World() {
    leagues.months[_november] = H2hMonthInfo(
      monthStart: _november,
      isPilot: false,
      seatedCount: 7,
    );
    leagues.drawn[_november] = [
      H2hDrawnGroup(
        leagueId: _elite,
        group: H2hDrawGroup(
          division: H2hDivision.first,
          groupIndex: 0,
          seats: [
            for (var s = 0; s < 4; s++) H2hDrawSeat(userId: _e[s], slot: s),
          ],
        ),
      ),
      H2hDrawnGroup(
        leagueId: _extra,
        group: H2hDrawGroup(
          division: H2hDivision.second,
          groupIndex: 0,
          seats: [
            for (var s = 0; s < 3; s++) H2hDrawSeat(userId: _x[s], slot: s),
          ],
        ),
      ),
    ];
    for (var s = 0; s < 4; s++) {
      leagues.seat(_e[s], _seatIn(_elite, H2hDivision.first, s));
    }
    for (var s = 0; s < 3; s++) {
      leagues.seat(_x[s], _seatIn(_extra, H2hDivision.second, s));
    }
    for (var n = 1; n <= 3; n++) {
      rounds.addRound(_round(n, locked: true));
    }
    rounds.addRound(_round(4, locked: false));
    rounds.dayOf(DateTime.utc(2026, 11, 4), 8, _round4Kickoff);

    // e1 missed rounds 1-3; e2 missed rounds 2-3; x3 missed round 2.
    store.present[_rid(1)] = {..._e.sublist(1), ..._x};
    store.present[_rid(2)] = {_e[2], _e[3], _x[0], _x[1]};
    store.present[_rid(3)] = {_e[2], _e[3], ..._x};
    for (var n = 1; n <= 3; n++) {
      store.lastKickoff[_rid(n)] = DateTime.utc(2026, 11, n, 20);
    }
    // x2 is the most committed but predicted on 4 days only; x1 qualifies.
    store.facts[_x[0]] = H2hCandidateFacts(
      userId: _x[0],
      missed: 6,
      points: 40,
      exact: 3,
      activeDays: 20,
    );
    store.facts[_x[1]] = H2hCandidateFacts(
      userId: _x[1],
      missed: 1,
      points: 50,
      exact: 5,
      activeDays: 4,
    );
    store.facts[_x[2]] = H2hCandidateFacts(
      userId: _x[2],
      missed: 0,
      points: 60,
      exact: 6,
      activeDays: 25,
    );
    _writeSheets();
  }

  final FakeH2hLeagueStore leagues = FakeH2hLeagueStore();
  final FakeH2hRoundStore rounds = FakeH2hRoundStore();
  final FakeH2hSheetReader sheets = FakeH2hSheetReader();
  late final _FakeMoveStore store = _FakeMoveStore(this);
  final _Sender sender = _Sender();
  final SequenceIds ids = SequenceIds();

  /// Round points: everybody present scores 3 in round 1 and 2 after it,
  /// except x1, who scores 9 a round in the extra group.
  List<H2hRoundScore> get scores => [
    for (var n = 1; n <= 3; n++)
      for (final u in store.present[_rid(n)]!)
        H2hRoundScore(
          userId: u,
          round: n,
          points: u == _x[0] ? 9 : (n == 1 ? 3 : 2),
          exactCount: 0,
          predictedCount: 3,
        ),
  ];

  static H2hSeat _seatIn(H2hLeagueId league, H2hDivision division, int slot) =>
      H2hSeat(
        leagueId: league,
        monthStart: _november,
        division: division,
        groupIndex: 0,
        slot: slot,
        capacity: H2hLeaguePolicy.groupCapacity,
        divisionGroups: 1,
        isPilot: false,
        joinedAt: _november,
      );

  /// The sheets as membersSql reads them: each seat's holders with their
  /// rounds.
  void _writeSheets() {
    List<H2hMember> holders(H2hLeagueId league, List<UserId> drawn) {
      final members = <H2hMember>[];
      for (var slot = 0; slot < drawn.length; slot++) {
        final changes = <(int, UserId)>[(1, drawn[slot])];
        for (final m in store.moves) {
          if (m.eliteLeagueId == league && m.eliteSlot == slot) {
            changes.add((m.fromRound, m.inUser));
          }
          if (m.extraLeagueId == league && m.extraSlot == slot) {
            changes.add((m.fromRound, m.outUser));
          }
        }
        changes.sort((a, b) => a.$1.compareTo(b.$1));
        for (var i = 0; i < changes.length; i++) {
          members.add(
            H2hMember(
              userId: changes[i].$2,
              slot: slot,
              joinedAt: _november,
              fromRound: changes[i].$1,
              untilRound: i + 1 < changes.length ? changes[i + 1].$1 - 1 : null,
            ),
          );
        }
      }
      return members;
    }

    for (final (league, drawn) in [(_elite, _e), (_extra, _x)]) {
      sheets.sheets[league] = H2hGroupSheet(
        members: holders(league, drawn),
        scores: scores,
        settledRounds: const {1, 2, 3},
        voidRounds: const {},
        lastKickoffs: {
          for (var n = 1; n <= 3; n++) n: DateTime.utc(2026, 11, n, 20),
        },
      );
    }
    // The seat each player holds now (seatSql).
    for (final m in store.moves) {
      leagues.seat(m.inUser, _seatIn(_elite, H2hDivision.first, m.eliteSlot));
      leagues.seat(m.outUser, _seatIn(_extra, H2hDivision.second, m.extraSlot));
    }
  }

  RunH2hAbsence get job => RunH2hAbsence(
    leagues: leagues,
    rounds: rounds,
    sheets: sheets,
    moves: store,
    sender: sender,
    idGenerator: ids,
  );

  AdminH2hAbsence desk(DateTime now) => AdminH2hAbsence(
    leagues: leagues,
    rounds: rounds,
    sheets: sheets,
    moves: store,
    profiles: NamingProfiles(),
    sender: sender,
    idGenerator: ids,
    clock: AtClock(now),
  );

  GetMyH2hLeague league(DateTime now) => GetMyH2hLeague(
    leagues: leagues,
    rounds: rounds,
    sheets: sheets,
    profiles: NamingProfiles(),
    clock: AtClock(now),
  );
}

final class _FakeMoveStore implements H2hSeatMoveStore {
  _FakeMoveStore(this.world);

  final _World world;
  final Map<H2hRoundId, Set<UserId>> present = {};
  final Map<H2hRoundId, DateTime> lastKickoff = {};
  final Map<UserId, H2hCandidateFacts> facts = {};
  final List<H2hSeatMove> moves = [];
  final Map<H2hRoundId, H2hRoundExcusal> excused = {};
  final Set<(H2hRoundId, UserId)> warnings = {};

  @override
  Future<Result<List<H2hSeatMove>>> movesOf(DateTime monthStart) async =>
      Result.ok([
        for (final m in moves)
          if (m.monthStart == monthStart) m,
      ]);

  @override
  Future<Result<List<H2hRoundAttendance>>> attendance(
    List<H2hRound> rounds,
  ) async => Result.ok([
    for (final r in rounds)
      if (r.locked)
        H2hRoundAttendance(
          roundId: r.id,
          fixtures: 8,
          lastKickoff: lastKickoff[r.id],
          present: present[r.id] ?? const {},
        ),
  ]);

  @override
  Future<Result<Map<H2hRoundId, H2hRoundExcusal>>> excusals(
    List<H2hRound> rounds,
  ) async => Result.ok({
    for (final r in rounds)
      if (excused[r.id] != null) r.id: excused[r.id]!,
  });

  @override
  Future<Result<List<H2hCandidateFacts>>> candidateFacts({
    required DateTime lastDay,
    required List<UserId> users,
  }) async => Result.ok([
    for (final u in users)
      facts[u] ??
          H2hCandidateFacts(
            userId: u,
            missed: 0,
            points: 0,
            exact: 0,
            activeDays: 0,
          ),
  ]);

  @override
  Future<Result<void>> recordMove({
    required H2hSeatMove move,
    required String logId,
  }) async {
    final clash = moves.any(
      (m) =>
          m.outUser == move.outUser ||
          m.inUser == move.inUser ||
          (m.eliteSlot == move.eliteSlot && m.fromRound == move.fromRound),
    );
    if (clash) {
      return const Result.err(
        AppError.invariant('h2h.move_refused', 'refused'),
      );
    }
    moves.add(move);
    world._writeSheets();
    return const Result.ok(null);
  }

  @override
  Future<Result<bool>> excuse({
    required H2hRoundId roundId,
    required String reason,
    required UserId by,
    required String logId,
  }) async {
    if (excused.containsKey(roundId)) {
      return const Result.ok(false);
    }
    excused[roundId] = H2hRoundExcusal(
      roundId: roundId,
      reason: reason,
      by: by,
      at: DateTime.utc(2026, 11, 4),
    );
    return const Result.ok(true);
  }

  @override
  Future<Result<bool>> recordWarning({
    required H2hRoundId roundId,
    required UserId userId,
  }) async => Result.ok(warnings.add((roundId, userId)));

  @override
  Future<Result<List<({H2hRoundId roundId, UserId userId, DateTime at})>>>
  warningsOf(List<H2hRound> rounds) async => Result.ok([
    for (final w in warnings)
      (roundId: w.$1, userId: w.$2, at: DateTime.utc(2026, 11, 3, 21)),
  ]);

  @override
  Future<Result<List<String>>> pushTokensOf(UserId userId) async =>
      Result.ok(['token-${userId.value}']);
}

final class _Sender implements PushSender {
  final List<(List<String>, String, String, String?)> sent = [];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    sent.add((tokens, title, body, link));
    return const Result.ok(<String>[]);
  }
}

void main() {
  group('RunH2hAbsence', () {
    test('warns the player whose run reached two, once', () async {
      final world = _World();
      final early = DateTime.utc(2026, 11, 3, 22);

      final first = await world.job.call(now: early);
      final second = await world.job.call(now: early);

      expect((first as Ok<H2hAbsenceRun>).value.warned, 1);
      expect((second as Ok<H2hAbsenceRun>).value.warned, 0);
      expect(world.store.warnings, {(_rid(3), _e[1])});
      expect(world.sender.sent.single.$1, ['token-${_e[1].value}']);
      expect(world.sender.sent.single.$4, PushLink.h2h);
      // Too early for a swap: round 4 kicks off at 15:00 tomorrow.
      expect(world.store.moves, isEmpty);
    });

    test('an hour before the next round, the player with three absences '
        'swaps seats with the first substitute who qualifies', () async {
      final world = _World();

      final result = await world.job.call(
        now: _round4Kickoff.subtract(const Duration(minutes: 30)),
      );

      expect((result as Ok<H2hAbsenceRun>).value.moved, 1);
      final move = world.store.moves.single;
      expect(move.kind, H2hSeatMoveKind.absence);
      expect(move.outUser, _e[0]);
      // x3 missed round 2, x2 predicted on 4 days: x1 comes up.
      expect(move.inUser, _x[0]);
      expect(move.fromRound, 4);
      expect((move.eliteSlot, move.extraSlot), (0, 0));
      expect([for (final r in move.absentRounds) r.round], [1, 2, 3]);
      expect(move.facts!.activeDays, 20);
      // Both are told, on the league's tab.
      final told = {for (final s in world.sender.sent) ...s.$1};
      expect(
        told,
        containsAll(['token-${_e[0].value}', 'token-${_x[0].value}']),
      );
    });

    test('never before the hour, never once the round started, and once '
        'only', () async {
      final world = _World();

      await world.job.call(
        now: _round4Kickoff.subtract(const Duration(minutes: 61)),
      );
      expect(world.store.moves, isEmpty);
      await world.job.call(now: _round4Kickoff);
      expect(world.store.moves, isEmpty);

      final inside = _round4Kickoff.subtract(const Duration(minutes: 20));
      await world.job.call(now: inside);
      final again = await world.job.call(now: inside);
      expect(world.store.moves, hasLength(1));
      expect((again as Ok<H2hAbsenceRun>).value.moved, 0);
    });

    test('an excused round neither counts nor breaks the run', () async {
      final world = _World();
      await world
          .desk(DateTime.utc(2026, 11, 4, 10))
          .excuse(principal: admin, roundId: _rid(3), reason: 'تعطل التطبيق');

      final result = await world.job.call(
        now: _round4Kickoff.subtract(const Duration(minutes: 30)),
      );

      // e1 now has two counted absences (rounds 1 and 2): no swap.
      expect((result as Ok<H2hAbsenceRun>).value.moved, 0);
    });

    test('relegate off: warnings only', () async {
      final world = _World();
      final job = RunH2hAbsence(
        leagues: world.leagues,
        rounds: world.rounds,
        sheets: world.sheets,
        moves: world.store,
        sender: world.sender,
        idGenerator: world.ids,
        relegate: false,
      );

      await job.call(now: _round4Kickoff.subtract(const Duration(minutes: 5)));

      expect(world.store.moves, isEmpty);
    });
  });

  group('the tables after a swap', () {
    test('the promoted player plays the elite group with his whole month; '
        'the relegated one the extra group with his', () async {
      final world = _World();
      await world.job.call(
        now: _round4Kickoff.subtract(const Duration(minutes: 30)),
      );
      final now = DateTime.utc(2026, 11, 4, 16);

      final promoted = await world
          .league(now)
          .call(
            principal: AuthenticatedUser(
              userId: _x[0],
              role: PlatformRole.user,
            ),
          );
      final relegated = await world
          .league(now)
          .call(
            principal: AuthenticatedUser(
              userId: _e[0],
              role: PlatformRole.user,
            ),
          );

      final up = (promoted as Ok<MyH2hLeague>).value;
      expect(up.seat!.leagueId, _elite);
      final table = {for (final p in up.placings) p.standing.userId: p};
      // The elite group's table: its four seats' holders now.
      expect(table.keys.toSet(), {_x[0], _e[1], _e[2], _e[3]});
      // x1's own month: 9 points in each of rounds 1-3, played in group 5.
      expect(table[_x[0]]!.standing.pointsFor, 27);
      expect(table[_x[0]]!.standing.played, 3);
      expect(up.rounds.map((r) => r.round.number), [1, 2, 3, 4]);
      // Round 1's opponent is from group 5, where x1 played it.
      expect(
        _x.contains(up.rounds.first.opponentId) ||
            up.rounds.first.opponentId == null,
        isTrue,
      );

      final down = (relegated as Ok<MyH2hLeague>).value;
      expect(down.seat!.leagueId, _extra);
      final extraTable = {for (final p in down.placings) p.standing.userId};
      expect(extraTable, {_e[0], _x[1], _x[2]});
      // e1 played rounds 1-3 in the elite group and missed them all.
      final mine = down.placings.firstWhere((p) => p.standing.userId == _e[0]);
      expect(mine.standing.lost, 3);
      expect(mine.standing.presentRounds, 0);
    });
  });

  group('AdminH2hAbsence', () {
    final beforeRound4 = DateTime.utc(2026, 11, 4, 10);

    test('the view: the count, the watch list and the substitutes', () async {
      final world = _World();

      final result = await world.desk(beforeRound4).view(principal: admin);

      final view = (result as Ok<H2hAbsenceView>).value;
      expect(view.active, isTrue);
      expect(view.nextRound!.number, 4);
      expect(
        view.relegatesAt,
        _round4Kickoff.subtract(const Duration(hours: 1)),
      );
      expect(
        [for (final r in view.rounds) r.counted],
        [true, true, true, false],
      );
      expect(
        [for (final w in view.watch) (w.seat.userId, w.absentRounds.length)],
        [(_e[0], 3), (_e[1], 2)],
      );
      expect([for (final c in view.candidates) c.seat.userId], [_x[0]]);
      expect(view.candidates.single.groupNumber, 5);
    });

    test('a player is refused', () async {
      final result = await _World().desk(beforeRound4).view(principal: player);

      expect(
        (result as Err<H2hAbsenceView>).error.kind,
        ErrorKind.authorization,
      );
    });

    test('a relegation by hand needs a reason and an elite player, takes '
        'the substitute the rules take, and happens once', () async {
      final world = _World();
      final desk = world.desk(beforeRound4);

      final noReason = await desk.relegate(
        principal: admin,
        userId: _e[3],
        reason: '  ',
      );
      final notElite = await desk.relegate(
        principal: admin,
        userId: _x[1],
        reason: 'تلاعب',
      );
      final done = await desk.relegate(
        principal: admin,
        userId: _e[3],
        reason: 'تلاعب بالتوقعات',
      );
      final twice = await desk.relegate(
        principal: admin,
        userId: _e[3],
        reason: 'تلاعب بالتوقعات',
      );

      expect((noReason as Err<H2hSeatMove>).error.code, 'h2h.reason_required');
      expect((notElite as Err<H2hSeatMove>).error.code, 'h2h.not_elite_player');
      final move = (done as Ok<H2hSeatMove>).value;
      expect(move.kind, H2hSeatMoveKind.admin);
      expect(move.inUser, _x[0]);
      expect(move.reason, 'تلاعب بالتوقعات');
      expect(move.decidedBy, admin.userId);
      expect(move.fromRound, 4);
      expect((twice as Err<H2hSeatMove>).error.code, 'h2h.already_relegated');
    });

    test('with no substitute left, a relegation by hand is refused', () async {
      final world = _World();
      world.store.facts.remove(_x[0]);

      final result = await world
          .desk(beforeRound4)
          .relegate(principal: admin, userId: _e[3], reason: 'مخالفة');

      expect((result as Err<H2hSeatMove>).error.code, 'h2h.no_substitute');
    });

    test(
      'an excusal needs a reason and a started round of the month',
      () async {
        final world = _World();
        final desk = world.desk(beforeRound4);

        final noReason = await desk.excuse(
          principal: admin,
          roundId: _rid(2),
          reason: '',
        );
        final notStarted = await desk.excuse(
          principal: admin,
          roundId: _rid(4),
          reason: 'تعطل',
        );
        final first = await desk.excuse(
          principal: admin,
          roundId: _rid(2),
          reason: 'تعطل',
        );
        final second = await desk.excuse(
          principal: admin,
          roundId: _rid(2),
          reason: 'تعطل',
        );

        expect((noReason as Err<bool>).error.code, 'h2h.reason_required');
        expect((notStarted as Err<bool>).error.code, 'h2h.round_not_started');
        expect((first as Ok<bool>).value, isTrue);
        expect((second as Ok<bool>).value, isFalse);
      },
    );
  });
}
