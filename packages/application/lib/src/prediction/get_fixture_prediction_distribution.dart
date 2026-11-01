import 'package:application/src/competition/fixture_visibility.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/prediction/ports/fixture_prediction_tally_reader.dart';
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
    FixtureScheduleRepository? fixtureScheduleRepository,
    int shareMinimum = crowdShareMinimum,
  }) : _fixturePredictions = fixturePredictionRepository,
       _schedules = fixtureScheduleRepository,
       _shareMinimum = shareMinimum;

  final FixturePredictionRepository _fixturePredictions;

  /// Optional: with it a hidden fixture, or a test fixture asked by a
  /// player, is refused as the feed leaves it out (review M-3).
  final FixtureScheduleRepository? _schedules;

  /// The fewest calls the split is shown from ([crowdShareMinimum]):
  /// under it both shares are 0 (review M-2).
  final int _shareMinimum;

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

    final FixtureScheduleRepository? schedules = _schedules;
    if (schedules != null) {
      final found = await schedules.findByFixture(fixture);
      if (found is Err<FixtureSchedule?>) {
        return Result.err(found.error);
      }
      if (!FixtureVisibility.playable(
        principal,
        (found as Ok<FixtureSchedule?>).value,
      )) {
        return const Result.err(FixtureVisibility.unavailable);
      }
    }

    final predictionsResult = await _fixturePredictions.listByFixture(fixture);
    if (predictionsResult is Err<List<FixturePredictionView>>) {
      return Result.err(predictionsResult.error);
    }

    final List<FixturePredictionView> views =
        (predictionsResult as Ok<List<FixturePredictionView>>).value;
    if (views.length < _shareMinimum) {
      return const Result.ok(
        FixturePredictionDistribution(
          homeWinPercentage: 0,
          awayWinPercentage: 0,
        ),
      );
    }

    var homeWins = 0;
    var awayWins = 0;
    for (final view in views) {
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
