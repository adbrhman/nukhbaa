import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/identity/postgres_favorite_team_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-2222-3333-4444-555555555555';
const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;

  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];
  int transactions = 0;

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    params.add(parameters);
    return _responses[sqls.length - 1];
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async {
    transactions += 1;
    return action(this);
  }

  @override
  Future<void> close() async {}
}

/// Hermetic unit tests for the row mapping and the statement sequence of
/// [PostgresFavoriteTeamRepository]. That the FK maps an unknown team to a
/// validation error needs a real ServerException, which has no public
/// constructor: check it by hand against the live database.
void main() {
  group('favoritesOf', () {
    test('answers the teams in the order the rows come back', () async {
      final connection = _FakeConnection([
        const Result.ok([
          {'team_id': _b},
          {'team_id': _a},
        ]),
      ]);

      final result = await PostgresFavoriteTeamRepository(
        connection,
      ).favoritesOf(const UserId(_user));

      expect((result as Ok<FavoriteTeams>).value.teams, const [
        TeamRef(_b),
        TeamRef(_a),
      ]);
      expect(connection.params.single['user_id'], _user);
    });

    test('no rows is none', () async {
      final connection = _FakeConnection([const Result.ok([])]);

      final result = await PostgresFavoriteTeamRepository(
        connection,
      ).favoritesOf(const UserId(_user));

      expect((result as Ok<FavoriteTeams>).value, FavoriteTeams.none);
    });

    test('a row without a team id is transient, not a guess', () async {
      final connection = _FakeConnection([
        const Result.ok([
          {'team_id': null},
        ]),
      ]);

      final result = await PostgresFavoriteTeamRepository(
        connection,
      ).favoritesOf(const UserId(_user));

      expect((result as Err<FavoriteTeams>).error.kind, ErrorKind.transient);
    });
  });

  group('replace', () {
    test('clears then inserts each team, in one transaction', () async {
      final connection = _FakeConnection([
        const Result.ok([]),
        const Result.ok([]),
        const Result.ok([]),
      ]);
      final teams =
          (FavoriteTeams.tryCreate(const [TeamRef(_b), TeamRef(_a)])
                  as Ok<FavoriteTeams>)
              .value;

      final result = await PostgresFavoriteTeamRepository(
        connection,
      ).replace(const UserId(_user), teams);

      expect((result as Ok<FavoriteTeams>).value, teams);
      expect(connection.transactions, 1);
      expect(connection.sqls, hasLength(3));
      expect(connection.sqls[0], contains('DELETE'));
      expect(connection.params[1]['team_id'], _b);
      expect(connection.params[2]['team_id'], _a);
    });

    test('a failed insert surfaces its error', () async {
      final connection = _FakeConnection([
        const Result.ok([]),
        const Result.err(AppError.transient('db.query_failed', 'down')),
      ]);
      final teams =
          (FavoriteTeams.tryCreate(const [TeamRef(_a)]) as Ok<FavoriteTeams>)
              .value;

      final result = await PostgresFavoriteTeamRepository(
        connection,
      ).replace(const UserId(_user), teams);

      expect((result as Err<FavoriteTeams>).error.code, 'db.query_failed');
    });
  });
}
