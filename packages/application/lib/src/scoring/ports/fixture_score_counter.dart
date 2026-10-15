import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port: how many players were scored on each of many fixtures, in one
/// read (batch 156). Implemented in Infrastructure over
/// `scoring.fixture_scores`.
abstract interface class FixtureScoreCounter {
  /// The number of scores of each fixture of [fixtures] that has any; a
  /// fixture with none is absent from the map.
  Future<Result<Map<String, int>>> countByFixtures(List<FixtureRef> fixtures);
}
