import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Aggregated home/away win shares for one fixture. No individual prediction,
/// points, or ledger value is exposed by this read model.
final class FixturePredictionDistribution {
  /// Creates a distribution result.
  const FixturePredictionDistribution({
    required this.homeWinPercentage,
    required this.awayWinPercentage,
  });

  /// Percentage of decisive predictions selecting the home team.
  final int homeWinPercentage;

  /// Percentage of decisive predictions selecting the away team.
  final int awayWinPercentage;
}

/// Reads the server-side prediction split for a fixture.
final class GetFixturePredictionDistribution {
  /// Creates the use-case over the existing prediction read port.
  const GetFixturePredictionDistribution({
    required FixturePredictionRepository fixturePredictionRepository,
  }) : _fixturePredictions = fixturePredictionRepository;

  final FixturePredictionRepository _fixturePredictions;

  /// Returns the home/away win percentages for [fixtureId]. Draw predictions
  /// are ignored so the two visible percentages describe the team split.
  Future<Result<FixturePredictionDistribution>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
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

    final linkResult = await _fixturePredictions.findSeasonFixture(
      sId,
      fixture,
    );
    if (linkResult is Err<SeasonFixture?>) {
      return Result.err(linkResult.error);
    }
    if ((linkResult as Ok<SeasonFixture?>).value == null) {
      return const Result.err(
        AppError.invariant(
          'prediction.fixture_not_in_season',
          'This fixture is not linked to the given season',
        ),
      );
    }

    final predictionsResult = await _fixturePredictions.listByFixture(fixture);
    if (predictionsResult is Err<List<FixturePredictionView>>) {
      return Result.err(predictionsResult.error);
    }

    var homeWins = 0;
    var awayWins = 0;
    for (final view
        in (predictionsResult as Ok<List<FixturePredictionView>>).value) {
      final prediction = view.prediction;
      if (prediction.homeGoals > prediction.awayGoals) {
        homeWins++;
      } else if (prediction.homeGoals < prediction.awayGoals) {
        awayWins++;
      }
    }

    final decisive = homeWins + awayWins;
    final homePercentage = decisive == 0
        ? 0
        : (homeWins * 100 / decisive).round();
    final awayPercentage = decisive == 0
        ? 0
        : (awayWins * 100 / decisive).round();

    return Result.ok(
      FixturePredictionDistribution(
        homeWinPercentage: homePercentage,
        awayWinPercentage: awayPercentage,
      ),
    );
  }
}
