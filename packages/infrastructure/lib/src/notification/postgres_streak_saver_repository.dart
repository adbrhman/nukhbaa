import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [StreakSaverRepository] (migrations 0039, 0055, 0063,
/// 0066).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter, and speaks only in application types.
final class PostgresStreakSaverRepository implements StreakSaverRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresStreakSaverRepository(this._connection);

  final PostgresConnection _connection;

  // Today's unpredicted fixtures per user, over the seasons they are active
  // in; the earliest of them decides whether the day can still be saved.
  // A day whose first gap already kicked off has its earliest gap in the
  // past, outside the window, and is never selected.
  static const String _dueSql = '''
WITH open_fixtures AS (
  SELECT p.user_id, fs.fixture_id, fs.kickoff_at
  FROM competition.participants p
  JOIN competition.season_fixtures sf ON sf.season_id = p.season_id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = sf.fixture_id
  WHERE p.status = 'active'
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = @today::date
    AND NOT EXISTS (
      SELECT 1
      FROM prediction.fixture_predictions fp
      WHERE fp.participant_id = p.id
        AND fp.fixture_id = fs.fixture_id
    )
),
first_open AS (
  SELECT DISTINCT ON (user_id) user_id, fixture_id, kickoff_at
  FROM open_fixtures
  ORDER BY user_id, kickoff_at, fixture_id
)
SELECT fo.user_id::text AS user_id,
       fo.fixture_id::text AS fixture_id,
       dt.token AS token,
       u.utc_offset_minutes AS utc_offset_minutes,
       COALESCE(np.streak_saver, true) AS streak_saver
FROM first_open fo
JOIN notification.device_tokens dt ON dt.user_id = fo.user_id
JOIN identity.users u ON u.id = fo.user_id
LEFT JOIN notification.notification_preferences np
  ON np.user_id = fo.user_id
WHERE fo.kickoff_at > @from
  AND fo.kickoff_at <= @to
  AND NOT EXISTS (
    SELECT 1
    FROM notification.proactive_sends ps
    WHERE ps.user_id = fo.user_id
      AND ps.kind = 'streak_saver'
      AND ps.send_date = @today::date
  )
ORDER BY fo.user_id
''';

  static const String _markSentSql = '''
INSERT INTO notification.proactive_sends
  (user_id, kind, ref_id, send_date, sent_at)
VALUES (@user_id, 'streak_saver', @fixture_id, @send_date::date, @sent_at)
ON CONFLICT ON CONSTRAINT proactive_sends_pkey DO NOTHING
''';

  static const String _forgetTokenSql = '''
DELETE FROM notification.device_tokens
WHERE token = @token
''';

  @override
  Future<Result<List<StreakSaverTarget>>> dueTargets({
    required String today,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _connection.query(
      _dueSql,
      parameters: {'today': today, 'from': from.toUtc(), 'to': to.toUtc()},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _targets(value),
    };
  }

  static Result<List<StreakSaverTarget>> _targets(
    List<Map<String, dynamic>> rows,
  ) {
    final order = <String>[];
    final tokens = <String, List<String>>{};
    final first = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final userId = row['user_id'];
      final fixtureId = row['fixture_id'];
      final token = row['token'];
      final optedIn = row['streak_saver'];
      final offset = row['utc_offset_minutes'];
      if (userId is! String ||
          fixtureId is! String ||
          token is! String ||
          optedIn is! bool ||
          (offset != null && offset is! int)) {
        return const Result.err(
          AppError.transient(
            'streak_saver.row_corrupt',
            'a streak-saver target row had unexpected column types',
          ),
        );
      }
      if (!first.containsKey(userId)) {
        order.add(userId);
        first[userId] = row;
      }
      tokens.putIfAbsent(userId, () => <String>[]).add(token);
    }

    final targets = <StreakSaverTarget>[];
    for (final key in order) {
      final row = first[key]!;
      final user = UserId.tryParse(key);
      final fixture = FixtureRef.tryParse(row['fixture_id'] as String);
      if (user is Err<UserId>) {
        return Result.err(user.error);
      }
      if (fixture is Err<FixtureRef>) {
        return Result.err(fixture.error);
      }
      final offset = row['utc_offset_minutes'];
      targets.add(
        StreakSaverTarget(
          userId: (user as Ok<UserId>).value,
          fixtureId: (fixture as Ok<FixtureRef>).value,
          tokens: List<String>.unmodifiable(tokens[key]!),
          optedIn: row['streak_saver'] as bool,
          utcOffsetMinutes: offset is int ? offset : null,
        ),
      );
    }
    return Result.ok(targets);
  }

  @override
  Future<Result<void>> markSent({
    required StreakSaverTarget target,
    required String sendDate,
    required DateTime now,
  }) async {
    final result = await _connection.query(
      _markSentSql,
      parameters: {
        'user_id': target.userId.value,
        'fixture_id': target.fixtureId.value,
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
