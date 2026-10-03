import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [ErrorLogRepository] over `ops.record_error()`
/// (migration 0087).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter with an explicit cast, so the function's
/// one signature resolves whatever the driver infers.
final class PostgresErrorLogRepository implements ErrorLogRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresErrorLogRepository(this._connection);

  final PostgresConnection _connection;

  static const String _recordSql = '''
SELECT
  group_id::bigint AS group_id,
  occurrences::bigint AS occurrences,
  status,
  severity,
  users_affected::bigint AS users_affected,
  is_new,
  reopened
FROM ops.record_error(
  @fingerprint::text, @problem_code::text, @source::text,
  @error_type::text, @error_code::text, @message::text,
  @location_file::text, @location_line::integer, @location_symbol::text,
  @severity::text, @build::text, @occurred_at::timestamptz,
  @user_id::uuid, @request_id::text, @route::text, @device::text,
  @os::text, @browser::text, @stack::text, @request_input::jsonb
)
''';

  @override
  Future<Result<RecordedError>> record(ErrorOccurrence occurrence) async {
    final result = await _connection.query(
      _recordSql,
      parameters: {
        'fingerprint': occurrence.fingerprint,
        'problem_code': occurrence.problemCode,
        'source': occurrence.source,
        'error_type': occurrence.errorType,
        'error_code': occurrence.errorCode,
        'message': occurrence.message,
        'location_file': occurrence.locationFile,
        'location_line': occurrence.locationLine,
        'location_symbol': occurrence.locationSymbol,
        'severity': occurrence.severity.name,
        'build': occurrence.build,
        'occurred_at': occurrence.occurredAt.toUtc(),
        'user_id': occurrence.userId,
        'request_id': occurrence.requestId,
        'route': occurrence.route,
        'device': occurrence.device,
        'os': occurrence.os,
        'browser': occurrence.browser,
        'stack': occurrence.stack,
        'request_input': occurrence.requestInputJson,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) when value.isEmpty =>
        const Result.err(
          AppError.transient(
            'errors.not_recorded',
            'The error log returned no row',
          ),
        ),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        RecordedError(
          groupId: (value.first['group_id'] as num).toInt(),
          occurrences: (value.first['occurrences'] as num).toInt(),
          status: value.first['status'] as String,
          severity: value.first['severity'] as String,
          usersAffected: (value.first['users_affected'] as num).toInt(),
          isNew: value.first['is_new'] as bool,
          reopened: value.first['reopened'] as bool,
        ),
      ),
    };
  }
}
