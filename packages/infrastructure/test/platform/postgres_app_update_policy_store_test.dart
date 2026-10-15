import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/platform/postgres_app_update_policy_store.dart';
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

/// The row mapping of the update-policy adapter (batch 147). The SQL is
/// checked against the schema by `0113_app_update_policy_test.sql`.
void main() {
  test('reads the minimum, and none as null', () async {
    final AppUpdatePolicyStore withMinimum = PostgresAppUpdatePolicyStore(
      _FakeConnection(
        const Result.ok([
          {'min_build_number': 212},
        ]),
      ),
    );
    final AppUpdatePolicyStore unset = PostgresAppUpdatePolicyStore(
      _FakeConnection(
        const Result.ok([
          {'min_build_number': null},
        ]),
      ),
    );

    expect((await withMinimum.minSupportedBuild() as Ok<int?>).value, 212);
    expect((await unset.minSupportedBuild() as Ok<int?>).value, isNull);
  });

  test('writes the number and who set it, and answers it', () async {
    final _FakeConnection connection = _FakeConnection(
      const Result.ok([
        {'min_build_number': 212},
      ]),
    );

    final Result<int?> stored = await PostgresAppUpdatePolicyStore(
      connection,
    ).setMinSupportedBuild(buildNumber: 212, by: const UserId('u-1'));

    expect((stored as Ok<int?>).value, 212);
    expect(connection.sqls.single, PostgresAppUpdatePolicyStore.writeSql);
    expect(connection.params.single, {
      'min_build_number': 212,
      'updated_by': 'u-1',
    });
  });

  test('a database failure is an error, not a minimum', () async {
    final AppUpdatePolicyStore store = PostgresAppUpdatePolicyStore(
      _FakeConnection(const Result.err(AppError.transient('db.down', 'down'))),
    );

    expect(await store.minSupportedBuild(), isA<Err<int?>>());
  });
}
