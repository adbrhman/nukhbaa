import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/submit_fixture_prediction.dart';
import 'package:application/src/social/ports/duel_challenge_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: accept a Duel invitation.
///
/// The existing prediction writer is deliberately reused. The sequence is
/// read challenge -> submit prediction -> atomically accept in Postgres. If
/// the final acceptance loses a race, the prediction remains safely saved and
/// no partial duel row is created.
final class AcceptDuelChallenge {
  const AcceptDuelChallenge({
    required DuelChallengeRepository duels,
    required SubmitFixturePrediction submitPrediction,
    required Clock clock,
  }) : _duels = duels,
       _submitPrediction = submitPrediction,
       _clock = clock;

  final DuelChallengeRepository _duels;
  final SubmitFixturePrediction _submitPrediction;
  final Clock _clock;

  Future<Result<Duel>> call({
    required AuthenticatedUser principal,
    required String challengeId,
    required int homeGoals,
    required int awayGoals,
    bool isDouble = false,
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
    if (challenge.targetUserId != null &&
        challenge.targetUserId != principal.userId) {
      return const Result.err(
        AppError.authorization(
          'social.duel_wrong_target',
          'This private duel is reserved for another user',
        ),
      );
    }

    final now = _clock.nowUtc();
    final prediction = await _submitPrediction.call(
      principal: principal,
      seasonId: challenge.seasonId.value,
      fixtureId: challenge.fixture.value,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      isDouble: isDouble,
    );
    if (prediction is Err<FixturePredictionView>) {
      return Result.err(prediction.error);
    }

    return _duels.acceptChallenge(
      challengeId: id,
      opponentUserId: principal.userId,
      nowUtc: now,
    );
  }
}
