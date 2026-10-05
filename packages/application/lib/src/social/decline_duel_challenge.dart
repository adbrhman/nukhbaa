import 'package:application/src/identity/authorization.dart';
import 'package:application/src/social/ports/duel_challenge_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: decline a private Duel invitation as its target.
final class DeclineDuelChallenge {
  const DeclineDuelChallenge({required DuelChallengeRepository duels})
    : _duels = duels;

  final DuelChallengeRepository _duels;

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
    final target = challenge.targetUserId;
    if (target == null) {
      return const Result.err(
        AppError.invariant(
          'social.duel_challenge_decline_requires_target',
          'Only a private duel challenge can be declined',
        ),
      );
    }
    if (target != principal.userId) {
      return const Result.err(
        AppError.authorization(
          'social.duel_not_target',
          'Only the invited target may decline this duel',
        ),
      );
    }

    return _duels.declineChallenge(
      challengeId: id,
      targetUserId: principal.userId,
    );
  }
}
