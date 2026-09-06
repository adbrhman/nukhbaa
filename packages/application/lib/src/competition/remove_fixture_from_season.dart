import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/scoring/ports/fixture_result_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: remove a fixture from a season — the inverse of
/// [LinkFixtureToSeason], and the season-scoped sibling of
/// [RemoveFixtureFromRound]. Admin-only.
///
/// ## What this is for
/// Correcting an admin's own entry mistake — a wrong team, a wrong kickoff,
/// a duplicate — in the window before anyone has acted on the fixture. It is
/// deliberately NOT a cancellation feature.
///
/// ## Why the guards are absolute
/// A season's fixtures are what the monthly leaderboard aggregates over, and
/// the ledger is append-only by construction (`ledger.reject_entry_mutation`
/// refuses every DELETE and UPDATE). So a fixture that has been predicted or
/// scored cannot be truly removed at all: unlinking it would leave points
/// standing in the ledger for a fixture no screen can show — a leaderboard
/// total nobody can account for, which is worse than the mistake being
/// corrected. Both guards therefore reject rather than cascade:
///   * any prediction exists ([FixturePredictionRepository.listByFixture])
///     -> [ErrorKind.invariant] `competition.fixture_has_predictions`
///   * a result is recorded ([FixtureResultRepository.findByFixture])
///     -> [ErrorKind.invariant] `competition.fixture_result_already_recorded`
///       (the same code [RemoveFixtureFromRound] raises, deliberately)
///
/// Both are checked even though either alone would usually be enough: a
/// result can be recorded before anyone predicts, and a prediction can exist
/// with no result yet.
///
/// The delete itself is idempotent
/// ([FixturePredictionRepository.unlinkFixtureFromSeason]): a link that is
/// already gone is `Ok(false)`, not an error, so a retried removal converges.
///
/// Never throws; returns a typed [Result].
final class RemoveFixtureFromSeason {
  /// Creates the use-case over its collaborators.
  const RemoveFixtureFromSeason({
    required CompetitionRepository competitionRepository,
    required FixturePredictionRepository fixturePredictionRepository,
    required FixtureResultRepository fixtureResultRepository,
  }) : _competitions = competitionRepository,
       _fixturePredictions = fixturePredictionRepository,
       _fixtureResults = fixtureResultRepository;

  final CompetitionRepository _competitions;
  final FixturePredictionRepository _fixturePredictions;
  final FixtureResultRepository _fixtureResults;

  /// Removes [fixtureId] from [seasonId]. `Ok(true)` when a link was
  /// removed, `Ok(false)` when there was nothing to remove.
  Future<Result<bool>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final seasonIdResult = SeasonId.tryParse(seasonId);
    if (seasonIdResult is Err<SeasonId>) {
      return Result.err(seasonIdResult.error);
    }
    final sId = (seasonIdResult as Ok<SeasonId>).value;

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    final fixture = (fixtureResult as Ok<FixtureRef>).value;

    // The season must exist (mirrors LinkFixtureToSeason's only
    // precondition — a season carries no lifecycle status to gate on).
    final seasonResult = await _competitions.findSeason(sId);
    if (seasonResult is Err<CompetitionSeason>) {
      return Result.err(seasonResult.error);
    }

    final predictions = await _fixturePredictions.listByFixture(fixture);
    if (predictions is Err<List<FixturePredictionView>>) {
      return Result.err(predictions.error);
    }
    if ((predictions as Ok<List<FixturePredictionView>>).value.isNotEmpty) {
      return const Result.err(
        AppError.invariant(
          'competition.fixture_has_predictions',
          'Users have already predicted this fixture, so it can no longer '
              'be removed from the season',
        ),
      );
    }

    final existingResult = await _fixtureResults.findByFixture(fixture);
    if (existingResult is Err<FixtureResult?>) {
      return Result.err(existingResult.error);
    }
    if ((existingResult as Ok<FixtureResult?>).value != null) {
      return const Result.err(
        AppError.invariant(
          'competition.fixture_result_already_recorded',
          'This fixture already has a recorded result and can no longer '
              'be removed from the season',
        ),
      );
    }

    return _fixturePredictions.unlinkFixtureFromSeason(
      seasonId: sId,
      fixture: fixture,
    );
  }
}
