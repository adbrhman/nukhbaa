import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [FrameReportRepository] (migrations 0070, 0071).
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
  frames, slow_frames, frozen_frames, worst_frame_ms, device_model
)
VALUES (
  @user_id, @reported_at, @build, @platform, @refresh_rate_hz,
  @frames, @slow_frames, @frozen_frames, @worst_frame_ms, @device_model
)
''';

  // The first row is every build together (build and platform are null,
  // ord 0); then one row per build and platform, newest report first, for
  // the @max_builds newest builds. The same build on the web and on a
  // phone reads as two rows: the two do not draw alike, and mixed they
  // hide which one is slow. Counts are cast to bigint so the driver
  // hands back plain ints.
  static const String _totalsSql = '''
SELECT * FROM (
  SELECT
    NULL::text AS build,
    NULL::text AS platform,
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
      platform,
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
      AND build IN (
        SELECT build
        FROM ops.frame_reports
        WHERE reported_at >= @since
        GROUP BY build
        ORDER BY max(reported_at) DESC
        LIMIT @max_builds
      )
    GROUP BY build, platform
    ORDER BY max(reported_at) DESC
  )
) totals
ORDER BY ord, last_reported_at DESC NULLS LAST
''';

  // Least smooth first: the share of slow frames, then the most sessions.
  // A model only with enough distinct users that no row is one person.
  static const String _devicesSql = '''
SELECT
  device_model,
  count(*)::bigint AS reports,
  count(DISTINCT user_id)::bigint AS users,
  sum(frames)::bigint AS frames,
  sum(slow_frames)::bigint AS slow_frames,
  sum(frozen_frames)::bigint AS frozen_frames
FROM ops.frame_reports
WHERE reported_at >= @since
  AND device_model IS NOT NULL
GROUP BY device_model
HAVING count(DISTINCT user_id) >= @min_users
ORDER BY
  sum(slow_frames)::float8 / nullif(sum(frames), 0) DESC NULLS LAST,
  count(*) DESC
LIMIT @limit
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
        'device_model': report.deviceModel,
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
            platform: row['platform'] as String?,
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

  @override
  Future<Result<List<DeviceTotals>>> devices({
    required DateTime since,
    required int minUsers,
    required int limit,
  }) async {
    final result = await _connection.query(
      _devicesSql,
      parameters: {
        'since': since.toUtc(),
        'min_users': minUsers,
        'limit': limit,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok([
        for (final row in value)
          DeviceTotals(
            deviceModel: row['device_model'] as String,
            reports: (row['reports'] as num).toInt(),
            users: (row['users'] as num).toInt(),
            frames: (row['frames'] as num).toInt(),
            slowFrames: (row['slow_frames'] as num).toInt(),
            frozenFrames: (row['frozen_frames'] as num).toInt(),
          ),
      ]),
    };
  }
}
