import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/platform/postgres_error_log_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    params.add(parameters);
    return _response;
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async => action(this);

  @override
  Future<void> close() async {}
}

final _at = DateTime.utc(2026, 10, 3, 12);

ErrorOccurrence _occurrence() => ErrorOccurrence(
  fingerprint: 'c55fabb093f4bb0e',
  problemCode: 'S7L9',
  source: 'server',
  errorType: 'StateError',
  errorCode: 'server.unexpected',
  message: 'Bad state: no element',
  locationFile: 'routes/seasons/index.dart',
  locationLine: 40,
  locationSymbol: 'onRequest',
  severity: ErrorSeverity.high,
  build: 'abc1234',
  occurredAt: _at,
  userId: '11111111-2222-3333-4444-555555555555',
  requestId: '0123456789abcdef0123456789abcdef',
  route: 'GET /seasons',
  browser: 'Dart/3.9 (dart:io)',
  stack: '#0 onRequest (routes/seasons/index.dart:40:3)',
  requestInputJson: '{"method":"GET"}',
);

/// Hermetic tests of the error-log adapter's binding and row mapping. The
/// function itself is tested on Postgres by supabase/tests/0087.
void main() {
  test('record calls ops.record_error with every field bound', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {
          'group_id': 7,
          'occurrences': 3,
          'status': 'new',
          'severity': 'high',
          'users_affected': 2,
          'is_new': false,
          'reopened': true,
        },
      ]),
    );

    final result = await PostgresErrorLogRepository(
      connection,
    ).record(_occurrence());

    expect(connection.sqls.single, contains('ops.record_error('));
    expect(connection.params.single, {
      'fingerprint': 'c55fabb093f4bb0e',
      'problem_code': 'S7L9',
      'source': 'server',
      'error_type': 'StateError',
      'error_code': 'server.unexpected',
      'message': 'Bad state: no element',
      'location_file': 'routes/seasons/index.dart',
      'location_line': 40,
      'location_symbol': 'onRequest',
      'severity': 'high',
      'build': 'abc1234',
      'occurred_at': _at,
      'user_id': '11111111-2222-3333-4444-555555555555',
      'request_id': '0123456789abcdef0123456789abcdef',
      'route': 'GET /seasons',
      'device': null,
      'os': null,
      'browser': 'Dart/3.9 (dart:io)',
      'stack': '#0 onRequest (routes/seasons/index.dart:40:3)',
      'request_input': '{"method":"GET"}',
    });
    final recorded = (result as Ok<RecordedError>).value;
    expect(recorded.groupId, 7);
    expect(recorded.occurrences, 3);
    expect(recorded.usersAffected, 2);
    expect(recorded.isNew, isFalse);
    expect(recorded.reopened, isTrue);
  });

  test('no row back is a transient failure', () async {
    final result = await PostgresErrorLogRepository(
      _FakeConnection(const Result.ok([])),
    ).record(_occurrence());

    expect((result as Err<RecordedError>).error.kind, ErrorKind.transient);
  });

  test('a driver failure passes through', () async {
    const failure = AppError.transient('db.timeout', 'timed out');
    final result = await PostgresErrorLogRepository(
      _FakeConnection(const Result.err(failure)),
    ).record(_occurrence());

    expect((result as Err<RecordedError>).error, failure);
  });
}
