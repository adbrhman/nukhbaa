import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [PreMatchReminderRepository] (migrations 0024, 0039,
/// 0055, 0063, 0065, 0066).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter, and speaks only in application types.
final class PostgresPreMatchReminderRepository
    implements PreMatchReminderRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresPreMatchReminderRepository(this._connection);

  final PostgresConnection _connection;

  // A fixture in the window, a follower of either side who is an active
  // participant of a season owning it, has not predicted it and was not
  // pushed about it; then one row per device. A fixture whose team ids are
  // still NULL matches no follower. DISTINCT folds a user who follows both
  // sides, or sits in two seasons that share the fixture, into one target.
  static const String _dueSql = '''
WITH window_fixtures AS (
  SELECT fs.fixture_id, fs.home_team, fs.away_team,
         fs.home_team_id, fs.away_team_id
  FROM competition.fixture_schedules fs
  WHERE fs.kickoff_at > @from
    AND fs.kickoff_at <= @to
),
due AS (
  SELECT DISTINCT p.user_id, wf.fixture_id, wf.home_team, wf.away_team
  FROM window_fixtures wf
  JOIN identity.user_favorite_teams uft
    ON uft.team_id IN (wf.home_team_id, wf.away_team_id)
  JOIN competition.season_fixtures sf ON sf.fixture_id = wf.fixture_id
  JOIN competition.participants p
    ON p.season_id = sf.season_id
   AND p.user_id = uft.user_id
   AND p.status = 'active'
  WHERE NOT EXISTS (
      SELECT 1
      FROM prediction.fixture_predictions fp
      WHERE fp.participant_id = p.id
        AND fp.fixture_id = wf.fixture_id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM notification.proactive_sends ps
      WHERE ps.user_id = p.user_id
        AND ps.kind = 'pre_match'
        AND ps.ref_id = wf.fixture_id
    )
)
SELECT due.user_id::text AS user_id,
       due.fixture_id::text AS fixture_id,
       due.home_team AS home_team,
       due.away_team AS away_team,
       dt.token AS token,
       u.utc_offset_minutes AS utc_offset_minutes,
       COALESCE(np.pre_match, true) AS pre_match
FROM due
JOIN notification.device_tokens dt ON dt.user_id = due.user_id
JOIN identity.users u ON u.id = due.user_id
LEFT JOIN notification.notification_preferences np
  ON np.user_id = due.user_id
ORDER BY due.user_id, due.fixture_id
''';

  static const String _markSentSql = '''
INSERT INTO notification.proactive_sends
  (user_id, kind, ref_id, send_date, sent_at)
VALUES (@user_id, 'pre_match', @fixture_id, @send_date::date, @sent_at)
ON CONFLICT ON CONSTRAINT proactive_sends_pkey DO NOTHING
''';

  static const String _forgetTokenSql = '''
DELETE FROM notification.device_tokens
WHERE token = @token
''';

  @override
  Future<Result<List<PreMatchTarget>>> dueTargets({
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _connection.query(
      _dueSql,
      parameters: {'from': from.toUtc(), 'to': to.toUtc()},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _targets(value),
    };
  }

  static Result<List<PreMatchTarget>> _targets(
    List<Map<String, dynamic>> rows,
  ) {
    final order = <String>[];
    final tokens = <String, List<String>>{};
    final first = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final userId = row['user_id'];
      final fixtureId = row['fixture_id'];
      final token = row['token'];
      final home = row['home_team'];
      final away = row['away_team'];
      final optedIn = row['pre_match'];
      final offset = row['utc_offset_minutes'];
      if (userId is! String ||
          fixtureId is! String ||
          token is! String ||
          home is! String ||
          away is! String ||
          optedIn is! bool ||
          (offset != null && offset is! int)) {
        return const Result.err(
          AppError.transient(
            'pre_match.row_corrupt',
            'a pre-match target row had unexpected column types',
          ),
        );
      }
      final key = '$userId/$fixtureId';
      if (!first.containsKey(key)) {
        order.add(key);
        first[key] = row;
      }
      tokens.putIfAbsent(key, () => <String>[]).add(token);
    }

    final targets = <PreMatchTarget>[];
    for (final key in order) {
      final row = first[key]!;
      final user = UserId.tryParse(row['user_id'] as String);
      final fixture = FixtureRef.tryParse(row['fixture_id'] as String);
      if (user is Err<UserId>) {
        return Result.err(user.error);
      }
      if (fixture is Err<FixtureRef>) {
        return Result.err(fixture.error);
      }
      final offset = row['utc_offset_minutes'];
      targets.add(
        PreMatchTarget(
          userId: (user as Ok<UserId>).value,
          fixtureId: (fixture as Ok<FixtureRef>).value,
          homeTeam: row['home_team'] as String,
          awayTeam: row['away_team'] as String,
          tokens: List<String>.unmodifiable(tokens[key]!),
          optedIn: row['pre_match'] as bool,
          utcOffsetMinutes: offset is int ? offset : null,
        ),
      );
    }
    return Result.ok(targets);
  }

  @override
  Future<Result<void>> markSent({
    required PreMatchTarget target,
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
