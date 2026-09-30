import 'package:application/src/scoring/ports/unscored_result_finder.dart';
import 'package:shared/shared.dart';

/// Scores one fixture again and posts it to the ledger -- the same two steps
/// the result recorders run after writing a result. Wired in the composition
/// root over `ScoreFixture` and `PostFixtureToLedger`, both idempotent.
typedef FixtureRescorer =
    Future<Result<void>> Function({required String fixtureId});

/// Finishes the scoring of every recently recorded result that was left
/// half-done.
///
/// A result whose scoring failed after it was written (a timed-out statement,
/// a lost connection, a restart in between) is found by [UnscoredResultFinder]
/// and scored again. Nothing is invented here: the fixture is scored from its
/// stored result by the same use-cases the admin and the sync call.
///
/// [settle] keeps the sweep away from a result that was recorded moments ago
/// and is still being scored by whoever recorded it. [lookback] bounds how far
/// back it looks, so a fixture that keeps failing stops being retried after a
/// few days instead of forever.
final class RescoreUnscoredResults {
  /// Creates the sweep over its collaborators.
  const RescoreUnscoredResults({
    required UnscoredResultFinder finder,
    required FixtureRescorer rescore,
    this.lookback = const Duration(days: 3),
    this.settle = const Duration(minutes: 10),
    this.maxPerRun = 10,
  }) : _finder = finder,
       _rescore = rescore;

  final UnscoredResultFinder _finder;
  final FixtureRescorer _rescore;

  /// How far back a recorded result is still looked at.
  final Duration lookback;

  /// How old a result must be before the sweep touches it.
  final Duration settle;

  /// At most this many fixtures are scored per run.
  final int maxPerRun;

  /// Scores the unfinished fixtures as of [now]; returns how many it scored.
  ///
  /// One fixture failing does not stop the others; the first failure is
  /// returned after the rest were tried, so the scheduler logs it.
  Future<Result<int>> call({required DateTime now}) async {
    final nowUtc = now.toUtc();
    final found = await _finder.fixturesWithUnscoredPredictions(
      recordedFrom: nowUtc.subtract(lookback),
      recordedBefore: nowUtc.subtract(settle),
      limit: maxPerRun,
    );
    if (found is Err<List<String>>) {
      return Result.err(found.error);
    }

    var rescored = 0;
    AppError? firstFailure;
    for (final fixtureId in (found as Ok<List<String>>).value) {
      final result = await _rescore(fixtureId: fixtureId);
      if (result is Err<void>) {
        firstFailure ??= result.error;
        continue;
      }
      rescored++;
    }

    final failure = firstFailure;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(rescored);
  }
}
