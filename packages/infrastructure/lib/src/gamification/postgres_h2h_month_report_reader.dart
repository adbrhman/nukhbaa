import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [H2hMonthReportReader] (migration 0100): one
/// statement that counts a month's draw, groups, seats and closing. The
/// outcomes are the month's `h2h_league_finished` events, the very facts
/// the next draw reads. It counts; it decides nothing.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hMonthReportReader implements H2hMonthReportReader {
  /// Creates the reader over [_connection].
  const PostgresH2hMonthReportReader(this._connection);

  final PostgresConnection _connection;

  static const String reportSql = '''
SELECT m.drawn_at                                      AS drawn_at,
       COALESCE(m.is_pilot, false)                     AS is_pilot,
       COALESCE(m.seated_count, 0)                     AS drawn_seats,
       (SELECT count(*)::integer
          FROM gamification.h2h_league_members lm
         WHERE lm.month_start = @month::date)          AS seats,
       (SELECT COALESCE(string_agg(g.division || ':' || g.n, ','
                                   ORDER BY g.division), '')
          FROM (SELECT l.division, count(*)::integer AS n
                  FROM gamification.h2h_leagues l
                 WHERE l.month_start = @month::date
                 GROUP BY l.division) g)               AS groups,
       c.closed_at                                     AS closed_at,
       COALESCE(c.member_count, 0)                     AS closed_members,
       (SELECT COALESCE(string_agg(o.outcome || ':' || o.n, ','
                                   ORDER BY o.outcome), '')
          FROM (SELECT e.payload ->> 'outcome' AS outcome,
                       count(*)::integer       AS n
                  FROM gamification.events e
                 WHERE e.event_type = 'h2h_league_finished'
                   AND e.payload ->> 'month' = to_char(@month::date, 'YYYY-MM-DD')
                 GROUP BY 1) o)                        AS outcomes
FROM (SELECT 1) one
LEFT JOIN gamification.h2h_months m ON m.month_start = @month::date
LEFT JOIN gamification.h2h_month_closures c ON c.month_start = @month::date
''';

  @override
  Future<Result<H2hMonthReport>> reportOf(DateTime monthStart) async {
    final month = DateTime.utc(monthStart.year, monthStart.month);
    final result = await _connection.query(
      reportSql,
      parameters: {'month': _isoDay(month)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.length != 1) {
      return Result.err(_corrupt());
    }
    final row = rows.single;
    final drawnSeats = _int(row['drawn_seats']);
    final seats = _int(row['seats']);
    final closedMembers = _int(row['closed_members']);
    final groups = _counts(row['groups']);
    final outcomes = _counts(row['outcomes']);
    if (drawnSeats == null ||
        seats == null ||
        closedMembers == null ||
        groups == null ||
        outcomes == null) {
      return Result.err(_corrupt());
    }
    return Result.ok(
      H2hMonthReport(
        monthStart: month,
        drawnAt: _timestamp(row['drawn_at']),
        isPilot: row['is_pilot'] == true,
        drawnSeats: drawnSeats,
        seats: seats,
        groupsByDivision: {
          for (final entry in groups.entries)
            if (int.tryParse(entry.key) case final level?) level: entry.value,
        },
        closedAt: _timestamp(row['closed_at']),
        closedMembers: closedMembers,
        outcomes: outcomes,
      ),
    );
  }

  /// `key:n,key:n` into a map; null when it is not that.
  static Map<String, int>? _counts(Object? raw) {
    final text = raw?.toString() ?? '';
    final counts = <String, int>{};
    if (text.isEmpty) {
      return counts;
    }
    for (final part in text.split(',')) {
      final at = part.lastIndexOf(':');
      if (at <= 0) {
        return null;
      }
      final n = int.tryParse(part.substring(at + 1));
      if (n == null) {
        return null;
      }
      counts[part.substring(0, at)] = n;
    }
    return counts;
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

  static String _isoDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static AppError _corrupt() => const AppError.transient(
    'gamification.h2h_row_corrupt',
    'A stored head-to-head month report could not be read',
  );
}
