import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [BadgeProgressReader] over `gamification.events`
/// (migration 0053, P2-6).
///
/// One read-only statement: the stream grouped by player, with each count a
/// `FILTER` over the event type. The index `events_user_type_occurred_idx`
/// exists for exactly this read. Nothing here writes, updates or deletes.
///
/// The event types, the outcome and the top tier are written as literals, and
/// the adapter's test pins each one to the domain constant it mirrors, so a
/// renamed wire value cannot silently make a badge unearnable.
///
/// A first place counts only on more than zero points; the guard is a `CASE`
/// so the cast to a number is never evaluated on a payload that is not one.
///
/// Total (Application ADR, Section 2): never throws.
final class PostgresBadgeProgressReader implements BadgeProgressReader {
  /// Creates the reader over an open [PostgresConnection].
  const PostgresBadgeProgressReader(this._connection);

  final PostgresConnection _connection;

  static const String _readAllSql = '''
SELECT e.user_id::text AS user_id,
       (count(*) FILTER (
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
       ))::int AS elite_weeks,
       string_agg(e.payload->>'code', ',') FILTER (
         WHERE e.event_type = 'badge_unlocked'
       ) AS unlocked_codes
FROM gamification.events e
GROUP BY e.user_id
ORDER BY e.user_id
''';

  @override
  Future<Result<List<UserBadgeStanding>>> readAll() async {
    final result = await _connection.query(_readAllSql);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;

    final standings = <UserBadgeStanding>[];
    for (final row in rows) {
      final idResult = UserId.tryParse(row['user_id']?.toString());
      if (idResult is Err<UserId>) {
        return Result.err(idResult.error);
      }
      standings.add(
        UserBadgeStanding(
          userId: (idResult as Ok<UserId>).value,
          progress: BadgeProgress(
            predictionsPlaced: _count(row['predictions_placed']),
            perfectDays: _count(row['perfect_days']),
            weeksFinished: _count(row['weeks_finished']),
            promotions: _count(row['promotions']),
            weeksWon: _count(row['weeks_won']),
            eliteWeeks: _count(row['elite_weeks']),
          ),
          unlocked: _codes(row['unlocked_codes']),
        ),
      );
    }
    return Result.ok(List<UserBadgeStanding>.unmodifiable(standings));
  }

  /// A count may arrive as an int or, under a text-codec projection, as a
  /// string. An unreadable one reads as zero: a badge is under-awarded and
  /// caught up on a later run, never granted on a number that was not read.
  static int _count(Object? raw) {
    if (raw is int) {
      return raw;
    }
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// The catalog badges named in the comma-joined [raw] codes. A code the
  /// catalog no longer knows is skipped.
  static Set<BadgeCode> _codes(Object? raw) {
    final codes = <BadgeCode>{};
    for (final part in (raw?.toString() ?? '').split(',')) {
      final code = BadgeCode.tryParse(part.trim());
      if (code != null) {
        codes.add(code);
      }
    }
    return codes;
  }
}
