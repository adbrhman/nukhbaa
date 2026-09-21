import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [FavoriteTeamRepository] over
/// `identity.user_favorite_teams` (migration 0065, plan P3-1).
///
/// [replace] deletes the user's rows and inserts the new set inside one
/// [PostgresConnection.runInTransaction], so a reader never sees half a
/// change. Each row is stamped with `clock_timestamp()`, which moves between
/// statements (unlike `now()`, fixed for the transaction), so the order the
/// caller gave is the order [favoritesOf] reads back.
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter. A team id missing from the catalog trips
/// the team FK, and maps off its constraint name to a validation error.
final class PostgresFavoriteTeamRepository implements FavoriteTeamRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresFavoriteTeamRepository(this._connection);

  final PostgresConnection _connection;

  static const String _listSql = '''
SELECT uft.team_id::text AS team_id
FROM identity.user_favorite_teams uft
WHERE uft.user_id = @user_id
ORDER BY uft.created_at, uft.team_id
''';

  static const String _clearSql = '''
DELETE FROM identity.user_favorite_teams
WHERE user_id = @user_id
''';

  static const String _insertSql = '''
INSERT INTO identity.user_favorite_teams (user_id, team_id, created_at)
VALUES (@user_id, @team_id, clock_timestamp())
''';

  @override
  Future<Result<FavoriteTeams>> favoritesOf(UserId userId) async {
    final result = await _connection.query(
      _listSql,
      parameters: {'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _favorites(value),
    };
  }

  @override
  Future<Result<FavoriteTeams>> replace(UserId userId, FavoriteTeams teams) {
    return _connection.runInTransaction<FavoriteTeams>((tx) async {
      final cleared = await tx.query(
        _clearSql,
        parameters: {'user_id': userId.value},
      );
      if (cleared is Err<List<Map<String, dynamic>>>) {
        return Result<FavoriteTeams>.err(cleared.error);
      }
      for (final team in teams.teams) {
        final inserted = await tx.query(
          _insertSql,
          parameters: {'user_id': userId.value, 'team_id': team.value},
        );
        if (inserted is Err<List<Map<String, dynamic>>>) {
          return Result<FavoriteTeams>.err(_reclassify(inserted.error));
        }
      }
      return Result<FavoriteTeams>.ok(teams);
    });
  }

  static Result<FavoriteTeams> _favorites(List<Map<String, dynamic>> rows) {
    final teams = <TeamRef>[];
    for (final row in rows) {
      final raw = row['team_id'];
      final parsed = TeamRef.tryParse(raw is String ? raw : null);
      if (parsed is Err<TeamRef>) {
        return const Result.err(
          AppError.transient(
            'identity.favorite_teams_row_corrupt',
            'a favorite team row had no team id',
          ),
        );
      }
      teams.add((parsed as Ok<TeamRef>).value);
    }
    return FavoriteTeams.tryCreate(teams);
  }

  static AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is ServerException &&
        cause.code == '23503' &&
        cause.constraintName == 'user_favorite_teams_team_id_fkey') {
      return const AppError.validation(
        'identity.favorite_team_unknown',
        'Unknown team',
      );
    }
    return error;
  }
}
