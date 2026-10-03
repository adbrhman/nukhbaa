import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/platform/postgres_error_log_admin_repository.dart';
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

final _seen = DateTime.utc(2026, 10, 3, 9);

Map<String, dynamic> _row() => {
  'id': 7,
  'problem_code': 'K7Q2',
  'source': 'android',
  'error_type': 'StateError',
  'error_code': null,
  'message': 'Bad state',
  'location_file': 'package:mobile/x.dart',
  'location_line': 12,
  'location_symbol': 'build',
  'severity': 'high',
  'status': 'new',
  'assignee_id': null,
  'assignee_name': null,
  'admin_notes': null,
  'first_build': 'abc1234',
  'last_build': 'abc1235',
  'first_seen_at': _seen,
  'last_seen_at': _seen,
  'occurrences': 12,
  'users_affected': 3,
  'reopened_count': 1,
};

/// Hermetic tests of the admin error-log adapter's binding and mapping. Its
/// SQL was run against Postgres with migrations 0087 and 0088 applied.
void main() {
  test('list binds the filters and maps each row', () async {
    final connection = _FakeConnection(Result.ok([_row()]));

    final result = await PostgresErrorLogAdminRepository(connection).list(
      kind: ErrorListKind.recurring,
      limit: 200,
      source: 'android',
      problemCode: 'K7Q2',
    );

    final view = (result as Ok<List<ErrorGroupView>>).value.single;
    expect(view.problemCode, 'K7Q2');
    expect(view.lastBuild, 'abc1235');
    expect(view.occurrences, 12);
    expect(view.reopenedCount, 1);
    expect(view.locationLine, 12);
    expect(connection.params.single, {
      'kind': 'recurring',
      'limit': 200,
      'source': 'android',
      'build': null,
      'code': 'K7Q2',
    });
  });

  test(
    'update binds every change and reports whether the error exists',
    () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'id': 7},
        ]),
      );
      final at = DateTime.utc(2026, 10, 3, 12);

      final result = await PostgresErrorLogAdminRepository(
        connection,
      ).update(7, at: at, status: 'fixed', setNotes: true, notes: 'done');

      expect((result as Ok<bool>).value, isTrue);
      expect(connection.sqls.single, contains('UPDATE ops.error_groups'));
      expect(connection.params.single, {
        'id': 7,
        'at': at,
        'status': 'fixed',
        'severity': null,
        'assignee': null,
        'clear_assignee': false,
        'set_notes': true,
        'notes': 'done',
      });
    },
  );

  test('a missing error has no detail', () async {
    final result = await PostgresErrorLogAdminRepository(
      _FakeConnection(const Result.ok([])),
    ).detail(99);

    expect((result as Ok<ErrorGroupDetail?>).value, isNull);
  });
}
