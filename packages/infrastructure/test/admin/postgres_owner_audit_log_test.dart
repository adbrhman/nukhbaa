import 'package:domain/domain.dart';
import 'package:infrastructure/src/admin/postgres_owner_audit_log.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _owner = '11111111-1111-4111-8111-111111111111';

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

/// Script 287: the adapter the composition root wires for the owners'
/// audit log. Its statement is checked against the table by
/// `supabase/tests/0219_owner_audit_log_test.sql`.
void main() {
  test('appends one row: who, the method, the path and the answer', () async {
    final connection = _Connection([const Result.ok([])]);

    final result = await PostgresOwnerAuditLog(connection).record(
      actor: const UserId(_owner),
      method: 'POST',
      path: '/owner/hidden-accounts/abc',
      status: 200,
    );

    expect(result, isA<Ok<void>>());
    expect(
      connection.sql.single,
      contains('INSERT INTO admin.owner_audit_log'),
    );
    expect(connection.parameters.single, {
      'actor': _owner,
      'method': 'POST',
      'path': '/owner/hidden-accounts/abc',
      'status': 200,
    });
  });

  test('a path past the bound is cut to it', () async {
    final connection = _Connection([const Result.ok([])]);

    await PostgresOwnerAuditLog(connection).record(
      actor: const UserId(_owner),
      method: 'PUT',
      path: '/owner/${'x' * 400}',
      status: 200,
    );

    expect(
      (connection.parameters.single['path']! as String).length,
      PostgresOwnerAuditLog.maxPath,
    );
  });

  test('a failed write is passed on', () async {
    final connection = _Connection([
      const Result.err(AppError.transient('db.down', 'down')),
    ]);

    final result = await PostgresOwnerAuditLog(connection).record(
      actor: const UserId(_owner),
      method: 'DELETE',
      path: '/owner/person-links/abc',
      status: 200,
    );

    expect((result as Err<void>).error.code, 'db.down');
  });
}
