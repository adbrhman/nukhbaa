import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [H2hDrawSource] (migration 0100).
///
/// **Active days** are the Riyadh days of the month on which a player holds
/// a prediction for a visible, non-test fixture that kicked off that day --
/// the reading the September simulation used. **Points** are the stored
/// fixture scores of that month, the double included. Suspended players are
/// left out of every list.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hDrawSource implements H2hDrawSource {
  /// Creates the source over [_connection].
  const PostgresH2hDrawSource(this._connection);

  final PostgresConnection _connection;

  static const String activeOrderSql = '''
WITH fx AS (
  SELECT DISTINCT sf.season_id, fs.fixture_id,
         (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date AS d
  FROM competition.season_fixtures sf
  JOIN competition.fixture_schedules fs ON fs.fixture_id = sf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date >= @month::date
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
        < (@month::date + interval '1 month')::date
),
per AS (
  SELECT p.user_id,
         count(DISTINCT fx.d) FILTER (WHERE fp.id IS NOT NULL) AS active_days,
         COALESCE(sum(s.points), 0)                           AS points,
         count(*) FILTER (WHERE s.grade = 'exact_scoreline')  AS exact
  FROM competition.participants p
  JOIN identity.users u ON u.id = p.user_id AND u.status <> 'suspended'
  JOIN fx ON fx.season_id = p.season_id
  LEFT JOIN prediction.fixture_predictions fp
    ON fp.fixture_id = fx.fixture_id AND fp.participant_id = p.id
  LEFT JOIN scoring.fixture_scores s
    ON s.fixture_id = fx.fixture_id AND s.participant_id = p.id
  GROUP BY p.user_id
)
SELECT user_id::text AS user_id
FROM per
WHERE active_days >= @min_days::integer
ORDER BY points DESC, exact DESC, user_id
''';

  static const String carriedSql = '''
SELECT e.user_id::text                           AS user_id,
       (e.payload ->> 'next_division')::integer   AS next_division,
       (e.payload ->> 'division')::integer        AS division,
       (e.payload ->> 'rank')::integer            AS rank
FROM gamification.events e
JOIN identity.users u ON u.id = e.user_id AND u.status <> 'suspended'
WHERE e.event_type = 'h2h_league_finished'
  AND e.payload ->> 'month' = @month::text
  AND e.payload ->> 'next_division' IS NOT NULL
ORDER BY 2, 3, 4, 1
''';

  static const String pilotOrderSql = '''
WITH pilot AS (
  SELECT a.user_id
  FROM gamification.experiment_assignments a
  JOIN identity.users u ON u.id = a.user_id AND u.status <> 'suspended'
  WHERE a.flag_key = 'h2h_pilot'
    AND a.variant = 'pilot'
),
fx AS (
  SELECT DISTINCT sf.season_id, sf.fixture_id
  FROM competition.season_fixtures sf
  JOIN competition.fixture_schedules fs ON fs.fixture_id = sf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date >= @month::date
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
        < (@month::date + interval '1 month')::date
),
per AS (
  SELECT p.user_id,
         COALESCE(sum(s.points), 0)                          AS points,
         count(*) FILTER (WHERE s.grade = 'exact_scoreline') AS exact
  FROM pilot pl
  JOIN competition.participants p ON p.user_id = pl.user_id
  JOIN fx ON fx.season_id = p.season_id
  JOIN scoring.fixture_scores s
    ON s.fixture_id = fx.fixture_id AND s.participant_id = p.id
  GROUP BY p.user_id
)
SELECT pl.user_id::text AS user_id
FROM pilot pl
LEFT JOIN per ON per.user_id = pl.user_id
ORDER BY COALESCE(per.points, 0) DESC, COALESCE(per.exact, 0) DESC, pl.user_id
''';

  @override
  Future<Result<List<UserId>>> activeOrder({
    required DateTime monthStart,
    required int minActiveDays,
  }) async {
    final result = await _connection.query(
      activeOrderSql,
      parameters: {'month': _isoDay(monthStart), 'min_days': minActiveDays},
    );
    return _users(result);
  }

  @override
  Future<Result<List<H2hCarry>>> carriedFrom(DateTime monthStart) async {
    final result = await _connection.query(
      carriedSql,
      parameters: {'month': _isoDay(monthStart)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final carried = <H2hCarry>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final user = UserId.tryParse(row['user_id']?.toString());
      final next = H2hDivision.ofLevel(_int(row['next_division']) ?? -1);
      final division = H2hDivision.ofLevel(_int(row['division']) ?? -1);
      final rank = _int(row['rank']);
      if (user is Err<UserId> ||
          next == null ||
          division == null ||
          rank == null) {
        return const Result.err(
          AppError.transient(
            'gamification.h2h_row_corrupt',
            'A stored head-to-head finish could not be read',
          ),
        );
      }
      carried.add(
        H2hCarry(
          userId: (user as Ok<UserId>).value,
          nextDivision: next,
          division: division,
          rank: rank,
        ),
      );
    }
    return Result.ok(List<H2hCarry>.unmodifiable(carried));
  }

  @override
  Future<Result<List<UserId>>> pilotOrder(DateTime monthStart) async {
    final result = await _connection.query(
      pilotOrderSql,
      parameters: {'month': _isoDay(monthStart)},
    );
    return _users(result);
  }

  static Result<List<UserId>> _users(
    Result<List<Map<String, dynamic>>> result,
  ) {
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final users = <UserId>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final parsed = UserId.tryParse(row['user_id']?.toString());
      if (parsed is Err<UserId>) {
        return Result.err(parsed.error);
      }
      users.add((parsed as Ok<UserId>).value);
    }
    return Result.ok(List<UserId>.unmodifiable(users));
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

  static String _isoDay(DateTime day) {
    final d = DateTime.utc(day.year, day.month, day.day);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
