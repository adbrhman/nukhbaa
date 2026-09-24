import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [FrameReportRepository] (migration 0070).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter.
final class PostgresFrameReportRepository implements FrameReportRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresFrameReportRepository(this._connection);

  final PostgresConnection _connection;

  static const String _insertSql = '''
INSERT INTO ops.frame_reports (
  user_id, reported_at, build, platform, refresh_rate_hz,
  frames, slow_frames, frozen_frames, worst_frame_ms
)
VALUES (
  @user_id, @reported_at, @build, @platform, @refresh_rate_hz,
  @frames, @slow_frames, @frozen_frames, @worst_frame_ms
)
''';

  // The first row is every build together (build is null, ord 0); then
  // one row per build, newest report first. Counts are cast to bigint so
  // the driver hands back plain ints.
  static const String _totalsSql = '''
SELECT * FROM (
  SELECT
    NULL::text AS build,
    count(*)::bigint AS reports,
    count(DISTINCT user_id)::bigint AS users,
    coalesce(sum(frames), 0)::bigint AS frames,
    coalesce(sum(slow_frames), 0)::bigint AS slow_frames,
    coalesce(sum(frozen_frames), 0)::bigint AS frozen_frames,
    coalesce(max(worst_frame_ms), 0)::bigint AS worst_frame_ms,
    max(reported_at) AS last_reported_at,
    0 AS ord
  FROM ops.frame_reports
  WHERE reported_at >= @since
  UNION ALL
  (
    SELECT
      build,
      count(*)::bigint,
      count(DISTINCT user_id)::bigint,
      coalesce(sum(frames), 0)::bigint,
      coalesce(sum(slow_frames), 0)::bigint,
      coalesce(sum(frozen_frames), 0)::bigint,
      coalesce(max(worst_frame_ms), 0)::bigint,
      max(reported_at),
      1
    FROM ops.frame_reports
    WHERE reported_at >= @since
    GROUP BY build
    ORDER BY max(reported_at) DESC
    LIMIT @max_builds
  )
) totals
ORDER BY ord, last_reported_at DESC NULLS LAST
''';

  @override
  Future<Result<void>> record({
    required UserId userId,
    required FrameReport report,
    required DateTime reportedAt,
  }) async {
    final result = await _connection.query(
      _insertSql,
      parameters: {
        'user_id': userId.value,
        'reported_at': reportedAt.toUtc(),
        'build': report.build,
        'platform': report.platform,
        'refresh_rate_hz': report.refreshRateHz,
        'frames': report.frames,
        'slow_frames': report.slowFrames,
        'frozen_frames': report.frozenFrames,
        'worst_frame_ms': report.worstFrameMs,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<List<FrameTotals>>> totals({
    required DateTime since,
    required int maxBuilds,
  }) async {
    final result = await _connection.query(
      _totalsSql,
      parameters: {'since': since.toUtc(), 'max_builds': maxBuilds},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok([
        for (final row in value)
          FrameTotals(
            build: row['build'] as String?,
            reports: (row['reports'] as num).toInt(),
            users: (row['users'] as num).toInt(),
            frames: (row['frames'] as num).toInt(),
            slowFrames: (row['slow_frames'] as num).toInt(),
            frozenFrames: (row['frozen_frames'] as num).toInt(),
            worstFrameMs: (row['worst_frame_ms'] as num).toInt(),
            lastReportedAt: (row['last_reported_at'] as DateTime?)?.toUtc(),
          ),
      ]),
    };
  }
}
