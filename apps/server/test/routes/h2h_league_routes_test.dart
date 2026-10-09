import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/h2h/pilot/index.dart' as pilot_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/rounds/[id]/index.dart' as withdraw_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/rounds/index.dart' as rounds_route;
// ignore: always_use_package_imports
import '../../routes/me/h2h-league/index.dart' as me_route;
import 'competition_route_harness.dart';

const _leagueId = '11111111-1111-1111-1111-111111111111';
const _newRoundId = '22222222-2222-2222-2222-222222222222';

String _id(int n) => '00000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

String _roundId(int n) =>
    '00000000-0000-0000-0000-${(100 + n).toString().padLeft(12, '0')}';

/// 2026-11-10 09:00 UTC is noon in Riyadh, inside November.
final _november = DateTime.utc(2026, 11, 10, 9);

/// 2026-10-15 09:00 UTC: before the league opens.
final _october = DateTime.utc(2026, 10, 15, 9);

/// Seats and month rows; every write is recorded.
final class _Leagues implements H2hLeagueStore {
  _Leagues({this.seat, this.month, this.failWith});

  final H2hSeat? seat;
  final H2hMonthInfo? month;
  final AppError? failWith;
  final List<List<H2hDrawnGroup>> draws = [];
  final List<bool> drawsPilot = [];

  @override
  Future<Result<H2hSeat?>> seatFor({
    required UserId userId,
    required DateTime monthStart,
  }) async {
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(seat?.monthStart == monthStart ? seat : null);
  }

  @override
  Future<Result<H2hMonthInfo?>> monthOf(DateTime monthStart) async =>
      Result.ok(month?.monthStart == monthStart ? month : null);

  @override
  Future<Result<int>> draw({
    required DateTime monthStart,
    required bool isPilot,
    required List<H2hDrawnGroup> groups,
    required int capacity,
  }) async {
    draws.add(groups);
    drawsPilot.add(isPilot);
    var seated = 0;
    for (final group in groups) {
      seated += group.group.seats.length;
    }
    return Result.ok(seated);
  }

  @override
  Future<Result<bool>> isClosed(DateTime monthStart) =>
      throw StateError('not used by the routes');

  @override
  Future<Result<List<H2hGroupRef>>> groupsOf(DateTime monthStart) =>
      throw StateError('not used by the routes');

  @override
  Future<Result<DateTime?>> nextUnclosedMonth() =>
      throw StateError('not used by the routes');

  @override
  Future<Result<void>> markClosed({
    required DateTime monthStart,
    required int memberCount,
  }) => throw StateError('not used by the routes');
}

/// A month of rounds and the fixtures of each day; approvals and
/// withdrawals are recorded.
final class _Rounds implements H2hRoundStore {
  _Rounds({this.rounds = const [], this.days = const [], this.withdrawError});

  final List<H2hRound> rounds;
  final List<H2hDayFixtures> days;
  final AppError? withdrawError;
  final List<int> approved = [];
  final List<String> withdrawn = [];

  @override
  Future<Result<List<H2hRound>>> roundsOf(DateTime monthStart) async =>
      Result.ok([
        for (final round in rounds)
          if (round.monthStart == monthStart) round,
      ]);

  @override
  Future<Result<H2hDayFixtures>> dayFixtures(DateTime day) async {
    for (final d in days) {
      if (d.day == day) {
        return Result.ok(d);
      }
    }
    return Result.ok(
      H2hDayFixtures(day: day, fixtureCount: 0, firstKickoff: null),
    );
  }

  @override
  Future<Result<List<H2hDayFixtures>>> daysBetween({
    required DateTime from,
    required DateTime through,
  }) async => Result.ok([
    for (final d in days)
      if (!d.day.isBefore(from) && !d.day.isAfter(through)) d,
  ]);

  @override
  Future<Result<void>> approve({
    required H2hRoundId id,
    required DateTime monthStart,
    required int number,
    required DateTime day,
    required int fixtureCount,
    required UserId? approvedBy,
  }) async {
    approved.add(number);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> withdraw(H2hRoundId roundId) async {
    final failure = withdrawError;
    if (failure != null) {
      return Result.err(failure);
    }
    withdrawn.add(roundId.value);
    return const Result.ok(null);
  }

  @override
  Future<Result<int>> lock({
    required H2hRoundId roundId,
    required DateTime day,
  }) => throw StateError('not used by the routes');
}

final class _Sheets implements H2hSheetReader {
  _Sheets(this.sheet);

  final H2hGroupSheet sheet;

  @override
  Future<Result<H2hGroupSheet>> sheetOf({
    required H2hLeagueId leagueId,
    required List<H2hRound> rounds,
  }) async => Result.ok(sheet);

  @override
  Future<Result<Map<UserId, int>>> activeDaysOf(DateTime monthStart) =>
      throw StateError('not used by the routes');
}

/// Names every member `name-<id>`; [_id] (1) has a picture.
final class _Profiles implements WeeklyLeagueProfileReader {
  static final DateTime pictureVersion = DateTime.utc(2026, 9, 1);

  @override
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  ) async => Result.ok({
    for (final id in userIds)
      id: WeeklyLeagueMemberProfile(
        displayName: 'name-${id.value}',
        avatarUpdatedAt: id.value == _id(1) ? pictureVersion : null,
      ),
  });
}

final class _PilotSource implements H2hDrawSource {
  _PilotSource(this.order);

  final List<UserId> order;

  @override
  Future<Result<List<UserId>>> pilotOrder(DateTime monthStart) async =>
      Result.ok(order);

  @override
  Future<Result<List<UserId>>> activeOrder({
    required DateTime monthStart,
    required int minActiveDays,
  }) => throw StateError('not used by the routes');

  @override
  Future<Result<List<H2hCarry>>> carriedFrom(DateTime monthStart) =>
      throw StateError('not used by the routes');
}

final _novemberStart = DateTime.utc(2026, 11);

H2hRound _round(int number, DateTime day, {bool locked = true}) => H2hRound(
  id: H2hRoundId(_roundId(number)),
  monthStart: _novemberStart,
  number: number,
  day: day,
  fixtureCount: 6 + number,
  approvedBy: number == 1 ? null : const UserId(kAdminId),
  lockedAt: locked ? day.add(const Duration(hours: 15)) : null,
);

/// The caller sits in slot 1 of a group of four in the second division.
/// With four seats the circle method pairs slot 1 with slot 2 in round 1,
/// slot 0 in round 2, slot 3 in round 3 and slot 2 again in round 4.
final _seat = H2hSeat(
  leagueId: const H2hLeagueId(_leagueId),
  monthStart: _novemberStart,
  division: H2hDivision.second,
  groupIndex: 0,
  slot: 1,
  capacity: 4,
  divisionGroups: 1,
  isPilot: false,
  joinedAt: DateTime.utc(2026, 10, 30),
);

/// Round 1 settled, round 2 live, round 3 void, round 4 not started.
final _rounds = [
  _round(1, DateTime.utc(2026, 11)),
  _round(2, DateTime.utc(2026, 11, 4)),
  _round(3, DateTime.utc(2026, 11, 7)),
  _round(4, DateTime.utc(2026, 11, 12), locked: false),
];

H2hRoundScore _score(String user, int round, int points, {int exact = 0}) =>
    H2hRoundScore(
      userId: UserId(user),
      round: round,
      points: points,
      exactCount: exact,
      predictedCount: 3,
    );

final _sheet = H2hGroupSheet(
  members: [
    H2hMember(userId: UserId(_id(1)), slot: 0, joinedAt: _seat.joinedAt),
    H2hMember(
      userId: const UserId(kNonMemberUserId),
      slot: 1,
      joinedAt: _seat.joinedAt,
    ),
    H2hMember(userId: UserId(_id(2)), slot: 2, joinedAt: _seat.joinedAt),
    H2hMember(userId: UserId(_id(3)), slot: 3, joinedAt: _seat.joinedAt),
  ],
  scores: [
    // Round 1: the caller beats slot 2; slots 0 and 3 draw on 8, and slot 0
    // ranks above slot 3 on its exact scoreline.
    _score(kNonMemberUserId, 1, 10),
    _score(_id(2), 1, 6),
    _score(_id(1), 1, 8, exact: 1),
    _score(_id(3), 1, 8),
    // Round 2, still being played: the caller trails slot 0.
    _score(kNonMemberUserId, 2, 3),
    _score(_id(1), 2, 5),
  ],
  settledRounds: const {1},
  voidRounds: const {3},
);

CompositionRoot _root({
  required DateTime now,
  _Leagues? leagues,
  _Rounds? rounds,
  _PilotSource? source,
}) {
  final store = leagues ?? _Leagues();
  final roundStore = rounds ?? _Rounds();
  final clock = FixedClock(now);
  final ids = ScriptedIdGenerator(const [_newRoundId]);
  return CompositionRoot.forTesting(
    getMyH2hLeague: GetMyH2hLeague(
      leagues: store,
      rounds: roundStore,
      sheets: _Sheets(_sheet),
      profiles: _Profiles(),
      clock: clock,
    ),
    listH2hRounds: ListH2hRounds(
      rounds: roundStore,
      leagues: store,
      clock: clock,
    ),
    approveH2hRound: ApproveH2hRound(
      rounds: roundStore,
      idGenerator: ids,
      clock: clock,
    ),
    withdrawH2hRound: WithdrawH2hRound(rounds: roundStore),
    startH2hPilot: StartH2hPilot(
      leagues: store,
      source: source ?? _PilotSource(const []),
      idGenerator: ScriptedIdGenerator(const [_leagueId]),
      clock: clock,
    ),
  );
}

List<Map<Object?, Object?>> _list(Object? raw) =>
    (raw! as List).cast<Map<Object?, Object?>>();

void main() {
  group('GET /me/h2h-league', () {
    test('before the league opens it is not started, with the date', () async {
      final response = await me_route.onRequest(
        wireContext(
          root: _root(now: _october),
          principal: nonMemberPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['state'], 'not_started');
      expect(body['month_start'], '2026-10-01');
      expect(body['starts_on'], '2026-11-01');
      expect(body['is_pilot'], false);
      expect(body['division'], isNull);
      expect(body['standings'], isEmpty);
      expect(body['rounds'], isEmpty);
    });

    test('a drawn month without the caller is not_in_draw', () async {
      final response = await me_route.onRequest(
        wireContext(
          root: _root(
            now: _november,
            leagues: _Leagues(
              month: H2hMonthInfo(
                monthStart: _novemberStart,
                isPilot: false,
                seatedCount: 64,
              ),
            ),
          ),
          principal: nonMemberPrincipal(),
          method: HttpMethod.get,
        ),
      );

      final body = await decodeBody(response);
      expect(body['state'], 'not_in_draw');
      expect(body['month_start'], '2026-11-01');
    });

    test('the open month: table, zones, and every round', () async {
      final response = await me_route.onRequest(
        wireContext(
          root: _root(
            now: _november,
            leagues: _Leagues(seat: _seat),
            rounds: _Rounds(rounds: _rounds),
          ),
          principal: nonMemberPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['state'], 'open');
      expect(body['division'], 2);
      expect(body['group_index'], 0);
      expect(body['my_rank'], 1);
      expect(body['promotion_zone'], 2);
      expect(body['relegation_zone'], 2);

      final standings = _list(body['standings']);
      expect(
        [for (final s in standings) s['user_id']],
        [kNonMemberUserId, _id(1), _id(3), _id(2)],
      );
      expect([for (final s in standings) s['rank']], [1, 2, 3, 4]);
      expect(
        [for (final s in standings) s['is_me']],
        [true, false, false, false],
      );
      final me = standings.first;
      expect(me['played'], 1);
      expect(me['won'], 1);
      expect(me['league_points'], 3);
      expect(me['points_for'], 10);
      expect(me['form'], ['win']);
      expect(standings[1]['form'], ['draw']);
      expect(standings[1]['exact_count'], 1);
      expect(standings[1]['display_name'], 'name-${_id(1)}');
      expect(
        standings[1]['avatar_url'],
        '/users/${_id(1)}/avatar'
        '?v=${_Profiles.pictureVersion.millisecondsSinceEpoch}',
      );
      expect(standings.last['form'], ['loss']);
      expect(standings.last['avatar_url'], isNull);

      final rounds = _list(body['rounds']);
      expect(
        [for (final r in rounds) r['status']],
        ['settled', 'live', 'voided', 'upcoming'],
      );
      expect(
        [for (final r in rounds) r['day']],
        ['2026-11-01', '2026-11-04', '2026-11-07', '2026-11-12'],
      );
      expect(
        [for (final r in rounds) r['opponent_user_id']],
        [_id(2), _id(1), _id(3), _id(2)],
      );
      expect(rounds.first['my_points'], 10);
      expect(rounds.first['opponent_points'], 6.0);
      expect(rounds.first['result'], 'win');
      expect(rounds.first['opponent_name'], 'name-${_id(2)}');
      expect(rounds[1]['my_points'], 3);
      expect(rounds[1]['opponent_points'], 5.0);
      expect(rounds[1]['result'], 'loss');
      for (final r in rounds.skip(2)) {
        expect(r['my_points'], isNull);
        expect(r['opponent_points'], isNull);
        expect(r['result'], isNull);
      }
    });

    test('a failure is mapped through the error envelope', () async {
      final response = await me_route.onRequest(
        wireContext(
          root: _root(
            now: _november,
            leagues: _Leagues(
              failWith: const AppError.transient('db.down', 'down'),
            ),
          ),
          principal: nonMemberPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect((await decodeBody(response))['code'], 'db.down');
    });

    test('a non-GET method is 405', () async {
      final response = await me_route.onRequest(
        wireContext(
          root: _root(now: _november),
          principal: nonMemberPrincipal(),
          method: HttpMethod.post,
        ),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('GET /admin/h2h/rounds', () {
    // Rounds 1..3 are approved (the last on the 7th); after today, the 10th,
    // the 14th has too few matches, the 15th is a fill day and the 16th a
    // regular one.
    _Rounds roundsWithDays() => _Rounds(
      rounds: _rounds.take(3).toList(),
      days: [
        H2hDayFixtures(
          day: DateTime.utc(2026, 11, 14),
          fixtureCount: 4,
          firstKickoff: DateTime.utc(2026, 11, 14, 15),
        ),
        H2hDayFixtures(
          day: DateTime.utc(2026, 11, 15),
          fixtureCount: 5,
          firstKickoff: DateTime.utc(2026, 11, 15, 15),
        ),
        H2hDayFixtures(
          day: DateTime.utc(2026, 11, 16),
          fixtureCount: 9,
          firstKickoff: DateTime.utc(2026, 11, 16, 12),
        ),
      ],
    );

    test('an admin reads the rounds and the next candidates', () async {
      final response = await rounds_route.onRequest(
        wireContext(
          root: _root(
            now: _november,
            leagues: _Leagues(
              month: H2hMonthInfo(
                monthStart: _novemberStart,
                isPilot: false,
                seatedCount: 64,
              ),
            ),
            rounds: roundsWithDays(),
          ),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['month_start'], '2026-11-01');
      expect(body['drawn'], true);
      expect(body['is_pilot'], false);
      final rounds = _list(body['rounds']);
      expect([for (final r in rounds) r['round']], [1, 2, 3]);
      expect(rounds.first['id'], _roundId(1));
      expect(rounds.first['automatic'], true);
      expect(rounds[1]['automatic'], false);
      expect(rounds.first['locked'], true);
      expect(rounds.first['fixture_count'], 7);
      final candidates = _list(body['candidates']);
      expect(
        [for (final c in candidates) c['day']],
        ['2026-11-15', '2026-11-16'],
      );
      expect([for (final c in candidates) c['kind']], ['fill', 'regular']);
      expect(candidates.last['first_kickoff'], '2026-11-16T12:00:00.000Z');
    });

    test('?day= picks that month', () async {
      final response = await rounds_route.onRequest(
        wireContext(
          root: _root(now: _november, rounds: roundsWithDays()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
          queryParameters: const {'day': '2026-12-05'},
        ),
      );

      final body = await decodeBody(response);
      expect(body['month_start'], '2026-12-01');
      expect(body['drawn'], false);
      expect(body['rounds'], isEmpty);
    });

    test('a day that is not a date is 400', () async {
      final response = await rounds_route.onRequest(
        wireContext(
          root: _root(now: _november),
          principal: adminPrincipal(),
          method: HttpMethod.get,
          queryParameters: const {'day': '2026-02-30'},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.day_invalid');
    });

    test('a player is refused', () async {
      final response = await rounds_route.onRequest(
        wireContext(
          root: _root(now: _november, rounds: roundsWithDays()),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });

  group('POST /admin/h2h/rounds', () {
    _Rounds roundsWithDay() => _Rounds(
      rounds: _rounds.take(3).toList(),
      days: [
        H2hDayFixtures(
          day: DateTime.utc(2026, 11, 15),
          fixtureCount: 5,
          firstKickoff: DateTime.utc(2026, 11, 15, 15),
        ),
      ],
    );

    test('an admin approves a fill day as round 4: 201', () async {
      final rounds = roundsWithDay();
      final response = await rounds_route.onRequest(
        wireContext(
          root: _root(now: _november, rounds: rounds),
          principal: adminPrincipal(),
          body: const {'day': '2026-11-15'},
        ),
      );

      expect(response.statusCode, HttpStatus.created);
      final body = await decodeBody(response);
      expect(body['id'], _newRoundId);
      expect(body['round'], 4);
      expect(body['day'], '2026-11-15');
      expect(body['fixture_count'], 5);
      expect(body['automatic'], false);
      expect(body['locked'], false);
      expect(rounds.approved, [4]);
    });

    test('a day already played is 409, nothing stored', () async {
      final rounds = roundsWithDay();
      final response = await rounds_route.onRequest(
        wireContext(
          root: _root(now: _november, rounds: rounds),
          principal: adminPrincipal(),
          body: const {'day': '2026-11-06'},
        ),
      );

      // The 6th is behind the clock: no round can start on it any more.
      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'h2h.round_day_started');
      expect(rounds.approved, isEmpty);
    });

    test('a missing or malformed day is 400, nothing stored', () async {
      for (final body in const [
        <String, Object?>{},
        {'day': 15},
        {'day': '15-11-2026'},
      ]) {
        final rounds = roundsWithDay();
        final response = await rounds_route.onRequest(
          wireContext(
            root: _root(now: _november, rounds: rounds),
            principal: adminPrincipal(),
            body: body,
          ),
        );
        expect(response.statusCode, HttpStatus.badRequest, reason: '$body');
        expect(rounds.approved, isEmpty);
      }
    });

    test('a player is refused, nothing stored', () async {
      final rounds = roundsWithDay();
      final response = await rounds_route.onRequest(
        wireContext(
          root: _root(now: _november, rounds: rounds),
          principal: userPrincipal(),
          body: const {'day': '2026-11-15'},
        ),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(rounds.approved, isEmpty);
    });

    test('another method is 405', () async {
      final response = await rounds_route.onRequest(
        wireContext(
          root: _root(now: _november),
          principal: adminPrincipal(),
          method: HttpMethod.put,
        ),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('DELETE /admin/h2h/rounds/{id}', () {
    test('an admin withdraws a round: 204', () async {
      final rounds = _Rounds();
      final response = await withdraw_route.onRequest(
        wireContext(
          root: _root(now: _november, rounds: rounds),
          principal: adminPrincipal(),
          method: HttpMethod.delete,
        ),
        _roundId(4),
      );

      expect(response.statusCode, HttpStatus.noContent);
      expect(rounds.withdrawn, [_roundId(4)]);
    });

    test('a refusal of the store is passed through', () async {
      final response = await withdraw_route.onRequest(
        wireContext(
          root: _root(
            now: _november,
            rounds: _Rounds(
              withdrawError: const AppError.invariant(
                'h2h.round_locked',
                'A round that started cannot be withdrawn',
              ),
            ),
          ),
          principal: adminPrincipal(),
          method: HttpMethod.delete,
        ),
        _roundId(1),
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'h2h.round_locked');
    });

    test('an id that is not a UUID is 400', () async {
      final rounds = _Rounds();
      final response = await withdraw_route.onRequest(
        wireContext(
          root: _root(now: _november, rounds: rounds),
          principal: adminPrincipal(),
          method: HttpMethod.delete,
        ),
        'round-4',
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(rounds.withdrawn, isEmpty);
    });

    test('a player is refused, nothing withdrawn', () async {
      final rounds = _Rounds();
      final response = await withdraw_route.onRequest(
        wireContext(
          root: _root(now: _november, rounds: rounds),
          principal: userPrincipal(),
          method: HttpMethod.delete,
        ),
        _roundId(4),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(rounds.withdrawn, isEmpty);
    });
  });

  group('POST /admin/h2h/pilot', () {
    test('an admin draws the pilot month', () async {
      final leagues = _Leagues();
      final response = await pilot_route.onRequest(
        wireContext(
          root: _root(
            now: _october,
            leagues: leagues,
            source: _PilotSource([for (var i = 1; i <= 6; i++) UserId(_id(i))]),
          ),
          principal: adminPrincipal(),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['seated'], 6);
      expect(leagues.drawsPilot, [true]);
    });

    test('after the league opened it is 409, nothing drawn', () async {
      final leagues = _Leagues();
      final response = await pilot_route.onRequest(
        wireContext(
          root: _root(
            now: _november,
            leagues: leagues,
            source: _PilotSource([UserId(_id(1)), UserId(_id(2))]),
          ),
          principal: adminPrincipal(),
        ),
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'h2h.pilot_after_launch');
      expect(leagues.draws, isEmpty);
    });

    test('a player is refused, nothing drawn', () async {
      final leagues = _Leagues();
      final response = await pilot_route.onRequest(
        wireContext(
          root: _root(
            now: _october,
            leagues: leagues,
            source: _PilotSource([UserId(_id(1)), UserId(_id(2))]),
          ),
          principal: userPrincipal(),
        ),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(leagues.draws, isEmpty);
    });

    test('a GET is 405', () async {
      final response = await pilot_route.onRequest(
        wireContext(
          root: _root(now: _october),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
