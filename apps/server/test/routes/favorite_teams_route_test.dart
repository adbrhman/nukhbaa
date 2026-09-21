import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/favorite-teams/index.dart' as route;
import 'competition_route_harness.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _c = '33333333-3333-4333-8333-333333333333';
const _d = '44444444-4444-4444-8444-444444444444';

/// In-memory stand-in for `identity.user_favorite_teams`, or a failure on
/// every call.
final class _MemoryFavorites implements FavoriteTeamRepository {
  _MemoryFavorites({this.failWith});

  final AppError? failWith;
  final Map<String, FavoriteTeams> stored = {};

  @override
  Future<Result<FavoriteTeams>> favoritesOf(UserId userId) async {
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(stored[userId.value] ?? FavoriteTeams.none);
  }

  @override
  Future<Result<FavoriteTeams>> replace(
    UserId userId,
    FavoriteTeams teams,
  ) async {
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    stored[userId.value] = teams;
    return Result.ok(teams);
  }
}

CompositionRoot _rootFor(_MemoryFavorites favorites) =>
    CompositionRoot.forTesting(
      getMyFavoriteTeams: GetMyFavoriteTeams(favorites: favorites),
      setMyFavoriteTeams: SetMyFavoriteTeams(favorites: favorites),
    );

Future<Response> _call(
  _MemoryFavorites favorites,
  HttpMethod method, {
  Object? body,
}) => route.onRequest(
  wireContext(
    root: _rootFor(favorites),
    principal: nonMemberPrincipal(),
    method: method,
    body: body,
  ),
);

void main() {
  group('GET /me/favorite-teams', () {
    test('a caller who never chose reads an empty list', () async {
      final response = await _call(_MemoryFavorites(), HttpMethod.get);

      expect(response.statusCode, HttpStatus.ok);
      expect(await decodeBody(response), {
        'schema_version': 1,
        'team_ids': <Object?>[],
      });
    });

    test('a failure is mapped through the error envelope', () async {
      final response = await _call(
        _MemoryFavorites(failWith: const AppError.transient('db.down', 'down')),
        HttpMethod.get,
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
    });
  });

  group('PUT /me/favorite-teams', () {
    test(
      'stores the set for the caller, in order, and reads it back',
      () async {
        final favorites = _MemoryFavorites();

        final response = await _call(
          favorites,
          HttpMethod.put,
          body: {
            'team_ids': [_b, _a],
          },
        );

        expect(response.statusCode, HttpStatus.ok);
        expect((await decodeBody(response))['team_ids'], [_b, _a]);
        expect(favorites.stored.keys, [kNonMemberUserId]);

        final reread = await _call(favorites, HttpMethod.get);
        expect((await decodeBody(reread))['team_ids'], [_b, _a]);
      },
    );

    test('an empty list clears the set', () async {
      final favorites = _MemoryFavorites();
      await _call(
        favorites,
        HttpMethod.put,
        body: {
          'team_ids': [_a],
        },
      );

      final response = await _call(
        favorites,
        HttpMethod.put,
        body: {'team_ids': <Object?>[]},
      );

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['team_ids'], isEmpty);
    });

    test('a fourth team is 400 and stores nothing', () async {
      final favorites = _MemoryFavorites();

      final response = await _call(
        favorites,
        HttpMethod.put,
        body: {
          'team_ids': [_a, _b, _c, _d],
        },
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        (await decodeBody(response))['code'],
        'identity.favorite_teams_too_many',
      );
      expect(favorites.stored, isEmpty);
    });

    test('a missing list or a malformed id is 400', () async {
      final favorites = _MemoryFavorites();

      final missing = await _call(
        favorites,
        HttpMethod.put,
        body: <String, Object?>{},
      );
      final malformed = await _call(
        favorites,
        HttpMethod.put,
        body: {
          'team_ids': ['not-a-uuid'],
        },
      );

      expect(missing.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(missing))['code'], 'request.field_missing');
      expect(malformed.statusCode, HttpStatus.badRequest);
      expect(favorites.stored, isEmpty);
    });
  });

  test('any other method is 405', () async {
    final response = await _call(_MemoryFavorites(), HttpMethod.post);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
