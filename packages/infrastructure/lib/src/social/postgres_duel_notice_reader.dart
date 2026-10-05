import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [DuelNoticeReader] (migrations 0090 and 0092): who
/// to tell about a duel event, with their push tokens and clock offset.
///
/// Tokens arrive joined into one string so no array is bound or decoded
/// (the same reason the score announcer passes ids as text). An FCM token
/// never contains a comma.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresDuelNoticeReader implements DuelNoticeReader {
  /// Creates the reader over [_connection].
  const PostgresDuelNoticeReader(this._connection);

  final PostgresConnection _connection;

  static const String _challengedSql = '''
SELECT c.target_user_id::text AS recipient_id,
       cp.user_id::text AS actor_id,
       COALESCE(cu.display_name, '') AS actor_name,
       c.code AS code,
       fs.home_team AS home_team,
       fs.away_team AS away_team,
       tu.utc_offset_minutes AS utc_offset_minutes,
       COALESCE((
         SELECT string_agg(dt.token, ',')
         FROM notification.device_tokens dt
         WHERE dt.user_id = c.target_user_id
       ), '') AS tokens
FROM social.duel_challenges c
JOIN competition.participants cp
  ON cp.id = c.challenger_participant_id
JOIN identity.users cu
  ON cu.id = cp.user_id
JOIN identity.users tu
  ON tu.id = c.target_user_id
JOIN competition.fixture_schedules fs
  ON fs.fixture_id = c.fixture_id
WHERE c.id = @challenge_id::uuid
''';

  static const String _acceptedSql = '''
SELECT cp.user_id::text AS recipient_id,
       op.user_id::text AS actor_id,
       COALESCE(ou.display_name, '') AS actor_name,
       c.code AS code,
       fs.home_team AS home_team,
       fs.away_team AS away_team,
       cu.utc_offset_minutes AS utc_offset_minutes,
       COALESCE((
         SELECT string_agg(dt.token, ',')
         FROM notification.device_tokens dt
         WHERE dt.user_id = cp.user_id
       ), '') AS tokens
FROM social.duels d
JOIN social.duel_challenges c
  ON c.id = d.challenge_id
JOIN competition.participants cp
  ON cp.id = d.challenger_participant_id
JOIN identity.users cu
  ON cu.id = cp.user_id
JOIN competition.participants op
  ON op.id = d.opponent_participant_id
JOIN identity.users ou
  ON ou.id = op.user_id
JOIN competition.fixture_schedules fs
  ON fs.fixture_id = d.fixture_id
WHERE d.id = @duel_id::uuid
''';

  @override
  Future<Result<DuelNotice?>> challengedNotice(
    DuelChallengeId challengeId,
  ) async {
    final result = await _connection.query(
      _challengedSql,
      parameters: {'challenge_id': challengeId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _map(value.first),
    };
  }

  @override
  Future<Result<DuelNotice?>> acceptedNotice(DuelId duelId) async {
    final result = await _connection.query(
      _acceptedSql,
      parameters: {'duel_id': duelId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _map(value.first),
    };
  }

  Result<DuelNotice?> _map(Map<String, dynamic> row) {
    final recipient = UserId.tryParse(row['recipient_id']?.toString());
    if (recipient is Err<UserId>) {
      return Result.err(_corrupt('recipient_id', recipient.error.message));
    }
    final actor = UserId.tryParse(row['actor_id']?.toString());
    if (actor is Err<UserId>) {
      return Result.err(_corrupt('actor_id', actor.error.message));
    }
    final actorName = row['actor_name'];
    final code = row['code'];
    final homeTeam = row['home_team'];
    final awayTeam = row['away_team'];
    final tokens = row['tokens'];
    if (actorName is! String ||
        code is! String ||
        homeTeam is! String ||
        awayTeam is! String ||
        tokens is! String) {
      return Result.err(_corrupt('text', 'not a string'));
    }
    final offset = row['utc_offset_minutes'];
    return Result.ok(
      DuelNotice(
        recipientUserId: (recipient as Ok<UserId>).value,
        actorUserId: (actor as Ok<UserId>).value,
        actorName: actorName,
        code: code,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        tokens: List<String>.unmodifiable(<String>[
          for (final String token in tokens.split(','))
            if (token.isNotEmpty) token,
        ]),
        utcOffsetMinutes: offset is int ? offset : null,
      ),
    );
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'social.row_corrupt',
    'Stored duel notice row has invalid $field: $detail',
  );
}
