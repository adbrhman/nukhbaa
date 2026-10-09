import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres-backed [H2hRoundStore] over the round tables of migration 0100.
///
/// A day's fixtures are the visible, non-test fixtures linked to a season
/// whose kickoff falls on that Riyadh day -- the same reading the streak
/// calendar and the match-day settlement use. [lock] freezes them inside one
/// transaction, fixtures first and the lock row last, so a lock row always
/// has its list; a second lock of the same round writes nothing.
///
/// The database refuses a round out of order, past 19, on a day already
/// taken, or a withdrawal that is not of the last unlocked round. Those
/// refusals arrive as constraint violations and are returned as
/// [ErrorKind.invariant] errors with a stable code.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hRoundStore implements H2hRoundStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresH2hRoundStore(this._connection);

  final PostgresConnection _connection;

  static const String roundsSql = '''
SELECT r.id::text                              AS id,
       r.round_no                              AS round_no,
       to_char(r.day, 'YYYY-MM-DD')            AS day,
       COALESCE(k.fixture_count, r.fixture_count) AS fixture_count,
       r.approved_by::text                     AS approved_by,
       k.locked_at                             AS locked_at
FROM gamification.h2h_rounds r
LEFT JOIN gamification.h2h_round_locks k ON k.round_id = r.id
WHERE r.month_start = @month::date
ORDER BY r.round_no
''';

  static const String daysSql = '''
SELECT to_char((fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date, 'YYYY-MM-DD')
         AS day,
       count(DISTINCT fs.fixture_id)::integer AS fixture_count,
       min(fs.kickoff_at)                     AS first_kickoff
FROM competition.fixture_schedules fs
WHERE fs.hidden_at IS NULL
  AND NOT fs.is_test
  AND EXISTS (
    SELECT 1 FROM competition.season_fixtures sf
    WHERE sf.fixture_id = fs.fixture_id
  )
  AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
      BETWEEN @from_day::date AND @through_day::date
GROUP BY 1
ORDER BY 1
''';

  static const String approveSql = '''
INSERT INTO gamification.h2h_rounds
  (id, month_start, round_no, day, fixture_count, approved_by)
VALUES (@id::uuid, @month::date, @round_no::smallint, @day::date,
        @fixture_count::smallint, @approved_by::uuid)
''';

  static const String withdrawSql = '''
DELETE FROM gamification.h2h_rounds
WHERE id = @id::uuid
RETURNING 1 AS withdrawn
''';

  static const String freezeFixturesSql = '''
INSERT INTO gamification.h2h_round_fixtures (round_id, fixture_id)
SELECT DISTINCT @round_id::uuid, fs.fixture_id
FROM competition.fixture_schedules fs
WHERE fs.hidden_at IS NULL
  AND NOT fs.is_test
  AND EXISTS (
    SELECT 1 FROM competition.season_fixtures sf
    WHERE sf.fixture_id = fs.fixture_id
  )
  AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = @day::date
  AND NOT EXISTS (
    SELECT 1 FROM gamification.h2h_round_locks k
    WHERE k.round_id = @round_id::uuid
  )
ON CONFLICT (round_id, fixture_id) DO NOTHING
''';

  static const String lockSql = '''
INSERT INTO gamification.h2h_round_locks (round_id, fixture_count)
SELECT @round_id::uuid, count(*)::smallint
FROM gamification.h2h_round_fixtures
WHERE round_id = @round_id::uuid
ON CONFLICT (round_id) DO NOTHING
''';

  static const String lockedCountSql = '''
SELECT fixture_count
FROM gamification.h2h_round_locks
WHERE round_id = @round_id::uuid
''';

  @override
  Future<Result<List<H2hRound>>> roundsOf(DateTime monthStart) async {
    final month = _dayOf(monthStart);
    final result = await _connection.query(
      roundsSql,
      parameters: {'month': _isoDay(month)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rounds = <H2hRound>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final id = H2hRoundId.tryParse(row['id']?.toString());
      final number = _int(row['round_no']);
      final day = _parseDay(row['day']);
      final count = _int(row['fixture_count']);
      if (id is Err<H2hRoundId> ||
          number == null ||
          day == null ||
          count == null) {
        return Result.err(_corrupt());
      }
      final rawApprover = row['approved_by']?.toString();
      UserId? approvedBy;
      if (rawApprover != null) {
        final parsed = UserId.tryParse(rawApprover);
        if (parsed is Err<UserId>) {
          return Result.err(_corrupt());
        }
        approvedBy = (parsed as Ok<UserId>).value;
      }
      rounds.add(
        H2hRound(
          id: (id as Ok<H2hRoundId>).value,
          monthStart: month,
          number: number,
          day: day,
          fixtureCount: count,
          approvedBy: approvedBy,
          lockedAt: _timestamp(row['locked_at']),
        ),
      );
    }
    return Result.ok(List<H2hRound>.unmodifiable(rounds));
  }

  @override
  Future<Result<H2hDayFixtures>> dayFixtures(DateTime day) async {
    final d = _dayOf(day);
    final result = await daysBetween(from: d, through: d);
    return switch (result) {
      Err<List<H2hDayFixtures>>(:final error) => Result.err(error),
      Ok<List<H2hDayFixtures>>(:final value) => Result.ok(
        value.isEmpty
            ? H2hDayFixtures(day: d, fixtureCount: 0, firstKickoff: null)
            : value.first,
      ),
    };
  }

  @override
  Future<Result<List<H2hDayFixtures>>> daysBetween({
    required DateTime from,
    required DateTime through,
  }) async {
    final result = await _connection.query(
      daysSql,
      parameters: {'from_day': _isoDay(from), 'through_day': _isoDay(through)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final days = <H2hDayFixtures>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final day = _parseDay(row['day']);
      final count = _int(row['fixture_count']);
      if (day == null || count == null) {
        return Result.err(_corrupt());
      }
      days.add(
        H2hDayFixtures(
          day: day,
          fixtureCount: count,
          firstKickoff: _timestamp(row['first_kickoff']),
        ),
      );
    }
    return Result.ok(List<H2hDayFixtures>.unmodifiable(days));
  }

  @override
  Future<Result<void>> approve({
    required H2hRoundId id,
    required DateTime monthStart,
    required int number,
    required DateTime day,
    required int fixtureCount,
    required UserId? approvedBy,
  }) async {
    final result = await _connection.query(
      approveSql,
      parameters: {
        'id': id.value,
        'month': _isoDay(monthStart),
        'round_no': number,
        'day': _isoDay(day),
        'fixture_count': fixtureCount,
        'approved_by': approvedBy?.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<void>> withdraw(H2hRoundId roundId) async {
    final result = await _connection.query(
      withdrawSql,
      parameters: {'id': roundId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.err(
                AppError.validation('h2h.round_unknown', 'No such round'),
              )
            : const Result.ok(null),
    };
  }

  @override
  Future<Result<int>> lock({
    required H2hRoundId roundId,
    required DateTime day,
  }) {
    return _connection.runInTransaction<int>((tx) async {
      final frozen = await tx.query(
        freezeFixturesSql,
        parameters: {'round_id': roundId.value, 'day': _isoDay(day)},
      );
      if (frozen is Err<List<Map<String, dynamic>>>) {
        return Result.err(frozen.error);
      }
      final locked = await tx.query(
        lockSql,
        parameters: {'round_id': roundId.value},
      );
      if (locked is Err<List<Map<String, dynamic>>>) {
        return Result.err(locked.error);
      }
      final count = await tx.query(
        lockedCountSql,
        parameters: {'round_id': roundId.value},
      );
      if (count is Err<List<Map<String, dynamic>>>) {
        return Result.err(count.error);
      }
      final rows = (count as Ok<List<Map<String, dynamic>>>).value;
      return Result.ok(
        rows.isEmpty ? 0 : _int(rows.first['fixture_count']) ?? 0,
      );
    });
  }

  /// Maps the 0100 backstops to stable invariant codes.
  static AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    return switch (cause.constraintName) {
      'h2h_rounds_in_order' ||
      'h2h_rounds_month_round_uniq' => const AppError.invariant(
        'h2h.round_out_of_order',
        'A round must come after the last approved round of its month',
      ),
      'h2h_rounds_round_no_range' => const AppError.invariant(
        'h2h.round_not_eligible',
        'A month holds at most 19 rounds',
      ),
      'h2h_rounds_day_uniq' => const AppError.invariant(
        'h2h.round_day_taken',
        'This day is a round already',
      ),
      'h2h_rounds_withdraw_last' => const AppError.invariant(
        'h2h.round_not_last',
        'Only the last round of a month can be withdrawn',
      ),
      'h2h_rounds_withdraw_unlocked' => const AppError.invariant(
        'h2h.round_locked',
        'A round that started cannot be withdrawn',
      ),
      _ => error,
    };
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

  static AppError _corrupt() => const AppError.transient(
    'gamification.h2h_row_corrupt',
    'A stored head-to-head round row could not be read',
  );
}
