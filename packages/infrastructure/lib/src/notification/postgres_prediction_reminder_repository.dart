import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [PredictionReminderRepository] (migrations 0039, 0040).
///
/// Total (Application ADR §2): never throws, binds every value through a
/// `@named` parameter, and speaks only in domain types.
final class PostgresPredictionReminderRepository
    implements PredictionReminderRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresPredictionReminderRepository(this._connection);

  final PostgresConnection _connection;

  // Only fixtures LINKED to a season count: an admin-ingested schedule row
  // nobody can predict on is not part of anyone's day.
  static const String _firstKickoffSql = '''
SELECT MIN(fs.kickoff_at) AS first_kickoff
FROM competition.fixture_schedules fs
JOIN competition.season_fixtures sf ON sf.fixture_id = fs.fixture_id
WHERE fs.kickoff_at >= @window_start
  AND fs.kickoff_at <  @window_end
''';

  // A user is due when they are an active participant of a season that has a
  // fixture today AND have predicted none of today's fixtures AND have not
  // been reminded today AND own a device. The join to device_tokens at the end
  // is what makes "has a device" part of the definition rather than an
  // afterthought.
  static const String _pendingSql = '''
WITH day_fixtures AS (
  SELECT DISTINCT sf.season_id, sf.fixture_id
  FROM competition.season_fixtures sf
  JOIN competition.fixture_schedules fs ON fs.fixture_id = sf.fixture_id
  WHERE fs.kickoff_at >= @window_start
    AND fs.kickoff_at <  @window_end
),
due AS (
  SELECT DISTINCT p.user_id
  FROM competition.participants p
  JOIN day_fixtures df ON df.season_id = p.season_id
  WHERE p.status = 'active'
    AND NOT EXISTS (
      SELECT 1
      FROM prediction.fixture_predictions fp
      WHERE fp.participant_id = p.id
        AND fp.fixture_id IN (SELECT fixture_id FROM day_fixtures)
    )
    AND NOT EXISTS (
      SELECT 1
      FROM notification.reminder_sends rs
      WHERE rs.user_id = p.user_id
        AND rs.reminder_date = @reminder_date::date
    )
)
SELECT due.user_id AS user_id, dt.token AS token
FROM due
JOIN notification.device_tokens dt ON dt.user_id = due.user_id
ORDER BY due.user_id
''';

  static const String _markSentSql = '''
INSERT INTO notification.reminder_sends (user_id, reminder_date, sent_at)
VALUES (@user_id, @reminder_date::date, @sent_at)
ON CONFLICT ON CONSTRAINT reminder_sends_pkey DO NOTHING
''';

  static const String _forgetTokenSql = '''
DELETE FROM notification.device_tokens
WHERE token = @token
''';

  @override
  Future<Result<DateTime?>> firstKickoffInWindow({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final result = await _connection.query(
      _firstKickoffSql,
      parameters: {
        'window_start': windowStart.toUtc(),
        'window_end': windowEnd.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _firstKickoff(value),
    };
  }

  Result<DateTime?> _firstKickoff(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Result.ok(null);
    }
    final raw = rows.first['first_kickoff'];
    if (raw == null) {
      return const Result.ok(null);
    }
    if (raw is! DateTime) {
      return const Result.err(
        AppError.transient(
          'reminder.row_corrupt',
          'first_kickoff was not a timestamp',
        ),
      );
    }
    return Result.ok(raw.toUtc());
  }

  @override
  Future<Result<List<ReminderTarget>>> pendingTargets({
    required DateTime windowStart,
    required DateTime windowEnd,
    required String reminderDate,
  }) async {
    final result = await _connection.query(
      _pendingSql,
      parameters: {
        'window_start': windowStart.toUtc(),
        'window_end': windowEnd.toUtc(),
        'reminder_date': reminderDate,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _targets(value),
    };
  }

  // One row per (user, token); the query orders by user so the grouping below
  // is a single pass.
  Result<List<ReminderTarget>> _targets(List<Map<String, dynamic>> rows) {
    final byUser = <String, List<String>>{};
    for (final row in rows) {
      final userId = row['user_id'];
      final token = row['token'];
      if (userId is! String || token is! String) {
        return const Result.err(
          AppError.transient(
            'reminder.row_corrupt',
            'a reminder target row had unexpected column types',
          ),
        );
      }
      byUser.putIfAbsent(userId, () => <String>[]).add(token);
    }

    final targets = <ReminderTarget>[];
    for (final entry in byUser.entries) {
      final parsed = UserId.tryParse(entry.key);
      if (parsed is Err<UserId>) {
        return Result.err(parsed.error);
      }
      targets.add(
        ReminderTarget(
          userId: (parsed as Ok<UserId>).value,
          tokens: entry.value,
        ),
      );
    }
    return Result.ok(targets);
  }

  @override
  Future<Result<void>> markSent({
    required List<UserId> userIds,
    required String reminderDate,
    required DateTime now,
  }) async {
    // One statement per user rather than an array parameter: the audience is
    // small, and a `uuid[]` cast has bitten this codebase before.
    for (final userId in userIds) {
      final result = await _connection.query(
        _markSentSql,
        parameters: {
          'user_id': userId.value,
          'reminder_date': reminderDate,
          'sent_at': now.toUtc(),
        },
      );
      if (result is Err<List<Map<String, dynamic>>>) {
        return Result.err(result.error);
      }
    }
    return const Result<void>.ok(null);
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
    return const Result<void>.ok(null);
  }
}
