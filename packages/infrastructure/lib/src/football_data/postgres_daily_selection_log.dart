import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// [DailySelectionLog] over `football_data.daily_selection_days` and
/// `football_data.daily_selection_candidates` (migration 0193, script 190).
///
/// One row per Riyadh day and one per match it looked at, replaced by every
/// run of the same day in one transaction, so the log holds the last choice
/// made for each day and why.
final class PostgresDailySelectionLog implements DailySelectionLog {
  /// Creates the log over an open [PostgresConnection].
  const PostgresDailySelectionLog(this._connection);

  final PostgresConnection _connection;

  static const String _daySql = '''
INSERT INTO football_data.daily_selection_days
  (riyadh_day, mode, base_count, target, busy, chosen, final_count, note,
   updated_at)
VALUES (@day::date, @mode::text, @base::integer, @target::integer,
        @busy::boolean, @chosen::integer, @final::integer, @note::text,
        @at::timestamptz)
ON CONFLICT (riyadh_day) DO UPDATE
SET mode = EXCLUDED.mode,
    base_count = EXCLUDED.base_count,
    target = EXCLUDED.target,
    busy = EXCLUDED.busy,
    chosen = EXCLUDED.chosen,
    final_count = EXCLUDED.final_count,
    note = EXCLUDED.note,
    updated_at = EXCLUDED.updated_at
''';

  static const String _clearSql = '''
DELETE FROM football_data.daily_selection_candidates
WHERE riyadh_day = @day::date
''';

  static const String _candidatesSql = '''
INSERT INTO football_data.daily_selection_candidates
  (riyadh_day, source, external_id, league_name, home_team, away_team,
   kickoff_at, score, reasons, decision)
SELECT @day::date, c.source, c.external_id, c.league_name, c.home_team,
       c.away_team, c.kickoff_at::timestamptz, nullif(c.score, '')::integer,
       c.reasons, c.decision
FROM unnest(@sources::text[], @external_ids::text[], @league_names::text[],
            @home_teams::text[], @away_teams::text[], @kickoffs::text[],
            @scores::text[], @reasons::text[], @decisions::text[])
  AS c(source, external_id, league_name, home_team, away_team, kickoff_at,
       score, reasons, decision)
ON CONFLICT (riyadh_day, source, external_id) DO NOTHING
''';

  @override
  Future<Result<void>> record({
    required DailySelectionDay day,
    required List<DailySelectionCandidate> candidates,
    required DateTime at,
  }) {
    final date = isoDay(day.day);
    return _connection.runInTransaction<void>((tx) async {
      final saved = await tx.query(
        _daySql,
        parameters: {
          'day': date,
          'mode': day.mode,
          'base': day.baseCount,
          'target': day.target,
          'busy': day.busy,
          'chosen': day.chosen,
          'final': day.finalCount,
          'note': day.note,
          'at': at.toUtc().toIso8601String(),
        },
      );
      if (saved is Err<List<Map<String, dynamic>>>) {
        return Result.err(saved.error);
      }
      final cleared = await tx.query(_clearSql, parameters: {'day': date});
      if (cleared is Err<List<Map<String, dynamic>>>) {
        return Result.err(cleared.error);
      }
      if (candidates.isEmpty) {
        return const Result.ok(null);
      }
      final inserted = await tx.query(
        _candidatesSql,
        parameters: {
          'day': date,
          'sources': [for (final c in candidates) c.source],
          'external_ids': [for (final c in candidates) c.externalId],
          'league_names': [for (final c in candidates) c.leagueName],
          'home_teams': [for (final c in candidates) c.homeTeam],
          'away_teams': [for (final c in candidates) c.awayTeam],
          'kickoffs': [
            for (final c in candidates) c.kickoffAt.toUtc().toIso8601String(),
          ],
          'scores': [for (final c in candidates) c.score?.toString() ?? ''],
          'reasons': [for (final c in candidates) c.reasons],
          'decisions': [for (final c in candidates) c.decision],
        },
      );
      return switch (inserted) {
        Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
        Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
      };
    });
  }
}
