import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [DuelPlayerDirectory]: active players by display
/// name.
///
/// `strpos` rather than `ILIKE`, so a typed `%` or `_` is matched as itself
/// instead of as a wildcard.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresDuelPlayerDirectory implements DuelPlayerDirectory {
  /// Creates the directory over [_connection].
  const PostgresDuelPlayerDirectory(this._connection);

  final PostgresConnection _connection;

  static const String _searchSql = '''
SELECT u.id::text AS user_id,
       u.display_name AS display_name
FROM identity.users u
WHERE u.status = 'active'
  AND u.display_name IS NOT NULL
  AND u.id <> @excluding::uuid
  AND strpos(lower(u.display_name), lower(@query::text)) > 0
ORDER BY (lower(u.display_name) = lower(@query::text)) DESC,
         strpos(lower(u.display_name), lower(@query::text)) ASC,
         u.display_name ASC
LIMIT @limit::int
''';

  @override
  Future<Result<List<DuelPlayer>>> search({
    required String query,
    required UserId excluding,
    required int limit,
  }) async {
    final result = await _connection.query(
      _searchSql,
      parameters: {
        'query': query,
        'excluding': excluding.value,
        'limit': limit,
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final players = <DuelPlayer>[];
    for (final row in rows) {
      final id = UserId.tryParse(row['user_id']?.toString());
      final name = row['display_name'];
      if (id is Err<UserId> || name is! String) {
        return const Result.err(
          AppError.transient(
            'social.row_corrupt',
            'Stored player row has an invalid id or name',
          ),
        );
      }
      players.add(
        DuelPlayer(userId: (id as Ok<UserId>).value, displayName: name),
      );
    }
    return Result.ok(List<DuelPlayer>.unmodifiable(players));
  }
}
