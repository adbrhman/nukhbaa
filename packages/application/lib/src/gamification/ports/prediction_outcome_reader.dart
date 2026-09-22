import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for "learn from your predictions" (plan P4-1): scored
/// predictions, never pending ones.
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient]. Reads only; decides nothing.
abstract interface class PredictionOutcomeReader {
  /// [userId]'s scored predictions of fixtures kicking off in `[from, to)`,
  /// one per fixture even when the user played it in two seasons.
  Future<Result<List<PredictionOutcome>>> outcomesOf({
    required UserId userId,
    required DateTime from,
    required DateTime to,
  });

  /// Every player's scored predictions of fixtures kicking off in
  /// `[from, to)`, as one tally: the community average a player's own
  /// accuracy is shown against.
  Future<Result<AccuracyTally>> communityTally({
    required DateTime from,
    required DateTime to,
  });
}
