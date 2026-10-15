import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [FixtureScoreCounter] (batch 156): one grouped
/// count over `scoring.fixture_scores`, whose primary key starts with
/// `fixture_id`. Checked against the schema by
/// `supabase/tests/fixture_score_counts_query_test.sql`; keep it identical.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresFixtureScoreCounter implements FixtureScoreCounter {
  /// Creates the counter over [_connection].
  const PostgresFixtureScoreCounter(this._connection);

  final PostgresConnection _connection;

  /// The count.
  static const String countSql = '''
SELECT fixture_id::text AS fixture_id, count(*)::int AS scores
FROM scoring.fixture_scores
WHERE fixture_id = ANY(@fixture_ids::uuid[])
GROUP BY fixture_id
''';

  @override
  Future<Result<Map<String, int>>> countByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    if (fixtures.isEmpty) return const Result.ok(<String, int>{});
    final result = await _connection.query(
      countSql,
      parameters: {
        'fixture_ids': [for (final f in fixtures) f.value],
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    return Result.ok(<String, int>{
      for (final row in rows)
        if (row['fixture_id'] case final String id)
          id: switch (row['scores']) {
            final int n => n,
            final num n => n.toInt(),
            _ => 0,
          },
    });
  }
}
