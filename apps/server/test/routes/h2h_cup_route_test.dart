/// `GET /me/h2h-cup` from the real entry point: the route handler, the real
/// use-case and the real mapper over a scripted cup store. A qualifier
/// reads his path, his pair and the day; a player outside the cup reads
/// `spectator` with the first places' path; no prediction of anybody is on the wire.
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
import '../../routes/me/h2h-cup/index.dart' as cup_route;
import 'competition_route_harness.dart';

/// The harness user holds the first seat of path 1.
const _me = kUserId;
const _b = '00000000-0000-4000-9000-000000000002';
const _c = '00000000-0000-4000-9000-000000000003';
const _d = '00000000-0000-4000-9000-000000000004';

final _november = DateTime.utc(2026, 11);

/// 2026-11-22 12:00 UTC: 15:00 in Riyadh.
final _now = DateTime.utc(2026, 11, 22, 12);

final class _Cups implements H2hCupStore {
  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async {
    if (monthStart != _november) {
      return const Result.ok(H2hCupState.empty);
    }
    const ids = [_me, _b, _c, _d];
    return Result.ok(
      H2hCupState(
        entries: [
          for (var i = 0; i < ids.length; i++)
            H2hCupEntry(
              userId: UserId(ids[i]),
              place: 1,
              groupNumber: i + 1,
              leaguePoints: 40,
              pointsFor: 100,
              exactCount: 10,
            ),
        ],
        stages: [
          H2hCupStage(
            id: const H2hCupStageId('55555555-5555-4555-8555-555555555555'),
            monthStart: _november,
            step: const H2hCupStep(1, H2hCupRound.semi),
            attempt: 1,
            day: DateTime.utc(2026, 11, 23),
            fixtureCount: 8,
            lockedAt: null,
            pairs: const [
              H2hCupPair(slot: 1, home: UserId(_me), away: UserId(_c)),
              H2hCupPair(slot: 2, home: UserId(_b), away: UserId(_d)),
            ],
            results: const <H2hCupResult>[],
          ),
        ],
        titles: const <H2hCupTitle>[],
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

CompositionRoot _root() => CompositionRoot.forTesting(
  getMyH2hCup: GetMyH2hCup(
    cups: _Cups(),
    profiles: _Profiles(),
    clock: FixedClock(_now),
  ),
);

List<Map<Object?, Object?>> _list(Object? raw) =>
    (raw! as List).cast<Map<Object?, Object?>>();

void main() {
  group('GET /me/h2h-cup', () {
    test('a qualifier reads his path, his pair and the day', () async {
      final response = await cup_route.onRequest(
        wireContext(
          root: _root(),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['state'], 'qualified');
      expect(body['month_start'], '2026-11-01');
      expect(body['place'], 1);
      expect(body['group_number'], 1);
      expect(_list(body['entrants']), hasLength(4));

      final stages = _list(body['stages']);
      expect([for (final s in stages) s['round']], ['semi', 'final']);
      expect([for (final s in stages) s['phase']], ['scheduled', 'waiting']);
      expect(stages.first['day'], '2026-11-23');
      expect(stages.first['expected_day'], 20);
      expect(stages.last['expected_day'], 21);

      final pairs = _list(stages.first['pairs']);
      expect(pairs, hasLength(2));
      final mine = pairs.singleWhere((p) => p['is_mine'] == true);
      expect((mine['home']! as Map)['user_id'], _me);
      expect((mine['home']! as Map)['is_me'], true);
      expect((mine['away']! as Map)['user_id'], _c);
      expect((mine['away']! as Map)['display_name'], 'name-$_c');
      expect(mine['decided'], false);

      // Names, days and figures only: no prediction on this wire.
      expect(body.toString(), isNot(contains('prediction')));
    });

    test('a player outside the cup watches the first places path', () async {
      final response = await cup_route.onRequest(
        wireContext(
          root: _root(),
          principal: const AuthenticatedUser(
            userId: UserId('00000000-0000-4000-9000-000000000099'),
            role: PlatformRole.user,
          ),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['state'], 'spectator');
      expect(body['place'], 1);
      expect(body['group_number'], 0);
      expect(_list(body['entrants']), hasLength(4));
      expect(_list(body['stages']), isNotEmpty);
      expect(_list(body['entrants']).any((p) => p['is_me'] == true), isFalse);
    });

    test('a POST is 405', () async {
      final response = await cup_route.onRequest(
        wireContext(root: _root(), principal: userPrincipal()),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
