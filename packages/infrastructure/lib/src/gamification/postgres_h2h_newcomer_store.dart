import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_league_store.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_turn_keeper.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres adapter for [H2hNewcomerStore] (NK277, migration 0213).
///
/// **Who is new** ([newcomersSql]): a prediction made since the month was
/// drawn, on a match of the month that is neither hidden nor a test match
/// (read by kickoff, so the kickoff index bounds it), by a player with no
/// seat in the month whose account is neither suspended nor hidden.
///
/// **Seating** ([seat]) writes the seat (`h2h_league_members`), the record
/// that it was a new player (`h2h_newcomer_seatings`) and, for the
/// twentieth, the group's start (`h2h_group_starts`) in one transaction.
/// **Opening** ([openWaitingGroup]) writes the group, its waiting row and
/// its secret order of the turns (`PostgresH2hTurnKeeper.ensureIn`, before
/// any seat, as migration 0184 requires) in one transaction. The
/// database's refusals are returned as the invariant
/// `h2h.newcomer_refused`, a freeze by the owner as `h2h.newcomers_frozen`.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hNewcomerStore implements H2hNewcomerStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresH2hNewcomerStore(this._connection);

  final PostgresConnection _connection;

  /// The players who should join a month now, first prediction first.
  static const String newcomersSql = '''
SELECT p.user_id::text AS user_id, min(fp.submitted_at) AS first_at
FROM gamification.h2h_months mo
JOIN competition.fixture_schedules fs
  ON fs.kickoff_at >= mo.drawn_at
JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = fs.fixture_id AND fp.submitted_at >= mo.drawn_at
JOIN competition.participants p ON p.id = fp.participant_id
JOIN identity.users u
  ON u.id = p.user_id AND u.status <> 'suspended' AND u.hidden_at IS NULL
WHERE mo.month_start = @month::date
  AND NOT mo.is_pilot
  AND fs.hidden_at IS NULL
  AND NOT fs.is_test
  AND NOT EXISTS (
    SELECT 1 FROM gamification.h2h_league_members m
    WHERE m.month_start = mo.month_start AND m.user_id = p.user_id
  )
GROUP BY p.user_id
ORDER BY min(fp.submitted_at), p.user_id
''';

  /// The month's waiting group that has not started, with its seats taken.
  static const String waitingSql = '''
SELECT w.league_id::text AS league_id,
       l.group_index     AS group_index,
       (SELECT count(*) FROM gamification.h2h_league_members m
         WHERE m.league_id = w.league_id)::integer AS seated
FROM gamification.h2h_waiting_groups w
JOIN gamification.h2h_leagues l ON l.id = w.league_id
WHERE w.month_start = @month::date
  AND NOT EXISTS (
    SELECT 1 FROM gamification.h2h_group_starts s
    WHERE s.league_id = w.league_id
  )
ORDER BY l.group_index
LIMIT 1
''';

  /// The group index the month's next extra group takes.
  static const String nextIndexSql = '''
SELECT COALESCE(max(l.group_index) + 1, 0)::integer AS next_index
FROM gamification.h2h_leagues l
WHERE l.month_start = @month::date
  AND l.division = 2
''';

  /// The record that a seat was taken by a new player.
  static const String newcomerSql = '''
INSERT INTO gamification.h2h_newcomer_seatings
  (month_start, user_id, league_id)
VALUES (@month::date, @user_id::uuid, @league_id::uuid)
''';

  /// A waiting group's start, once it holds twenty players.
  static const String startSql = '''
INSERT INTO gamification.h2h_group_starts (league_id, from_round)
VALUES (@league_id::uuid, @from_round::smallint)
''';

  @override
  Future<Result<List<UserId>>> newcomersOf(DateTime monthStart) async {
    final result = await _connection.query(
      newcomersSql,
      parameters: {'month': _isoDay(monthStart)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final users = <UserId>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final user = UserId.tryParse(row['user_id']?.toString());
      if (user is Err<UserId>) {
        return Result.err(_corrupt('newcomer'));
      }
      users.add((user as Ok<UserId>).value);
    }
    return Result.ok(List<UserId>.unmodifiable(users));
  }

  @override
  Future<Result<H2hWaitingGroup?>> waitingGroupOf(DateTime monthStart) async {
    final result = await _connection.query(
      waitingSql,
      parameters: {'month': _isoDay(monthStart)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(null);
    }
    final id = H2hLeagueId.tryParse(rows.first['league_id']?.toString());
    final index = _int(rows.first['group_index']);
    final seated = _int(rows.first['seated']);
    if (id is Err<H2hLeagueId> || index == null || seated == null) {
      return Result.err(_corrupt('waiting group'));
    }
    return Result.ok(
      H2hWaitingGroup(
        leagueId: (id as Ok<H2hLeagueId>).value,
        groupIndex: index,
        seated: seated,
      ),
    );
  }

  @override
  Future<Result<int>> nextExtraIndexOf(DateTime monthStart) async {
    final result = await _connection.query(
      nextIndexSql,
      parameters: {'month': _isoDay(monthStart)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    return Result.ok(rows.isEmpty ? 0 : _int(rows.first['next_index']) ?? 0);
  }

  @override
  Future<Result<void>> openWaitingGroup({
    required DateTime monthStart,
    required H2hLeagueId leagueId,
    required int groupIndex,
  }) async {
    final month = _isoDay(monthStart);
    final result = await _connection.runInTransaction<void>((tx) async {
      final group = await tx.query(
        PostgresH2hLeagueStore.insertGroupSql,
        parameters: {
          'id': leagueId.value,
          'month': month,
          'division': H2hLeaguePolicy.extraDivision.level,
          'group_index': groupIndex,
          'capacity': H2hLeaguePolicy.groupCapacity,
        },
      );
      if (group is Err<List<Map<String, dynamic>>>) {
        return Result.err(group.error);
      }
      final waiting = await tx.query(
        PostgresH2hLeagueStore.insertWaitingSql,
        parameters: {'league_id': leagueId.value, 'month': month},
      );
      if (waiting is Err<List<Map<String, dynamic>>>) {
        return Result.err(waiting.error);
      }
      final turns = await PostgresH2hTurnKeeper.ensureIn(tx, monthStart);
      if (turns is Err<int>) {
        return Result.err(turns.error);
      }
      return const Result.ok(null);
    });
    return switch (result) {
      Ok<void>() => const Result.ok(null),
      Err<void>(:final error) => Result.err(_refusal(error)),
    };
  }

  @override
  Future<Result<void>> seat({
    required DateTime monthStart,
    required H2hLeagueId leagueId,
    required UserId userId,
    required int slot,
    int? startFrom,
  }) async {
    final month = _isoDay(monthStart);
    final result = await _connection.runInTransaction<void>((tx) async {
      final member = await tx.query(
        PostgresH2hLeagueStore.insertSeatSql,
        parameters: {
          'league_id': leagueId.value,
          'month': month,
          'user_id': userId.value,
          'slot': slot,
        },
      );
      if (member is Err<List<Map<String, dynamic>>>) {
        return Result.err(member.error);
      }
      final record = await tx.query(
        newcomerSql,
        parameters: {
          'month': month,
          'user_id': userId.value,
          'league_id': leagueId.value,
        },
      );
      if (record is Err<List<Map<String, dynamic>>>) {
        return Result.err(record.error);
      }
      if (startFrom != null) {
        final start = await tx.query(
          startSql,
          parameters: {'league_id': leagueId.value, 'from_round': startFrom},
        );
        if (start is Err<List<Map<String, dynamic>>>) {
          return Result.err(start.error);
        }
      }
      return const Result.ok(null);
    });
    return switch (result) {
      Ok<void>() => const Result.ok(null),
      Err<void>(:final error) => Result.err(_refusal(error)),
    };
  }

  /// The database's refusals of 0100 and 0213: one invariant code for the
  /// job, and the owner's freeze its own.
  static AppError _refusal(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final name = cause.constraintName ?? '';
    if (name == 'h2h_newcomers_frozen') {
      return const AppError.invariant(
        'h2h.newcomers_frozen',
        'New players are frozen by the owner',
      );
    }
    if (name.startsWith('h2h_')) {
      return AppError.invariant(
        'h2h.newcomer_refused',
        'The seat of a new player was refused: $name',
      );
    }
    return error;
  }

  static AppError _corrupt(String what) => AppError.transient(
    'gamification.h2h_row_corrupt',
    'A stored head-to-head $what row could not be read',
  );

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

  static String _isoDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
