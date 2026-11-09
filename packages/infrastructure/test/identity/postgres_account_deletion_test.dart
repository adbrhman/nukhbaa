import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/identity/postgres_account_deletion.dart';
import 'package:infrastructure/src/support/supabase_image_store.dart';
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

/// Answers each query with the next scripted result, in order.
final class _Script implements PostgresConnection {
  _Script(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;

  final List<String> sqls = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    return _responses.removeAt(0);
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

final class _Eraser implements SupportImageEraser {
  final List<List<String>> calls = [];

  @override
  Future<Result<void>> erase(List<String> paths) async {
    calls.add(paths);
    return const Result.ok(null);
  }
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

  test('the support pictures are read first and erased after', () async {
    final connection = _Script([
      const Result.ok([
        {'image_path': 'p/u/1.jpg'},
        {'image_path': null},
        {'image_path': 'p/u/2.jpg'},
      ]),
      const Result.ok([
        {'deleted': true},
      ]),
    ]);
    final eraser = _Eraser();

    final result = await PostgresAccountDeletion(
      connection,
      onDeleted: (_) {},
      images: eraser,
    ).anonymise(const UserId(_user));

    expect((result as Ok<bool>).value, isTrue);
    expect(connection.sqls.first, contains('support.messages'));
    expect(connection.sqls.last, contains('identity.delete_account('));
    expect(eraser.calls, [
      ['p/u/1.jpg', 'p/u/2.jpg'],
    ]);
  });

  test('nothing is erased when nothing was deleted or it failed', () async {
    final notDeleted = _Eraser();
    await PostgresAccountDeletion(
      _Script([
        const Result.ok([
          {'image_path': 'p/u/1.jpg'},
        ]),
        const Result.ok([
          {'deleted': false},
        ]),
      ]),
      onDeleted: (_) {},
      images: notDeleted,
    ).anonymise(const UserId(_user));
    expect(notDeleted.calls, isEmpty);

    final failed = _Eraser();
    final result = await PostgresAccountDeletion(
      _Script([
        const Result.ok([
          {'image_path': 'p/u/1.jpg'},
        ]),
        const Result.err(AppError.transient('db.down', 'down')),
      ]),
      onDeleted: (_) {},
      images: failed,
    ).anonymise(const UserId(_user));
    expect(result, isA<Err<bool>>());
    expect(failed.calls, isEmpty);
  });
}
