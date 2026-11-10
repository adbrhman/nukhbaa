import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/platform/postgres_play_update_policy_store.dart';
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

/// The row mapping of the Play update-policy adapter (script 253). The SQL
/// is checked against the schema by `0206_play_min_build_test.sql`.
void main() {
  test('reads the Play column only, and none as null', () async {
    final _FakeConnection connection = _FakeConnection(
      const Result.ok([
        {'min_build_number': 845},
      ]),
    );
    final AppUpdatePolicyStore unset = PostgresPlayUpdatePolicyStore(
      _FakeConnection(
        const Result.ok([
          {'min_build_number': null},
        ]),
      ),
    );

    expect(
      (await PostgresPlayUpdatePolicyStore(connection).minSupportedBuild()
              as Ok<int?>)
          .value,
      845,
    );
    expect(connection.sqls.single, PostgresPlayUpdatePolicyStore.readSql);
    expect(connection.sqls.single, contains('min_play_build_number'));
    expect((await unset.minSupportedBuild() as Ok<int?>).value, isNull);
  });

  test('writes the Play number and who set it, never the APK one', () async {
    final _FakeConnection connection = _FakeConnection(
      const Result.ok([
        {'min_build_number': 845},
      ]),
    );

    final Result<int?> stored = await PostgresPlayUpdatePolicyStore(
      connection,
    ).setMinSupportedBuild(buildNumber: 845, by: const UserId('u-1'));

    expect((stored as Ok<int?>).value, 845);
    expect(connection.sqls.single, PostgresPlayUpdatePolicyStore.writeSql);
    expect(connection.sqls.single, isNot(contains('SET min_build_number')));
    expect(connection.params.single, {
      'min_build_number': 845,
      'updated_by': 'u-1',
    });
  });

  test('a database failure is an error, not a minimum', () async {
    final AppUpdatePolicyStore store = PostgresPlayUpdatePolicyStore(
      _FakeConnection(const Result.err(AppError.transient('db.down', 'down'))),
    );

    expect(await store.minSupportedBuild(), isA<Err<int?>>());
  });
}
