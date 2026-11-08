/// `GET /me/h2h-league/elite` from the real entry point: the route handler,
/// the real use-case and the real mapper over scripted stores. The four
/// elite groups arrive with names, records and points only, the caller's
/// own line marked, and nothing of the extra groups, the empty seats or any
/// match.
library;

import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/h2h-league/elite.dart' as elite_route;
import 'competition_route_harness.dart';

const _groupA = '11111111-1111-4111-8111-11111111111a';
const _groupB = '11111111-1111-4111-8111-11111111111b';
const _groupC = '11111111-1111-4111-8111-11111111111c';

/// The harness user holds seat 0 of the first elite group.
const _me = kUserId;
const _other = '00000000-0000-4000-9000-000000000002';
const _third = '00000000-0000-4000-9000-000000000003';
const _fourth = '00000000-0000-4000-9000-000000000004';

final _november = DateTime.utc(2026, 11);
final _october = DateTime.utc(2026, 10);

/// 2026-11-10 09:00 UTC: noon in Riyadh.
final _novemberNow = DateTime.utc(2026, 11, 10, 9);

/// 2026-10-10 09:00 UTC.
final _octoberNow = DateTime.utc(2026, 10, 10, 9);

final class _Leagues implements H2hLeagueStore {
  _Leagues(this.month);

  final DateTime month;

  @override
  Future<Result<H2hMonthInfo?>> monthOf(DateTime monthStart) async => Result.ok(
    monthStart == month
        ? H2hMonthInfo(monthStart: month, isPilot: false, seatedCount: 12)
        : null,
  );

  @override
  Future<Result<List<H2hGroupRef>>> groupsOf(DateTime monthStart) async =>
      Result.ok(
        monthStart == month
            ? const [
                H2hGroupRef(
                  leagueId: H2hLeagueId(_groupA),
                  division: H2hDivision.first,
                  groupIndex: 0,
                  capacity: 20,
                ),
                H2hGroupRef(
                  leagueId: H2hLeagueId(_groupB),
                  division: H2hDivision.first,
                  groupIndex: 1,
                  capacity: 20,
                ),
                H2hGroupRef(
                  leagueId: H2hLeagueId(_groupC),
                  division: H2hDivision.second,
                  groupIndex: 0,
                  capacity: 20,
                ),
              ]
            : const <H2hGroupRef>[],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

final class _Rounds implements H2hRoundStore {
  _Rounds(this.month);

  final DateTime month;

  @override
  Future<Result<List<H2hRound>>> roundsOf(DateTime monthStart) async =>
      Result.ok([
        if (monthStart == month)
          H2hRound(
            id: const H2hRoundId('00000000-0000-4000-8000-000000000101'),
            monthStart: month,
            number: 1,
            day: DateTime.utc(month.year, month.month, 3),
            fixtureCount: 6,
            approvedBy: null,
            lockedAt: DateTime.utc(month.year, month.month, 3, 12),
          ),
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

final class _Sheets implements H2hSheetReader {
  @override
  Future<Result<H2hGroupSheet>> sheetOf({
    required H2hLeagueId leagueId,
    required List<H2hRound> rounds,
  }) async {
    final ids = leagueId.value == _groupA
        ? [_me, _other]
        : leagueId.value == _groupB
        ? [_third, _fourth]
        : ['00000000-0000-4000-9000-000000000009'];
    return Result.ok(
      H2hGroupSheet(
        members: [
          for (var i = 0; i < ids.length; i++)
            H2hMember(
              userId: UserId(ids[i]),
              slot: i,
              joinedAt: DateTime.utc(2026, 10, 31),
            ),
        ],
        scores: [
          for (var i = 0; i < ids.length; i++)
            H2hRoundScore(
              userId: UserId(ids[i]),
              round: 1,
              points: 9 - i * 3,
              exactCount: 0,
              predictedCount: 6,
            ),
        ],
        settledRounds: const {1},
        voidRounds: const <int>{},
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
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

CompositionRoot _root(DateTime month, DateTime now) {
  return CompositionRoot.forTesting(
    getH2hEliteTables: GetH2hEliteTables(
      groups: AdminGetH2hGroups(
        leagues: _Leagues(month),
        rounds: _Rounds(month),
        sheets: _Sheets(),
        profiles: _Profiles(),
        clock: FixedClock(now),
      ),
    ),
  );
}

List<Map<Object?, Object?>> _list(Object? raw) =>
    (raw! as List).cast<Map<Object?, Object?>>();

void main() {
  group('GET /me/h2h-league/elite', () {
    test('the elite groups, the caller marked, nothing else', () async {
      final response = await elite_route.onRequest(
        wireContext(
          root: _root(_november, _novemberNow),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['month_start'], '2026-11-01');
      expect(body['drawn'], true);
      final groups = _list(body['groups']);
      expect([for (final g in groups) g['league_id']], [_groupA, _groupB]);
      expect([for (final g in groups) g['division']], [1, 1]);
      // No empty seat is announced to the players.
      expect(
        [for (final g in groups) g['free_slots']],
        [<Object?>[], <Object?>[]],
      );
      final first = _list(groups.first['standings']);
      expect(first, hasLength(2));
      expect(first.first['display_name'], startsWith('name-'));
      expect(
        [
          for (final s in _list(groups[0]['standings']))
            if (s['is_me'] == true) s['user_id'],
        ],
        [_me],
      );
      expect([
        for (final s in _list(groups[1]['standings']))
          if (s['is_me'] == true) s['user_id'],
      ], isEmpty);
      // No match and no prediction on this wire.
      final text = body.toString();
      expect(text, isNot(contains('matches')));
      expect(text, isNot(contains(_groupC)));
    });

    test('before the elite draw there are no groups', () async {
      final response = await elite_route.onRequest(
        wireContext(
          root: _root(_october, _octoberNow),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(_list(body['groups']), isEmpty);
    });

    test('a POST is 405', () async {
      final response = await elite_route.onRequest(
        wireContext(
          root: _root(_november, _novemberNow),
          principal: userPrincipal(),
        ),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
