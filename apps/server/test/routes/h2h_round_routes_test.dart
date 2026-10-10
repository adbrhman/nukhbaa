/// The head-to-head screen's server side, from the real entry points:
/// `GET /me/h2h-league/rounds/{n}` and `GET /me/h2h-league` run their route
/// handler, the real use-cases, the real Postgres round reader and the real
/// mapper; only the database is scripted.
///
/// The database here is deliberately broken: it answers the opponent's
/// predictions on EVERY fixture, kicked off or not, as if the reader's
/// `kickoff_at <= now` filter were gone. What the client receives must still
/// hold the opponent's pick of a fixture back until that fixture kicks off
/// by the server clock.
library;

import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/h2h-league/index.dart' as month_route;
// ignore: always_use_package_imports
import '../../routes/me/h2h-league/rounds/[n]/index.dart' as round_route;
import 'competition_route_harness.dart';

const _leagueId = '11111111-1111-1111-1111-111111111111';
const _opponent = '00000000-0000-0000-0000-000000000001';
const _f1 = '00000000-0000-0000-0000-0000000000f1';
const _f2 = '00000000-0000-0000-0000-0000000000f2';
const _f3 = '00000000-0000-0000-0000-0000000000f3';

final _novemberStart = DateTime.utc(2026, 11);

/// f2 kicks off at 15:00 UTC on the 10th.
final _f2Kickoff = DateTime.utc(2026, 11, 10, 15);
final _minuteBefore = _f2Kickoff.subtract(const Duration(minutes: 1));

/// The caller (slot 0) meets slot 3 in round 1 of a group of four.
H2hSeat _seat() => H2hSeat(
  leagueId: const H2hLeagueId(_leagueId),
  monthStart: _novemberStart,
  division: H2hDivision.second,
  groupIndex: 0,
  slot: 0,
  capacity: 4,
  divisionGroups: 1,
  isPilot: true,
  joinedAt: DateTime.utc(2026, 10, 30),
);

H2hRound _round(int number, DateTime day, {required bool locked}) => H2hRound(
  id: H2hRoundId(
    '00000000-0000-0000-0000-${(100 + number).toString().padLeft(12, '0')}',
  ),
  monthStart: _novemberStart,
  number: number,
  day: day,
  fixtureCount: 3,
  approvedBy: null,
  lockedAt: locked ? day.add(const Duration(hours: 9)) : null,
);

/// Round 1 on the 10th is being played; round 2 on the 12th is next.
final _rounds = [
  _round(1, DateTime.utc(2026, 11, 10), locked: true),
  _round(2, DateTime.utc(2026, 11, 12), locked: false),
];

final class _Leagues implements H2hLeagueStore {
  _Leagues(this.seat);

  final H2hSeat? seat;

  @override
  Future<Result<H2hSeat?>> seatFor({
    required UserId userId,
    required DateTime monthStart,
  }) async => Result.ok(
    userId.value == kNonMemberUserId && seat?.monthStart == monthStart
        ? seat
        : null,
  );

  @override
  Future<Result<H2hMonthInfo?>> monthOf(DateTime monthStart) async =>
      const Result.ok(null);

  @override
  Future<Result<int>> draw({
    required DateTime monthStart,
    required bool isPilot,
    required List<H2hDrawnGroup> groups,
    required int capacity,
  }) => throw StateError('not used by these routes');

  @override
  Future<Result<bool>> isClosed(DateTime monthStart) =>
      throw StateError('not used by these routes');

  @override
  Future<Result<List<H2hGroupRef>>> groupsOf(DateTime monthStart) =>
      throw StateError('not used by these routes');

  @override
  Future<Result<DateTime?>> nextUnclosedMonth() =>
      throw StateError('not used by these routes');

  @override
  Future<Result<void>> markClosed({
    required DateTime monthStart,
    required int memberCount,
  }) => throw StateError('not used by these routes');
}

final class _Rounds implements H2hRoundStore {
  @override
  Future<Result<List<H2hRound>>> roundsOf(DateTime monthStart) async =>
      Result.ok([
        for (final round in _rounds)
          if (round.monthStart == monthStart) round,
      ]);

  @override
  Future<Result<List<H2hDayFixtures>>> daysBetween({
    required DateTime from,
    required DateTime through,
  }) async => Result.ok([
    H2hDayFixtures(
      day: DateTime.utc(2026, 11, 10),
      fixtureCount: 3,
      firstKickoff: DateTime.utc(2026, 11, 10, 12),
    ),
    H2hDayFixtures(
      day: DateTime.utc(2026, 11, 12),
      fixtureCount: 7,
      firstKickoff: DateTime.utc(2026, 11, 12, 16),
    ),
  ]);

  @override
  Future<Result<H2hDayFixtures>> dayFixtures(DateTime day) =>
      throw StateError('not used by these routes');

  @override
  Future<Result<void>> approve({
    required H2hRoundId id,
    required DateTime monthStart,
    required int number,
    required DateTime day,
    required int fixtureCount,
    required UserId? approvedBy,
  }) => throw StateError('not used by these routes');

  @override
  Future<Result<void>> withdraw(H2hRoundId roundId) =>
      throw StateError('not used by these routes');

  @override
  Future<Result<int>> lock({
    required H2hRoundId roundId,
    required DateTime day,
  }) => throw StateError('not used by these routes');
}

/// The group. With [opponentSeated] false, slot 3 is empty and the caller
/// plays the group average. With [opponentPlayed] false, the opponent has
/// no prediction in round 1 at all.
final class _Sheets implements H2hSheetReader {
  _Sheets({
    required this.myPoints,
    this.opponentSeated = true,
    this.opponentPlayed = true,
  });

  final int myPoints;
  final bool opponentSeated;
  final bool opponentPlayed;

  @override
  Future<Result<H2hGroupSheet>> sheetOf({
    required H2hLeagueId leagueId,
    required List<H2hRound> rounds,
  }) async {
    final joined = DateTime.utc(2026, 10, 30);
    return Result.ok(
      H2hGroupSheet(
        members: [
          H2hMember(
            userId: const UserId(kNonMemberUserId),
            slot: 0,
            joinedAt: joined,
          ),
          H2hMember(
            userId: const UserId('00000000-0000-0000-0000-000000000002'),
            slot: 1,
            joinedAt: joined,
          ),
          H2hMember(
            userId: const UserId('00000000-0000-0000-0000-000000000003'),
            slot: 2,
            joinedAt: joined,
          ),
          if (opponentSeated)
            H2hMember(
              userId: const UserId(_opponent),
              slot: 3,
              joinedAt: joined,
            ),
        ],
        scores: [
          H2hRoundScore(
            userId: const UserId(kNonMemberUserId),
            round: 1,
            points: myPoints,
            exactCount: myPoints > 0 ? 1 : 0,
            predictedCount: 2,
          ),
          if (opponentSeated && opponentPlayed)
            const H2hRoundScore(
              userId: UserId(_opponent),
              round: 1,
              points: 0,
              exactCount: 0,
              predictedCount: 2,
            ),
        ],
        settledRounds: const <int>{},
        voidRounds: const <int>{},
      ),
    );
  }

  @override
  Future<Result<Map<UserId, int>>> activeDaysOf(DateTime monthStart) =>
      throw StateError('not used by these routes');
}

final class _Profiles implements WeeklyLeagueProfileReader {
  @override
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  ) async => Result.ok({
    for (final id in userIds)
      id: WeeklyLeagueMemberProfile(displayName: 'name-${id.value}'),
  });
}

/// A database that answers whatever the reader asks, in order, and records
/// every statement and its parameters.
final class _ScriptedDatabase implements PostgresConnection {
  _ScriptedDatabase(this._answers);

  final List<List<Map<String, dynamic>>> _answers;
  final List<String> sqls = [];
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    this.parameters.add(parameters);
    return Result.ok(_answers[sqls.length - 1]);
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async => action(this);

  @override
  Future<void> close() async {}
}

Map<String, dynamic> _fixture(
  String id,
  DateTime kickoff, {
  bool counted = true,
  int? home,
  int? away,
}) => {
  'fixture_id': id,
  'home_team': 'Home $id',
  'away_team': 'Away $id',
  'home_team_id': null,
  'away_team_id': null,
  'kickoff_at': kickoff,
  'counted': counted,
  'home_goals': home,
  'away_goals': away,
};

Map<String, dynamic> _pick(
  String user,
  String fixture,
  int home,
  int away, {
  bool isDouble = false,
  int? points,
  bool exact = false,
}) => {
  'user_id': user,
  'fixture_id': fixture,
  'home_goals': home,
  'away_goals': away,
  'is_double': isDouble,
  'points': points,
  'exact': exact,
};

/// Round 1: f1 (12:00, ended 2-1), f2 (15:00), f3 (moved off the day, to
/// the 11th). The opponent's f2 pick is 7-7 doubled and f3 is 8-8: neither
/// may reach the client before its kickoff.
_ScriptedDatabase _database() => _ScriptedDatabase([
  [
    _fixture(_f1, DateTime.utc(2026, 11, 10, 12), home: 2, away: 1),
    _fixture(_f2, _f2Kickoff),
    _fixture(_f3, DateTime.utc(2026, 11, 11, 18), counted: false),
  ],
  [
    _pick(kNonMemberUserId, _f1, 2, 1, isDouble: true, points: 6, exact: true),
    _pick(kNonMemberUserId, _f2, 1, 0),
    _pick(_opponent, _f1, 0, 1, points: 0),
    _pick(_opponent, _f2, 7, 7, isDouble: true),
    _pick(_opponent, _f3, 8, 8),
  ],
]);

CompositionRoot _root({
  required DateTime now,
  required _ScriptedDatabase database,
  _Sheets? sheets,
}) {
  final clock = FixedClock(now);
  final leagues = _Leagues(_seat());
  final rounds = _Rounds();
  GetMyH2hLeague league() => GetMyH2hLeague(
    leagues: leagues,
    rounds: rounds,
    sheets: sheets ?? _Sheets(myPoints: 6),
    profiles: _Profiles(),
    clock: clock,
  );
  return CompositionRoot.forTesting(
    getMyH2hMonth: GetMyH2hMonth(
      league: league(),
      rounds: rounds,
      clock: clock,
    ),
    getMyH2hRound: GetMyH2hRound(
      league: league(),
      fixtures: PostgresH2hRoundFixtureReader(database),
      clock: clock,
    ),
  );
}

Future<Response> _getRound(CompositionRoot root, String n) =>
    round_route.onRequest(
      wireContext(
        root: root,
        principal: nonMemberPrincipal(),
        method: HttpMethod.get,
      ),
      n,
    );

Map<String, Object?> _line(Map<String, Object?> body, String fixtureId) =>
    (body['fixtures']! as List).cast<Map<String, Object?>>().singleWhere(
      (f) => f['fixture_id'] == fixtureId,
    );

void main() {
  group('GET /me/h2h-league/rounds/{n}: the opponent stays secret', () {
    test('a minute before kickoff the opponent pick is not sent', () async {
      final database = _database();
      final response = await _getRound(
        _root(now: _minuteBefore, database: database),
        '1',
      );

      expect(response.statusCode, HttpStatus.ok);
      final text = await response.body();
      expect(text, isNot(contains('"home_goals":7')));
      expect(text, isNot(contains('"home_goals":8')));

      final body = jsonDecode(text) as Map<String, Object?>;
      final f2 = _line(body, _f2);
      expect(f2['theirs'], isNull);
      expect(f2['theirs_hidden'], isTrue);
      expect(f2['state'], 'not_started');
      expect((f2['mine']! as Map)['home_goals'], 1);

      final f3 = _line(body, _f3);
      expect(f3['theirs'], isNull);
      expect(f3['theirs_hidden'], isTrue);
      expect(f3['state'], 'void');

      final f1 = _line(body, _f1);
      expect((f1['theirs']! as Map)['away_goals'], 1);
      expect(f1['theirs_hidden'], isFalse);
      expect(f1['state'], 'finished');

      // Their counts: f1 only (kicked off and counted).
      expect(body['theirs'], {'predicted': 1, 'exact': 0, 'doubles': 0});
      expect(body['mine'], {'predicted': 2, 'exact': 1, 'doubles': 1});

      // The database was asked with the server clock and the opponent.
      expect(database.parameters[1]['now'], _minuteBefore);
      expect(database.parameters[1]['opponent'], _opponent);
      expect(database.parameters[1]['reader'], kNonMemberUserId);
    });

    test('at the kickoff minute it is sent', () async {
      final body = await decodeBody(
        await _getRound(_root(now: _f2Kickoff, database: _database()), '1'),
      );

      final f2 = _line(body, _f2);
      expect(f2['theirs'], {
        'home_goals': 7,
        'away_goals': 7,
        'is_double': true,
        'points': null,
        'exact': false,
      });
      expect(f2['theirs_hidden'], isFalse);
      expect(f2['state'], 'live');
      expect(body['theirs'], {'predicted': 2, 'exact': 0, 'doubles': 1});
    });

    test(
      'a live round tells nothing of whether the opponent predicted',
      () async {
        // No points for either side yet, and the opponent has no prediction
        // in the round at all: the policy would call it a win.
        final body = await decodeBody(
          await _getRound(
            _root(
              now: _minuteBefore,
              database: _database(),
              sheets: _Sheets(myPoints: 0, opponentPlayed: false),
            ),
            '1',
          ),
        );

        expect(body['status'], 'live');
        expect(body['my_points'], 0);
        expect(body['opponent_points'], 0);
        expect(body['result'], 'draw');
      },
    );

    test('the group average shows nothing of an opponent', () async {
      final body = await decodeBody(
        await _getRound(
          _root(
            now: _f2Kickoff,
            database: _database(),
            sheets: _Sheets(myPoints: 6, opponentSeated: false),
          ),
          '1',
        ),
      );

      expect(body['opponent_user_id'], isNull);
      expect(body['opponent_name'], isNull);
      expect(body['theirs'], isNull);
      for (final f
          in (body['fixtures']! as List).cast<Map<String, Object?>>()) {
        expect(f['theirs'], isNull);
        expect(f['theirs_hidden'], isFalse);
      }
    });
  });

  group('GET /me/h2h-league/rounds/{n}: the round', () {
    test('the round, its opponent and the fixtures by kickoff', () async {
      final body = await decodeBody(
        await _getRound(_root(now: _minuteBefore, database: _database()), '1'),
      );

      expect(body['round'], 1);
      expect(body['day'], '2026-11-10');
      expect(body['status'], 'live');
      expect(body['first_kickoff'], '2026-11-10T12:00:00.000Z');
      expect(body['opponent_user_id'], _opponent);
      expect(body['opponent_name'], 'name-$_opponent');
      expect(body['my_points'], 6);
      expect(body['result'], 'win');
      expect(
        [for (final f in body['fixtures']! as List) (f as Map)['fixture_id']],
        [_f1, _f2, _f3],
      );
    });

    test('a caller with no seat is refused', () async {
      final stranger = await round_route.onRequest(
        wireContext(
          root: _root(now: _minuteBefore, database: _database()),
          principal: memberPrincipal(),
          method: HttpMethod.get,
        ),
        '1',
      );
      expect(stranger.statusCode, HttpStatus.conflict);
      expect((await decodeBody(stranger))['code'], 'h2h.not_seated');
    });

    test('a round the month does not have is refused', () async {
      final response = await _getRound(
        _root(now: _minuteBefore, database: _database()),
        '5',
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'h2h.round_unknown');
    });

    for (final bad in ['0', '20', 'x', '01', '-1', '']) {
      test('"$bad" is not a round number', () async {
        final database = _database();
        final response = await _getRound(
          _root(now: _minuteBefore, database: database),
          bad,
        );

        expect(response.statusCode, HttpStatus.badRequest);
        expect((await decodeBody(response))['code'], 'h2h.round_invalid');
        expect(database.sqls, isEmpty);
      });
    }

    test('a non-GET method is 405', () async {
      final response = await round_route.onRequest(
        wireContext(
          root: _root(now: _minuteBefore, database: _database()),
          principal: nonMemberPrincipal(),
          method: HttpMethod.post,
        ),
        '1',
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('GET /me/h2h-league for the screen', () {
    Future<Map<String, Object?>> month(DateTime now, {_Sheets? sheets}) async =>
        decodeBody(
          await month_route.onRequest(
            wireContext(
              root: _root(now: now, database: _database(), sheets: sheets),
              principal: nonMemberPrincipal(),
              method: HttpMethod.get,
            ),
          ),
        );

    test('phases, first kickoffs and the days left', () async {
      final body = await month(_minuteBefore);

      expect(body['days_left'], 20);
      final rounds = (body['rounds']! as List).cast<Map<String, Object?>>();
      expect([for (final r in rounds) r['status']], ['live', 'open']);
      expect(
        [for (final r in rounds) r['first_kickoff']],
        ['2026-11-10T12:00:00.000Z', '2026-11-12T16:00:00.000Z'],
      );
    });

    test('a live round shows points only, not the policy result', () async {
      final body = await month(
        _minuteBefore,
        sheets: _Sheets(myPoints: 0, opponentPlayed: false),
      );

      final live = (body['rounds']! as List).cast<Map<String, Object?>>().first;
      expect(live['my_points'], 0);
      expect(live['opponent_points'], 0);
      expect(live['result'], 'draw');
    });
  });
}
