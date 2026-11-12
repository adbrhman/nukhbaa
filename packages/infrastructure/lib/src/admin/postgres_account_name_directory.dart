import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [AccountNameDirectory] (script 263): every account's id,
/// e-mail and display name, oldest first, for the close-name check. A few
/// hundred short lines, read when an account registers and when an admin
/// opens the new players.
///
/// Total: never throws; a malformed row is skipped.
final class PostgresAccountNameDirectory implements AccountNameDirectory {
  /// Creates the directory over an open [PostgresConnection].
  const PostgresAccountNameDirectory(this._connection);

  final PostgresConnection _connection;

  /// The most accounts one read returns.
  static const int maxAccounts = 20000;

  static const String _sql = '''
SELECT u.id::text AS id, u.email, u.display_name
FROM identity.users u
WHERE u.display_name IS NOT NULL
  AND btrim(u.display_name) <> ''
ORDER BY u.created_at, u.id
LIMIT @limit
''';

  @override
  Future<Result<List<AccountName>>> all() async {
    final result = await _connection.query(
      _sql,
      parameters: {'limit': maxAccounts},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    return Result.ok(<AccountName>[
      for (final Map<String, dynamic> row
          in (result as Ok<List<Map<String, dynamic>>>).value)
        if (UserId.tryParse(row['id']?.toString()) case Ok<UserId>(
          :final value,
        ))
          if (row['display_name'] case final String name)
            AccountName(
              id: value,
              displayName: name,
              email: row['email'] as String?,
            ),
    ]);
  }
}
