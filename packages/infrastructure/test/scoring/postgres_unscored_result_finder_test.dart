import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/scoring/postgres_unscored_result_finder.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;
  String? sql;
  Map<String, Object?>? parameters;

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    this.sql = sql;
    this.parameters = parameters;
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
  group('PostgresUnscoredResultFinder', () {
    test('binds the window and the limit, and returns the ids', () async {
      final connection = _FakeConnection(
        const Result.ok(<Map<String, dynamic>>[
          {'fixture_id': 'c8000000-0000-4000-8000-0000000000f1'},
          {'fixture_id': 'c8000000-0000-4000-8000-0000000000f3'},
        ]),
      );
      final finder = PostgresUnscoredResultFinder(connection);

      final result = await finder.fixturesWithUnscoredPredictions(
        recordedFrom: DateTime.utc(2026, 9, 27, 12),
        recordedBefore: DateTime.utc(2026, 9, 30, 11, 50),
        limit: 10,
      );

      expect((result as Ok<List<String>>).value, <String>[
        'c8000000-0000-4000-8000-0000000000f1',
        'c8000000-0000-4000-8000-0000000000f3',
      ]);
      expect(
        connection.sql,
        contains('scoring.fixtures_with_unscored_predictions'),
      );
      expect(connection.parameters, <String, Object?>{
        'recorded_from': '2026-09-27T12:00:00.000Z',
        'recorded_before': '2026-09-30T11:50:00.000Z',
        'limit': 10,
      });
    });

    test('a failed query is returned as it came', () async {
      final finder = PostgresUnscoredResultFinder(
        _FakeConnection(
          const Result.err(
            AppError.transient('db.query_timeout', 'Database query timed out'),
          ),
        ),
      );

      final result = await finder.fixturesWithUnscoredPredictions(
        recordedFrom: DateTime.utc(2026, 9, 27),
        recordedBefore: DateTime.utc(2026, 9, 30),
        limit: 10,
      );

      expect((result as Err<List<String>>).error.code, 'db.query_timeout');
    });
  });
}
