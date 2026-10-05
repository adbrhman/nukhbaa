import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/social/ports/duel_challenge_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: cancel an open Duel invitation owned by the challenger.
final class CancelDuelChallenge {
  const CancelDuelChallenge({
    required DuelChallengeRepository duels,
    required CompetitionRepository competition,
  }) : _duels = duels,
       _competition = competition;

  final DuelChallengeRepository _duels;
  final CompetitionRepository _competition;

  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required String challengeId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);

    final idResult = DuelChallengeId.tryParse(challengeId);
    if (idResult is Err<DuelChallengeId>) return Result.err(idResult.error);
    final id = (idResult as Ok<DuelChallengeId>).value;

    final challengeResult = await _duels.findChallenge(id);
    if (challengeResult is Err<DuelChallenge?>) {
      return Result.err(challengeResult.error);
    }
    final challenge = (challengeResult as Ok<DuelChallenge?>).value;
    if (challenge == null) {
      return const Result.err(
        AppError.invariant(
          'social.duel_challenge_not_found',
          'Duel challenge was not found',
        ),
      );
    }
    if (!challenge.isOpen) {
      return const Result.err(
        AppError.invariant(
          'social.duel_challenge_not_open',
          'Duel challenge is no longer open',
        ),
      );
    }

    final participantResult = await _competition.findParticipant(
      challenge.seasonId,
      principal.userId,
    );
    if (participantResult is Err<Participant?>) {
      return Result.err(participantResult.error);
    }
    final participant = (participantResult as Ok<Participant?>).value;
    if (participant?.id != challenge.challengerParticipantId) {
      return const Result.err(
        AppError.authorization(
          'social.duel_not_challenger',
          'Only the challenger may cancel this duel',
        ),
      );
    }

    return _duels.cancelChallenge(
      challengeId: id,
      challengerUserId: principal.userId,
    );
  }
}
