import 'package:domain/domain.dart';
import 'package:infrastructure/src/admin/postgres_owner_registry.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _primary = '11111111-1111-4111-8111-111111111111';
const _backup = '22222222-2222-4222-8222-222222222222';

/// Answers each query in turn from [_answers].
final class _Connection implements PostgresConnection {
  _Connection(this._answers);

  final List<Result<List<Map<String, dynamic>>>> _answers;
  final List<String> sql = <String>[];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    this.sql.add(sql);
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

/// Script 285: the adapter the composition root wires for the owner seats.
/// Its SQL runs against the schema in
/// `supabase/tests/0217_platform_owners_test.sql`.
void main() {
  test('reads the seats in the order the view gives, primary first', () async {
    final connection = _Connection([
      const Result.ok([
        {'id': _primary},
        {'id': _backup},
      ]),
    ]);

    final result = await PostgresOwnerRegistry(connection).activeOwners();

    expect((result as Ok<List<UserId>>).value, const <UserId>[
      UserId(_primary),
      UserId(_backup),
    ]);
    expect(connection.sql.single, contains('admin.active_owners'));
    expect(connection.sql.single, contains("(seat = 'primary') DESC"));
  });

  test('no seat that can act is an empty list', () async {
    final connection = _Connection([const Result.ok([])]);

    final result = await PostgresOwnerRegistry(connection).activeOwners();

    expect((result as Ok<List<UserId>>).value, isEmpty);
  });

  test('a malformed id is corrupt, not a seat', () async {
    final connection = _Connection([
      const Result.ok([
        {'id': 'not-a-uuid'},
      ]),
    ]);

    final result = await PostgresOwnerRegistry(connection).activeOwners();

    expect((result as Err<List<UserId>>).error.code, 'identity.row_corrupt');
  });

  test('a failed read is passed on', () async {
    final connection = _Connection([
      const Result.err(AppError.transient('db.down', 'down')),
    ]);

    final result = await PostgresOwnerRegistry(connection).activeOwners();

    expect((result as Err<List<UserId>>).error.code, 'db.down');
  });
}
