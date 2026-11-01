/// Port: which predictors of a fixture belong to suspended accounts.
library;

import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The participants who predicted a fixture and whose account is suspended
/// now (an admin's suspension, or a deleted account, which stays suspended).
///
/// A suspended account is on no board and earns no reward (decided by the
/// owner 2026-10-02 and 2026-11-01): [ScoreFixture] and [GetLiveStanding]
/// leave its call out of the sole exact count with this. A separate port,
/// taken optionally, so every existing construction keeps compiling.
abstract interface class SuspendedPredictorsReader {
  /// The suspended predictors of [fixture]; empty when there are none.
  Future<Result<Set<ParticipantId>>> suspendedOn(FixtureRef fixture);
}
