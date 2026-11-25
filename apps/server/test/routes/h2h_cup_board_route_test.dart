// NK312_04
/// `GET /me/h2h-cup/board` from the real entry point: the route handler, the
/// real use-case and the real mapper over a scripted cup store and a pick
/// reader that LEAKS on purpose (it hands over the opponent's pick of a
/// fixture that has not kicked off). What reaches the wire is read as text:
/// no pick key and no pick figure for a fixture that has not started, for a
/// player and for an admin alike.
library;

import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/h2h-cup/board/index.dart' as board_route;
import 'competition_route_harness.dart';

/// The harness user plays the first pair of path 1, home side.
const _me = kUserId;
const _b = '00000000-0000-4000-9000-000000000002';
const _c = '00000000-0000-4000-9000-000000000003';
const _d = '00000000-0000-4000-9000-000000000004';

const _notStarted = '00000000-0000-4000-9000-0000000000a1';
const _started = '00000000-0000-4000-9000-0000000000a2';

final _november = DateTime.utc(2026, 11);

/// 2026-11-22 12:00 UTC.
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
            day: DateTime.utc(2026, 11, 22),
            fixtureCount: 2,
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

/// Hands over EVERY player's pick of every fixture, whatever the clock says.
final class _LeakyPicks implements H2hCupPickReader {
  @override
  Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>> fixturesOf({
    required List<H2hCupStage> stages,
    required UserId reader,
    required DateTime nowUtc,
  }) async {
    H2hFixturePick pick(int home, int away, int points) => H2hFixturePick(
      homeGoals: home,
      awayGoals: away,
      isDouble: false,
      points: points,
      exact: false,
    );
    return Result.ok({
      for (final stage in stages)
        stage.id: [
          H2hCupStageFixture(
            fixtureId: _notStarted,
            homeTeam: 'Alpha',
            awayTeam: 'Beta',
            homeTeamId: null,
            awayTeamId: null,
            kickoffAt: DateTime.utc(2026, 11, 22, 18),
            counted: true,
            homeGoals: null,
            awayGoals: null,
            picks: {
              const UserId(_me): pick(1, 0, 0),
              const UserId(_c): pick(7, 5, 77),
              const UserId(_b): pick(7, 5, 77),
              const UserId(_d): pick(7, 5, 77),
            },
          ),
          H2hCupStageFixture(
            fixtureId: _started,
            homeTeam: 'Gamma',
            awayTeam: 'Delta',
            homeTeamId: null,
            awayTeamId: null,
            kickoffAt: DateTime.utc(2026, 11, 22, 9),
            counted: true,
            homeGoals: null,
            awayGoals: null,
            picks: {
              const UserId(_me): pick(2, 2, 4), // NK330B_03
              const UserId(_c): pick(3, 1, 6),
            },
          ),
        ],
    });
  }
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

CompositionRoot _root({DateTime? now}) => CompositionRoot.forTesting(
  getH2hCupBoard: GetH2hCupBoard(
    cups: _Cups(),
    picks: _LeakyPicks(),
    profiles: _Profiles(),
    clock: FixedClock(now ?? _now),
  ),
);

List<Map<Object?, Object?>> _list(Object? raw) =>
    (raw! as List).cast<Map<Object?, Object?>>();

Future<Map<String, Object?>> _get(AuthenticatedUser principal) async {
  final response = await board_route.onRequest(
    wireContext(root: _root(), principal: principal, method: HttpMethod.get),
  );
  expect(response.statusCode, HttpStatus.ok);
  return decodeBody(response);
}

/// The fixtures of the first pair of the semi-final of path 1, by id.
Map<String, Map<Object?, Object?>> _firstPairFixtures(
  Map<String, Object?> body,
) {
  final path = _list(body['paths']).single;
  final stage = _list(path['stages']).first;
  final pair = _list(stage['pairs']).singleWhere((p) => p['slot'] == 1);
  return {
    for (final f in _list(pair['fixtures'])) f['fixture_id']! as String: f,
  };
}

Map<Object?, Object?> _sideOf(Map<Object?, Object?> fixture, String key) =>
    fixture[key]! as Map<Object?, Object?>;

void main() {
  group('GET /me/h2h-cup/board', () {
    test('a qualifier reads his own picks and only the started ones of '
        'his opponent', () async {
      final body = await _get(userPrincipal());
      expect(body['month_start'], '2026-11-01');

      final fixtures = _firstPairFixtures(body);
      expect(fixtures.keys, containsAll([_notStarted, _started]));

      // Not started: his own side shows, the opponent's is withheld, nothing
      // else on the side.
      final early = fixtures[_notStarted]!;
      expect(early['state'], 'not_started');
      final mine = _sideOf(early, 'home_side');
      expect(mine['revealed'], true);
      expect((mine['pick']! as Map)['home_goals'], 1);
      expect(_sideOf(early, 'away_side'), {'revealed': false});

      // Started: both sides show.
      final late = fixtures[_started]!;
      expect(late['state'], 'live');
      expect((_sideOf(late, 'home_side')['pick']! as Map)['home_goals'], 2);
      final theirs = _sideOf(late, 'away_side');
      expect(theirs['revealed'], true);
      expect((theirs['pick']! as Map)['home_goals'], 3);
    });

    test('no pick figure of a fixture that has not started is anywhere on '
        'the wire, the other pair included', () async {
      final body = await _get(userPrincipal());
      final text = jsonEncode(body);
      // The leaky reader gave the opponents 7-5 and 77 points.
      expect(text, isNot(contains('"home_goals":7')));
      expect(text, isNot(contains('"points":77')));

      final stage = _list(_list(body['paths']).single['stages']).first;
      final second = _list(stage['pairs']).singleWhere((p) => p['slot'] == 2);
      final early = _list(
        second['fixtures'],
      ).singleWhere((f) => f['fixture_id'] == _notStarted);
      expect(_sideOf(early, 'home_side'), {'revealed': false});
      expect(_sideOf(early, 'away_side'), {'revealed': false});
    });

    test('a player outside the cup sees nothing of a fixture that has not '
        'started', () async {
      final body = await _get(
        const AuthenticatedUser(
          userId: UserId('00000000-0000-4000-9000-000000000099'),
          role: PlatformRole.user,
        ),
      );
      final early = _firstPairFixtures(body)[_notStarted]!;
      expect(_sideOf(early, 'home_side'), {'revealed': false});
      expect(_sideOf(early, 'away_side'), {'revealed': false});
      expect(jsonEncode(body), isNot(contains('"points":77')));
    });

    test('an admin who is not an owner reads what a player reads', () async {
      final body = await _get(
        const AuthenticatedUser(
          userId: UserId('00000000-0000-4000-9000-000000000098'),
          role: PlatformRole.admin,
        ),
      );
      final early = _firstPairFixtures(body)[_notStarted]!;
      expect(_sideOf(early, 'home_side'), {'revealed': false});
      expect(_sideOf(early, 'away_side'), {'revealed': false});
      expect(jsonEncode(body), isNot(contains('"points":77')));
    });

    test('no cup stands: 200 with no month and no paths', () async {
      final response = await board_route.onRequest(
        wireContext(
          root: _root(now: DateTime.utc(2027, 3, 10, 12)),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body.containsKey('month_start'), isFalse);
      expect(_list(body['paths']), isEmpty);
    });

    // NK330B_04
    test('each pair carries its points: the started fixtures it shows, '
        'nothing of a withheld side', () async {
      final body = await _get(userPrincipal());
      final stage = _list(_list(body['paths']).single['stages']).first;
      final pairs = _list(stage['pairs']);

      final first = pairs.singleWhere((p) => p['slot'] == 1);
      expect(first['home_points'], 4);
      expect(first['away_points'], 6);
      final second = pairs.singleWhere((p) => p['slot'] == 2);
      expect(second['home_points'], 0);
      expect(second['away_points'], 0);
      expect(jsonEncode(body), isNot(contains('_points":77')));
    });

    test('a player outside the cup reads the same pair totals from the '
        'started fixtures alone', () async {
      final body = await _get(
        const AuthenticatedUser(
          userId: UserId('00000000-0000-4000-9000-000000000099'),
          role: PlatformRole.user,
        ),
      );
      final stage = _list(_list(body['paths']).single['stages']).first;
      final first = _list(stage['pairs']).singleWhere((p) => p['slot'] == 1);
      expect(first['home_points'], 4);
      expect(first['away_points'], 6);
      expect(jsonEncode(body), isNot(contains('_points":77')));
    });

    test('a POST is 405', () async {
      final response = await board_route.onRequest(
        wireContext(root: _root(), principal: userPrincipal()),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
