import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One player's badge record (P2-8): what their stream adds up to, and when
/// each badge they hold was granted.
final class PlayerBadgeRecord {
  /// Creates a record.
  const PlayerBadgeRecord({required this.progress, required this.unlockedAt});

  /// A player with no history: every count zero, nothing held.
  static const PlayerBadgeRecord none = PlayerBadgeRecord(
    progress: BadgeProgress(),
    unlockedAt: <BadgeCode, DateTime>{},
  );

  /// What the player's stream adds up to.
  final BadgeProgress progress;

  /// Each held badge and the moment its `badge_unlocked` event occurred.
  final Map<BadgeCode, DateTime> unlockedAt;
}

/// Read port over the gamification stream for ONE player's badges (P2-8).
///
/// The evaluator's [BadgeProgressReader] reads every player at once for the
/// scheduler; this reads a single player for a request, so a page load never
/// pays for the whole stream.
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient]. Read-only: nothing here writes.
abstract interface class PlayerBadgeReader {
  /// The record of [userId]. A player with no events reads as
  /// [PlayerBadgeRecord.none], not as an error. A stored code the catalog no
  /// longer knows is left out.
  Future<Result<PlayerBadgeRecord>> recordOf(UserId userId);
}
