import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/admin/postgres_admin_activity_log.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _admin = '11111111-1111-4111-8111-111111111111';

/// Answers each query in turn from [_answers].
final class _Connection implements PostgresConnection {
  _Connection(this._answers);

  final List<Result<List<Map<String, dynamic>>>> _answers;
  final List<String> sql = <String>[];
  final List<Map<String, Object?>> parameters = <Map<String, Object?>>[];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    this.sql.add(sql);
    this.parameters.add(parameters);
    return _answers.removeAt(0);
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) => action(this);

  @override
  Future<void> close() async {}
}

// NK300_11
/// Script 300: the adapter the composition root wires for the admins'
/// activity log. Its statements are checked against the table by
/// `supabase/tests/0224_admin_activity_log_test.sql`.
void main() {
  test('appends one row: who, the method, the path and the answer', () async {
    final connection = _Connection([const Result.ok([])]);

    final result = await PostgresAdminActivityLog(connection).record(
      actor: const UserId(_admin),
      method: 'PUT',
      path: '/fixtures/abc/result',
      status: 200,
    );

    expect(result, isA<Ok<void>>());
    expect(
      connection.sql.single,
      contains('INSERT INTO admin.admin_activity_log'),
    );
    expect(connection.parameters.single, {
      'actor': _admin,
      'method': 'PUT',
      'path': '/fixtures/abc/result',
      'status': 200,
    });
  });

  test('reads the latest with the admin and the target', () async {
    final connection = _Connection([
      Result.ok([
        {
          'id': 7,
          'actor_name': 'Khalid',
          'method': 'PUT',
          'path': '/fixtures/abc/result',
          'occurred_at': DateTime.utc(2026, 11, 21, 18),
          'target': 'A \u00d7 B',
          'result': '2-1',
        },
      ]),
    ]);

    final result = await PostgresAdminActivityLog(connection).latest(limit: 5);

    final List<AdminActivity> lines = (result as Ok<List<AdminActivity>>).value;
    expect(lines.single.actorName, 'Khalid');
    expect(lines.single.target, 'A \u00d7 B');
    expect(lines.single.result, '2-1');
    expect(lines.single.at, DateTime.utc(2026, 11, 21, 18));
    expect(connection.parameters.single, {'limit': 5});
  });

  test('a malformed row is a transient error', () async {
    final connection = _Connection([
      const Result.ok([
        {'id': 'x'},
      ]),
    ]);

    final result = await PostgresAdminActivityLog(connection).latest();

    expect(result, isA<Err<List<AdminActivity>>>());
  });
}
