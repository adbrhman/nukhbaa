import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/list_fixture_predictions.dart';
import 'package:application/src/social/ports/prediction_reaction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the reactions every prediction for one fixture received
/// (migration 0094), with the caller's own -- shown on the predictions
/// board beside each prediction.
///
/// The gate is the predictions' own: whoever may see the predictions
/// ([ListFixturePredictions] -- a member of the season, once the fixture
/// has kicked off) may see their reactions, and nobody else. Its refusals
/// pass through unchanged.
///
/// Never throws; returns a typed [Result].
final class ListPredictionReactions {
  /// Creates the use-case over its collaborators.
  const ListPredictionReactions({
    required ListFixturePredictions reveal,
    required PredictionReactionRepository reactions,
  }) : _reveal = reveal,
       _reactions = reactions;

  final ListFixturePredictions _reveal;
  final PredictionReactionRepository _reactions;

  /// The tallies of [fixtureId] in [seasonId], as [principal] sees them.
  Future<Result<List<PredictionReactionTally>>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final gate = await _reveal(
      principal: principal,
      seasonId: seasonId,
      fixtureId: fixtureId,
    );
    if (gate is Err<FixturePredictionReveal>) {
      return Result.err(gate.error);
    }
    // The reveal parsed both ids before it let the caller through.
    return _reactions.tallies(
      seasonId: (SeasonId.tryParse(seasonId) as Ok<SeasonId>).value,
      fixture: (FixtureRef.tryParse(fixtureId) as Ok<FixtureRef>).value,
      viewer: principal.userId,
    );
  }
}
