import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [RankSnapshotReader] over
/// `leaderboard.season_rank_snapshots`.
final class PostgresRankSnapshotReader implements RankSnapshotReader {
  /// Creates the reader over its [PostgresConnection].
  const PostgresRankSnapshotReader(this._connection);

  final PostgresConnection _connection;

  // The season's most recent capture, and only that one. Comparing against
  // "the newest snapshot" rather than "yesterday's" keeps the arrows correct
  // when a capture is missed: the comparison is simply older, never absent.
  static const String _latestRanksSql = '''
SELECT participant_id, rank
FROM leaderboard.season_rank_snapshots
WHERE season_id = @season_id
  AND captured_on = (
        SELECT max(captured_on)
        FROM leaderboard.season_rank_snapshots
        WHERE season_id = @season_id
      )
''';

  @override
  Future<Result<Map<String, int>>> latestRanks(SeasonId seasonId) async {
    final result = await _connection.query(
      _latestRanksSql,
      parameters: {'season_id': seasonId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(<String, int>{
        for (final row in value)
          if (row['participant_id'] != null && row['rank'] is int)
            row['participant_id'].toString(): row['rank'] as int,
      }),
    };
  }
}
