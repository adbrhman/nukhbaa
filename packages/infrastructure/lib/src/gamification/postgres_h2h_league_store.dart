import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [H2hLeagueStore] over the tables of migration 0100.
///
/// [draw] runs in one transaction that starts by inserting the month row:
/// when the row exists already the insert does nothing, the draw writes
/// nothing more and returns 0, so two concurrent draws cannot both seat a
/// month.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hLeagueStore implements H2hLeagueStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresH2hLeagueStore(this._connection);

  final PostgresConnection _connection;

  static const String monthOfSql = '''
SELECT is_pilot, seated_count
FROM gamification.h2h_months
WHERE month_start = @month::date
''';

  static const String isClosedSql = '''
SELECT 1 AS hit
FROM gamification.h2h_month_closures
WHERE month_start = @month::date
''';

  static const String insertMonthSql = '''
INSERT INTO gamification.h2h_months (month_start, is_pilot, seated_count)
VALUES (@month::date, @is_pilot::boolean, @seated::integer)
ON CONFLICT (month_start) DO NOTHING
RETURNING 1 AS inserted
''';

  static const String insertGroupSql = '''
INSERT INTO gamification.h2h_leagues
  (id, month_start, division, group_index, capacity)
VALUES (@id::uuid, @month::date, @division::smallint,
        @group_index::smallint, @capacity::smallint)
''';

  static const String insertSeatSql = '''
INSERT INTO gamification.h2h_league_members
  (league_id, month_start, user_id, slot)
VALUES (@league_id::uuid, @month::date, @user_id::uuid, @slot::smallint)
''';

  static const String seatSql = '''
SELECT m.league_id::text AS league_id,
       l.division        AS division,
       l.group_index     AS group_index,
       m.slot            AS slot,
       l.capacity        AS capacity,
       m.joined_at       AS joined_at,
       mo.is_pilot       AS is_pilot,
       (SELECT count(*)
          FROM gamification.h2h_leagues l2
         WHERE l2.month_start = l.month_start
           AND l2.division = l.division)::integer AS division_groups
FROM gamification.h2h_league_members m
JOIN gamification.h2h_leagues l ON l.id = m.league_id
JOIN gamification.h2h_months mo ON mo.month_start = m.month_start
WHERE m.user_id = @user_id::uuid
  AND m.month_start = @month::date
''';

  static const String groupsSql = '''
SELECT id::text    AS league_id,
       division    AS division,
       group_index AS group_index,
       capacity    AS capacity
FROM gamification.h2h_leagues
WHERE month_start = @month::date
ORDER BY division, group_index
''';

  static const String nextUnclosedSql = '''
SELECT to_char(min(m.month_start), 'YYYY-MM-DD') AS month
FROM gamification.h2h_months m
WHERE NOT EXISTS (
  SELECT 1 FROM gamification.h2h_month_closures c
  WHERE c.month_start = m.month_start
)
''';

  static const String markClosedSql = '''
INSERT INTO gamification.h2h_month_closures (month_start, member_count)
VALUES (@month::date, @member_count::integer)
ON CONFLICT (month_start) DO NOTHING
''';

  @override
  Future<Result<H2hMonthInfo?>> monthOf(DateTime monthStart) async {
    final result = await _connection.query(
      monthOfSql,
      parameters: {'month': _isoDay(monthStart)},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.ok(null)
            : Result.ok(
                H2hMonthInfo(
                  monthStart: _dayOf(monthStart),
                  isPilot: value.first['is_pilot'] == true,
                  seatedCount: _int(value.first['seated_count']) ?? 0,
                ),
              ),
    };
  }

  @override
  Future<Result<bool>> isClosed(DateTime monthStart) async {
    final result = await _connection.query(
      isClosedSql,
      parameters: {'month': _isoDay(monthStart)},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  @override
  Future<Result<int>> draw({
    required DateTime monthStart,
    required bool isPilot,
    required List<H2hDrawnGroup> groups,
    required int capacity,
  }) async {
    final month = _isoDay(monthStart);
    var seats = 0;
    for (final drawn in groups) {
      seats += drawn.group.seats.length;
    }
    final total = seats;

    return _connection.runInTransaction<int>((tx) async {
      final inserted = await tx.query(
        insertMonthSql,
        parameters: {'month': month, 'is_pilot': isPilot, 'seated': total},
      );
      if (inserted is Err<List<Map<String, dynamic>>>) {
        return Result.err(inserted.error);
      }
      if ((inserted as Ok<List<Map<String, dynamic>>>).value.isEmpty) {
        // Drawn already: nothing more is written.
        return const Result.ok(0);
      }
      for (final drawn in groups) {
        final group = await tx.query(
          insertGroupSql,
          parameters: {
            'id': drawn.leagueId.value,
            'month': month,
            'division': drawn.group.division.level,
            'group_index': drawn.group.groupIndex,
            'capacity': capacity,
          },
        );
        if (group is Err<List<Map<String, dynamic>>>) {
          return Result.err(group.error);
        }
        for (final seat in drawn.group.seats) {
          final row = await tx.query(
            insertSeatSql,
            parameters: {
              'league_id': drawn.leagueId.value,
              'month': month,
              'user_id': seat.userId.value,
              'slot': seat.slot,
            },
          );
          if (row is Err<List<Map<String, dynamic>>>) {
            return Result.err(row.error);
          }
        }
      }
      return Result.ok(total);
    });
  }

  @override
  Future<Result<H2hSeat?>> seatFor({
    required UserId userId,
    required DateTime monthStart,
  }) async {
    final result = await _connection.query(
      seatSql,
      parameters: {'user_id': userId.value, 'month': _isoDay(monthStart)},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.ok(null)
            : _mapSeat(value.first, _dayOf(monthStart)),
    };
  }

  @override
  Future<Result<List<H2hGroupRef>>> groupsOf(DateTime monthStart) async {
    final result = await _connection.query(
      groupsSql,
      parameters: {'month': _isoDay(monthStart)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final groups = <H2hGroupRef>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final id = H2hLeagueId.tryParse(row['league_id']?.toString());
      final division = H2hDivision.ofLevel(_int(row['division']) ?? -1);
      final index = _int(row['group_index']);
      final capacity = _int(row['capacity']);
      if (id is Err<H2hLeagueId> ||
          division == null ||
          index == null ||
          capacity == null) {
        return Result.err(_corrupt('group'));
      }
      groups.add(
        H2hGroupRef(
          leagueId: (id as Ok<H2hLeagueId>).value,
          division: division,
          groupIndex: index,
          capacity: capacity,
        ),
      );
    }
    return Result.ok(List<H2hGroupRef>.unmodifiable(groups));
  }

  @override
  Future<Result<DateTime?>> nextUnclosedMonth() async {
    final result = await _connection.query(nextUnclosedSql);
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isEmpty ? null : _parseDay(value.first['month']),
      ),
    };
  }

  @override
  Future<Result<void>> markClosed({
    required DateTime monthStart,
    required int memberCount,
  }) async {
    final result = await _connection.query(
      markClosedSql,
      parameters: {'month': _isoDay(monthStart), 'member_count': memberCount},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  static Result<H2hSeat?> _mapSeat(Map<String, dynamic> row, DateTime month) {
    final id = H2hLeagueId.tryParse(row['league_id']?.toString());
    final division = H2hDivision.ofLevel(_int(row['division']) ?? -1);
    final groupIndex = _int(row['group_index']);
    final slot = _int(row['slot']);
    final capacity = _int(row['capacity']);
    final divisionGroups = _int(row['division_groups']);
    final joinedAt = _timestamp(row['joined_at']);
    if (id is Err<H2hLeagueId> ||
        division == null ||
        groupIndex == null ||
        slot == null ||
        capacity == null ||
        divisionGroups == null ||
        joinedAt == null) {
      return Result.err(_corrupt('seat'));
    }
    return Result.ok(
      H2hSeat(
        leagueId: (id as Ok<H2hLeagueId>).value,
        monthStart: month,
        division: division,
        groupIndex: groupIndex,
        slot: slot,
        capacity: capacity,
        divisionGroups: divisionGroups,
        isPilot: row['is_pilot'] == true,
        joinedAt: joinedAt,
      ),
    );
  }

  /// A number may arrive as an int, a BigInt or, under a text-codec
  /// projection, a string. A cast would throw, and this adapter is total.
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
    if (raw is DateTime) {
      return raw.toUtc();
    }
    return DateTime.tryParse(raw?.toString() ?? '')?.toUtc();
  }

  static DateTime? _parseDay(Object? raw) {
    if (raw == null) {
      return null;
    }
    final parsed = DateTime.tryParse(raw.toString());
    return parsed == null ? null : _dayOf(parsed);
  }

  static DateTime _dayOf(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static String _isoDay(DateTime day) {
    final d = _dayOf(day);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static AppError _corrupt(String what) => AppError.transient(
    'gamification.h2h_row_corrupt',
    'A stored head-to-head $what row could not be read',
  );
}
