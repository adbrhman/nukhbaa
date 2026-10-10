/// `GET /me/h2h-league/rounds/{n}/matches` from the real entry point: the
/// route handler, the real use-cases and the real mapper over scripted
/// stores. It sends every pair of the caller's own group with stored
/// points only: no prediction field exists in the answer, and a live round
/// never tells who has not predicted.
library;

import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/h2h-league/rounds/[n]/matches/index.dart'
    as matches_route;
import 'competition_route_harness.dart';

const _leagueId = '11111111-1111-1111-1111-111111111111';
const _u1 = '00000000-0000-0000-0000-000000000001';
const _u2 = '00000000-0000-0000-0000-000000000002';
const _u3 = '00000000-0000-0000-0000-000000000003';

final _novemberStart = DateTime.utc(2026, 11);

/// 2026-11-10 14:59 UTC: round 1 (the 10th) is being played.
final _now = DateTime.utc(2026, 11, 10, 14, 59);

H2hRound _round(int number, DateTime day, {required bool locked}) => H2hRound(
  id: H2hRoundId(
    '00000000-0000-0000-0000-${(100 + number).toString().padLeft(12, '0')}',
  ),
  monthStart: _novemberStart,
  number: number,
  day: day,
  fixtureCount: 6,
  approvedBy: null,
  lockedAt: locked ? day.add(const Duration(hours: 9)) : null,
);

final _rounds = [
  _round(1, DateTime.utc(2026, 11, 10), locked: true),
  _round(2, DateTime.utc(2026, 11, 12), locked: false),
];

final class _Leagues implements H2hLeagueStore {
  @override
  Future<Result<H2hSeat?>> seatFor({
    required UserId userId,
    required DateTime monthStart,
  }) async => Result.ok(
    userId.value == kNonMemberUserId && monthStart == _novemberStart
        ? H2hSeat(
            leagueId: const H2hLeagueId(_leagueId),
            monthStart: _novemberStart,
            division: H2hDivision.second,
            groupIndex: 0,
            slot: 0,
            capacity: 4,
            divisionGroups: 1,
            isPilot: true,
            joinedAt: DateTime.utc(2026, 10, 30),
          )
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
  }) async => const Result.ok(<H2hDayFixtures>[]);

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

/// The caller (slot 0), u1 (1), u2 (2), u3 (3). Round 1: 0-3, 1-2. So far
/// the caller has 4 and u3 7; u1 has 0 and u2 has no prediction at all.
final class _Sheets implements H2hSheetReader {
  @override
  Future<Result<H2hGroupSheet>> sheetOf({
    required H2hLeagueId leagueId,
    required List<H2hRound> rounds,
  }) async {
    final joined = DateTime.utc(2026, 10, 30);
    H2hRoundScore score(String user, int points) => H2hRoundScore(
      userId: UserId(user),
      round: 1,
      points: points,
      exactCount: 0,
      predictedCount: 2,
    );
    return Result.ok(
      H2hGroupSheet(
        members: [
          for (final (slot, user) in [kNonMemberUserId, _u1, _u2, _u3].indexed)
            H2hMember(userId: UserId(user), slot: slot, joinedAt: joined),
        ],
        scores: [score(kNonMemberUserId, 4), score(_u3, 7), score(_u1, 0)],
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

CompositionRoot _root() {
  final sheets = _Sheets();
  return CompositionRoot.forTesting(
    getMyH2hGroupRound: GetMyH2hGroupRound(
      league: GetMyH2hLeague(
        leagues: _Leagues(),
        rounds: _Rounds(),
        sheets: sheets,
        profiles: _Profiles(),
        clock: FixedClock(_now),
      ),
      sheets: sheets,
    ),
  );
}

Future<Response> _get(String n, {AuthenticatedUser? principal}) =>
    matches_route.onRequest(
      wireContext(
        root: _root(),
        principal: principal ?? nonMemberPrincipal(),
        method: HttpMethod.get,
      ),
      n,
    );

List<Map<String, Object?>> _matches(Map<String, Object?> body) =>
    (body['matches']! as List).cast<Map<String, Object?>>();

void main() {
  test('a live round: every pair, the caller first, points only', () async {
    final response = await _get('1');

    expect(response.statusCode, HttpStatus.ok);
    final text = await response.body();
    // Nobody's prediction is part of this answer.
    expect(text, isNot(contains('goals')));
    expect(text, isNot(contains('is_double')));

    final body = await decodeBody(await _get('1'));
    expect(body['round'], 1);
    expect(body['day'], '2026-11-10');
    expect(body['status'], 'live');
    final matches = _matches(body);
    expect(matches, hasLength(2));

    final mine = matches.first;
    expect(mine['home_user_id'], kNonMemberUserId);
    expect(mine['home_is_me'], isTrue);
    expect(mine['away_user_id'], _u3);
    expect(mine['away_name'], 'name-$_u3');
    expect(mine['home_points'], 4);
    expect(mine['away_points'], 7);
    expect(mine['winner'], 'away');

    // u2 has not predicted yet, u1 has 0: by points they are level. The
    // policy would give u1 the round -- and so tell that u2 has no pick.
    final theirs = matches.last;
    expect((theirs['home_user_id'], theirs['away_user_id']), (_u1, _u2));
    expect(theirs['home_points'], 0);
    expect(theirs['away_points'], 0);
    expect(theirs['winner'], 'draw');
  });

  test('the next round: the pairs, no points, no winner', () async {
    final body = await decodeBody(await _get('2'));

    expect(body['status'], 'open');
    for (final match in _matches(body)) {
      expect(match['home_points'], isNull);
      expect(match['away_points'], isNull);
      expect(match['winner'], isNull);
    }
    // Round 2 with four seats: 0-1, 2-3.
    expect(_matches(body).first['away_user_id'], _u1);
  });

  test('a caller with no seat is refused', () async {
    final response = await _get('1', principal: memberPrincipal());

    expect(response.statusCode, HttpStatus.conflict);
    expect((await decodeBody(response))['code'], 'h2h.not_seated');
  });

  test('a round the month does not have is refused', () async {
    final response = await _get('7');

    expect(response.statusCode, HttpStatus.conflict);
    expect((await decodeBody(response))['code'], 'h2h.round_unknown');
  });

  for (final bad in ['0', '20', 'x', '01', '']) {
    test('"$bad" is not a round number', () async {
      final response = await _get(bad);

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.round_invalid');
    });
  }

  test('a non-GET method is 405', () async {
    final response = await matches_route.onRequest(
      wireContext(
        root: _root(),
        principal: nonMemberPrincipal(),
        method: HttpMethod.post,
      ),
      '1',
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
