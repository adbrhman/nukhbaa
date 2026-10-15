import 'package:application/src/scoring/my_fixture_score.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reads one user's own predictions that have a score or a recorded result,
/// in one query (`scoring.my_fixture_scores`, migration 0171).
///
/// Its own narrow port rather than another method on
/// [FixtureScoreRepository]: it reads across predictions, scores and
/// results for one user, where that repository answers for one fixture.
abstract interface class MyFixtureScoreReader {
  /// Every prediction of [userId], in every season they joined, that has a
  /// score or a recorded result. Empty when there is none.
  Future<Result<List<MyFixtureScore>>> listByUser(UserId userId);
}
