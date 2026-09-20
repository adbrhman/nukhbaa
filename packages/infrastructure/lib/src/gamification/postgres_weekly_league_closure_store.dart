import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [WeeklyLeagueClosureStore] over the tables of migration
/// 0061 (P2-5).
///
/// Three small statements and no write except one insert:
///
/// * the OLDEST week that has a group and no closure row is one `min()`
///   over `weekly_leagues`, anti-joined to `weekly_league_closures`;
/// * the groups of a week are a plain read, with the tier as the stored
///   number;
/// * closing a week is `INSERT ... ON CONFLICT (week_start) DO NOTHING`.
///   `DO NOTHING` is what makes a replay harmless, and it is also why the
///   append-only trigger of migration 0061 never fires: a conflict that
///   updates nothing is not an UPDATE. This adapter never issues an UPDATE
///   or a DELETE against these tables, and the database would reject both.
///
/// Weeks are plain `date` values projected as `YYYY-MM-DD` text, so the
/// adapter does not depend on how the driver decodes a `date` and the
/// session time zone cannot shift one.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresWeeklyLeagueClosureStore
    implements WeeklyLeagueClosureStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresWeeklyLeagueClosureStore(this._connection);

  final PostgresConnection _connection;

  static const String _nextUnclosedSql = '''
SELECT to_char(min(l.week_start), 'YYYY-MM-DD') AS week_start
FROM gamification.weekly_leagues l
WHERE NOT EXISTS (
  SELECT 1
  FROM gamification.weekly_league_closures c
  WHERE c.week_start = l.week_start
)
''';

  static const String _groupsSql = '''
SELECT l.id::text AS league_id,
       l.tier     AS tier
FROM gamification.weekly_leagues l
WHERE l.week_start = @week_start::date
ORDER BY l.tier ASC, l.group_index ASC
''';

  static const String _markClosedSql = '''
INSERT INTO gamification.weekly_league_closures (week_start, member_count)
VALUES (@week_start::date, @member_count::int)
ON CONFLICT (week_start) DO NOTHING
''';

  @override
  Future<Result<DateTime?>> nextUnclosedWeek() async {
    final result = await _connection.query(_nextUnclosedSql);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final raw = rows.isEmpty ? null : rows.first['week_start']?.toString();
    if (raw == null || raw.isEmpty) {
      return const Result.ok(null);
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return const Result.err(
        AppError.transient(
          'gamification.row_corrupt',
          'A weekly league row carries an unreadable week',
        ),
      );
    }
    return Result.ok(DateTime.utc(parsed.year, parsed.month, parsed.day));
  }

  @override
  Future<Result<List<WeeklyLeagueGroupRef>>> groupsOf(
    DateTime weekStart,
  ) async {
    final result = await _connection.query(
      _groupsSql,
      parameters: {'week_start': _isoDay(weekStart)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;

    final groups = <WeeklyLeagueGroupRef>[];
    for (final row in rows) {
      final idResult = WeeklyLeagueId.tryParse(row['league_id']?.toString());
      if (idResult is Err<WeeklyLeagueId>) {
        return Result.err(idResult.error);
      }
      // A tier this generation of the ladder does not know is an error, not
      // a skip: skipping the group would let the week be marked closed with
      // that group never judged, and a closed week is never judged again.
      final tier = WeeklyLeagueTier.ofLevel(_int(row['tier']));
      if (tier == null) {
        return const Result.err(
          AppError.transient(
            'gamification.weekly_league_tier_unknown',
            'Stored weekly league tier is not a known tier',
          ),
        );
      }
      groups.add(
        WeeklyLeagueGroupRef(
          leagueId: (idResult as Ok<WeeklyLeagueId>).value,
          tier: tier,
        ),
      );
    }
    return Result.ok(List<WeeklyLeagueGroupRef>.unmodifiable(groups));
  }

  @override
  Future<Result<void>> markClosed({
    required DateTime weekStart,
    required int memberCount,
  }) async {
    final result = await _connection.query(
      _markClosedSql,
      parameters: {
        'week_start': _isoDay(weekStart),
        'member_count': memberCount,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  /// `smallint` may arrive as an int or, under a text-codec projection, as a
  /// string. A cast would throw, and this adapter is total.
  static int _int(Object? raw) {
    if (raw is int) {
      return raw;
    }
    return int.tryParse(raw?.toString() ?? '') ?? -1;
  }

  static String _isoDay(DateTime day) {
    final utc = day.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }
}
