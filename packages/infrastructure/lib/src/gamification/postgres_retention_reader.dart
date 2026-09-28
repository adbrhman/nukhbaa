import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [RetentionReader] (migration 0069).
///
/// Reads the measurement views as they are -- `kpi_weekly_engagement`,
/// `kpi_league_retention` and `user_active_days` -- so the dashboard and a
/// hand-run query can never disagree. Days and weeks are Riyadh days and
/// Monday-opened Riyadh weeks, as the views define them.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresRetentionReader implements RetentionReader {
  /// Creates the reader over [_connection].
  const PostgresRetentionReader(this._connection);

  final PostgresConnection _connection;

  // One row per week with any play or any league seat. Counts are cast to
  // bigint so the driver hands back plain ints; the week comes back as
  // text so no driver date handling stands between it and the Riyadh day.
  static const String _weeksSql = '''
WITH engagement AS (
  SELECT
    week_start,
    sum(active_users)::bigint AS active_users,
    sum(active_3plus)::bigint AS active_3plus,
    coalesce(sum(active_users) FILTER (WHERE in_league), 0)::bigint
      AS league_active,
    coalesce(sum(active_3plus) FILTER (WHERE in_league), 0)::bigint
      AS league_active_3plus
  FROM gamification.kpi_weekly_engagement
  WHERE week_start BETWEEN @from::date AND @through::date
  GROUP BY week_start
),
seats AS (
  SELECT
    week_start,
    members::bigint AS league_members,
    returned_next_week::bigint AS league_returned
  FROM gamification.kpi_league_retention
  WHERE week_start BETWEEN @from::date AND @through::date
)
SELECT
  to_char(coalesce(e.week_start, s.week_start), 'YYYY-MM-DD') AS week_start,
  coalesce(e.active_users, 0) AS active_users,
  coalesce(e.active_3plus, 0) AS active_3plus,
  coalesce(e.league_active, 0) AS league_active,
  coalesce(e.league_active_3plus, 0) AS league_active_3plus,
  coalesce(s.league_members, 0) AS league_members,
  coalesce(s.league_returned, 0) AS league_returned
FROM engagement e
FULL JOIN seats s ON s.week_start = e.week_start
ORDER BY 1 DESC
''';

  // The first active day is taken over the whole history (a player back
  // after a year is not new); only then are the window's cohorts kept.
  // Day N is judged once it has ended: first_day + N before @today.
  static const String _cohortsSql = '''
WITH firsts AS (
  SELECT user_id, min(activity_date) AS first_day
  FROM gamification.user_active_days
  GROUP BY user_id
),
cohort AS (
  SELECT
    user_id,
    first_day,
    first_day - (extract(isodow FROM first_day)::int - 1) AS week_start
  FROM firsts
  WHERE first_day BETWEEN @from::date AND @today::date
),
marks AS (
  SELECT
    c.week_start,
    c.user_id,
    c.first_day,
    coalesce(bool_or(a.activity_date = c.first_day + 1), false) AS day1,
    coalesce(bool_or(a.activity_date = c.first_day + 7), false) AS day7,
    coalesce(bool_or(a.activity_date = c.first_day + 14), false) AS day14,
    coalesce(
      bool_or(a.activity_date BETWEEN c.first_day + 21 AND c.first_day + 27),
      false
    ) AS week4
  FROM cohort c
  LEFT JOIN gamification.user_active_days a
    ON a.user_id = c.user_id
   AND a.activity_date BETWEEN c.first_day + 1 AND c.first_day + 27
  GROUP BY c.week_start, c.user_id, c.first_day
)
SELECT
  to_char(week_start, 'YYYY-MM-DD') AS week_start,
  count(*)::bigint AS users,
  count(*) FILTER (WHERE first_day + 1 < @today::date)::bigint
    AS day1_eligible,
  count(*) FILTER (WHERE first_day + 1 < @today::date AND day1)::bigint
    AS day1,
  count(*) FILTER (WHERE first_day + 7 < @today::date)::bigint
    AS day7_eligible,
  count(*) FILTER (WHERE first_day + 7 < @today::date AND day7)::bigint
    AS day7,
  count(*) FILTER (WHERE first_day + 14 < @today::date)::bigint
    AS day14_eligible,
  count(*) FILTER (WHERE first_day + 14 < @today::date AND day14)::bigint
    AS day14,
  count(*) FILTER (WHERE first_day + 27 < @today::date)::bigint
    AS week4_eligible,
  count(*) FILTER (WHERE first_day + 27 < @today::date AND week4)::bigint
    AS week4
FROM marks
GROUP BY week_start
ORDER BY week_start DESC
''';

  static const AppError _corrupt = AppError.transient(
    'retention.row_corrupt',
    'a retention row carries an unreadable week',
  );

  @override
  Future<Result<List<WeeklyActivity>>> weeks({
    required DateTime from,
    required DateTime through,
  }) async {
    final result = await _connection.query(
      _weeksSql,
      parameters: {'from': _isoDay(from), 'through': _isoDay(through)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <WeeklyActivity>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final DateTime? week = _parseDay(row['week_start']);
      if (week == null) {
        return const Result.err(_corrupt);
      }
      out.add(
        WeeklyActivity(
          weekStart: week,
          activeUsers: _int(row['active_users']),
          active3Plus: _int(row['active_3plus']),
          leagueActive: _int(row['league_active']),
          leagueActive3Plus: _int(row['league_active_3plus']),
          leagueMembers: _int(row['league_members']),
          leagueReturned: _int(row['league_returned']),
        ),
      );
    }
    return Result.ok(out);
  }

  @override
  Future<Result<List<RetentionCohort>>> cohorts({
    required DateTime from,
    required DateTime today,
  }) async {
    final result = await _connection.query(
      _cohortsSql,
      parameters: {'from': _isoDay(from), 'today': _isoDay(today)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <RetentionCohort>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final DateTime? week = _parseDay(row['week_start']);
      if (week == null) {
        return const Result.err(_corrupt);
      }
      out.add(
        RetentionCohort(
          weekStart: week,
          users: _int(row['users']),
          day1Eligible: _int(row['day1_eligible']),
          day1: _int(row['day1']),
          day7Eligible: _int(row['day7_eligible']),
          day7: _int(row['day7']),
          day14Eligible: _int(row['day14_eligible']),
          day14: _int(row['day14']),
          week4Eligible: _int(row['week4_eligible']),
          week4: _int(row['week4']),
        ),
      );
    }
    return Result.ok(out);
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  static DateTime? _parseDay(Object? value) {
    final DateTime? parsed = value == null
        ? null
        : DateTime.tryParse(value.toString());
    return parsed == null
        ? null
        : DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  static String _isoDay(DateTime day) {
    final utc = day.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }
}
