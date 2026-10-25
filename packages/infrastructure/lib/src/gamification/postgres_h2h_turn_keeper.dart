import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [H2hTurnKeeper] over `gamification.h2h_league_turns`
/// (migration 0184).
///
/// [ensureSql] gives every group of a month without an order one: the
/// turns 1 .. capacity - 1 shuffled by `gen_random_uuid()` in the database,
/// so the order never passes through the server's memory or a log. A group
/// whose member was seated before a round of its month locked is left out,
/// as 0184's trigger would refuse it. The draw and the extra groups run the
/// same statement in the transaction that opens their groups ([ensureIn]).
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hTurnKeeper implements H2hTurnKeeper {
  /// Creates the keeper over an open [PostgresConnection].
  const PostgresH2hTurnKeeper(this._connection);

  final PostgresConnection _connection;

  /// Gives the groups of month `@month` that may take one their order.
  static const String ensureSql = '''
INSERT INTO gamification.h2h_league_turns (league_id, turns)
SELECT l.id,
       ARRAY(
         SELECT g::smallint
         FROM generate_series(1, l.capacity - 1) AS g
         ORDER BY gen_random_uuid()
       )
FROM gamification.h2h_leagues l
WHERE l.month_start = @month::date
  AND NOT EXISTS (
    SELECT 1 FROM gamification.h2h_league_turns t WHERE t.league_id = l.id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM gamification.h2h_league_members m
    JOIN gamification.h2h_rounds r ON r.month_start = l.month_start
    JOIN gamification.h2h_round_locks k ON k.round_id = r.id
    WHERE m.league_id = l.id
      AND m.joined_at <= k.locked_at
  )
ON CONFLICT (league_id) DO NOTHING
RETURNING league_id::text AS league_id
''';

  /// Runs [ensureSql] for the month opened by [monthStart] on [executor]:
  /// the connection, or the transaction that has just opened groups.
  static Future<Result<int>> ensureIn(
    DbExecutor executor,
    DateTime monthStart,
  ) async {
    final result = await executor.query(
      ensureSql,
      parameters: {'month': _isoDay(monthStart)},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(value.length),
    };
  }

  @override
  Future<Result<int>> ensureTurns(DateTime monthStart) =>
      ensureIn(_connection, monthStart);

  static String _isoDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
