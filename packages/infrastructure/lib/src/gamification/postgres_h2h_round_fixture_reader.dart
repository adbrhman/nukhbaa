import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [H2hRoundFixtureReader] (migration 0100). It reads;
/// it writes nothing and scores nothing.
///
/// **A round's fixtures.** A locked round's are its frozen list
/// (`h2h_round_fixtures`); a fixture of it that left the round's day, was
/// hidden or is a test fixture comes back with `counted` false -- the very
/// condition `PostgresH2hSheetReader` sums the round with. An unlocked
/// round's are the visible, non-test fixtures of a season that kick off on
/// its Riyadh day, the list `PostgresH2hRoundStore.lock` would freeze now.
///
/// **The picks.** One per player and fixture, over every participation the
/// player holds, as the sheet sums them: the goals and the double of the
/// first submitted prediction, the stored points summed (null while every
/// score is still `pending` or none is stored), exact when any score says
/// so.
///
/// **Secrecy.** The opponent's predictions are selected only for fixtures
/// whose kickoff is at or before `@now` -- the server clock the use-case
/// passes, which then checks the same rule with `FixtureLock`. A fixture
/// that has not kicked off never brings the opponent's row out of the
/// database.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hRoundFixtureReader implements H2hRoundFixtureReader {
  /// Creates the reader over [_connection].
  const PostgresH2hRoundFixtureReader(this._connection);

  final PostgresConnection _connection;

  static const String fixturesSql = '''
WITH list AS (
  SELECT rf.fixture_id
  FROM gamification.h2h_round_fixtures rf
  WHERE @locked::boolean
    AND rf.round_id = @round_id::uuid
  UNION
  SELECT fs.fixture_id
  FROM competition.fixture_schedules fs
  WHERE NOT @locked::boolean
    AND fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND EXISTS (
      SELECT 1 FROM competition.season_fixtures sf
      WHERE sf.fixture_id = fs.fixture_id
    )
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = @day::date
)
SELECT fs.fixture_id::text    AS fixture_id,
       fs.home_team           AS home_team,
       fs.away_team           AS away_team,
       fs.home_team_id::text  AS home_team_id,
       fs.away_team_id::text  AS away_team_id,
       fs.kickoff_at          AS kickoff_at,
       COALESCE(
         fs.hidden_at IS NULL
           AND NOT fs.is_test
           AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = @day::date,
         false)               AS counted,
       res.home_goals         AS home_goals,
       res.away_goals         AS away_goals
FROM list l
JOIN competition.fixture_schedules fs ON fs.fixture_id = l.fixture_id
LEFT JOIN scoring.fixture_results res ON res.fixture_id = l.fixture_id
ORDER BY fs.kickoff_at, fs.fixture_id
''';

  static const String picksSql = '''
SELECT p.user_id::text            AS user_id,
       fp.fixture_id::text        AS fixture_id,
       fp.home_goals              AS home_goals,
       fp.away_goals              AS away_goals,
       fp.is_double               AS is_double,
       sc.points                  AS points,
       COALESCE(sc.exact, false)  AS exact
FROM competition.participants p
JOIN competition.season_fixtures sf ON sf.season_id = p.season_id
JOIN competition.fixture_schedules fs ON fs.fixture_id = sf.fixture_id
JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = sf.fixture_id AND fp.participant_id = p.id
LEFT JOIN LATERAL (
  SELECT (sum(s.points) FILTER (WHERE s.grade <> 'pending'))::integer AS points,
         bool_or(s.grade = 'exact_scoreline')                        AS exact
  FROM scoring.fixture_scores s
  WHERE s.fixture_id = fp.fixture_id
    AND s.participant_id = p.id
) sc ON true
WHERE sf.fixture_id = ANY(string_to_array(@fixture_ids::text, ',')::uuid[])
  AND (p.user_id = @reader::uuid
       OR (p.user_id = @opponent::uuid
           AND fs.kickoff_at <= @now::timestamptz))
ORDER BY p.user_id, fp.fixture_id, fp.submitted_at, p.id
''';

  @override
  Future<Result<List<H2hRoundFixture>>> fixturesOf({
    required H2hRound round,
    required UserId reader,
    required UserId? opponent,
    required DateTime nowUtc,
  }) async {
    final fixturesResult = await _connection.query(
      fixturesSql,
      parameters: {
        'locked': round.locked,
        'round_id': round.id.value,
        'day': _isoDay(round.day),
      },
    );
    if (fixturesResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(fixturesResult.error);
    }
    final rows = (fixturesResult as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(<H2hRoundFixture>[]);
    }

    final ids = <String>[];
    for (final row in rows) {
      final id = row['fixture_id']?.toString();
      if (id == null || id.isEmpty) {
        return Result.err(_corrupt('fixture'));
      }
      ids.add(id);
    }

    final picksResult = await _connection.query(
      picksSql,
      parameters: {
        'fixture_ids': ids.join(','),
        'reader': reader.value,
        'opponent': opponent?.value,
        'now': nowUtc.toUtc(),
      },
    );
    if (picksResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(picksResult.error);
    }
    final picks = <String, _Pick>{};
    for (final row in (picksResult as Ok<List<Map<String, dynamic>>>).value) {
      final user = UserId.tryParse(row['user_id']?.toString());
      final fixture = row['fixture_id']?.toString();
      final home = _int(row['home_goals']);
      final away = _int(row['away_goals']);
      if (user is Err<UserId> ||
          fixture == null ||
          home == null ||
          away == null) {
        return Result.err(_corrupt('prediction'));
      }
      final key = _key((user as Ok<UserId>).value, fixture);
      final points = _int(row['points']);
      final exact = row['exact'] == true;
      final known = picks[key];
      if (known == null) {
        picks[key] = _Pick(
          homeGoals: home,
          awayGoals: away,
          isDouble: row['is_double'] == true,
          points: points,
          exact: exact,
        );
      } else {
        known
          ..points = _sum(known.points, points)
          ..exact = known.exact || exact;
      }
    }

    final fixtures = <H2hRoundFixture>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final id = ids[i];
      fixtures.add(
        H2hRoundFixture(
          fixtureId: id,
          homeTeam: row['home_team']?.toString() ?? '',
          awayTeam: row['away_team']?.toString() ?? '',
          homeTeamId: row['home_team_id']?.toString(),
          awayTeamId: row['away_team_id']?.toString(),
          kickoffAt: _timestamp(row['kickoff_at']),
          counted: row['counted'] == true,
          homeGoals: _int(row['home_goals']),
          awayGoals: _int(row['away_goals']),
          mine: picks[_key(reader, id)]?.toPick(),
          theirs: opponent == null ? null : picks[_key(opponent, id)]?.toPick(),
        ),
      );
    }
    return Result.ok(List<H2hRoundFixture>.unmodifiable(fixtures));
  }

  static String _key(UserId user, String fixture) => '${user.value}|$fixture';

  static int? _sum(int? a, int? b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return a + b;
  }

  static int? _int(Object? raw) {
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

  static DateTime? _timestamp(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is DateTime) {
      return raw.toUtc();
    }
    return DateTime.tryParse(raw.toString())?.toUtc();
  }

  static String _isoDay(DateTime day) {
    final d = DateTime.utc(day.year, day.month, day.day);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static AppError _corrupt(String what) => AppError.transient(
    'gamification.h2h_row_corrupt',
    'A stored head-to-head $what row could not be read',
  );
}

/// A pick while the participations of one player are folded into it.
final class _Pick {
  _Pick({
    required this.homeGoals,
    required this.awayGoals,
    required this.isDouble,
    required this.points,
    required this.exact,
  });

  final int homeGoals;
  final int awayGoals;
  final bool isDouble;
  int? points;
  bool exact;

  H2hFixturePick toPick() => H2hFixturePick(
    homeGoals: homeGoals,
    awayGoals: awayGoals,
    isDouble: isDouble,
    points: points,
    exact: exact,
  );
}
