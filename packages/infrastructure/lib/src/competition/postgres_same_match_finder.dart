import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres [SameMatchFinder] over `competition.fixture_schedules`.
///
/// Spelling is normalised as in the fixtures sync's adoption query
/// (`PostgresProviderSyncStore`): hamza forms, alif maqsura, taa marbuta
/// and spaces. A side agrees when it is the same catalog team, the same
/// normalised name, or -- only when one of the two has no team on file --
/// one name inside the other, three letters at least; two different teams
/// on file never agree by a name inside another (audit C-04). Test and
/// hidden fixtures are skipped. The nearest kickoff to the middle of the
/// window wins. Tested in supabase/tests/same_match_query_test.sql.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresSameMatchFinder implements SameMatchFinder {
  /// Creates the finder over [_connection].
  const PostgresSameMatchFinder(this._connection);

  final PostgresConnection _connection;

  static const String _sameMatchSql = '''
WITH target AS (
  SELECT regexp_replace(translate(btrim(@home_name::text), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS h,
         regexp_replace(translate(btrim(@away_name::text), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS a,
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
         regexp_replace(translate(btrim(s.home_team), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS h,
         regexp_replace(translate(btrim(s.away_team), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS a
  FROM competition.fixture_schedules s
  WHERE s.kickoff_at >= @from::timestamptz
    AND s.kickoff_at < @to::timestamptz
    -- A test fixture is never a real match, and a hidden one was taken
    -- out of the contest by an admin (0098).
    AND NOT s.is_test
    AND s.hidden_at IS NULL
)
SELECT c.fixture_id::text AS fixture_id,
       c.home_team,
       c.away_team,
       c.kickoff_at
FROM candidates c, target t
-- A side agrees when it is the same catalog team, or the same name once
-- spelling is normalised (one club, two catalog rows), or -- only when a
-- side has no team on file -- one name inside the other, three letters
-- at least. Two different teams on file never agree by a name that sits
-- inside another (audit C-04).
WHERE ((c.home_team_id IS NOT NULL AND c.home_team_id = t.home_id)
       OR c.h = t.h
       OR ((c.home_team_id IS NULL OR t.home_id IS NULL)
           AND length(t.h) >= 3 AND length(c.h) >= 3
           AND (strpos(t.h, c.h) > 0 OR strpos(c.h, t.h) > 0)))
  AND ((c.away_team_id IS NOT NULL AND c.away_team_id = t.away_id)
       OR c.a = t.a
       OR ((c.away_team_id IS NULL OR t.away_id IS NULL)
           AND length(t.a) >= 3 AND length(c.a) >= 3
           AND (strpos(t.a, c.a) > 0 OR strpos(c.a, t.a) > 0)))
ORDER BY abs(extract(epoch from (c.kickoff_at - t.kickoff))),
         c.fixture_id
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
      ),
    );
  }
}
