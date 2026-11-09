import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [AccountAgeReader]: `identity.users.created_at`.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresAccountAgeReader implements AccountAgeReader {
  /// Creates the reader over [_connection].
  const PostgresAccountAgeReader(this._connection);

  final PostgresConnection _connection;

  static const String _sql = '''
SELECT id::text AS user_id, created_at
FROM identity.users
WHERE id = ANY(@ids::uuid[])
''';

  @override
  Future<Result<Map<String, DateTime>>> createdAt(List<UserId> users) async {
    if (users.isEmpty) {
      return const Result.ok(<String, DateTime>{});
    }
    final result = await _connection.query(
      _sql,
      parameters: {
        'ids': [for (final user in users) user.value],
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <String, DateTime>{};
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final Object? id = row['user_id'];
      final Object? at = row['created_at'];
      if (id is String && at is DateTime) {
        out[id] = at.toUtc();
      }
    }
    return Result.ok(Map<String, DateTime>.unmodifiable(out));
  }
}
