import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Persistence port for Duel challenges and accepted duels.
///
/// The Postgres adapter is responsible for calling the ratified 0090 database
/// functions and mapping their constraint names to stable [AppError] codes.
/// Application never performs SQL or owns a transaction boundary.
abstract interface class DuelChallengeRepository {
  /// Creates a shareable challenge and returns the stored challenge.
  ///
  /// The database generates the challenge UUID/code and re-checks every
  /// cross-row invariant, including the pending-challenge cap and kickoff
  /// lead-time guard.
  Future<Result<DuelChallenge>> createChallenge({
    required SeasonId seasonId,
    required FixtureRef fixture,
    required ParticipantId challengerParticipantId,
    required UserId? targetUserId,
    required int capacity,
    required DateTime nowUtc,
  });

  /// Finds a challenge by its public UUID. Missing is a normal command
  /// precondition and is represented by `Ok(null)`.
  Future<Result<DuelChallenge?>> findChallenge(DuelChallengeId id);

  /// Atomically accepts one opponent into the challenge after the application
  /// has submitted that opponent's prediction. The database locks the
  /// challenge row and requires both predictions before inserting the duel.
  Future<Result<Duel>> acceptChallenge({
    required DuelChallengeId challengeId,
    required UserId opponentUserId,
    required DateTime nowUtc,
  });

  /// Cancels an open challenge owned by [challengerUserId].
  Future<Result<void>> cancelChallenge({
    required DuelChallengeId challengeId,
    required UserId challengerUserId,
  });

  /// Declines an open private challenge addressed to [targetUserId].
  Future<Result<void>> declineChallenge({
    required DuelChallengeId challengeId,
    required UserId targetUserId,
  });
}
