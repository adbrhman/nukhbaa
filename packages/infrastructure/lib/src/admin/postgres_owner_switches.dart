import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [OwnerSwitches] over `ops.owner_switches` (script 286,
/// migration 0218). Read on every call: nothing is cached, so a switch
/// turned off takes effect on the next run.
///
/// Total: never throws; a malformed row is a transient `ops.row_corrupt`.
final class PostgresOwnerSwitches implements OwnerSwitches {
  /// Creates the switches over an open [PostgresConnection].
  const PostgresOwnerSwitches(this._connection);

  final PostgresConnection _connection;

  // NK286_02
  static const String _sql = '''
SELECT is_on
FROM ops.owner_switches
WHERE switch_key = @key
''';

  @override
  Future<Result<bool>> isOn(OwnerSwitch which) async {
    final result = await _connection.query(
      _sql,
      parameters: {'key': which.key},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(true);
    }
    final Object? value = rows.first['is_on'];
    if (value is! bool) {
      return const Result.err(
        AppError.transient('ops.row_corrupt', 'An owner switch is not a flag'),
      );
    }
    return Result.ok(value);
  }
}
