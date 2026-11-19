import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [OwnerRegistry] over `admin.active_owners` (script 285,
/// migration 0217): the owner seats whose account is an active admin that
/// was not erased, the primary first.
///
/// Total: never throws; a malformed row is a transient
/// `identity.row_corrupt`.
final class PostgresOwnerRegistry implements OwnerRegistry {
  /// Creates the registry over an open [PostgresConnection].
  const PostgresOwnerRegistry(this._connection);

  final PostgresConnection _connection;

  // NK285_02
  static const String _sql = '''
SELECT user_id::text AS id
FROM admin.active_owners
ORDER BY (seat = 'primary') DESC, added_at, user_id
''';

  @override
  Future<Result<List<UserId>>> activeOwners() async {
    final result = await _connection.query(_sql);
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _map(value),
    };
  }

  static Result<List<UserId>> _map(List<Map<String, dynamic>> rows) {
    final List<UserId> out = <UserId>[];
    for (final Map<String, dynamic> row in rows) {
      final Result<UserId> id = UserId.tryParse(row['id']?.toString());
      if (id is Err<UserId>) {
        return const Result.err(
          AppError.transient(
            'identity.row_corrupt',
            'An owner seat has an invalid id',
          ),
        );
      }
      out.add((id as Ok<UserId>).value);
    }
    return Result.ok(out);
  }
}
