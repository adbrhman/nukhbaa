import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/leaderboard/postgres_account_age_reader.dart';
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

const _u1 = UserId('00000000-0000-4000-8204-000000000001');
const _u2 = UserId('00000000-0000-4000-8204-000000000002');

/// Hermetic tests of the row mapping; the SQL reads the one column
/// `identity.users.created_at` (migration 0001).
void main() {
  test('the creation dates are read by user id, in UTC', () async {
    final connection = _FakeConnection(
      Result.ok([
        {'user_id': _u1.value, 'created_at': DateTime.utc(2026, 1, 5)},
        {'user_id': _u2.value, 'created_at': null},
        {'user_id': 7, 'created_at': DateTime.utc(2026, 1, 1)},
      ]),
    );

    final result = await PostgresAccountAgeReader(
      connection,
    ).createdAt(const [_u1, _u2]);

    final dates = (result as Ok<Map<String, DateTime>>).value;
    expect(dates, {_u1.value: DateTime.utc(2026, 1, 5)});
    expect(connection.params.single, {
      'ids': [_u1.value, _u2.value],
    });
  });

  test('nobody asked is nothing read', () async {
    final connection = _FakeConnection(const Result.ok([]));

    final result = await PostgresAccountAgeReader(
      connection,
    ).createdAt(const []);

    expect((result as Ok<Map<String, DateTime>>).value, isEmpty);
    expect(connection.params, isEmpty);
  });

  test('a failed read is an error, not an empty answer', () async {
    final connection = _FakeConnection(
      const Result.err(AppError.transient('db.down', 'down')),
    );

    final result = await PostgresAccountAgeReader(
      connection,
    ).createdAt(const [_u1]);

    expect((result as Err<Map<String, DateTime>>).error.code, 'db.down');
  });
}
