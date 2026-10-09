import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for who is drawn into a head-to-head month (migration 0100).
///
/// Backed by `PostgresH2hDrawSource`. It lists and orders; who lands in which
/// division is `H2hLeaguePolicy.cut`.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class H2hDrawSource {
  /// The players who predicted on at least [minActiveDays] Riyadh days of the
  /// month opened by [monthStart], best first: points of that month, then
  /// exact scorelines, then the user id. Suspended players are left out.
  Future<Result<List<UserId>>> activeOrder({
    required DateTime monthStart,
    required int minActiveDays,
  });

  /// The members of the month opened by [monthStart] who were drawn into the
  /// next month by its `h2h_league_finished` events, in the order the draw
  /// seats them: next division, then the division played, then the rank.
  /// Suspended players are left out.
  Future<Result<List<H2hCarry>>> carriedFrom(DateTime monthStart);

  /// The users in the pilot (flag `h2h_pilot`, variant `pilot`), best points
  /// of the month opened by [monthStart] first. Suspended players are left
  /// out.
  Future<Result<List<UserId>>> pilotOrder(DateTime monthStart);
}

/// A member a judged month sends into the next one.
final class H2hCarry {
  /// Creates a carry.
  const H2hCarry({
    required this.userId,
    required this.nextDivision,
    required this.division,
    required this.rank,
  });

  /// The player.
  final UserId userId;

  /// The division the player is drawn into.
  final H2hDivision nextDivision;

  /// The division the player played.
  final H2hDivision division;

  /// The player's rank in their group.
  final int rank;
}
