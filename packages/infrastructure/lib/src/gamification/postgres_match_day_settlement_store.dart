import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [MatchDaySettlementStore] (P1-5).
///
/// Settling is ONE statement for the whole span: a generated series of days
/// is left-joined to the per-day fixture counts (so a day with no fixture
/// still gets its row, with 0) and inserted in one go. `ON CONFLICT (day) DO
/// NOTHING` is what makes a re-run harmless: a settled day keeps the count it
/// was frozen with. Days are plain `date` arithmetic, never a timestamp, so
/// the session time zone cannot shift one.
///
/// The same statement freezes the per-season breakdown into
/// `gamification.settled_day_seasons` (migration 0060), which is what the
/// streak calendar reads so that a day counts only for the seasons the
/// reader took part in. A data-modifying CTE runs to completion whether or
/// not the outer query reads it, and both halves share one snapshot and one
/// transaction: either the day and its seasons are both frozen, or neither
/// is. Only days that had fixtures get a per-season row; `settled_days`
/// alone carries the empty days, so it stays the watermark.
///
/// The day columns are projected as `YYYY-MM-DD` text so the adapter does not
/// depend on how the driver decodes a `date`.
///
/// Total (Application ADR §2): never throws, binds every value through a
/// `@named` parameter (Security ADR §2).
final class PostgresMatchDaySettlementStore implements MatchDaySettlementStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresMatchDaySettlementStore(this._connection);

  final PostgresConnection _connection;

  static const String _lastSettledSql = '''
SELECT to_char(max(day), 'YYYY-MM-DD') AS day
FROM gamification.settled_days
''';

  static const String _firstFixtureSql = '''
SELECT to_char(
         min((fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date),
         'YYYY-MM-DD'
       ) AS day
FROM competition.season_fixtures sf
JOIN competition.fixture_schedules fs
  ON fs.fixture_id = sf.fixture_id
''';

  static const String _settleSql = '''
WITH span AS (
  SELECT (@from::date + g.i)::date AS d
  FROM generate_series(0, @through::date - @from::date) AS g(i)
),
counts AS (
  SELECT (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date AS d,
         count(DISTINCT sf.fixture_id)::int AS n
  FROM competition.season_fixtures sf
  JOIN competition.fixture_schedules fs
    ON fs.fixture_id = sf.fixture_id
  WHERE (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
        BETWEEN @from::date AND @through::date
  GROUP BY 1
),
season_counts AS (
  SELECT (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date AS d,
         sf.season_id AS season_id,
         count(DISTINCT sf.fixture_id)::int AS n
  FROM competition.season_fixtures sf
  JOIN competition.fixture_schedules fs
    ON fs.fixture_id = sf.fixture_id
  WHERE (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
        BETWEEN @from::date AND @through::date
  GROUP BY 1, 2
),
settled_seasons AS (
  INSERT INTO gamification.settled_day_seasons (day, season_id, fixture_count)
  SELECT sc.d, sc.season_id, sc.n
  FROM season_counts sc
  ON CONFLICT (day, season_id) DO NOTHING
  RETURNING day
)
INSERT INTO gamification.settled_days (day, fixture_count)
SELECT span.d, COALESCE(counts.n, 0)
FROM span
LEFT JOIN counts
  ON counts.d = span.d
ON CONFLICT (day) DO NOTHING
RETURNING day
''';

  @override
  Future<Result<DateTime?>> lastSettledDay() => _readDay(_lastSettledSql);

  @override
  Future<Result<DateTime?>> firstFixtureDay() => _readDay(_firstFixtureSql);

  @override
  Future<Result<int>> settle({
    required DateTime from,
    required DateTime through,
  }) async {
    final result = await _connection.query(
      _settleSql,
      parameters: {'from': _isoDay(from), 'through': _isoDay(through)},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(value.length),
    };
  }

  Future<Result<DateTime?>> _readDay(String sql) async {
    final result = await _connection.query(sql);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final raw = rows.isEmpty ? null : rows.first['day']?.toString();
    if (raw == null || raw.isEmpty) {
      return const Result.ok(null);
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return const Result.err(
        AppError.transient(
          'gamification.row_corrupt',
          'A settled-day row carries an unreadable day',
        ),
      );
    }
    return Result.ok(DateTime.utc(parsed.year, parsed.month, parsed.day));
  }

  static String _isoDay(DateTime day) {
    final utc = day.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }
}
