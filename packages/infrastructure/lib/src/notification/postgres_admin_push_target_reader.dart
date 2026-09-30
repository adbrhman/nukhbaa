import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed administrator push-target reader.
///
/// The recipient guard is in SQL: only active `identity.users` rows whose
/// platform role is `admin` can contribute device tokens.
final class PostgresAdminPushTargetReader implements AdminPushTargetReader {
  const PostgresAdminPushTargetReader(this._connection);

  final PostgresConnection _connection;

  static const String _sql = '''
SELECT dt.token
FROM identity.users u
JOIN notification.device_tokens dt ON dt.user_id = u.id
WHERE u.role = 'admin'
  AND u.status = 'active'
ORDER BY u.id, dt.token
''';

  @override
  Future<Result<List<String>>> tokensForActiveAdmins() async {
    final result = await _connection.query(_sql);
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        List<String>.unmodifiable([
          for (final row in value)
            if (row['token'] is String && (row['token'] as String).isNotEmpty)
              row['token'] as String,
        ]),
      ),
    };
  }
}
