import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_device_token_repository.dart';
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

/// Hermetic tests for the device-token adapter. Which rows the statement
/// keeps (web tokens retired by a native registration, a web registration
/// not kept beside a native token, web-only players unaffected) is SQL,
/// checked against a seeded Postgres 16 before batch 118.
void main() {
  group('PostgresDeviceTokenRepository.upsert', () {
    test('sends one statement with the token, user and platform', () async {
      final connection = _FakeConnection(const Result.ok([]));

      final result = await PostgresDeviceTokenRepository(connection).upsert(
        userId: (UserId.tryParse(_user) as Ok<UserId>).value,
        token: 'tok-1',
        platform: 'android',
      );

      expect(result, isA<Ok<void>>());
      expect(connection.sqls, hasLength(1));
      expect(connection.params.single, {
        'token': 'tok-1',
        'user_id': _user,
        'platform': 'android',
      });
    });

    test('one push per phone: web tokens give way to the app', () async {
      final connection = _FakeConnection(const Result.ok([]));

      await PostgresDeviceTokenRepository(connection).upsert(
        userId: (UserId.tryParse(_user) as Ok<UserId>).value,
        token: 'tok-2',
        platform: 'web',
      );

      final sql = connection.sqls.single;
      expect(sql, contains('retired_web AS'));
      expect(sql, contains('skipped_web AS'));
      expect(sql, contains("platform <> 'web'"));
      expect(sql, contains('ON CONFLICT (token) DO UPDATE'));
    });

    test('a driver failure comes back as the same error', () async {
      const failure = AppError.transient('db.down', 'down');
      final connection = _FakeConnection(const Result.err(failure));

      final result = await PostgresDeviceTokenRepository(connection).upsert(
        userId: (UserId.tryParse(_user) as Ok<UserId>).value,
        token: 'tok-3',
        platform: 'android',
      );

      expect(result, isA<Err<void>>());
      expect((result as Err<void>).error.code, 'db.down');
    });
  });
}
