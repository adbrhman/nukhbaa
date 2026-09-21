import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [PlayerBadgeReader] over `gamification.events`
/// (migration 0053, P2-8).
///
/// Two read-only statements, both bounded to one player by
/// `events_user_type_occurred_idx`: the counts, then the badges held. The
/// counts are the evaluator's (`PostgresBadgeProgressReader`) with the same
/// literals, narrowed to one user; without a `GROUP BY` the aggregate always
/// yields exactly one row, zeros for a player with no events. Nothing here
/// writes, updates or deletes.
///
/// Total (Application ADR, Section 2): never throws, binds the user through
/// a `@named` parameter (Security ADR, Section 2).
final class PostgresPlayerBadgeReader implements PlayerBadgeReader {
  /// Creates the reader over an open [PostgresConnection].
  const PostgresPlayerBadgeReader(this._connection);

  final PostgresConnection _connection;

  static const String _progressSql = '''
SELECT (count(*) FILTER (
         WHERE e.event_type = 'prediction_placed'
       ))::int AS predictions_placed,
       (count(*) FILTER (
         WHERE e.event_type = 'daily_challenge_completed'
       ))::int AS perfect_days,
       (count(*) FILTER (
         WHERE e.event_type = 'weekly_league_finished'
       ))::int AS weeks_finished,
       (count(*) FILTER (
         WHERE e.event_type = 'weekly_league_finished'
           AND e.payload->>'outcome' = 'promoted'
       ))::int AS promotions,
       (count(*) FILTER (
         WHERE e.event_type = 'weekly_league_finished'
           AND e.payload->>'rank' = '1'
           AND CASE
                 WHEN jsonb_typeof(e.payload->'points') = 'number'
                   THEN (e.payload->>'points')::numeric > 0
                 ELSE false
               END
       ))::int AS weeks_won,
       (count(*) FILTER (
         WHERE e.event_type = 'weekly_league_finished'
           AND e.payload->>'tier' = '5'
       ))::int AS elite_weeks
FROM gamification.events e
WHERE e.user_id = @user_id
''';

  static const String _unlockedSql = '''
SELECT e.payload->>'code' AS code,
       min(e.occurred_at) AS unlocked_at
FROM gamification.events e
WHERE e.user_id = @user_id
  AND e.event_type = 'badge_unlocked'
GROUP BY e.payload->>'code'
''';

  @override
  Future<Result<PlayerBadgeRecord>> recordOf(UserId userId) async {
    final progressResult = await _connection.query(
      _progressSql,
      parameters: {'user_id': userId.value},
    );
    if (progressResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(progressResult.error);
    }
    final progressRows =
        (progressResult as Ok<List<Map<String, dynamic>>>).value;

    final unlockedResult = await _connection.query(
      _unlockedSql,
      parameters: {'user_id': userId.value},
    );
    if (unlockedResult is Err<List<Map<String, dynamic>>>) {
      return Result.err(unlockedResult.error);
    }
    final unlockedRows =
        (unlockedResult as Ok<List<Map<String, dynamic>>>).value;

    final progress = progressRows.isEmpty
        ? const BadgeProgress()
        : _progressOf(progressRows.first);

    final unlockedAt = <BadgeCode, DateTime>{};
    for (final row in unlockedRows) {
      final code = BadgeCode.tryParse(row['code']?.toString().trim());
      if (code == null) {
        continue;
      }
      unlockedAt[code] = _timestamp(row['unlocked_at']);
    }

    return Result.ok(
      PlayerBadgeRecord(
        progress: progress,
        unlockedAt: Map<BadgeCode, DateTime>.unmodifiable(unlockedAt),
      ),
    );
  }

  static BadgeProgress _progressOf(Map<String, dynamic> row) => BadgeProgress(
    predictionsPlaced: _count(row['predictions_placed']),
    perfectDays: _count(row['perfect_days']),
    weeksFinished: _count(row['weeks_finished']),
    promotions: _count(row['promotions']),
    weeksWon: _count(row['weeks_won']),
    eliteWeeks: _count(row['elite_weeks']),
  );

  /// A count may arrive as an int or, under a text-codec projection, as a
  /// string. An unreadable one reads as zero: progress is understated, never
  /// overstated.
  static int _count(Object? raw) {
    if (raw is int) {
      return raw;
    }
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// A `timestamptz` arrives as a [DateTime]; a text codec would make it a
  /// string. A held badge stays held even when its moment cannot be read, so
  /// an unreadable one becomes the epoch rather than dropping the badge.
  static DateTime _timestamp(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    return DateTime.tryParse(raw?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}
