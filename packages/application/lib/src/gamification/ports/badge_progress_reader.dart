import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One player's tally and the badges already held (P2-6).
final class UserBadgeStanding {
  /// Creates a standing.
  const UserBadgeStanding({
    required this.userId,
    required this.progress,
    required this.unlocked,
  });

  /// Whose standing this is.
  final UserId userId;

  /// What the player's stream adds up to.
  final BadgeProgress progress;

  /// The badges the player already holds, from `badge_unlocked` events.
  final Set<BadgeCode> unlocked;
}

/// Read port over the gamification stream for the badge evaluator (P2-6).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient]. Read-only: nothing here writes.
abstract interface class BadgeProgressReader {
  /// The standing of every player who has at least one event.
  ///
  /// A code stored in a `badge_unlocked` event that the catalog no longer
  /// knows is left out of `unlocked` rather than failing the read.
  Future<Result<List<UserBadgeStanding>>> readAll();
}
