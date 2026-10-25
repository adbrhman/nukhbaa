import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [RetiredBuildReader] over `ops.frame_reports`
/// (migration 0070, script 149): a build is dated by its first Android
/// session, and a player uses the build of their newest one.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2). The statement is
/// checked against the real schema by
/// `supabase/tests/retired_build_players_query_test.sql`; keep them
/// identical.
final class PostgresRetiredBuildReader implements RetiredBuildReader {
  /// Creates the reader over [_connection].
  const PostgresRetiredBuildReader(this._connection);

  final PostgresConnection _connection;

  /// The players whose newest Android session ran a build first seen before
  /// `@before`.
  static const String playersSql = '''
WITH first_seen AS (
  SELECT build, min(reported_at) AS first_seen
  FROM ops.frame_reports
  WHERE platform = 'android'
  GROUP BY build
),
latest AS (
  SELECT DISTINCT ON (user_id) user_id, build
  FROM ops.frame_reports
  WHERE platform = 'android'
  ORDER BY user_id, reported_at DESC
)
SELECT l.user_id::text AS user_id
FROM latest l
JOIN first_seen f ON f.build = l.build
WHERE f.first_seen < @before::timestamptz
''';

  @override
  Future<Result<Set<UserId>>> playersOnBuildsBefore(DateTime before) async {
    final result = await _connection.query(
      playersSql,
      parameters: {'before': before.toUtc().toIso8601String()},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final players = <UserId>{};
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final parsed = UserId.tryParse(row['user_id']?.toString());
      if (parsed is Err<UserId>) {
        return const Result.err(
          AppError.transient(
            'platform.frame_report_corrupt',
            'A stored session report names no user',
          ),
        );
      }
      players.add((parsed as Ok<UserId>).value);
    }
    return Result.ok(Set<UserId>.unmodifiable(players));
  }
}
