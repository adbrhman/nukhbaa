import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [FixturePredictionTallyReader] over
/// `prediction.fixture_predictions`.
///
/// One grouped query for the whole fixture set, never one per fixture --
/// `WHERE fixture_id = ANY(@fixture_ids::uuid[])` is the same batching idiom
/// [PostgresFixtureScheduleRepository.findByFixtures] already uses, and the
/// explicit `::uuid[]` cast is not optional: without it the driver sends the
/// list as text and Postgres rejects the comparison (the `uuid[]` bug that
/// once returned 503 on `/rounds/{id}/fixtures`).
///
/// `migration 0019` indexes `fixture_id` (`fixture_predictions_fixture_idx`),
/// so this is an index scan plus an aggregate, and it reads no scoreline into
/// the server at all -- only two counts per fixture. Draws match neither
/// filter, which is what makes the two percentages a split between the teams
/// rather than between all three outcomes.
///
/// A fixture nobody has predicted produces no row: absent, not zero. The
/// caller decides what that means (see [FixturePredictionTallyReader]).
///
/// All values bind through `@named` parameters (Security ADR section 2).
final class PostgresFixturePredictionTallyReader
    implements FixturePredictionTallyReader {
  /// Creates the reader over an open [PostgresConnection].
  const PostgresFixturePredictionTallyReader(this._connection);

  final PostgresConnection _connection;

  static const String _tallySql = '''
SELECT fixture_id,
       COUNT(*) FILTER (WHERE home_goals > away_goals) AS home_wins,
       COUNT(*) FILTER (WHERE home_goals < away_goals) AS away_wins
FROM prediction.fixture_predictions
WHERE fixture_id = ANY(@fixture_ids::uuid[])
GROUP BY fixture_id
''';

  @override
  Future<Result<List<FixtureOutcomeTally>>> tallyByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    if (fixtures.isEmpty) {
      return const Result.ok(<FixtureOutcomeTally>[]);
    }
    final result = await _connection.query(
      _tallySql,
      parameters: {
        'fixture_ids': [for (final f in fixtures) f.value],
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapRows(value),
    };
  }

  Result<List<FixtureOutcomeTally>> _mapRows(List<Map<String, dynamic>> rows) {
    final tallies = <FixtureOutcomeTally>[];
    for (final row in rows) {
      final Object? rawId = row['fixture_id'];
      if (rawId == null) continue;
      final parsed = FixtureRef.tryParse(rawId.toString());
      // A row whose id will not parse is a storage-level impossibility here
      // (the column is `uuid`), and a malformed one must not take down a
      // whole feed for a decoration: skip it, and every other fixture still
      // gets its split.
      if (parsed is Err<FixtureRef>) continue;
      tallies.add(
        FixtureOutcomeTally(
          fixture: (parsed as Ok<FixtureRef>).value,
          homeWins: _count(row['home_wins']),
          awayWins: _count(row['away_wins']),
        ),
      );
    }
    return Result.ok(List<FixtureOutcomeTally>.unmodifiable(tallies));
  }

  /// `COUNT(*)` comes back as `bigint`, which the driver may hand over as an
  /// `int` or as something that only knows how to print itself.
  int _count(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw == null) return 0;
    return int.tryParse(raw.toString()) ?? 0;
  }
}
