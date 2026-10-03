import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [ErrorReleaseReader] over `ops.error_group_builds` and
/// `ops.error_groups` (migration 0087).
///
/// Total (Application ADR section 2): never throws.
final class PostgresErrorReleaseReader implements ErrorReleaseReader {
  /// Creates the reader over an open [PostgresConnection].
  const PostgresErrorReleaseReader(this._connection);

  final PostgresConnection _connection;

  static const String _releasesSql = '''
SELECT
  b.build,
  count(*)::bigint AS errors,
  count(*) FILTER (WHERE g.severity = 'critical')::bigint AS critical,
  sum(b.occurrences)::bigint AS occurrences,
  min(b.first_seen_at) AS first_seen_at,
  max(b.last_seen_at) AS last_seen_at
FROM ops.error_group_builds b
JOIN ops.error_groups g ON g.id = b.group_id
GROUP BY b.build
ORDER BY max(b.last_seen_at) DESC
LIMIT @limit::integer
''';

  static const String _filesSql = '''
SELECT
  g.location_file AS file,
  count(*)::bigint AS errors,
  sum(g.occurrences)::bigint AS occurrences
FROM ops.error_groups g
WHERE g.location_file IS NOT NULL
GROUP BY g.location_file
ORDER BY sum(g.occurrences) DESC, g.location_file
LIMIT @limit::integer
''';

  @override
  Future<Result<List<ErrorReleaseSummary>>> releases({
    required int limit,
  }) async {
    final result = await _connection.query(
      _releasesSql,
      parameters: {'limit': limit},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok([
        for (final row in value)
          ErrorReleaseSummary(
            build: row['build'] as String,
            errors: (row['errors'] as num).toInt(),
            critical: (row['critical'] as num).toInt(),
            occurrences: (row['occurrences'] as num).toInt(),
            firstSeenAt: (row['first_seen_at'] as DateTime).toUtc(),
            lastSeenAt: (row['last_seen_at'] as DateTime).toUtc(),
          ),
      ]),
    };
  }

  @override
  Future<Result<List<ErrorFileSummary>>> files({required int limit}) async {
    final result = await _connection.query(
      _filesSql,
      parameters: {'limit': limit},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok([
        for (final row in value)
          ErrorFileSummary(
            file: row['file'] as String,
            errors: (row['errors'] as num).toInt(),
            occurrences: (row['occurrences'] as num).toInt(),
          ),
      ]),
    };
  }
}
