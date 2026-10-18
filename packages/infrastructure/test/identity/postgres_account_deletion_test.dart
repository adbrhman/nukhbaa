import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/identity/postgres_account_deletion.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = 'aaaaaaaa-0000-0000-0000-000000000001';

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

/// Hermetic tests for the account-deletion adapter (migration 0178). What
/// the function erases is SQL; here: one statement with the caller's id, the
/// answer read, and the user cache dropped whatever the outcome.
void main() {
  test('one call of identity.delete_account with the id; true read', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'deleted': true},
      ]),
    );
    final List<String> forgotten = [];

    final result = await PostgresAccountDeletion(
      connection,
      onDeleted: (id) => forgotten.add(id.value),
    ).anonymise(const UserId(_user));

    expect((result as Ok<bool>).value, isTrue);
    expect(connection.sqls.single, contains('identity.delete_account('));
    expect(connection.params.single, {'user_id': _user});
    expect(forgotten, [_user]);
  });

  test('nothing to do reads false', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'deleted': false},
      ]),
    );

    final result = await PostgresAccountDeletion(
      connection,
      onDeleted: (_) {},
    ).anonymise(const UserId(_user));

    expect((result as Ok<bool>).value, isFalse);
  });

  test('a failed call is returned and the cache still dropped', () async {
    final connection = _FakeConnection(
      const Result.err(AppError.transient('db.down', 'down')),
    );
    final List<String> forgotten = [];

    final result = await PostgresAccountDeletion(
      connection,
      onDeleted: (id) => forgotten.add(id.value),
    ).anonymise(const UserId(_user));

    expect(result, isA<Err<bool>>());
    expect(forgotten, [_user]);
  });
}
