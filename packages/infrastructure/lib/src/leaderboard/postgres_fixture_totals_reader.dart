import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [FixtureTotalsReader].
///
/// Sums `scoring.fixture_scores` per participant inside the database, so the
/// monthly board costs one row per player on the wire instead of one row
/// per player per fixture. The grade buckets are exactly the ones
/// `FixtureLeaderboard.rank` and `leaderboard.season_fixture_standings`
/// (migration 0034) use: `decided` excludes `pending`. The primary key
/// `(fixture_id, participant_id)` serves the `ANY` filter.
final class PostgresFixtureTotalsReader implements FixtureTotalsReader {
  /// Creates the reader over [_connection].
  const PostgresFixtureTotalsReader(this._connection);

  final PostgresConnection _connection;

  static const String _totalsSql = '''
SELECT participant_id::text                                  AS participant_id,
       sum(points)::bigint                                   AS total_points,
       count(*)::bigint                                      AS fixtures_scored,
       count(*) FILTER (WHERE grade = 'exact_scoreline')::bigint
                                                             AS exact_count,
       count(*) FILTER (
         WHERE grade IN ('exact_scoreline', 'correct_outcome', 'incorrect')
       )::bigint                                             AS decided_count
FROM scoring.fixture_scores
WHERE fixture_id = ANY(@fixture_ids::uuid[])
GROUP BY participant_id
''';

  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) async {
    if (fixtures.isEmpty) {
      return const Result.ok(<ParticipantFixtureTotals>[]);
    }
    final result = await _connection.query(
      _totalsSql,
      parameters: {
        'fixture_ids': [for (final fixture in fixtures) fixture.value],
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapAll(value),
    };
  }

  static Result<List<ParticipantFixtureTotals>> _mapAll(
    List<Map<String, dynamic>> rows,
  ) {
    final mapped = <ParticipantFixtureTotals>[];
    for (final row in rows) {
      final idResult = ParticipantId.tryParse(
        row['participant_id']?.toString(),
      );
      if (idResult is Err<ParticipantId>) {
        return Result.err(_corrupt('participant_id', idResult.error.message));
      }
      final totalPoints = _readInt(row['total_points']);
      final fixturesScored = _readInt(row['fixtures_scored']);
      final exactCount = _readInt(row['exact_count']);
      final decidedCount = _readInt(row['decided_count']);
      if (totalPoints == null ||
          fixturesScored == null ||
          exactCount == null ||
          decidedCount == null) {
        return Result.err(_corrupt('counts', 'not an integer'));
      }
      final totals = ParticipantFixtureTotals.of(
        participantId: (idResult as Ok<ParticipantId>).value,
        totalPoints: totalPoints,
        fixturesScored: fixturesScored,
        exactCount: exactCount,
        decidedCount: decidedCount,
      );
      if (totals is Err<ParticipantFixtureTotals>) {
        return Result.err(totals.error);
      }
      mapped.add((totals as Ok<ParticipantFixtureTotals>).value);
    }
    return Result.ok(List<ParticipantFixtureTotals>.unmodifiable(mapped));
  }

  static int? _readInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is BigInt && raw.isValidInt) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'leaderboard.row_corrupt',
    'Stored fixture totals have invalid $field: $detail',
  );
}
