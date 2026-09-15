import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [SportingSeasonStandingsReader].
///
/// Sums `leaderboard.season_fixture_standings` (migration 0034, the same
/// per-month fixture store the monthly board and the daily snapshot read)
/// across every monthly contest of the season, per user. A monthly contest
/// is identified by its `MM/YYYY` label -- the same rule `GET /months`
/// applies -- and the label, not the stored instants, decides which season a
/// month belongs to, so no time-zone offset can move a month across the
/// September boundary.
final class PostgresSportingSeasonStandingsReader
    implements SportingSeasonStandingsReader {
  /// Creates the reader over [_connection].
  const PostgresSportingSeasonStandingsReader(this._connection);

  final PostgresConnection _connection;

  // The CASE keeps the integer casts away from any label that is not a
  // monthly contest; a WHERE clause alone gives no evaluation-order
  // guarantee.
  static const String _standingsSql = '''
WITH months AS (
  SELECT id,
         CASE
           WHEN length(label) = 7 AND label ~ '^[0-9]{2}/[0-9]{4}'
           THEN substr(label, 4, 4)::int * 100 + substr(label, 1, 2)::int
         END AS month_key
  FROM competition.seasons
)
SELECT p.user_id::text                          AS user_id,
       max(u.display_name)                      AS display_name,
       sum(f.total_points)::bigint              AS total_points,
       sum(f.fixtures_scored)::bigint           AS fixtures_scored,
       sum(f.exact_count)::bigint               AS exact_count,
       sum(f.decided_count)::bigint             AS decided_count,
       count(DISTINCT f.season_id)::bigint      AS months_played
FROM leaderboard.season_fixture_standings f
JOIN months m
  ON m.id = f.season_id
JOIN competition.participants p
  ON p.id = f.participant_id
JOIN identity.users u
  ON u.id = p.user_id
WHERE m.month_key BETWEEN @first_key AND @last_key
GROUP BY p.user_id
''';

  @override
  Future<Result<List<SportingSeasonStanding>>> standings(
    SportingSeason season,
  ) async {
    final result = await _connection.query(
      _standingsSql,
      parameters: {
        'first_key': season.firstMonthKey,
        'last_key': season.lastMonthKey,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapAll(value),
    };
  }

  static Result<List<SportingSeasonStanding>> _mapAll(
    List<Map<String, dynamic>> rows,
  ) {
    final mapped = <SportingSeasonStanding>[];
    for (final row in rows) {
      final userIdResult = UserId.tryParse(row['user_id']?.toString());
      if (userIdResult is Err<UserId>) {
        return Result.err(_corrupt('user_id', userIdResult.error.message));
      }
      final userId = (userIdResult as Ok<UserId>).value;
      final totalPoints = _readInt(row['total_points']);
      final fixturesScored = _readInt(row['fixtures_scored']);
      final exactCount = _readInt(row['exact_count']);
      final decidedCount = _readInt(row['decided_count']);
      final monthsPlayed = _readInt(row['months_played']);
      if (totalPoints == null ||
          fixturesScored == null ||
          exactCount == null ||
          decidedCount == null ||
          monthsPlayed == null) {
        return Result.err(_corrupt('counts', 'not an integer'));
      }
      final name = row['display_name']?.toString().trim() ?? '';
      final standing = SportingSeasonStanding.projected(
        userId: userId,
        displayName: name.isEmpty ? userId.value : name,
        totalPoints: totalPoints,
        fixturesScored: fixturesScored,
        exactCount: exactCount,
        decidedCount: decidedCount,
        monthsPlayed: monthsPlayed,
      );
      if (standing is Err<SportingSeasonStanding>) {
        return Result.err(standing.error);
      }
      mapped.add((standing as Ok<SportingSeasonStanding>).value);
    }
    return Result.ok(List<SportingSeasonStanding>.unmodifiable(mapped));
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
    'Stored sporting-season standing has invalid $field: $detail',
  );
}
