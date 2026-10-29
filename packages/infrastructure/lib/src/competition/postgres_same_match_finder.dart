import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres [SameMatchFinder] over `competition.fixture_schedules`.
///
/// Names are compared by `competition.team_name_key` (migration 0110):
/// hamza forms, alif maqsura, taa marbuta, case and spaces folded. A side
/// agrees when it is the same catalog team, the same name key, or -- only
/// when one of the two has no team on file -- one name inside the other,
/// three letters at least; two different teams on file never agree by a
/// name inside another (audit C-04). Home and away entered the other way
/// round are the same match. One club in both -- the same team or the same
/// name key, on either side -- is found too (script 93, migration 0175): a
/// club plays one match in 12 hours, so "هوفنهايم - بيشتكاش" is caught
/// beside "هوفنهايم - بشكتاش". Test and hidden fixtures are skipped. The
/// same match wins over one club alike, then the nearest kickoff to the
/// middle of the window. Tested in supabase/tests/same_match_query_test.sql;
/// the schedule's own trigger (0110, 0175) refuses whatever slips past.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresSameMatchFinder implements SameMatchFinder {
  /// Creates the finder over [_connection].
  const PostgresSameMatchFinder(this._connection);

  final PostgresConnection _connection;

  static const String _sameMatchSql = '''
WITH target AS (
  SELECT competition.team_name_key(@home_name::text) AS h,
         competition.team_name_key(@away_name::text) AS a,
         @home_id::uuid AS home_id,
         @away_id::uuid AS away_id,
         @from::timestamptz + (@to::timestamptz - @from::timestamptz) / 2 AS kickoff
),
candidates AS (
  SELECT s.fixture_id,
         s.home_team,
         s.away_team,
         s.kickoff_at,
         s.home_team_id,
         s.away_team_id,
         competition.team_name_key(s.home_team) AS h,
         competition.team_name_key(s.away_team) AS a
  FROM competition.fixture_schedules s
  WHERE s.kickoff_at >= @from::timestamptz
    AND s.kickoff_at < @to::timestamptz
    -- A test fixture is never a real match, and a hidden one was taken
    -- out of the contest by an admin (0098).
    AND NOT s.is_test
    AND s.hidden_at IS NULL
),
-- Each stored fixture against the new match as given and with its sides
-- swapped: home and away entered the other way round are the same match.
sides AS (
  SELECT c.*, t.h AS new_h, t.a AS new_a,
         t.home_id AS new_home_id, t.away_id AS new_away_id, t.kickoff
  FROM candidates c, target t
  UNION ALL
  SELECT c.*, t.a, t.h, t.away_id, t.home_id, t.kickoff
  FROM candidates c, target t
),
-- A side agrees when it is the same catalog team, or the same name key
-- (competition.team_name_key, 0110: one club, two catalog rows), or --
-- only when a side has no team on file -- one name inside the other,
-- three letters at least. Two different teams on file never agree by a
-- name that sits inside another (audit C-04). One club in both matches --
-- the same team or the same name key, on either side -- is enough to
-- refuse (0175): a club plays one match in 12 hours.
judged AS (
  SELECT s.*,
         COALESCE(
           ((s.home_team_id IS NOT NULL AND s.home_team_id = s.new_home_id)
            OR s.h = s.new_h
            OR ((s.home_team_id IS NULL OR s.new_home_id IS NULL)
                AND length(s.new_h) >= 3 AND length(s.h) >= 3
                AND (strpos(s.new_h, s.h) > 0 OR strpos(s.h, s.new_h) > 0)))
           AND ((s.away_team_id IS NOT NULL AND s.away_team_id = s.new_away_id)
            OR s.a = s.new_a
            OR ((s.away_team_id IS NULL OR s.new_away_id IS NULL)
                AND length(s.new_a) >= 3 AND length(s.a) >= 3
                AND (strpos(s.new_a, s.a) > 0 OR strpos(s.a, s.new_a) > 0))),
           false) AS both_sides,
         COALESCE(
           (s.home_team_id IS NOT NULL
              AND s.home_team_id IN (s.new_home_id, s.new_away_id))
           OR (s.away_team_id IS NOT NULL
              AND s.away_team_id IN (s.new_home_id, s.new_away_id))
           OR s.h IN (s.new_h, s.new_a)
           OR s.a IN (s.new_h, s.new_a),
           false) AS one_club
  FROM sides s
)
SELECT j.fixture_id::text AS fixture_id,
       j.home_team,
       j.away_team,
       j.kickoff_at,
       j.both_sides,
       EXISTS (
         SELECT 1 FROM competition.season_fixtures sf
         WHERE sf.fixture_id = j.fixture_id
       ) AS linked
FROM judged j
WHERE j.both_sides OR j.one_club
-- The same match first, then the nearest kickoff to the middle.
ORDER BY j.both_sides DESC,
         abs(extract(epoch from (j.kickoff_at - j.kickoff))),
         j.fixture_id
LIMIT 1
''';

  @override
  Future<Result<SameMatch?>> find({
    required String homeTeam,
    required String awayTeam,
    required String? homeTeamId,
    required String? awayTeamId,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _connection.query(
      _sameMatchSql,
      parameters: {
        'home_name': homeTeam.trim(),
        'away_name': awayTeam.trim(),
        'home_id': homeTeamId,
        'away_id': awayTeamId,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(null);
    }
    final row = rows.first;
    final fixtureId = row['fixture_id'];
    final home = row['home_team'];
    final away = row['away_team'];
    final kickoffAt = row['kickoff_at'];
    if (fixtureId is! String ||
        home is! String ||
        away is! String ||
        kickoffAt is! DateTime) {
      return const Result.err(
        AppError.transient(
          'competition.row_corrupt',
          'A fixture_schedules row read as the same match is malformed',
        ),
      );
    }
    return Result.ok(
      SameMatch(
        fixtureId: fixtureId,
        homeTeam: home,
        awayTeam: away,
        kickoffAt: kickoffAt.toUtc(),
        bothSides: row['both_sides'] != false,
        linked: row['linked'] != false,
      ),
    );
  }
}
