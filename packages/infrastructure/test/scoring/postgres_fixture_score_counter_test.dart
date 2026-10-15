import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/scoring/postgres_fixture_score_counter.dart';
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

const String _f1 = '00000000-0156-4000-8000-0000000000f1';
const String _f2 = '00000000-0156-4000-8000-0000000000f2';

/// The row mapping of the score counter (batch 156). The SQL is checked
/// against the schema by `fixture_score_counts_query_test.sql`.
void main() {
  test('one query for every fixture, mapped by id', () async {
    final _FakeConnection connection = _FakeConnection(
      const Result.ok([
        {'fixture_id': _f1, 'scores': 12},
        {'fixture_id': _f2, 'scores': 3},
      ]),
    );

    final Result<Map<String, int>> counts = await PostgresFixtureScoreCounter(
      connection,
    ).countByFixtures(const [FixtureRef(_f1), FixtureRef(_f2)]);

    expect((counts as Ok<Map<String, int>>).value, {_f1: 12, _f2: 3});
    expect(connection.sqls, [PostgresFixtureScoreCounter.countSql]);
    expect(connection.params.single['fixture_ids'], [_f1, _f2]);
  });

  test('nothing asked: no query', () async {
    final _FakeConnection connection = _FakeConnection(const Result.ok([]));

    final Result<Map<String, int>> counts = await PostgresFixtureScoreCounter(
      connection,
    ).countByFixtures(const []);

    expect((counts as Ok<Map<String, int>>).value, isEmpty);
    expect(connection.sqls, isEmpty);
  });
}
