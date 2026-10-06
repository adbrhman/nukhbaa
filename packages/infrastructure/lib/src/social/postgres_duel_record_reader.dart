import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [DuelRecordReader].
///
/// Nothing about a result is stored on a duel (0090): it is derived here
/// from both players' scores for the duel's fixture, like `ListMyDuels`
/// does for one player. `supabase/tests/duel_wins_query_test.sql` runs
/// [winsSql] against the real tables, with its parameter inlined.
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter.
final class PostgresDuelRecordReader implements DuelRecordReader {
  /// Creates the reader over an open [PostgresConnection].
  const PostgresDuelRecordReader(this._connection);

  final PostgresConnection _connection;

  /// Settled duels of the season -- both scores final -- and, per player,
  /// those where they scored more points than their opponent.
  static const String winsSql = '''
WITH settled AS (
  SELECT d.challenger_participant_id AS a,
         d.opponent_participant_id AS b,
         sa.points AS pa,
         sb.points AS pb
  FROM social.duels d
  JOIN social.duel_challenges c
    ON c.id = d.challenge_id
  JOIN scoring.fixture_scores sa
    ON sa.fixture_id = d.fixture_id
   AND sa.participant_id = d.challenger_participant_id
  JOIN scoring.fixture_scores sb
    ON sb.fixture_id = d.fixture_id
   AND sb.participant_id = d.opponent_participant_id
  WHERE c.season_id = @season_id::uuid
    AND sa.grade <> 'pending'
    AND sb.grade <> 'pending'
)
SELECT w.participant_id::text AS participant_id, count(*)::int AS wins
FROM (
  SELECT s.a AS participant_id FROM settled s WHERE s.pa > s.pb
  UNION ALL
  SELECT s.b AS participant_id FROM settled s WHERE s.pb > s.pa
) w
GROUP BY w.participant_id
''';

  @override
  Future<Result<Map<ParticipantId, int>>> winsInSeason(
    SeasonId seasonId,
  ) async {
    final result = await _connection.query(
      winsSql,
      parameters: {'season_id': seasonId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _map(value),
    };
  }

  Result<Map<ParticipantId, int>> _map(List<Map<String, dynamic>> rows) {
    final Map<ParticipantId, int> wins = {};
    for (final row in rows) {
      final participant = ParticipantId.tryParse(
        row['participant_id']?.toString(),
      );
      if (participant is Err<ParticipantId>) {
        return Result.err(
          _corrupt('participant_id', participant.error.message),
        );
      }
      final Object? count = row['wins'];
      if (count is! int || count < 1) {
        return Result.err(_corrupt('wins', 'not a positive integer'));
      }
      wins[(participant as Ok<ParticipantId>).value] = count;
    }
    return Result.ok(wins);
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'social.duel_wins_row_corrupt',
    'duel wins.$field is corrupt: $detail',
  );
}
