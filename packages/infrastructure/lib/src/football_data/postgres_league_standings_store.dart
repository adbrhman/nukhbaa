import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// [LeagueStandingsStore] over `football_data.league_standings` (migration
/// 0192, script 189).
///
/// One row per club of a kept table. A save writes the new table with its
/// read time, then removes the rows of the table before it; a read takes only
/// the rows of the latest read time, so a save interrupted between its two
/// statements never mixes two tables.
final class PostgresLeagueStandingsStore implements LeagueStandingsStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresLeagueStandingsStore(this._connection);

  final PostgresConnection _connection;

  static const String _latestSql = '''
SELECT s.team_external_id AS team_external_id,
       s.position         AS position,
       s.points           AS points,
       s.played           AS played,
       s.fetched_at       AS fetched_at
FROM football_data.league_standings s
WHERE s.source = @source
  AND s.league_ref = @league_ref
  AND s.fetched_at = (SELECT max(m.fetched_at)
                        FROM football_data.league_standings m
                       WHERE m.source = @source
                         AND m.league_ref = @league_ref)
ORDER BY s.position, s.team_external_id
''';

  static const String _saveSql = '''
INSERT INTO football_data.league_standings
  (source, league_ref, team_external_id, position, points, played,
   fetched_at)
SELECT @source::text, @league_ref::text, r.team, r.place,
       nullif(r.points, '')::integer, nullif(r.played, '')::integer,
       @fetched_at::timestamptz
FROM unnest(@teams::text[], @places::int[], @points::text[],
            @played::text[]) AS r(team, place, points, played)
ON CONFLICT (source, league_ref, team_external_id) DO UPDATE
SET position = EXCLUDED.position,
    points = EXCLUDED.points,
    played = EXCLUDED.played,
    fetched_at = EXCLUDED.fetched_at
''';

  static const String _pruneSql = '''
DELETE FROM football_data.league_standings
WHERE source = @source
  AND league_ref = @league_ref
  AND fetched_at < @fetched_at::timestamptz
''';

  @override
  Future<Result<StoredLeagueTable?>> latest({
    required String source,
    required String leagueRef,
  }) async {
    final result = await _connection.query(
      _latestSql,
      parameters: {'source': source, 'league_ref': leagueRef},
    );
    switch (result) {
      case Err<List<Map<String, dynamic>>>(:final error):
        return Result.err(error);
      case Ok<List<Map<String, dynamic>>>(:final value):
        if (value.isEmpty) {
          return const Result.ok(null);
        }
        final rows = <LeagueStandingRow>[];
        DateTime? fetchedAt;
        for (final row in value) {
          final position = row['position'];
          final at = row['fetched_at'];
          if (position is! int || at is! DateTime) {
            return const Result.err(
              AppError.transient(
                'football_data.row_corrupt',
                'Stored league table is malformed',
              ),
            );
          }
          fetchedAt ??= at.toUtc();
          final points = row['points'];
          final played = row['played'];
          rows.add(
            LeagueStandingRow(
              teamExternalId: row['team_external_id'].toString(),
              position: position,
              points: points is int ? points : null,
              played: played is int ? played : null,
            ),
          );
        }
        return Result.ok(StoredLeagueTable(rows: rows, fetchedAt: fetchedAt!));
    }
  }

  @override
  Future<Result<void>> save({
    required String source,
    required String leagueRef,
    required List<LeagueStandingRow> rows,
    required DateTime fetchedAt,
  }) async {
    if (rows.isEmpty) {
      return const Result.ok(null);
    }
    final at = fetchedAt.toUtc().toIso8601String();
    final saved = await _connection.query(
      _saveSql,
      parameters: {
        'source': source,
        'league_ref': leagueRef,
        'fetched_at': at,
        'teams': [for (final row in rows) row.teamExternalId],
        'places': [for (final row in rows) row.position],
        'points': [for (final row in rows) row.points?.toString() ?? ''],
        'played': [for (final row in rows) row.played?.toString() ?? ''],
      },
    );
    if (saved is Err<List<Map<String, dynamic>>>) {
      return Result.err(saved.error);
    }
    final pruned = await _connection.query(
      _pruneSql,
      parameters: {'source': source, 'league_ref': leagueRef, 'fetched_at': at},
    );
    return switch (pruned) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }
}
