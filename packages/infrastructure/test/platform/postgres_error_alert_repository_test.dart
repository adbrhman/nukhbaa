import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/platform/postgres_error_alert_repository.dart';
import 'package:infrastructure/src/platform/postgres_error_release_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;
  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
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

/// Hermetic tests of the alert and release adapters; their SQL runs against
/// Postgres in supabase/tests/0089.
void main() {
  test('claim binds the occurrence and reads the reason', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'reason': 'new_critical'},
      ]),
    );
    final at = DateTime.utc(2026, 10, 3, 12);

    final result = await PostgresErrorAlertRepository(
      connection,
    ).claim(groupId: 7, isNew: true, reopened: false, at: at);

    expect((result as Ok<String?>).value, 'new_critical');
    expect(connection.params.single, {
      'group_id': 7,
      'is_new': true,
      'reopened': false,
      'at': at,
    });
  });

  test('no reason is null', () async {
    final result = await PostgresErrorAlertRepository(
      _FakeConnection(
        const Result.ok([
          {'reason': null},
        ]),
      ),
    ).claim(groupId: 7, isNew: false, reopened: false, at: DateTime.utc(2026));

    expect((result as Ok<String?>).value, isNull);
  });

  test('files map each row', () async {
    final result = await PostgresErrorReleaseReader(
      _FakeConnection(
        const Result.ok([
          {'file': 'routes/x.dart', 'errors': 2, 'occurrences': 9},
        ]),
      ),
    ).files(limit: 10);

    final rows = (result as Ok<List<ErrorFileSummary>>).value;
    expect(rows.single.file, 'routes/x.dart');
    expect(rows.single.occurrences, 9);
  });
}
