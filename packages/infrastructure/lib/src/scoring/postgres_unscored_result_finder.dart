import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [UnscoredResultFinder] over
/// `scoring.fixtures_with_unscored_predictions` (migration 0080).
///
/// The rule lives in SQL, where the migration's end-to-end test exercises it
/// against real tables; this adapter only binds the window and maps the ids.
final class PostgresUnscoredResultFinder implements UnscoredResultFinder {
  /// Creates the finder over the shared [PostgresConnection].
  const PostgresUnscoredResultFinder(this._connection);

  final PostgresConnection _connection;

  static const String _sql = '''
SELECT fixture_id::text AS fixture_id
FROM scoring.fixtures_with_unscored_predictions(
  @recorded_from::timestamptz,
  @recorded_before::timestamptz,
  @limit::int
)
''';

  @override
  Future<Result<List<String>>> fixturesWithUnscoredPredictions({
    required DateTime recordedFrom,
    required DateTime recordedBefore,
    required int limit,
  }) async {
    final result = await _connection.query(
      _sql,
      parameters: {
        'recorded_from': recordedFrom.toUtc().toIso8601String(),
        'recorded_before': recordedBefore.toUtc().toIso8601String(),
        'limit': limit,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(<String>[
        for (final row in value) row['fixture_id'].toString(),
      ]),
    };
  }
}
