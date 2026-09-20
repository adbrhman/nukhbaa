import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [StreakRepository].
///
/// One statement: the CTE lists the match days, and the EXISTS marks the ones
/// this user completed. Settled days (`gamification.settled_day_seasons`,
/// migration 0060) are read exactly as they were frozen; only the days after
/// the newest settled one -- the watermark is still `settled_days` -- are
/// derived live from the fixture schedule (a day exists because a fixture
/// kicks off in it), so a fixture moved later cannot rewrite a day that is
/// over. With nothing settled the live branch covers every day, as it always
/// did.
///
/// Both branches are restricted to the seasons the reader is an ACTIVE
/// participant in. A participant row is created when a user joins a season,
/// never implicitly, so a day only other seasons played is not a day this
/// user could have played, and counting it would break a streak the user had
/// no way to keep. The completion lookup is on `dedupe_key`, which carries a
/// unique index from migration 0053, so the per-day probe is an index hit
/// rather than a scan of the stream.
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
WITH my_seasons AS (
  SELECT p.season_id
  FROM competition.participants p
  WHERE p.user_id = @user_id
    AND p.status = 'active'::competition.participant_status
),
days AS (
  (
    SELECT sds.day AS d
    FROM gamification.settled_day_seasons sds
    JOIN my_seasons ms
      ON ms.season_id = sds.season_id
    WHERE sds.fixture_count > 0
      AND sds.day <= @up_to::date
  )
  UNION
  (
    SELECT DISTINCT (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date AS d
    FROM competition.season_fixtures sf
    JOIN my_seasons ms
      ON ms.season_id = sf.season_id
    JOIN competition.fixture_schedules fs
      ON fs.fixture_id = sf.fixture_id
    WHERE (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date <= @live_up_to::date
      AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date >
        COALESCE(
          (SELECT max(s2.day) FROM gamification.settled_days s2),
          '-infinity'::date
        )
  )
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
        'live_up_to': isoDay,
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
