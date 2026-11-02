import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/champions/[id]/prize/index.dart' as prize_route;
import 'competition_route_harness.dart';

const _season = 'c2040000-0000-4000-8000-000000000021';

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 11, 20, 12);
}

/// One month, never crowned.
final class _Champions implements MonthChampionRepository {
  @override
  Future<Result<ChampionMonth?>> month(SeasonId season) async {
    if (season.value != _season) {
      return const Result.ok(null);
    }
    return Result.ok(
      ChampionMonth(
        seasonId: season,
        label: '11/2026',
        startAt: DateTime.utc(2026, 10, 31, 21),
        endAt: DateTime.utc(2026, 11, 30, 21),
        fixtures: const [],
        unscoredFixtures: 0,
        crowned: const [],
      ),
    );
  }

  @override
  Future<Result<void>> crown({
    required SeasonId season,
    required List<ChampionToCrown> champions,
    required UserId crownedBy,
    required DateTime crownedAt,
  }) async => const Result.ok(null);

  @override
  Future<Result<List<MonthChampion>>> list({required int limit}) async =>
      const Result.ok([]);

  @override
  Future<Result<bool>> setPhoto({
    required SeasonId season,
    required UserId user,
    required List<int> bytes,
    required String mime,
    required DateTime now,
  }) async => const Result.ok(false);

  @override
  Future<Result<StoredAvatar?>> photo({
    required SeasonId season,
    required UserId user,
  }) async => const Result.ok(null);
}

/// Keeps the prizes set; nothing else is asked of it here.
final class _Store implements MonthCrownStore {
  final Map<String, (String, UserId)> prizes = {};

  @override
  Future<Result<void>> setPrize({
    required SeasonId season,
    required String prize,
    required UserId setBy,
    required DateTime setAt,
  }) async {
    prizes[season.value] = (prize, setBy);
    return const Result.ok(null);
  }

  @override
  Future<Result<String?>> prizeFor(SeasonId season) async =>
      Result.ok(prizes[season.value]?.$1);

  @override
  Future<Result<List<CrownDueMonth>>> dueMonths({
    required DateTime now,
    required Duration window,
  }) async => const Result.ok([]);

  @override
  Future<Result<MonthCrownState>> stateOf({
    required SeasonId season,
    required DateTime now,
    required Duration postponedAfter,
  }) async =>
      const Result.ok(MonthCrownState(waiting: 0, skipped: 0, rescore: 0));

  @override
  Future<Result<List<FixtureRef>>> toRescore(SeasonId season) async =>
      const Result.ok([]);

  @override
  Future<Result<bool>> noteOnce({
    required SeasonId season,
    required String kind,
    required String signature,
  }) async => const Result.ok(false);

  @override
  Future<Result<DateTime?>> resultsWrittenAfter({
    required SeasonId season,
    required DateTime since,
  }) async => const Result.ok(null);
}

CompositionRoot _root(_Store store) => CompositionRoot.forTesting(
  adminSetMonthPrize: AdminSetMonthPrize(
    champions: _Champions(),
    store: store,
    clock: const _Clock(),
  ),
);

void main() {
  group('PUT /admin/champions/{seasonId}/prize', () {
    test('an admin sets the month\'s prize ahead, trimmed', () async {
      final store = _Store();
      final response = await prize_route.onRequest(
        wireContext(
          root: _root(store),
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {'prize': ' 200 ريال سعودي '},
        ),
        _season,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['prize'], '200 ريال سعودي');
      expect(store.prizes[_season], ('200 ريال سعودي', const UserId(kAdminId)));
    });

    test('a blank prize is a 400, a player a 401', () async {
      final store = _Store();
      final blank = await prize_route.onRequest(
        wireContext(
          root: _root(store),
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {'prize': '   '},
        ),
        _season,
      );
      expect(blank.statusCode, HttpStatus.badRequest);

      final player = await prize_route.onRequest(
        wireContext(
          root: _root(store),
          principal: userPrincipal(),
          method: HttpMethod.put,
          body: const {'prize': '200'},
        ),
        _season,
      );
      expect(player.statusCode, HttpStatus.unauthorized);
      expect(store.prizes, isEmpty);
    });

    test('an unknown month is a 409; another method a 405', () async {
      final store = _Store();
      final unknown = await prize_route.onRequest(
        wireContext(
          root: _root(store),
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {'prize': '200'},
        ),
        'c2040000-0000-4000-8000-000000000099',
      );
      expect(unknown.statusCode, HttpStatus.conflict);

      final get = await prize_route.onRequest(
        wireContext(
          root: _root(store),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        _season,
      );
      expect(get.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
