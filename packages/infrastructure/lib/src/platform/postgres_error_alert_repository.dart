import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [ErrorAlertRepository] over `ops.claim_error_alert()`
/// (migration 0089).
///
/// Total (Application ADR section 2): never throws.
final class PostgresErrorAlertRepository implements ErrorAlertRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresErrorAlertRepository(this._connection);

  final PostgresConnection _connection;

  static const String _claimSql = '''
SELECT ops.claim_error_alert(
  @group_id::bigint, @is_new::boolean, @reopened::boolean, @at::timestamptz
) AS reason
''';

  @override
  Future<Result<String?>> claim({
    required int groupId,
    required bool isNew,
    required bool reopened,
    required DateTime at,
  }) async {
    final result = await _connection.query(
      _claimSql,
      parameters: {
        'group_id': groupId,
        'is_new': isNew,
        'reopened': reopened,
        'at': at.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isEmpty ? null : value.first['reason'] as String?,
      ),
    };
  }
}
