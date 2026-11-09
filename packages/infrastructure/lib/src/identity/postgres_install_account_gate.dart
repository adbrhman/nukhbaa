import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [InstallAccountGate] over
/// `identity.install_accounts` (migration 0197): the install id is stored
/// as md5 only, so it is hashed here as `PostgresDeviceSightings` does.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresInstallAccountGate implements InstallAccountGate {
  /// Creates the gate over an open [PostgresConnection].
  const PostgresInstallAccountGate(this._connection);

  final PostgresConnection _connection;

  static const String _sql = '''
SELECT (
  EXISTS (
    SELECT 1
    FROM identity.install_accounts
    WHERE install_key = md5(@install::text)
      AND user_id = @user_id::uuid
  )
  OR (
    SELECT count(DISTINCT user_id)
    FROM identity.install_accounts
    WHERE install_key = md5(@install::text)
  ) < @limit::int
) AS admitted
''';

  @override
  Future<Result<bool>> admits({
    required String installId,
    required UserId userId,
    required int limit,
  }) async {
    final result = await _connection.query(
      _sql,
      parameters: {
        'install': installId,
        'user_id': userId.value,
        'limit': limit,
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final Object? admitted = rows.isEmpty ? null : rows.first['admitted'];
    if (admitted is! bool) {
      return const Result.err(
        AppError.transient(
          'identity.row_corrupt',
          'The phone check returned no answer',
        ),
      );
    }
    return Result.ok(admitted);
  }
}
