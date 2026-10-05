import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [DuelReader] over migration 0090.
///
/// Reads `social.duel_challenges` and `social.duels` joined to the fixture
/// schedule, the players' names, their live predictions and their official
/// fixture scores. It masks nothing and decides nothing: the use-cases hide
/// the opponent's prediction before kickoff and derive every state.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresDuelReader implements DuelReader {
  /// Creates the reader over [_connection].
  const PostgresDuelReader(this._connection);

  final PostgresConnection _connection;

  static const String _challengeColumns = '''
SELECT c.id::text AS id,
       c.code AS code,
       c.season_id::text AS season_id,
       c.fixture_id::text AS fixture_id,
       fs.home_team AS home_team,
       fs.away_team AS away_team,
       fs.kickoff_at AS kickoff_at,
       cp.user_id::text AS challenger_user_id,
       COALESCE(cu.display_name, '') AS challenger_name,
       c.target_user_id::text AS target_user_id,
       c.capacity::int AS capacity,
       (
         SELECT count(*)
         FROM social.duels d
         WHERE d.challenge_id = c.id
       )::int AS accepted_count,
       c.status::text AS status,
       c.created_at AS created_at
FROM social.duel_challenges c
JOIN competition.participants cp
  ON cp.id = c.challenger_participant_id
JOIN identity.users cu
  ON cu.id = cp.user_id
JOIN competition.fixture_schedules fs
  ON fs.fixture_id = c.fixture_id
''';

  static const String _byCodeSql =
      '''
$_challengeColumns
WHERE c.code = @code::text
''';

  static const String _openForSql =
      '''
$_challengeColumns
WHERE c.status = 'open'
  AND fs.kickoff_at > @now::timestamptz
  AND (cp.user_id = @user_id::uuid OR c.target_user_id = @user_id::uuid)
  AND (
    SELECT count(*)
    FROM social.duels d
    WHERE d.challenge_id = c.id
  ) < c.capacity
ORDER BY fs.kickoff_at ASC, c.created_at ASC
LIMIT @limit::int
''';

  static const String _duelsSql = '''
WITH mine AS (
  SELECT d.id,
         d.challenge_id,
         d.fixture_id,
         d.accepted_at,
         (cp.user_id = @user_id::uuid) AS caller_is_challenger,
         CASE WHEN cp.user_id = @user_id::uuid
              THEN d.challenger_participant_id
              ELSE d.opponent_participant_id END AS my_participant_id,
         CASE WHEN cp.user_id = @user_id::uuid
              THEN d.opponent_participant_id
              ELSE d.challenger_participant_id END AS their_participant_id
  FROM social.duels d
  JOIN competition.participants cp
    ON cp.id = d.challenger_participant_id
  JOIN competition.participants op
    ON op.id = d.opponent_participant_id
  WHERE cp.user_id = @user_id::uuid
     OR op.user_id = @user_id::uuid
)
SELECT m.id::text AS id,
       m.challenge_id::text AS challenge_id,
       m.fixture_id::text AS fixture_id,
       fs.home_team AS home_team,
       fs.away_team AS away_team,
       fs.kickoff_at AS kickoff_at,
       m.accepted_at AS accepted_at,
       m.caller_is_challenger AS caller_is_challenger,
       tp.user_id::text AS opponent_user_id,
       COALESCE(tu.display_name, '') AS opponent_name,
       myp.home_goals AS my_home_goals,
       myp.away_goals AS my_away_goals,
       myp.is_double AS my_is_double,
       thp.home_goals AS their_home_goals,
       thp.away_goals AS their_away_goals,
       thp.is_double AS their_is_double,
       mys.grade AS my_grade,
       mys.points AS my_points,
       ths.grade AS their_grade,
       ths.points AS their_points
FROM mine m
JOIN competition.fixture_schedules fs
  ON fs.fixture_id = m.fixture_id
JOIN competition.participants tp
  ON tp.id = m.their_participant_id
JOIN identity.users tu
  ON tu.id = tp.user_id
LEFT JOIN prediction.fixture_predictions myp
  ON myp.fixture_id = m.fixture_id
 AND myp.participant_id = m.my_participant_id
LEFT JOIN prediction.fixture_predictions thp
  ON thp.fixture_id = m.fixture_id
 AND thp.participant_id = m.their_participant_id
LEFT JOIN scoring.fixture_scores mys
  ON mys.fixture_id = m.fixture_id
 AND mys.participant_id = m.my_participant_id
LEFT JOIN scoring.fixture_scores ths
  ON ths.fixture_id = m.fixture_id
 AND ths.participant_id = m.their_participant_id
WHERE fs.kickoff_at >= @since::timestamptz
ORDER BY fs.kickoff_at DESC, m.accepted_at DESC
LIMIT @limit::int
''';

  @override
  Future<Result<DuelChallengePreview?>> findChallengeByCode(
    DuelCode code,
  ) async {
    final result = await _connection.query(
      _byCodeSql,
      parameters: {'code': code.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapChallenge(value.first),
    };
  }

  @override
  Future<Result<List<DuelChallengePreview>>> listOpenChallengesFor({
    required UserId userId,
    required DateTime now,
    required int limit,
  }) async {
    final result = await _connection.query(
      _openForSql,
      parameters: {'user_id': userId.value, 'now': now.toUtc(), 'limit': limit},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final challenges = <DuelChallengePreview>[];
    for (final row in rows) {
      final mapped = _mapChallenge(row);
      if (mapped is Err<DuelChallengePreview>) {
        return Result.err(mapped.error);
      }
      challenges.add((mapped as Ok<DuelChallengePreview>).value);
    }
    return Result.ok(List<DuelChallengePreview>.unmodifiable(challenges));
  }

  @override
  Future<Result<List<DuelRecord>>> listDuelsFor({
    required UserId userId,
    required DateTime since,
    required int limit,
  }) async {
    final result = await _connection.query(
      _duelsSql,
      parameters: {
        'user_id': userId.value,
        'since': since.toUtc(),
        'limit': limit,
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final duels = <DuelRecord>[];
    for (final row in rows) {
      final mapped = _mapDuel(row);
      if (mapped is Err<DuelRecord>) {
        return Result.err(mapped.error);
      }
      duels.add((mapped as Ok<DuelRecord>).value);
    }
    return Result.ok(List<DuelRecord>.unmodifiable(duels));
  }

  Result<DuelChallengePreview> _mapChallenge(Map<String, dynamic> row) {
    final id = DuelChallengeId.tryParse(row['id']?.toString());
    if (id is Err<DuelChallengeId>) {
      return Result.err(_corrupt('id', id.error.message));
    }
    final code = DuelCode.tryParse(row['code']?.toString());
    if (code is Err<DuelCode>) {
      return Result.err(_corrupt('code', code.error.message));
    }
    final season = SeasonId.tryParse(row['season_id']?.toString());
    if (season is Err<SeasonId>) {
      return Result.err(_corrupt('season_id', season.error.message));
    }
    final fixture = FixtureRef.tryParse(row['fixture_id']?.toString());
    if (fixture is Err<FixtureRef>) {
      return Result.err(_corrupt('fixture_id', fixture.error.message));
    }
    final challenger = UserId.tryParse(row['challenger_user_id']?.toString());
    if (challenger is Err<UserId>) {
      return Result.err(
        _corrupt('challenger_user_id', challenger.error.message),
      );
    }
    final rawTarget = row['target_user_id'];
    UserId? target;
    if (rawTarget != null) {
      final parsed = UserId.tryParse(rawTarget.toString());
      if (parsed is Err<UserId>) {
        return Result.err(_corrupt('target_user_id', parsed.error.message));
      }
      target = (parsed as Ok<UserId>).value;
    }
    final status = DuelChallengeStatus.tryParse(row['status']?.toString());
    if (status is Err<DuelChallengeStatus>) {
      return Result.err(_corrupt('status', status.error.message));
    }
    final homeTeam = row['home_team'];
    final awayTeam = row['away_team'];
    final challengerName = row['challenger_name'];
    final capacity = row['capacity'];
    final accepted = row['accepted_count'];
    final kickoffAt = _readUtcTimestamp(row['kickoff_at']);
    final createdAt = _readUtcTimestamp(row['created_at']);
    if (homeTeam is! String || awayTeam is! String) {
      return Result.err(_corrupt('team', 'not a string'));
    }
    if (challengerName is! String) {
      return Result.err(_corrupt('challenger_name', 'not a string'));
    }
    if (capacity is! int || accepted is! int) {
      return Result.err(_corrupt('capacity', 'not an integer'));
    }
    if (kickoffAt == null || createdAt == null) {
      return Result.err(_corrupt('timestamp', 'not a timestamp'));
    }
    return Result.ok(
      DuelChallengePreview(
        challengeId: (id as Ok<DuelChallengeId>).value,
        code: (code as Ok<DuelCode>).value,
        seasonId: (season as Ok<SeasonId>).value,
        fixture: (fixture as Ok<FixtureRef>).value,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        kickoffAt: kickoffAt,
        challengerUserId: (challenger as Ok<UserId>).value,
        challengerName: challengerName,
        targetUserId: target,
        capacity: capacity,
        acceptedCount: accepted,
        status: (status as Ok<DuelChallengeStatus>).value,
        createdAt: createdAt,
      ),
    );
  }

  Result<DuelRecord> _mapDuel(Map<String, dynamic> row) {
    final id = DuelId.tryParse(row['id']?.toString());
    if (id is Err<DuelId>) {
      return Result.err(_corrupt('id', id.error.message));
    }
    final challenge = DuelChallengeId.tryParse(row['challenge_id']?.toString());
    if (challenge is Err<DuelChallengeId>) {
      return Result.err(_corrupt('challenge_id', challenge.error.message));
    }
    final fixture = FixtureRef.tryParse(row['fixture_id']?.toString());
    if (fixture is Err<FixtureRef>) {
      return Result.err(_corrupt('fixture_id', fixture.error.message));
    }
    final opponent = UserId.tryParse(row['opponent_user_id']?.toString());
    if (opponent is Err<UserId>) {
      return Result.err(_corrupt('opponent_user_id', opponent.error.message));
    }
    final homeTeam = row['home_team'];
    final awayTeam = row['away_team'];
    final opponentName = row['opponent_name'];
    final callerIsChallenger = row['caller_is_challenger'];
    final kickoffAt = _readUtcTimestamp(row['kickoff_at']);
    final acceptedAt = _readUtcTimestamp(row['accepted_at']);
    if (homeTeam is! String || awayTeam is! String) {
      return Result.err(_corrupt('team', 'not a string'));
    }
    if (opponentName is! String) {
      return Result.err(_corrupt('opponent_name', 'not a string'));
    }
    if (callerIsChallenger is! bool) {
      return Result.err(_corrupt('caller_is_challenger', 'not a boolean'));
    }
    if (kickoffAt == null || acceptedAt == null) {
      return Result.err(_corrupt('timestamp', 'not a timestamp'));
    }
    return Result.ok(
      DuelRecord(
        duelId: (id as Ok<DuelId>).value,
        challengeId: (challenge as Ok<DuelChallengeId>).value,
        fixture: (fixture as Ok<FixtureRef>).value,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        kickoffAt: kickoffAt,
        acceptedAt: acceptedAt,
        callerIsChallenger: callerIsChallenger,
        opponentUserId: (opponent as Ok<UserId>).value,
        opponentName: opponentName,
        myPick: _pick(
          row['my_home_goals'],
          row['my_away_goals'],
          row['my_is_double'],
        ),
        opponentPick: _pick(
          row['their_home_goals'],
          row['their_away_goals'],
          row['their_is_double'],
        ),
        myScore: _score(row['my_grade'], row['my_points']),
        opponentScore: _score(row['their_grade'], row['their_points']),
      ),
    );
  }

  /// A pick from its three nullable columns; null when the LEFT JOIN found
  /// no prediction row.
  static DuelPick? _pick(Object? home, Object? away, Object? isDouble) {
    if (home is! int || away is! int) {
      return null;
    }
    return DuelPick(
      homeGoals: home,
      awayGoals: away,
      isDouble: isDouble == true,
    );
  }

  /// A score from its two nullable columns; null when the LEFT JOIN found no
  /// score row.
  static DuelScore? _score(Object? grade, Object? points) {
    if (grade is! String || points is! int) {
      return null;
    }
    return DuelScore(grade: grade, points: points);
  }

  static DateTime? _readUtcTimestamp(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw is String) {
      return DateTime.tryParse(raw)?.toUtc();
    }
    return null;
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'social.row_corrupt',
    'Stored duel row has invalid $field: $detail',
  );
}
