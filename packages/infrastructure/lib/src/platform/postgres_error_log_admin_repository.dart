import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [ErrorLogAdminRepository] over `ops.error_groups`,
/// `ops.error_samples` and `ops.error_group_builds` (migrations 0087,
/// 0088).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter with an explicit cast.
final class PostgresErrorLogAdminRepository implements ErrorLogAdminRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresErrorLogAdminRepository(this._connection);

  final PostgresConnection _connection;

  // "Open" is new or in progress: a fixed, verified or ignored error is
  // nobody's work until it comes back.
  static const String _recurring =
      "g.status IN ('new', 'in_progress') AND "
      '(g.occurrences >= ${ErrorLogAdminRepository.recurringFrom} '
      'OR g.reopened_count > 0)';

  static const String _critical =
      "g.status IN ('new', 'in_progress') AND g.severity = 'critical'";

  static const String _countsSql =
      '''
SELECT
  count(*)::bigint AS all_count,
  count(*) FILTER (WHERE g.status = 'new')::bigint AS fresh_count,
  count(*) FILTER (WHERE $_recurring)::bigint AS recurring_count,
  count(*) FILTER (WHERE $_critical)::bigint AS critical_count
FROM ops.error_groups g
''';

  static const String _columns = '''
  g.id::bigint AS id, g.problem_code, g.source, g.error_type, g.error_code,
  g.message, g.location_file, g.location_line, g.location_symbol,
  g.severity, g.status, g.assignee_id::text AS assignee_id,
  u.display_name AS assignee_name, g.admin_notes, g.first_build,
  g.last_build, g.first_seen_at, g.last_seen_at,
  g.occurrences::bigint AS occurrences,
  g.users_affected::bigint AS users_affected,
  g.reopened_count::bigint AS reopened_count
''';

  static const String _listSql =
      '''
SELECT $_columns
FROM ops.error_groups g
LEFT JOIN identity.users u ON u.id = g.assignee_id
WHERE (
    @code::text IS NOT NULL AND g.problem_code = @code::text
  ) OR (
    @code::text IS NULL
    AND CASE @kind::text
      WHEN 'new' THEN g.status = 'new'
      WHEN 'recurring' THEN $_recurring
      WHEN 'critical' THEN $_critical
      ELSE true
    END
    AND (@source::text IS NULL OR g.source = @source::text)
    AND (
      @build::text IS NULL OR EXISTS (
        SELECT 1 FROM ops.error_group_builds b
        WHERE b.group_id = g.id AND b.build = @build::text
      )
    )
  )
ORDER BY g.last_seen_at DESC, g.id DESC
LIMIT @limit::integer
''';

  static const String _groupSql =
      '''
SELECT $_columns
FROM ops.error_groups g
LEFT JOIN identity.users u ON u.id = g.assignee_id
WHERE g.id = @id::bigint
''';

  static const String _samplesSql = '''
SELECT
  s.occurred_at, s.build, s.message, s.request_id,
  s.user_id::text AS user_id, u.display_name AS user_name, s.route,
  s.device, s.os, s.browser, s.stack,
  s.request_input::text AS request_input
FROM ops.error_samples s
LEFT JOIN identity.users u ON u.id = s.user_id
WHERE s.group_id = @id::bigint
ORDER BY s.occurred_at DESC
''';

  static const String _buildsSql = '''
SELECT b.build, b.occurrences::bigint AS occurrences, b.first_seen_at,
       b.last_seen_at
FROM ops.error_group_builds b
WHERE b.group_id = @id::bigint
ORDER BY b.last_seen_at DESC
LIMIT 20
''';

  static const String _adminsSql = '''
SELECT u.id::text AS id, u.display_name
FROM identity.users u
WHERE u.role = 'admin' AND u.status = 'active'
ORDER BY u.display_name
''';

  // A status that changes stamps status_changed_at; the same status keeps
  // the old stamp.
  static const String _updateSql = '''
UPDATE ops.error_groups g SET
  status = coalesce(@status::text, g.status),
  status_changed_at = CASE
    WHEN @status::text IS NOT NULL AND @status::text <> g.status
      THEN @at::timestamptz
    ELSE g.status_changed_at
  END,
  severity = coalesce(@severity::text, g.severity),
  assignee_id = CASE
    WHEN @clear_assignee::boolean THEN NULL
    WHEN @assignee::uuid IS NOT NULL THEN @assignee::uuid
    ELSE g.assignee_id
  END,
  admin_notes = CASE
    WHEN @set_notes::boolean THEN @notes::text
    ELSE g.admin_notes
  END
WHERE g.id = @id::bigint
RETURNING g.id::bigint AS id
''';

  @override
  Future<Result<ErrorListCounts>> counts() async {
    final result = await _connection.query(_countsSql);
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isEmpty
            ? const ErrorListCounts(all: 0, fresh: 0, recurring: 0, critical: 0)
            : ErrorListCounts(
                all: _int(value.first['all_count']),
                fresh: _int(value.first['fresh_count']),
                recurring: _int(value.first['recurring_count']),
                critical: _int(value.first['critical_count']),
              ),
      ),
    };
  }

  @override
  Future<Result<List<ErrorGroupView>>> list({
    required ErrorListKind kind,
    required int limit,
    String? source,
    String? build,
    String? problemCode,
  }) async {
    final result = await _connection.query(
      _listSql,
      parameters: {
        'kind': kind.wire,
        'limit': limit,
        'source': source,
        'build': build,
        'code': problemCode,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok([
        for (final row in value) _group(row),
      ]),
    };
  }

  @override
  Future<Result<ErrorGroupDetail?>> detail(int id) async {
    final group = await _connection.query(_groupSql, parameters: {'id': id});
    if (group is Err<List<Map<String, dynamic>>>) {
      return Result.err(group.error);
    }
    final rows = (group as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(null);
    }
    final samples = await _connection.query(
      _samplesSql,
      parameters: {'id': id},
    );
    if (samples is Err<List<Map<String, dynamic>>>) {
      return Result.err(samples.error);
    }
    final builds = await _connection.query(_buildsSql, parameters: {'id': id});
    if (builds is Err<List<Map<String, dynamic>>>) {
      return Result.err(builds.error);
    }
    return Result.ok(
      ErrorGroupDetail(
        group: _group(rows.first),
        samples: [
          for (final row in (samples as Ok<List<Map<String, dynamic>>>).value)
            ErrorSampleView(
              occurredAt: (row['occurred_at'] as DateTime).toUtc(),
              build: row['build'] as String,
              message: row['message'] as String,
              requestId: row['request_id'] as String?,
              userId: row['user_id'] as String?,
              userName: row['user_name'] as String?,
              route: row['route'] as String?,
              device: row['device'] as String?,
              os: row['os'] as String?,
              browser: row['browser'] as String?,
              stack: row['stack'] as String?,
              requestInputJson: row['request_input'] as String?,
            ),
        ],
        builds: [
          for (final row in (builds as Ok<List<Map<String, dynamic>>>).value)
            ErrorBuildView(
              build: row['build'] as String,
              occurrences: _int(row['occurrences']),
              firstSeenAt: (row['first_seen_at'] as DateTime).toUtc(),
              lastSeenAt: (row['last_seen_at'] as DateTime).toUtc(),
            ),
        ],
      ),
    );
  }

  @override
  Future<Result<List<AdminRef>>> admins() async {
    final result = await _connection.query(_adminsSql);
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok([
        for (final row in value)
          AdminRef(
            id: row['id'] as String,
            displayName: (row['display_name'] as String?) ?? '',
          ),
      ]),
    };
  }

  @override
  Future<Result<bool>> update(
    int id, {
    required DateTime at,
    String? status,
    String? severity,
    String? assigneeId,
    bool clearAssignee = false,
    bool setNotes = false,
    String? notes,
  }) async {
    final result = await _connection.query(
      _updateSql,
      parameters: {
        'id': id,
        'at': at.toUtc(),
        'status': status,
        'severity': severity,
        'assignee': assigneeId,
        'clear_assignee': clearAssignee,
        'set_notes': setNotes,
        'notes': notes,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  static int _int(Object? value) => (value as num?)?.toInt() ?? 0;

  static ErrorGroupView _group(Map<String, dynamic> row) => ErrorGroupView(
    id: _int(row['id']),
    problemCode: row['problem_code'] as String,
    source: row['source'] as String,
    errorType: row['error_type'] as String,
    errorCode: row['error_code'] as String?,
    message: row['message'] as String,
    locationFile: row['location_file'] as String?,
    locationLine: (row['location_line'] as num?)?.toInt(),
    locationSymbol: row['location_symbol'] as String?,
    severity: row['severity'] as String,
    status: row['status'] as String,
    assigneeId: row['assignee_id'] as String?,
    assigneeName: row['assignee_name'] as String?,
    adminNotes: row['admin_notes'] as String?,
    firstBuild: row['first_build'] as String,
    lastBuild: row['last_build'] as String,
    firstSeenAt: (row['first_seen_at'] as DateTime).toUtc(),
    lastSeenAt: (row['last_seen_at'] as DateTime).toUtc(),
    occurrences: _int(row['occurrences']),
    usersAffected: _int(row['users_affected']),
    reopenedCount: _int(row['reopened_count']),
  );
}
