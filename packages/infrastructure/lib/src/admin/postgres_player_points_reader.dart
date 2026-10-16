import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [PlayerPointsReader] (batch 146b): one read of the
/// player's participation in the month and every movement of the fixture
/// ledger, with each match's sides. No row: he never played in the month;
/// one row without an entry: he played and moved no points yet. Checked
/// against the schema by `supabase/tests/player_points_query_test.sql`;
/// keep the two identical.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresPlayerPointsReader implements PlayerPointsReader {
  /// Creates the reader over [_connection].
  const PostgresPlayerPointsReader(this._connection);

  final PostgresConnection _connection;

  /// The read.
  static const String pointsSql = '''
SELECT p.id::text AS participant_id,
       e.id::text AS id,
       e.fixture_id::text AS fixture_id,
       s.home_team AS home_team,
       s.away_team AS away_team,
       e.entry_kind::text AS kind,
       e.amount AS amount,
       e.occurred_at AS occurred_at
FROM competition.participants p
LEFT JOIN ledger.fixture_point_entries e ON e.participant_id = p.id
LEFT JOIN competition.fixture_schedules s ON s.fixture_id = e.fixture_id
WHERE p.user_id = @user_id::uuid
  AND p.season_id = @season_id::uuid
ORDER BY e.occurred_at, e.id
''';

  @override
  Future<Result<PlayerMonthPoints>> pointsOf({
    required UserId user,
    required SeasonId season,
  }) async {
    final result = await _connection.query(
      pointsSql,
      parameters: {'user_id': user.value, 'season_id': season.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(
        PlayerMonthPoints(participantId: null, entries: <PlayerPointEntry>[]),
      );
    }
    final List<PlayerPointEntry> entries = <PlayerPointEntry>[];
    for (final Map<String, dynamic> row in rows) {
      final Object? id = row['id'];
      if (id is! String) continue; // played, no movement yet
      final DateTime? at = switch (row['occurred_at']) {
        final DateTime t => t.toUtc(),
        final String t => DateTime.tryParse(t)?.toUtc(),
        _ => null,
      };
      final Object? amount = row['amount'];
      if (at == null || amount is! num) {
        return const Result.err(
          AppError.transient(
            'storage.corrupt_row',
            'A fixture point entry could not be read',
          ),
        );
      }
      entries.add(
        PlayerPointEntry(
          id: id,
          fixtureId: row['fixture_id']?.toString() ?? '',
          homeTeam: row['home_team'] as String?,
          awayTeam: row['away_team'] as String?,
          kind: row['kind']?.toString() ?? '',
          amount: amount.toInt(),
          occurredAt: at,
        ),
      );
    }
    return Result.ok(
      PlayerMonthPoints(
        participantId: rows.first['participant_id']?.toString(),
        entries: List<PlayerPointEntry>.unmodifiable(entries),
      ),
    );
  }
}
