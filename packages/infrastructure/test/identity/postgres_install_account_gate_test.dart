import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/identity/postgres_install_account_gate.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Answers every statement with [answer], and keeps what it was asked.
final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this.answer);

  final Result<List<Map<String, dynamic>>> answer;
  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    params.add(parameters);
    return answer;
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

const _user = UserId('00000000-0000-4000-8245-000000000001');
const _phone = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

/// Hermetic tests of the answer mapping; the SQL reads
/// `identity.install_accounts` (migration 0197).
void main() {
  test('the answer is read, and the phone, the account and the limit are '
      'bound', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'admitted': false},
      ]),
    );

    final result = await PostgresInstallAccountGate(
      connection,
    ).admits(installId: _phone, userId: _user, limit: 2);

    expect((result as Ok<bool>).value, isFalse);
    expect(connection.params.single, {
      'install': _phone,
      'user_id': _user.value,
      'limit': 2,
    });
  });

  test('a row without a clear answer is an error, not a yes', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'admitted': null},
      ]),
    );

    final result = await PostgresInstallAccountGate(
      connection,
    ).admits(installId: _phone, userId: _user, limit: 2);

    expect((result as Err<bool>).error.code, 'identity.row_corrupt');
  });

  test('a failed read is an error', () async {
    final connection = _FakeConnection(
      const Result.err(AppError.transient('db.down', 'down')),
    );

    final result = await PostgresInstallAccountGate(
      connection,
    ).admits(installId: _phone, userId: _user, limit: 2);

    expect((result as Err<bool>).error.code, 'db.down');
  });
}
