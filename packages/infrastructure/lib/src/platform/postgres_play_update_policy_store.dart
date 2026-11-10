import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for the oldest Google Play build the service still
/// supports (migration 0206, script 253): `min_play_build_number` on the one
/// row of `ops.app_update_policy`.
///
/// It answers the [AppUpdatePolicyStore] port, as the APK minimum's
/// [PostgresAppUpdatePolicyStore] does, so the same
/// [CachedAppUpdatePolicyStore] holds it and the use-cases take it as a
/// second policy. Writing it never touches `min_build_number`.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2). Both statements
/// are checked against the real schema by
/// `supabase/tests/0206_play_min_build_test.sql`; keep them identical.
final class PostgresPlayUpdatePolicyStore implements AppUpdatePolicyStore {
  /// Creates the store over [_connection].
  const PostgresPlayUpdatePolicyStore(this._connection);

  final PostgresConnection _connection;

  /// Reads the Play minimum.
  static const String readSql = '''
SELECT min_play_build_number AS min_build_number
FROM ops.app_update_policy
WHERE id
''';

  /// Writes the Play minimum (null clears it), creating the row if 0113's
  /// insert is somehow missing.
  static const String writeSql = '''
INSERT INTO ops.app_update_policy (id, min_play_build_number, updated_by, updated_at)
VALUES (true, @min_build_number::integer, @updated_by::uuid, now())
ON CONFLICT (id) DO UPDATE
SET min_play_build_number = excluded.min_play_build_number,
    updated_by            = excluded.updated_by,
    updated_at            = excluded.updated_at
RETURNING min_play_build_number AS min_build_number
''';

  @override
  Future<Result<int?>> minSupportedBuild() async {
    final result = await _connection.query(readSql);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    return Result.ok(
      rows.isEmpty ? null : _int(rows.first['min_build_number']),
    );
  }

  @override
  Future<Result<int?>> setMinSupportedBuild({
    required int? buildNumber,
    required UserId by,
  }) async {
    final result = await _connection.query(
      writeSql,
      parameters: {'min_build_number': buildNumber, 'updated_by': by.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    return Result.ok(
      rows.isEmpty ? null : _int(rows.first['min_build_number']),
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    _ => null,
  };
}
