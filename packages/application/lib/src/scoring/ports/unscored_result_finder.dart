import 'package:shared/shared.dart';

/// Finds fixtures whose result is recorded but at least one of whose
/// predictions still has no `scoring.fixture_scores` row.
///
/// Recording a result and scoring it are two separate writes (the admin's
/// `PUT /fixtures/{id}/result`, the provider sync's recorder). When the
/// second one fails, the result stands and nothing ever asks again: the sync
/// only looks at fixtures WITHOUT a result, and the monthly board, which sums
/// `scoring.fixture_scores`, silently shows no points for that match. This
/// read is what lets a sweep find those fixtures.
abstract interface class UnscoredResultFinder {
  /// Fixture ids (as strings) whose result was recorded in
  /// [recordedFrom, recordedBefore) and that still hold an unscored
  /// prediction, oldest result first, at most [limit].
  Future<Result<List<String>>> fixturesWithUnscoredPredictions({
    required DateTime recordedFrom,
    required DateTime recordedBefore,
    required int limit,
  });
}
