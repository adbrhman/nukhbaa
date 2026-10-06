import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/list_fixture_predictions.dart';
import 'package:application/src/social/ports/prediction_reaction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: take back the caller's reaction to a prediction
/// (migration 0094). Behind the same gate as reacting
/// ([ListFixturePredictions]); taking back a reaction that does not exist
/// is a success that answers false.
///
/// Never throws; returns a typed [Result].
final class RemovePredictionReaction {
  /// Creates the use-case over its collaborators.
  const RemovePredictionReaction({
    required ListFixturePredictions reveal,
    required PredictionReactionRepository reactions,
  }) : _reveal = reveal,
       _reactions = reactions;

  final ListFixturePredictions _reveal;
  final PredictionReactionRepository _reactions;

  /// Takes back [principal]'s reaction to [targetParticipantId]'s
  /// prediction for [fixtureId] in [seasonId].
  Future<Result<bool>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
    required String targetParticipantId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final targetResult = ParticipantId.tryParse(targetParticipantId);
    if (targetResult is Err<ParticipantId>) {
      return Result.err(targetResult.error);
    }
    final gate = await _reveal(
      principal: principal,
      seasonId: seasonId,
      fixtureId: fixtureId,
    );
    if (gate is Err<FixturePredictionReveal>) {
      return Result.err(gate.error);
    }
    return _reactions.remove(
      fixture: (FixtureRef.tryParse(fixtureId) as Ok<FixtureRef>).value,
      target: (targetResult as Ok<ParticipantId>).value,
      reactor: principal.userId,
    );
  }
}
