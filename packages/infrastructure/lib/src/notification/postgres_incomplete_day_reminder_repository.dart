import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [IncompleteDayReminderRepository] (migrations 0039, 0055,
/// 0063, 0106).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter, and speaks only in application types.
final class PostgresIncompleteDayReminderRepository
    implements IncompleteDayReminderRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresIncompleteDayReminderRepository(this._connection);

  final PostgresConnection _connection;

  // Today's matches per player, over the seasons they are active in, each
  // with whether the player predicted it. A player is due when they
  // predicted at least one, still have one to predict that kicks off after
  // @now, the earliest of those kicks off in (@from, @to], and they were not
  // pushed today. Checked against a seeded Postgres 16 before batch 117:
  // none predicted, all predicted, the first gap later than the window,
  // already pushed today and no device all stay out; a gap that already
  // kicked off is not counted.
  static const String _dueSql = '''
WITH day_fixtures AS (
  SELECT p.user_id,
         fs.fixture_id,
         fs.kickoff_at,
         EXISTS (
           SELECT 1
           FROM prediction.fixture_predictions fp
           WHERE fp.participant_id = p.id
             AND fp.fixture_id = fs.fixture_id
         ) AS predicted
  FROM competition.participants p
  JOIN competition.season_fixtures sf ON sf.season_id = p.season_id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = sf.fixture_id
  WHERE p.status = 'active'
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = @today::date
    AND fs.hidden_at IS NULL
    AND NOT fs.is_test
),
per_user AS (
  SELECT user_id,
         bool_or(predicted) AS predicted_any,
         COUNT(DISTINCT fixture_id)
           FILTER (WHERE NOT predicted AND kickoff_at > @now) AS remaining,
         MIN(kickoff_at)
           FILTER (WHERE NOT predicted AND kickoff_at > @now) AS next_open
  FROM day_fixtures
  GROUP BY user_id
)
SELECT pu.user_id::text AS user_id,
       pu.remaining::int AS remaining,
       dt.token AS token,
       u.utc_offset_minutes AS utc_offset_minutes,
       COALESCE(np.prediction_reminder, true) AS prediction_reminder
FROM per_user pu
JOIN notification.device_tokens dt ON dt.user_id = pu.user_id
JOIN identity.users u ON u.id = pu.user_id
LEFT JOIN notification.notification_preferences np
  ON np.user_id = pu.user_id
WHERE pu.predicted_any
  AND pu.remaining > 0
  AND pu.next_open > @from
  AND pu.next_open <= @to
  AND NOT EXISTS (
    SELECT 1
    FROM notification.incomplete_day_sends s
    WHERE s.user_id = pu.user_id
      AND s.send_date = @today::date
  )
ORDER BY pu.user_id, dt.token
''';

  static const String _markSentSql = '''
INSERT INTO notification.incomplete_day_sends (user_id, send_date, sent_at)
VALUES (@user_id, @send_date::date, @sent_at)
ON CONFLICT ON CONSTRAINT incomplete_day_sends_pkey DO NOTHING
''';

  static const String _forgetTokenSql = '''
DELETE FROM notification.device_tokens
WHERE token = @token
''';

  @override
  Future<Result<List<IncompleteDayTarget>>> dueTargets({
    required String today,
    required DateTime now,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _connection.query(
      _dueSql,
      parameters: {
        'today': today,
        'now': now.toUtc(),
        'from': from.toUtc(),
        'to': to.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _targets(value),
    };
  }

  // One row per (player, token); the query orders by player, so the
  // grouping below keeps the players in order.
  static Result<List<IncompleteDayTarget>> _targets(
    List<Map<String, dynamic>> rows,
  ) {
    final order = <String>[];
    final tokens = <String, List<String>>{};
    final first = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final userId = row['user_id'];
      final remaining = row['remaining'];
      final token = row['token'];
      final optedIn = row['prediction_reminder'];
      final offset = row['utc_offset_minutes'];
      if (userId is! String ||
          remaining is! int ||
          token is! String ||
          optedIn is! bool ||
          (offset != null && offset is! int)) {
        return const Result.err(
          AppError.transient(
            'incomplete_day.row_corrupt',
            'an incomplete-day target row had unexpected column types',
          ),
        );
      }
      if (!first.containsKey(userId)) {
        order.add(userId);
        first[userId] = row;
      }
      tokens.putIfAbsent(userId, () => <String>[]).add(token);
    }

    final targets = <IncompleteDayTarget>[];
    for (final key in order) {
      final row = first[key]!;
      final user = UserId.tryParse(key);
      if (user is Err<UserId>) {
        return Result.err(user.error);
      }
      final offset = row['utc_offset_minutes'];
      targets.add(
        IncompleteDayTarget(
          userId: (user as Ok<UserId>).value,
          tokens: List<String>.unmodifiable(tokens[key]!),
          remaining: row['remaining'] as int,
          optedIn: row['prediction_reminder'] as bool,
          utcOffsetMinutes: offset is int ? offset : null,
        ),
      );
    }
    return Result.ok(targets);
  }

  @override
  Future<Result<void>> markSent({
    required UserId userId,
    required String sendDate,
    required DateTime now,
  }) async {
    final result = await _connection.query(
      _markSentSql,
      parameters: {
        'user_id': userId.value,
        'send_date': sendDate,
        'sent_at': now.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) async {
    for (final token in tokens) {
      final result = await _connection.query(
        _forgetTokenSql,
        parameters: {'token': token},
      );
      if (result is Err<List<Map<String, dynamic>>>) {
        return Result.err(result.error);
      }
    }
    return const Result.ok(null);
  }
}
