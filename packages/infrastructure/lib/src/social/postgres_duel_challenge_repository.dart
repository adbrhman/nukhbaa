import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres adapter for [DuelChallengeRepository] (migration 0090).
///
/// Every rule lives in the 0090 database functions: the 30-minute lead time,
/// the ten-pending cap, capacity, private targets, the row lock on accept,
/// the one-duel-per-pair rule and the two-predictions requirement. This
/// adapter binds values, calls those functions, reads the stored row back
/// and maps the raised constraint names to stable [AppError] codes. It
/// decides nothing.
///
/// Create and accept run the function and the read-back in one
/// transaction, so a failed read-back never leaves a challenge or a duel the
/// caller was told did not happen.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresDuelChallengeRepository implements DuelChallengeRepository {
  /// Creates the repository over [_connection].
  const PostgresDuelChallengeRepository(this._connection);

  final PostgresConnection _connection;

  // The 0090 function takes the challenger's user id; the port carries the
  // season participant, so the user id is resolved from that participant in
  // the same statement. An unknown participant resolves to NULL and the
  // function refuses it as duel_challenger_not_participant.
  static const String _createSql = '''
SELECT social.create_duel_challenge(
  (
    SELECT p.user_id
    FROM competition.participants p
    WHERE p.id = @challenger_participant_id::uuid
      AND p.season_id = @season_id::uuid
  ),
  @season_id::uuid,
  @fixture_id::uuid,
  @capacity::int,
  @target_user_id::uuid,
  @now::timestamptz
)::text AS id
''';

  static const String _findChallengeSql = '''
SELECT c.id::text AS id,
       c.code AS code,
       c.season_id::text AS season_id,
       c.fixture_id::text AS fixture_id,
       c.challenger_participant_id::text AS challenger_participant_id,
       c.target_user_id::text AS target_user_id,
       c.capacity::int AS capacity,
       c.status::text AS status,
       c.created_at AS created_at,
       c.updated_at AS updated_at
FROM social.duel_challenges c
WHERE c.id = @challenge_id::uuid
''';

  static const String _acceptSql = '''
SELECT social.accept_duel_challenge(
  @challenge_id::uuid, @opponent_user_id::uuid, @now::timestamptz
)::text AS id
''';

  static const String _findDuelSql = '''
SELECT d.id::text AS id,
       d.challenge_id::text AS challenge_id,
       d.fixture_id::text AS fixture_id,
       d.challenger_participant_id::text AS challenger_participant_id,
       d.opponent_participant_id::text AS opponent_participant_id,
       d.accepted_at AS accepted_at,
       d.created_at AS created_at
FROM social.duels d
WHERE d.id = @duel_id::uuid
''';

  // Both functions return void; wrapping them keeps a void column off the
  // wire (the same shape PostgresReferralRepository uses).
  static const String _cancelSql = '''
SELECT count(*)::bigint AS done
FROM (
  SELECT social.cancel_duel_challenge(
    @challenge_id::uuid, @challenger_user_id::uuid
  )
) AS call
''';

  static const String _declineSql = '''
SELECT count(*)::bigint AS done
FROM (
  SELECT social.decline_duel_challenge(
    @challenge_id::uuid, @target_user_id::uuid
  )
) AS call
''';

  @override
  Future<Result<DuelChallenge>> createChallenge({
    required SeasonId seasonId,
    required FixtureRef fixture,
    required ParticipantId challengerParticipantId,
    required UserId? targetUserId,
    required int capacity,
    required DateTime nowUtc,
  }) async {
    final result = await _connection.runInTransaction<DuelChallenge>((
      tx,
    ) async {
      final created = await tx.query(
        _createSql,
        parameters: {
          'challenger_participant_id': challengerParticipantId.value,
          'season_id': seasonId.value,
          'fixture_id': fixture.value,
          'capacity': capacity,
          'target_user_id': targetUserId?.value,
          'now': nowUtc.toUtc(),
        },
      );
      if (created is Err<List<Map<String, dynamic>>>) {
        return Result.err(created.error);
      }
      final rows = (created as Ok<List<Map<String, dynamic>>>).value;
      final id = rows.isEmpty ? null : rows.first['id'];
      if (id is! String) {
        return Result.err(_corrupt('duel_challenges', 'id', 'no id returned'));
      }
      final read = await tx.query(
        _findChallengeSql,
        parameters: {'challenge_id': id},
      );
      return switch (read) {
        Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
        Ok<List<Map<String, dynamic>>>(:final value) =>
          value.isEmpty
              ? Result.err(
                  _corrupt('duel_challenges', 'id', 'created row not found'),
                )
              : _mapChallenge(value.first),
      };
    });
    return switch (result) {
      Err<DuelChallenge>(:final error) => Result.err(_reclassify(error)),
      Ok<DuelChallenge>() => result,
    };
  }

  @override
  Future<Result<DuelChallenge?>> findChallenge(DuelChallengeId id) async {
    final result = await _connection.query(
      _findChallengeSql,
      parameters: {'challenge_id': id.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapChallenge(value.first),
    };
  }

  @override
  Future<Result<Duel>> acceptChallenge({
    required DuelChallengeId challengeId,
    required UserId opponentUserId,
    required DateTime nowUtc,
  }) async {
    final result = await _connection.runInTransaction<Duel>((tx) async {
      final accepted = await tx.query(
        _acceptSql,
        parameters: {
          'challenge_id': challengeId.value,
          'opponent_user_id': opponentUserId.value,
          'now': nowUtc.toUtc(),
        },
      );
      if (accepted is Err<List<Map<String, dynamic>>>) {
        return Result.err(accepted.error);
      }
      final rows = (accepted as Ok<List<Map<String, dynamic>>>).value;
      final id = rows.isEmpty ? null : rows.first['id'];
      if (id is! String) {
        return Result.err(_corrupt('duels', 'id', 'no id returned'));
      }
      final read = await tx.query(_findDuelSql, parameters: {'duel_id': id});
      return switch (read) {
        Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
        Ok<List<Map<String, dynamic>>>(:final value) =>
          value.isEmpty
              ? Result.err(_corrupt('duels', 'id', 'accepted row not found'))
              : _mapDuel(value.first),
      };
    });
    return switch (result) {
      Err<Duel>(:final error) => Result.err(_reclassify(error)),
      Ok<Duel>() => result,
    };
  }

  @override
  Future<Result<void>> cancelChallenge({
    required DuelChallengeId challengeId,
    required UserId challengerUserId,
  }) async {
    final result = await _connection.query(
      _cancelSql,
      parameters: {
        'challenge_id': challengeId.value,
        'challenger_user_id': challengerUserId.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<void>> declineChallenge({
    required DuelChallengeId challengeId,
    required UserId targetUserId,
  }) async {
    final result = await _connection.query(
      _declineSql,
      parameters: {
        'challenge_id': challengeId.value,
        'target_user_id': targetUserId.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  /// The stable error for a constraint name raised by migration 0090, or
  /// null when the name is not a duel rule.
  ///
  /// Public so a test can check this table against every constraint name
  /// the migration raises: the driver's [ServerException] has no public
  /// constructor, so the full reclassification path is only reachable
  /// against a live server.
  static AppError? errorForConstraint(String constraint) =>
      _constraintErrors[constraint];

  static const Map<String, AppError> _constraintErrors = {
    'duel_challenges_capacity_range': AppError.validation(
      'social.duel_capacity_out_of_range',
      'Duel challenge capacity must be between 1 and 10',
    ),
    'duel_challenges_private_capacity': AppError.validation(
      'social.duel_private_capacity_invalid',
      'A private duel challenge must have capacity one',
    ),
    'duel_challenges_not_self': AppError.validation(
      'social.duel_self_target',
      'A duel challenge cannot target the challenger',
    ),
    'duel_fixture_not_in_season': AppError.invariant(
      'social.duel_fixture_not_in_season',
      'The fixture is not part of this season',
    ),
    'duel_minimum_lead_time': AppError.invariant(
      'social.duel_minimum_lead_time',
      'A duel must be created at least 30 minutes before kickoff',
    ),
    'duel_challenger_not_participant': AppError.invariant(
      'social.duel_challenger_not_participant',
      'You must be an active participant in the season',
    ),
    'duel_target_not_active': AppError.invariant(
      'social.duel_target_not_active',
      'The invited player is not active',
    ),
    'duel_max_pending_challenges': AppError.invariant(
      'social.duel_max_pending_challenges',
      'You already have ten pending duel challenges',
    ),
    'duel_not_found': AppError.invariant(
      'social.duel_challenge_not_found',
      'Duel challenge was not found',
    ),
    'duel_not_open': AppError.invariant(
      'social.duel_challenge_not_open',
      'Duel challenge is no longer open',
    ),
    'duel_challenges_status_immutable': AppError.invariant(
      'social.duel_challenge_not_open',
      'Duel challenge is no longer open',
    ),
    'duel_expired': AppError.invariant(
      'social.duel_expired',
      'The duel challenge expired at kickoff',
    ),
    'duel_challenger_inactive': AppError.invariant(
      'social.duel_challenger_inactive',
      'The challenger is no longer active',
    ),
    'duel_challenger_self': AppError.validation(
      'social.duel_self_accept',
      'You cannot accept your own duel challenge',
    ),
    'duel_wrong_target': AppError.authorization(
      'social.duel_wrong_target',
      'This private duel is reserved for another user',
    ),
    'duel_opponent_not_participant': AppError.invariant(
      'social.duel_opponent_not_participant',
      'You must be an active participant in the season',
    ),
    'duel_capacity_full': AppError.invariant(
      'social.duel_capacity_full',
      'This duel challenge is full',
    ),
    'duel_pair_already_exists': AppError.invariant(
      'social.duel_pair_already_exists',
      'You already have a duel with this player for this fixture',
    ),
    'duels_fixture_pair_uniq': AppError.invariant(
      'social.duel_pair_already_exists',
      'You already have a duel with this player for this fixture',
    ),
    'duels_challenge_opponent_uniq': AppError.invariant(
      'social.duel_pair_already_exists',
      'You already have a duel with this player for this fixture',
    ),
    'duel_challenger_prediction_required': AppError.invariant(
      'social.duel_challenger_prediction_required',
      'The challenger has no prediction for this fixture',
    ),
    'duel_opponent_prediction_required': AppError.invariant(
      'social.duel_opponent_prediction_required',
      'You must submit a prediction before accepting',
    ),
    'duel_cancel_not_allowed': AppError.invariant(
      'social.duel_cancel_not_allowed',
      'This duel challenge cannot be cancelled',
    ),
    'duel_decline_not_allowed': AppError.invariant(
      'social.duel_decline_not_allowed',
      'This duel challenge cannot be declined',
    ),
    'duel_challenges_identity_immutable': AppError.invariant(
      'social.duel_integrity_violation',
      'The write violated a duel integrity rule',
    ),
  };

  /// Maps a driver integrity failure to its duel rule. Anything else -- a
  /// network fault, a timeout, an unattributed error -- stays transient.
  AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    const integrityCodes = {'23505', '23503', '23514'};
    final code = cause.code;
    if (code == null || !integrityCodes.contains(code)) {
      return error;
    }
    final constraint = cause.constraintName;
    final mapped = constraint == null ? null : _constraintErrors[constraint];
    return mapped ??
        const AppError.invariant(
          'social.duel_integrity_violation',
          'The write violated a duel integrity rule',
        );
  }

  Result<DuelChallenge> _mapChallenge(Map<String, dynamic> row) {
    final id = DuelChallengeId.tryParse(row['id']?.toString());
    if (id is Err<DuelChallengeId>) {
      return Result.err(_corrupt('duel_challenges', 'id', id.error.message));
    }
    final code = DuelCode.tryParse(row['code']?.toString());
    if (code is Err<DuelCode>) {
      return Result.err(
        _corrupt('duel_challenges', 'code', code.error.message),
      );
    }
    final season = SeasonId.tryParse(row['season_id']?.toString());
    if (season is Err<SeasonId>) {
      return Result.err(
        _corrupt('duel_challenges', 'season_id', season.error.message),
      );
    }
    final fixture = FixtureRef.tryParse(row['fixture_id']?.toString());
    if (fixture is Err<FixtureRef>) {
      return Result.err(
        _corrupt('duel_challenges', 'fixture_id', fixture.error.message),
      );
    }
    final challenger = ParticipantId.tryParse(
      row['challenger_participant_id']?.toString(),
    );
    if (challenger is Err<ParticipantId>) {
      return Result.err(
        _corrupt(
          'duel_challenges',
          'challenger_participant_id',
          challenger.error.message,
        ),
      );
    }
    final rawTarget = row['target_user_id'];
    UserId? target;
    if (rawTarget != null) {
      final parsed = UserId.tryParse(rawTarget.toString());
      if (parsed is Err<UserId>) {
        return Result.err(
          _corrupt('duel_challenges', 'target_user_id', parsed.error.message),
        );
      }
      target = (parsed as Ok<UserId>).value;
    }
    final capacity = row['capacity'];
    if (capacity is! int) {
      return Result.err(
        _corrupt('duel_challenges', 'capacity', 'not an integer'),
      );
    }
    final status = DuelChallengeStatus.tryParse(row['status']?.toString());
    if (status is Err<DuelChallengeStatus>) {
      return Result.err(
        _corrupt('duel_challenges', 'status', status.error.message),
      );
    }
    final createdAt = _readUtcTimestamp(row['created_at']);
    if (createdAt == null) {
      return Result.err(
        _corrupt('duel_challenges', 'created_at', 'not a timestamp'),
      );
    }
    final updatedAt = _readUtcTimestamp(row['updated_at']);
    if (updatedAt == null) {
      return Result.err(
        _corrupt('duel_challenges', 'updated_at', 'not a timestamp'),
      );
    }
    return Result.ok(
      DuelChallenge.fromStored(
        id: (id as Ok<DuelChallengeId>).value,
        code: (code as Ok<DuelCode>).value,
        seasonId: (season as Ok<SeasonId>).value,
        fixture: (fixture as Ok<FixtureRef>).value,
        challengerParticipantId: (challenger as Ok<ParticipantId>).value,
        targetUserId: target,
        capacity: capacity,
        status: (status as Ok<DuelChallengeStatus>).value,
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
    );
  }

  Result<Duel> _mapDuel(Map<String, dynamic> row) {
    final id = DuelId.tryParse(row['id']?.toString());
    if (id is Err<DuelId>) {
      return Result.err(_corrupt('duels', 'id', id.error.message));
    }
    final challenge = DuelChallengeId.tryParse(row['challenge_id']?.toString());
    if (challenge is Err<DuelChallengeId>) {
      return Result.err(
        _corrupt('duels', 'challenge_id', challenge.error.message),
      );
    }
    final fixture = FixtureRef.tryParse(row['fixture_id']?.toString());
    if (fixture is Err<FixtureRef>) {
      return Result.err(_corrupt('duels', 'fixture_id', fixture.error.message));
    }
    final challenger = ParticipantId.tryParse(
      row['challenger_participant_id']?.toString(),
    );
    if (challenger is Err<ParticipantId>) {
      return Result.err(
        _corrupt(
          'duels',
          'challenger_participant_id',
          challenger.error.message,
        ),
      );
    }
    final opponent = ParticipantId.tryParse(
      row['opponent_participant_id']?.toString(),
    );
    if (opponent is Err<ParticipantId>) {
      return Result.err(
        _corrupt('duels', 'opponent_participant_id', opponent.error.message),
      );
    }
    final acceptedAt = _readUtcTimestamp(row['accepted_at']);
    if (acceptedAt == null) {
      return Result.err(_corrupt('duels', 'accepted_at', 'not a timestamp'));
    }
    final createdAt = _readUtcTimestamp(row['created_at']);
    if (createdAt == null) {
      return Result.err(_corrupt('duels', 'created_at', 'not a timestamp'));
    }
    return Result.ok(
      Duel.fromStored(
        id: (id as Ok<DuelId>).value,
        challengeId: (challenge as Ok<DuelChallengeId>).value,
        fixture: (fixture as Ok<FixtureRef>).value,
        challengerParticipantId: (challenger as Ok<ParticipantId>).value,
        opponentParticipantId: (opponent as Ok<ParticipantId>).value,
        acceptedAt: acceptedAt,
        createdAt: createdAt,
      ),
    );
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

  static AppError _corrupt(String table, String field, String detail) =>
      AppError.transient(
        'social.row_corrupt',
        'Stored $table row has invalid $field: $detail',
      );
}
