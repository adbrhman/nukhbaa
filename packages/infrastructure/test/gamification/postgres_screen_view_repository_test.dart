import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_screen_view_repository.dart';
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

/// Hermetic tests of the binding. The statement itself runs against
/// migration 0093 in supabase/tests/0093_screen_views_test.sql.
void main() {
  const user = UserId('11111111-2222-3333-4444-555555555555');
  final reportedAt = DateTime.utc(2026, 10, 6, 21, 15);

  test('one statement binds the day, the caller and parallel arrays', () async {
    final connection = _FakeConnection(const Result.ok([]));

    final result = await PostgresScreenViewRepository(connection).add(
      userId: user,
      day: DateTime.utc(2026, 10, 7),
      opens: {'home': 4, 'duels': 1},
      reportedAt: reportedAt,
    );

    expect(result.isOk, isTrue);
    expect(connection.sqls.single, PostgresScreenViewRepository.upsertSql);
    expect(connection.sqls.single, contains('gamification.screen_views'));
    expect(connection.sqls.single, contains('@screens::text[]'));
    expect(connection.sqls.single, contains('@opens::int[]'));
    expect(connection.params.single, {
      'view_date': '2026-10-07',
      'user_id': user.value,
      'reported_at': reportedAt,
      'screens': ['home', 'duels'],
      'opens': [4, 1],
    });
  });

  test('an empty report touches nothing', () async {
    final connection = _FakeConnection(const Result.ok([]));

    final result = await PostgresScreenViewRepository(connection).add(
      userId: user,
      day: DateTime.utc(2026, 10, 7),
      opens: const {},
      reportedAt: reportedAt,
    );

    expect(result.isOk, isTrue);
    expect(connection.sqls, isEmpty);
  });

  test('a driver failure is returned, not thrown', () async {
    final connection = _FakeConnection(
      const Result.err(AppError.transient('db.unavailable', 'down')),
    );

    final result = await PostgresScreenViewRepository(connection).add(
      userId: user,
      day: DateTime.utc(2026, 10, 7),
      opens: {'home': 1},
      reportedAt: reportedAt,
    );

    expect((result as Err<void>).error.code, 'db.unavailable');
  });
}
