import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/admin/postgres_hidden_account_store.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _a = '11111111-1111-4111-8111-111111111111';

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

/// Script 258: the adapter the composition root wires for the owner's
/// hidden accounts. Its SQL runs against the schema in
/// `supabase/tests/0207_hidden_accounts_test.sql`.
void main() {
  test('maps a hidden account', () async {
    final connection = _Connection([
      Result.ok([
        {
          'id': _a,
          'email': 'r@t.io',
          'role': 'user',
          'status': 'active',
          'display_name': 'مراجع التطبيق',
          'hidden_at': DateTime.utc(2026, 11, 11, 20),
        },
      ]),
    ]);

    final result = await PostgresHiddenAccountStore(connection).list();

    final HiddenAccount line = (result as Ok<List<HiddenAccount>>).value.single;
    expect(line.user.id, const UserId(_a));
    expect(line.user.displayName, 'مراجع التطبيق');
    expect(line.hiddenAt, DateTime.utc(2026, 11, 11, 20));
    expect(connection.parameters.single['limit'], 200);
  });

  test('a row without its time is corrupt', () async {
    final connection = _Connection([
      Result.ok([
        {
          'id': _a,
          'email': 'r@t.io',
          'role': 'user',
          'status': 'active',
          'display_name': 'x',
          'hidden_at': null,
        },
      ]),
    ]);

    final result = await PostgresHiddenAccountStore(connection).list();

    expect(
      (result as Err<List<HiddenAccount>>).error.code,
      'identity.row_corrupt',
    );
  });

  test('hide and show say whether an account was there', () async {
    final connection = _Connection([
      Result.ok([
        {'id': _a},
      ]),
      Result.ok(const []),
    ]);
    final store = PostgresHiddenAccountStore(connection);

    final hidden = await store.hide(const UserId(_a));
    final shown = await store.show(const UserId(_a));

    expect((hidden as Ok<bool>).value, isTrue);
    expect((shown as Ok<bool>).value, isFalse);
    expect(connection.sql.first, contains('coalesce(hidden_at, now())'));
    expect(connection.sql.last, contains('hidden_at = NULL'));
    expect(connection.parameters.first['id'], _a);
  });

  test('a failed write is the error itself', () async {
    final connection = _Connection([
      const Result.err(AppError.transient('db.down', 'down')),
    ]);

    final result = await PostgresHiddenAccountStore(
      connection,
    ).hide(const UserId(_a));

    expect((result as Err<bool>).error.code, 'db.down');
  });
}
