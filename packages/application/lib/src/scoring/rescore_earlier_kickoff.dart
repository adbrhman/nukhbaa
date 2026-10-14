import 'package:application/src/scoring/ports/fixture_result_repository.dart';
import 'package:application/src/scoring/rescore_unscored_results.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Scores a fixture again after its kickoff was brought forward (audit
/// C-03).
///
/// `ScoreFixture` gives nothing to a prediction stamped at or after the
/// stored kickoff, so bringing the kickoff forward makes every prediction
/// sent in between a late one. A fixture with no result yet needs nothing:
/// it is scored from the new kickoff when its result comes. One whose result
/// is already recorded is scored and posted again through the same
/// [FixtureRescorer] the rescore sweep uses (`ScoreFixture`, then
/// `PostFixtureToLedger`; both idempotent, a changed score is posted as a
/// correction, and nobody is pushed twice).
///
/// Never throws; answers whether the fixture was scored again.
final class RescoreEarlierKickoff {
  /// Creates the use-case over its collaborators.
  const RescoreEarlierKickoff({
    required FixtureResultRepository resultRepository,
    required FixtureRescorer rescore,
  }) : _results = resultRepository,
       _rescore = rescore;

  final FixtureResultRepository _results;
  final FixtureRescorer _rescore;

  /// Scores [fixture] again when its result is recorded.
  Future<Result<bool>> call(FixtureRef fixture) async {
    final found = await _results.findByFixture(fixture);
    if (found is Err<FixtureResult?>) {
      return Result.err(found.error);
    }
    if ((found as Ok<FixtureResult?>).value == null) {
      return const Result.ok(false);
    }
    final rescored = await _rescore(fixtureId: fixture.value);
    if (rescored is Err<void>) {
      return Result.err(rescored.error);
    }
    return const Result.ok(true);
  }
}
