import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [WeeklyLeagueStandingsReader] (P2-4).
///
/// One statement, one row per member of the group, so a group of twenty costs
/// twenty rows on the wire and one round trip.
///
/// **The points are the monthly board's points over a different fixture
/// list.** The sums are the ones `PostgresFixtureTotalsReader` computes --
/// `scoring.fixture_scores` plus `ledger.fixture_point_entries` of kind
/// `streak_bonus` -- and the grade buckets are the same: `decided` excludes
/// `pending`. What changes is the fixture list: for each participation the
/// user holds, the fixtures of THAT season that kicked off on a Riyadh day of
/// the week. Going through `season_fixtures` keeps the week consistent with
/// the month: a fixture taken out of a season stops counting in both.
///
/// **Membership is by user, points are by participant.** `members` starts
/// from the group, so a member who has scored nothing, or who holds no
/// participation at all, still appears -- as a zero.
///
/// **No season window is applied.** A week can straddle two monthly seasons;
/// filtering on "the season that is open now" would drop the points earned
/// before the boundary. A participation only carries scores for the fixtures
/// of its own season, so the week window alone bounds the sum.
///
/// `AT TIME ZONE 'Asia/Riyadh'` is the boundary migration 0054, the daily
/// challenge and the streak use. Riyadh has no daylight saving, so the named
/// zone and the fixed +3 offset agree on every date.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresWeeklyLeagueStandingsReader
    implements WeeklyLeagueStandingsReader {
  /// Creates the reader over [_connection].
  const PostgresWeeklyLeagueStandingsReader(this._connection);

  final PostgresConnection _connection;

  static const String _standingsSql = '''
WITH members AS (
  SELECT m.user_id,
         m.joined_at
  FROM gamification.weekly_league_members m
  WHERE m.league_id = @league_id::uuid
),
week_fixtures AS (
  SELECT mb.user_id,
         p.id AS participant_id,
         sf.fixture_id
  FROM members mb
  JOIN competition.participants p
    ON p.user_id = mb.user_id
   AND p.status = 'active'::competition.participant_status
  JOIN competition.season_fixtures sf
    ON sf.season_id = p.season_id
  JOIN competition.fixture_schedules fs
    ON fs.fixture_id = sf.fixture_id
  WHERE (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
        BETWEEN @week_start::date AND @week_end::date
),
scores AS (
  SELECT wf.user_id,
         sum(s.points)::bigint AS score_points,
         count(*) FILTER (WHERE s.grade = 'exact_scoreline')::bigint
           AS exact_count,
         count(*) FILTER (
           WHERE s.grade IN ('exact_scoreline', 'correct_outcome', 'incorrect')
         )::bigint AS decided_count
  FROM week_fixtures wf
  JOIN scoring.fixture_scores s
    ON s.fixture_id = wf.fixture_id
   AND s.participant_id = wf.participant_id
  GROUP BY wf.user_id
),
bonuses AS (
  SELECT wf.user_id,
         sum(b.amount)::bigint AS bonus_points
  FROM week_fixtures wf
  JOIN ledger.fixture_point_entries b
    ON b.fixture_id = wf.fixture_id
   AND b.participant_id = wf.participant_id
   AND b.entry_kind = 'streak_bonus'
  GROUP BY wf.user_id
)
SELECT mb.user_id::text AS user_id,
       mb.joined_at AS joined_at,
       (COALESCE(s.score_points, 0) + COALESCE(b.bonus_points, 0))::bigint
         AS total_points,
       COALESCE(s.exact_count, 0)::bigint AS exact_count,
       COALESCE(s.decided_count, 0)::bigint AS decided_count
FROM members mb
LEFT JOIN scores s
  ON s.user_id = mb.user_id
LEFT JOIN bonuses b
  ON b.user_id = mb.user_id
ORDER BY mb.user_id
''';

  @override
  Future<Result<List<WeeklyLeagueEntry>>> entriesOf({
    required WeeklyLeagueId leagueId,
    required DateTime weekStart,
  }) async {
    // Normalised to its Monday, so a caller cannot ask for a window that
    // starts mid-week and ends on a Sunday.
    final monday = WeeklyLeaguePolicy.weekStartOf(weekStart);
    final sunday = monday.add(const Duration(days: 6));

    final result = await _connection.query(
      _standingsSql,
      parameters: {
        'league_id': leagueId.value,
        'week_start': _isoDay(monday),
        'week_end': _isoDay(sunday),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapAll(value),
    };
  }

  static Result<List<WeeklyLeagueEntry>> _mapAll(
    List<Map<String, dynamic>> rows,
  ) {
    final entries = <WeeklyLeagueEntry>[];
    for (final row in rows) {
      final userResult = UserId.tryParse(row['user_id']?.toString());
      if (userResult is Err<UserId>) {
        return Result.err(_corrupt('user_id', userResult.error.message));
      }
      final joinedAt = _readTimestamp(row['joined_at']);
      if (joinedAt == null) {
        return Result.err(_corrupt('joined_at', 'not a timestamp'));
      }
      final points = _readInt(row['total_points']);
      final exactCount = _readInt(row['exact_count']);
      final decidedCount = _readInt(row['decided_count']);
      if (points == null || exactCount == null || decidedCount == null) {
        return Result.err(_corrupt('counts', 'not an integer'));
      }
      entries.add(
        WeeklyLeagueEntry(
          userId: (userResult as Ok<UserId>).value,
          points: points,
          exactCount: exactCount,
          decidedCount: decidedCount,
          joinedAt: joinedAt,
        ),
      );
    }
    return Result.ok(List<WeeklyLeagueEntry>.unmodifiable(entries));
  }

  /// `bigint` may arrive as an int, a BigInt or, under a text-codec
  /// projection, a string. A cast would throw, and this adapter is total.
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

  static DateTime? _readTimestamp(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    return DateTime.tryParse(raw?.toString() ?? '')?.toUtc();
  }

  static String _isoDay(DateTime day) {
    final utc = day.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'gamification.weekly_league_row_corrupt',
    'Stored weekly league standing has invalid $field: $detail',
  );
}
