/// `GET /owner/h2h-cup` from the real entry point: the route handler, the
/// real use-case and the real mapper over scripted stores. The owner reads
/// the whole cup of a month -- the three paths with names, stages, pairs and
/// results, and the month's rounds. (The owner gate itself is tested with
/// the other `/owner` routes.)
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
import '../../routes/owner/h2h-cup/index.dart' as cup_route;
import 'competition_route_harness.dart';

final _november = DateTime.utc(2026, 11);

/// 2026-11-22 12:00 UTC.
final _now = DateTime.utc(2026, 11, 22, 12);

String _id(int n) => '00000000-0000-4000-9000-${n.toString().padLeft(12, '0')}';

final class _Cups implements H2hCupStore {
  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async {
    if (monthStart != _november) {
      return const Result.ok(H2hCupState.empty);
    }
    return Result.ok(
      H2hCupState(
        entries: [
          for (var place = 1; place <= 3; place++)
            for (var g = 1; g <= 4; g++)
              H2hCupEntry(
                userId: UserId(_id((place - 1) * 4 + g)),
                place: place,
                groupNumber: g,
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
            pairs: [
              H2hCupPair(slot: 1, home: UserId(_id(1)), away: UserId(_id(3))),
              H2hCupPair(slot: 2, home: UserId(_id(2)), away: UserId(_id(4))),
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

final class _Rounds implements H2hRoundStore {
  @override
  Future<Result<List<H2hRound>>> roundsOf(DateTime monthStart) async =>
      Result.ok([
        if (monthStart == _november)
          H2hRound(
            id: const H2hRoundId('00000000-0000-4000-8000-000000000601'),
            monthStart: _november,
            number: 1,
            day: DateTime.utc(2026, 11, 3),
            fixtureCount: 8,
            approvedBy: null,
            lockedAt: DateTime.utc(2026, 11, 3, 12),
          ),
      ]);

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
  getOwnerH2hCup: GetOwnerH2hCup(
    cups: _Cups(),
    rounds: _Rounds(),
    profiles: _Profiles(),
    clock: FixedClock(_now),
  ),
);

const _owner = AuthenticatedUser(
  userId: UserId(kUserId),
  role: PlatformRole.admin,
);

List<Map<Object?, Object?>> _list(Object? raw) =>
    (raw! as List).cast<Map<Object?, Object?>>();

void main() {
  group('GET /owner/h2h-cup', () {
    test(
      'the owner reads the three paths, the stages and the rounds',
      () async {
        final response = await cup_route.onRequest(
          wireContext(root: _root(), principal: _owner, method: HttpMethod.get),
        );

        expect(response.statusCode, HttpStatus.ok);
        final body = await decodeBody(response);
        expect(body['month_start'], '2026-11-01');
        expect(_list(body['months']).single['has_cup'], true);
        final rounds = _list(body['rounds']);
        expect(rounds.single['number'], 1);
        expect(rounds.single['locked'], true);
        expect(rounds.single['by_system'], true);

        final paths = _list(body['paths']);
        expect([for (final p in paths) p['place']], [1, 2, 3]);
        expect([for (final p in paths) _list(p['entrants']).length], [4, 4, 4]);
        final stages = _list(paths.first['stages']);
        expect([for (final s in stages) s['phase']], ['scheduled', 'waiting']);
        final pairs = _list(stages.first['pairs']);
        expect(pairs, hasLength(2));
        expect((pairs.first['home']! as Map)['display_name'], 'name-${_id(1)}');
        expect((pairs.first['away']! as Map)['user_id'], _id(3));
        expect(body.toString(), isNot(contains('prediction')));
      },
    );

    test('a month that is not a date is 400', () async {
      final response = await cup_route.onRequest(
        wireContext(
          root: _root(),
          principal: _owner,
          method: HttpMethod.get,
          queryParameters: const {'month': 'soon'},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      final body = await decodeBody(response);
      expect(body['code'], 'owner.h2h_month_invalid');
    });

    test('a month without a cup has no paths', () async {
      final response = await cup_route.onRequest(
        wireContext(
          root: _root(),
          principal: _owner,
          method: HttpMethod.get,
          queryParameters: const {'month': '2026-12-01'},
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['month_start'], '2026-12-01');
      expect(_list(body['paths']), isEmpty);
    });

    test('a POST is 405', () async {
      final response = await cup_route.onRequest(
        wireContext(root: _root(), principal: _owner),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
