import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [StreakRepository].
///
/// One statement: the CTE lists the match days (a day exists because a
/// fixture kicks off in it), and the EXISTS marks the ones this user
/// completed. The lookup is on `dedupe_key`, which carries a unique index
/// from migration 0053, so the per-day probe is an index hit rather than a
/// scan of the stream.
///
/// The user id is bound twice — once as a uuid for the equality, once as
/// text for the key — rather than once and cast, so neither binding depends
/// on the driver inferring a type from a concatenation.
///
/// Total (Application ADR §2): never throws, binds every value through a
/// `@named` parameter (Security ADR §2).
final class PostgresStreakRepository implements StreakRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresStreakRepository(this._connection);

  final PostgresConnection _connection;

  static const String _calendarSql = '''
WITH days AS (
  SELECT DISTINCT (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date AS d
  FROM competition.season_fixtures sf
  JOIN competition.fixture_schedules fs
    ON fs.fixture_id = sf.fixture_id
  WHERE (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date <= @up_to::date
  ORDER BY d DESC
  LIMIT @limit_days
)
SELECT
  days.d AS day,
  EXISTS (
    SELECT 1
    FROM gamification.events e
    WHERE e.user_id = @user_id
      AND e.event_type = 'daily_challenge_completed'
      AND e.dedupe_key =
        'daily_challenge_completed:' || @user_key || ':' ||
        to_char(days.d, 'YYYY-MM-DD')
  ) AS completed
FROM days
ORDER BY days.d DESC
''';

  @override
  Future<Result<List<MatchDayCompletion>>> completionCalendar({
    required UserId userId,
    required DateTime upToDay,
    required int limitDays,
  }) async {
    final utcDay = upToDay.toUtc();
    final isoDay =
        '${utcDay.year.toString().padLeft(4, '0')}-'
        '${utcDay.month.toString().padLeft(2, '0')}-'
        '${utcDay.day.toString().padLeft(2, '0')}';

    final result = await _connection.query(
      _calendarSql,
      parameters: {
        'up_to': isoDay,
        'limit_days': limitDays,
        'user_id': userId.value,
        'user_key': userId.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        Result.ok(<MatchDayCompletion>[
          for (final row in value)
            MatchDayCompletion(
              day: _day(row['day']),
              completed: row['completed'] == true,
            ),
        ]),
    };
  }

  /// A `date` column arrives as a [DateTime] from the driver, but a text
  /// codec projection would make it a string; a cast would throw, and this
  /// adapter is total.
  static DateTime _day(Object? raw) {
    if (raw is DateTime) {
      return DateTime.utc(raw.year, raw.month, raw.day);
    }
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) {
      return DateTime.utc(1970);
    }
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }
}
