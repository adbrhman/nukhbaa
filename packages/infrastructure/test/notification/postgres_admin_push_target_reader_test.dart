import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_admin_push_target_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;
  final List<String> sqls = <String>[];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
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

void main() {
  group('PostgresAdminPushTargetReader', () {
    test(
      'returns only the selected token column from the guarded query',
      () async {
        final connection = _FakeConnection(
          const Result.ok([
            {'token': 'admin-a'},
            {'token': 'admin-b'},
            {'token': null},
            {'token': ''},
          ]),
        );

        final result = await PostgresAdminPushTargetReader(
          connection,
        ).tokensForActiveAdmins();

        expect(result, isA<Ok<List<String>>>());
        expect((result as Ok<List<String>>).value, ['admin-a', 'admin-b']);
        final sql = connection.sqls.single;
        expect(sql, contains("u.role = 'admin'"));
        expect(sql, contains("u.status = 'active'"));
        expect(sql, contains('dt.user_id = u.id'));
      },
    );

    test('propagates a database failure', () async {
      const failure = AppError.transient('db.query_failed', 'boom');
      final connection = _FakeConnection(const Result.err(failure));

      final result = await PostgresAdminPushTargetReader(
        connection,
      ).tokensForActiveAdmins();

      expect(result, isA<Err<List<String>>>());
      expect((result as Err<List<String>>).error.code, failure.code);
    });
  });
}
