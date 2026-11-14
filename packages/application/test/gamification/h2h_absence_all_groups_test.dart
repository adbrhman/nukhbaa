/// Absence in every group from December 2026 (NK278, migration 0214),
/// through the real use-cases: the swap from an elite group to المجموعة 5
/// and from one extra group to the next, the last group's seat left for
/// the waiting list with or without a fill, the fill of a seat left vacant
/// before, a second run that moves nobody twice, the caller on the waiting
/// list, and November run exactly as before.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

const _e1 = H2hLeagueId('11111111-1111-4111-8111-000000000001');
const _g5 = H2hLeagueId('11111111-1111-4111-8111-000000000005');
const _g6 = H2hLeagueId('11111111-1111-4111-8111-000000000006');
const _w7 = H2hLeagueId('11111111-1111-4111-8111-000000000007');

// المجموعة 1: e0..e3; المجموعة 5: x0..x3; المجموعة 6: y0..y3, the last
// that plays; المجموعة 7 waits with w0, w1.
final _e = [for (var i = 0; i < 4; i++) userNo(100 + i)];
final _x = [for (var i = 0; i < 4; i++) userNo(200 + i)];
final _y = [for (var i = 0; i < 4; i++) userNo(300 + i)];
final _w = [for (var i = 0; i < 2; i++) userNo(400 + i)];

H2hRoundId _rid(DateTime month, int n) => H2hRoundId(
  '22222222-2222-4222-8${month.month.toString().padLeft(3, '0')}-'
  '${n.toString().padLeft(12, '0')}',
);

final class _World {
  _World(this.month, {this.lockedRounds = 3}) {
    leagues.months[month] = H2hMonthInfo(
      monthStart: month,
      isPilot: false,
      seatedCount: 14,
    );
    leagues.drawn[month] = [
      for (final (id, division, index) in [
        (_e1, H2hDivision.first, 0),
        (_g5, H2hDivision.second, 0),
        (_g6, H2hDivision.second, 1),
        (_w7, H2hDivision.second, 2),
      ])
        H2hDrawnGroup(
          leagueId: id,
          group: H2hDrawGroup(
            division: division,
            groupIndex: index,
            seats: const <H2hDrawSeat>[],
          ),
        ),
    ];
    for (var n = 1; n <= lockedRounds + 1; n++) {
      rounds.addRound(
        H2hRound(
          id: _rid(month, n),
          monthStart: month,
          number: n,
          day: DateTime.utc(month.year, month.month, n),
          fixtureCount: 8,
          approvedBy: null,
          lockedAt: n <= lockedRounds
              ? DateTime.utc(month.year, month.month, n, 12)
              : null,
        ),
      );
    }
    final next = lockedRounds + 1;
    rounds.dayOf(
      DateTime.utc(month.year, month.month, next),
      8,
      DateTime.utc(month.year, month.month, next, 15),
    );

    // e0, x0, y0 and y1 predicted nothing in rounds 1 to 3; everybody
    // else, the waiting list included, predicted in every round.
    final absent = {_e[0], _x[0], _y[0], _y[1]};
    for (var n = 1; n <= lockedRounds; n++) {
      moves.present[_rid(month, n)] = {
        for (final u in [..._e, ..._x, ..._y, ..._w])
          if (!absent.contains(u) || n > 3) u,
      };
      moves.lastKickoff[_rid(month, n)] = DateTime.utc(
        month.year,
        month.month,
        n,
        20,
      );
    }
    // The commitment decides, not the points: x1 predicted more than x2,
    // who scored more; y2 more than y3; w0 qualifies, w1 has four days.
    _facts(_x[1], predicted: 30, points: 10);
    _facts(_x[2], predicted: 20, points: 99);
    _facts(_x[3], predicted: 10, points: 50);
    _facts(_y[2], predicted: 30, points: 10);
    _facts(_y[3], predicted: 20, points: 90);
    _facts(_w[0], predicted: 25, points: 5);
    _facts(_w[1], predicted: 40, points: 60, activeDays: 4);

    List<H2hMember> seated(List<UserId> users, {int from = 1}) => [
      for (var s = 0; s < users.length; s++)
        H2hMember(userId: users[s], slot: s, joinedAt: month, fromRound: from),
    ];
    final scores = [
      for (var n = 1; n <= lockedRounds; n++)
        for (final u in moves.present[_rid(month, n)]!)
          H2hRoundScore(
            userId: u,
            round: n,
            points: 3,
            exactCount: 0,
            predictedCount: 3,
          ),
    ];
    for (final (id, members) in [
      (_e1, seated(_e)),
      (_g5, seated(_x)),
      (_g6, seated(_y)),
      (_w7, seated(_w, from: H2hLeaguePolicy.waitingFromRound)),
    ]) {
      sheets.sheets[id] = H2hGroupSheet(
        members: members,
        scores: scores,
        settledRounds: {for (var n = 1; n <= lockedRounds; n++) n},
        voidRounds: const <int>{},
      );
    }
  }

  final DateTime month;
  final int lockedRounds;
  final FakeH2hLeagueStore leagues = FakeH2hLeagueStore();
  final FakeH2hRoundStore rounds = FakeH2hRoundStore();
  final FakeH2hSheetReader sheets = FakeH2hSheetReader();
  final _Moves moves = _Moves();
  final _Vacancies vacancies = _Vacancies();
  final _Sender sender = _Sender();
  final SequenceIds ids = SequenceIds();

  void _facts(
    UserId user, {
    required int predicted,
    required int points,
    int activeDays = 20,
  }) {
    moves.facts[user] = H2hCandidateFacts(
      userId: user,
      missed: 0,
      points: points,
      exact: 0,
      activeDays: activeDays,
      predicted: predicted,
    );
  }

  /// The minute before the next round's first kickoff.
  DateTime get relegationTime =>
      DateTime.utc(month.year, month.month, lockedRounds + 1, 14, 30);

  RunH2hAbsence get job => RunH2hAbsence(
    leagues: leagues,
    rounds: rounds,
    sheets: sheets,
    moves: moves,
    sender: sender,
    idGenerator: ids,
    vacancies: vacancies,
  );
}

final class _Moves implements H2hSeatMoveStore {
  final Map<H2hRoundId, Set<UserId>> present = {};
  final Map<H2hRoundId, DateTime> lastKickoff = {};
  final Map<UserId, H2hCandidateFacts> facts = {};
  final List<H2hSeatMove> moves = [];

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
  ) async => const Result.ok({});

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

  /// Refuses what 0189 and 0214 refuse: a player out or in twice.
  @override
  Future<Result<void>> recordMove({
    required H2hSeatMove move,
    required String logId,
  }) async {
    if (moves.any(
      (m) => m.outUser == move.outUser || m.inUser == move.inUser,
    )) {
      return const Result.err(
        AppError.invariant('h2h.move_refused', 'refused'),
      );
    }
    moves.add(move);
    return const Result.ok(null);
  }

  @override
  Future<Result<bool>> excuse({
    required H2hRoundId roundId,
    required String reason,
    required UserId by,
    required String logId,
  }) async => const Result.ok(false);

  @override
  Future<Result<bool>> recordWarning({
    required H2hRoundId roundId,
    required UserId userId,
  }) async => const Result.ok(true);

  @override
  Future<Result<List<({H2hRoundId roundId, UserId userId, DateTime at})>>>
  warningsOf(List<H2hRound> rounds) async => const Result.ok([]);

  @override
  Future<Result<List<String>>> pushTokensOf(UserId userId) async =>
      Result.ok(['token-${userId.value}']);
}

/// In memory, all or nothing as the transaction of 0214: a vacancy with a
/// fill the database refuses stores neither.
final class _Vacancies implements H2hVacancyStore {
  final List<H2hSeatVacancy> vacancies = [];
  final Map<String, H2hVacancyFill> fills = {};
  Set<UserId> refuseFillOf = {};
  int reads = 0;
  int writes = 0;

  @override
  Future<Result<List<H2hSeatVacancy>>> vacanciesOf(DateTime monthStart) async {
    reads++;
    return Result.ok([
      for (final v in vacancies)
        if (v.monthStart == monthStart)
          H2hSeatVacancy(
            id: v.id,
            monthStart: v.monthStart,
            leagueId: v.leagueId,
            slot: v.slot,
            outUser: v.outUser,
            fromRound: v.fromRound,
            filledBy: fills[v.id]?.inUser,
            filledFrom: fills[v.id]?.fromRound,
          ),
    ]);
  }

  bool _refused(H2hVacancyFill fill) =>
      refuseFillOf.contains(fill.inUser) ||
      fills.containsKey(fill.vacancyId) ||
      fills.values.any((f) => f.inUser == fill.inUser);

  @override
  Future<Result<void>> vacate({
    required H2hSeatVacancy vacancy,
    H2hVacancyFill? fill,
  }) async {
    writes++;
    if (vacancies.any((v) => v.outUser == vacancy.outUser) ||
        (fill != null && _refused(fill))) {
      return const Result.err(
        AppError.invariant('h2h.move_refused', 'refused'),
      );
    }
    vacancies.add(vacancy);
    if (fill != null) {
      fills[vacancy.id] = fill;
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> fill(H2hVacancyFill fill) async {
    writes++;
    if (_refused(fill)) {
      return const Result.err(
        AppError.invariant('h2h.move_refused', 'refused'),
      );
    }
    fills[fill.vacancyId] = fill;
    return const Result.ok(null);
  }
}

final class _Sender implements PushSender {
  final List<(List<String>, String, String)> sent = [];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    sent.add((tokens, title, body));
    return const Result.ok(<String>[]);
  }
}

void main() {
  final december = DateTime.utc(2026, 12);

  group('December: absence in every group', () {
    test('each group sends its absent player one group down, and the last '
        'group leaves his seat for the waiting list', () async {
      final world = _World(december);

      final run =
          ((await world.job.call(now: world.relegationTime))
                  as Ok<H2hAbsenceRun>)
              .value;

      expect(run.moved, 2);
      expect(run.vacated, 2);
      expect(run.filled, 1);
      expect(run.unfilled, 0);
      // المجموعة 1 to 5: x1, the most committed, comes up (not x2, who
      // scored more).
      final fromElite = world.moves.moves.firstWhere((m) => m.outUser == _e[0]);
      expect(fromElite.inUser, _x[1]);
      expect((fromElite.eliteLeagueId, fromElite.eliteSlot), (_e1, 0));
      expect((fromElite.extraLeagueId, fromElite.extraSlot), (_g5, 1));
      expect(fromElite.fromRound, 4);
      // المجموعة 5 to 6: y2 comes up.
      final fromFive = world.moves.moves.firstWhere((m) => m.outUser == _x[0]);
      expect(fromFive.inUser, _y[2]);
      expect((fromFive.eliteLeagueId, fromFive.extraLeagueId), (_g5, _g6));
      // المجموعة 6 is the last that plays: y0's seat goes to w0 at once,
      // y1's stays vacant (w1 predicted on four days only).
      final byOut = {for (final v in world.vacancies.vacancies) v.outUser: v};
      expect(byOut[_y[0]]!.leagueId, _g6);
      expect(byOut[_y[0]]!.slot, 0);
      expect(byOut[_y[0]]!.fromRound, 4);
      final fill = world.vacancies.fills[byOut[_y[0]]!.id]!;
      expect(fill.inUser, _w[0]);
      expect((fill.fromLeagueId, fill.fromSlot), (_w7, 0));
      expect(fill.fromRound, 4);
      expect(world.vacancies.fills[byOut[_y[1]]!.id], isNull);
      // Nobody moves twice.
      final movedUsers = [
        for (final m in world.moves.moves) ...[m.outUser, m.inUser],
        for (final v in world.vacancies.vacancies) v.outUser,
        for (final f in world.vacancies.fills.values) f.inUser,
      ];
      expect(movedUsers.toSet(), hasLength(movedUsers.length));
      // Everybody is told.
      final told = {for (final s in world.sender.sent) s.$1.single};
      for (final u in [_e[0], _x[1], _x[0], _y[2], _y[0], _y[1], _w[0]]) {
        expect(told.contains('token-${u.value}'), isTrue, reason: '$u');
      }
      expect(
        world.sender.sent.where((s) => s.$2 == RunH2hAbsence.vacatedTitle),
        hasLength(2),
      );
    });

    test('a second run, and a third, moves nobody again', () async {
      final world = _World(december);
      await world.job.call(now: world.relegationTime);
      final moves = world.moves.moves.length;
      final vacancies = world.vacancies.vacancies.length;
      final fills = world.vacancies.fills.length;
      final told = world.sender.sent.length;

      for (var i = 0; i < 2; i++) {
        final again =
            ((await world.job.call(now: world.relegationTime))
                    as Ok<H2hAbsenceRun>)
                .value;
        expect(
          (again.moved, again.vacated, again.filled),
          (0, 0, 0),
          reason: 'run ${i + 2}',
        );
      }
      expect(world.moves.moves, hasLength(moves));
      expect(world.vacancies.vacancies, hasLength(vacancies));
      expect(world.vacancies.fills, hasLength(fills));
      expect(world.sender.sent, hasLength(told));
    });

    test('a refused fill stores neither: the absent player keeps his seat '
        'and is tried again', () async {
      final world = _World(december)..vacancies.refuseFillOf = {_w[0]};

      final run =
          ((await world.job.call(now: world.relegationTime))
                  as Ok<H2hAbsenceRun>)
              .value;

      // y0's vacancy and its fill were refused together; y1's, with no
      // fill, was stored.
      expect(run.vacated, 1);
      expect(run.filled, 0);
      expect(world.vacancies.vacancies.map((v) => v.outUser).toList(), [_y[1]]);
      expect(world.vacancies.fills, isEmpty);
      expect(
        world.sender.sent.any((s) => s.$1.single == 'token-${_y[0].value}'),
        isFalse,
      );

      // The next run, the refusal gone: y0 leaves his seat, and w0 fills
      // the oldest vacant seat first, y1's.
      world.vacancies.refuseFillOf = {};
      final again =
          ((await world.job.call(now: world.relegationTime))
                  as Ok<H2hAbsenceRun>)
              .value;
      expect((again.vacated, again.filled), (1, 1));
      final byOut = {for (final v in world.vacancies.vacancies) v.outUser: v};
      expect(world.vacancies.fills[byOut[_y[1]]!.id]!.inUser, _w[0]);
      expect(world.vacancies.fills[byOut[_y[0]]!.id], isNull);
    });

    test('a seat left vacant is filled before a later round, once a player '
        'of the waiting list qualifies', () async {
      final world = _World(december);
      await world.job.call(now: world.relegationTime);
      final vacant = world.vacancies.vacancies.firstWhere(
        (v) => v.outUser == _y[1],
      );

      // Round 4 played; w1 now predicted on twenty days.
      final later = _World(december, lockedRounds: 4)
        ..moves.moves.addAll(world.moves.moves)
        ..vacancies.vacancies.addAll(world.vacancies.vacancies)
        ..vacancies.fills.addAll(world.vacancies.fills)
        .._facts(_w[1], predicted: 40, points: 60);
      final run =
          ((await later.job.call(now: later.relegationTime))
                  as Ok<H2hAbsenceRun>)
              .value;

      expect(run.filled, 1);
      expect(run.vacated, 0);
      final fill = later.vacancies.fills[vacant.id]!;
      expect(fill.inUser, _w[1]);
      expect(fill.fromRound, 5);
      expect((fill.fromLeagueId, fill.fromSlot), (_w7, 1));
    });

    test('a player of a group with no qualifying substitute below stays, '
        'and is tried again', () async {
      final world = _World(december);
      for (final u in _y) {
        world.moves.facts.remove(u);
      }

      final run =
          ((await world.job.call(now: world.relegationTime))
                  as Ok<H2hAbsenceRun>)
              .value;

      expect(run.unfilled, 1);
      expect(world.moves.moves.any((m) => m.outUser == _x[0]), isFalse);
      expect(world.moves.moves.any((m) => m.outUser == _e[0]), isTrue);
    });

    test('the player who left his seat reads the waiting list', () async {
      final world = _World(december);
      await world.job.call(now: world.relegationTime);
      Future<MyH2hLeague> league(UserId user) async =>
          ((await GetMyH2hLeague(
                    leagues: world.leagues,
                    rounds: world.rounds,
                    sheets: world.sheets,
                    profiles: NamingProfiles(),
                    clock: AtClock(world.relegationTime),
                    vacancies: world.vacancies,
                  )(
                    principal: AuthenticatedUser(
                      userId: user,
                      role: PlatformRole.user,
                    ),
                  ))
                  as Ok<MyH2hLeague>)
              .value;

      expect((await league(_y[0])).state, H2hLeagueState.waitingList);
      expect((await league(userNo(999))).state, H2hLeagueState.notInDraw);
    });
  });

  test('November: elite absence only, as before; no vacancy is read or '
      'written', () async {
    final november = DateTime.utc(2026, 11);
    final world = _World(november);

    final run =
        ((await world.job.call(now: world.relegationTime)) as Ok<H2hAbsenceRun>)
            .value;

    expect(run.moved, 1);
    expect(run.vacated, 0);
    expect(world.moves.moves.single.outUser, _e[0]);
    expect(world.vacancies.reads, 0);
    expect(world.vacancies.writes, 0);
    expect(
      world.sender.sent.any((s) => s.$3 == RunH2hAbsence.warningBodyDecember),
      isFalse,
    );
  });
}
