/// Port for reading the daily rank snapshot behind the movement arrows.
library;

import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reads the most recent daily snapshot of a season's standings.
///
/// The snapshot is written by pg_cron (migration 0030, repointed at the
/// fixture standings by 0034), never by the server. This port is read-only by
/// design: nothing in the application layer should be able to forge a past
/// rank, because a fabricated one would produce an arrow no participant
/// earned.
///
/// A single-method port rather than a widening of an existing one: the
/// snapshot is not competition state and not a point store, and the only
/// use-case that needs it is the fixture board.
///
/// Contract (Application ADR Section 2):
/// * MUST NOT throw -- every outcome is a typed [Result].
/// * MUST map infrastructure failures to [ErrorKind.transient].
/// * An empty map is a legitimate answer, not an error: no capture has run
///   for this season yet, which is the normal state on a season's first day.
abstract interface class RankSnapshotReader {
  /// Returns participant-id-value -> rank as of the season's most recent
  /// capture. Participants absent from that capture are absent from the map,
  /// which the caller renders as "new" rather than as an arrow.
  Future<Result<Map<String, int>>> latestRanks(SeasonId seasonId);
}
