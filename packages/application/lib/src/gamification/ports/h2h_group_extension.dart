import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for adding groups to a head-to-head month already drawn (decided
/// 2026-10-11): who is waiting for a seat, and the writing of the new
/// groups.
///
/// Backed by `PostgresH2hGroupExtension`. It reads and stores; which groups
/// to open and for whom is `AddH2hGroups`'s, by `H2hLeaguePolicy.extend`.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient]; a database refusal is an [ErrorKind.invariant].
abstract interface class H2hGroupExtension {
  /// The players with no seat in [monthStart] who predicted on at least
  /// [minActiveDays] Riyadh days of that month: the most days first, then
  /// the most points, the most exact scorelines, the user id.
  Future<Result<List<UserId>>> waitingByParticipation({
    required DateTime monthStart,
    required int minActiveDays,
  });

  /// Writes [groups] and their seats into the drawn month [monthStart], all
  /// or nothing, and answers the seats written. A group place or a player
  /// already taken that month is refused by the database.
  Future<Result<int>> addGroups({
    required DateTime monthStart,
    required List<H2hDrawnGroup> groups,
    required int capacity,
  });
}
